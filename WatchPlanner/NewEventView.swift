import SwiftUI
import UIKit

// New event: name, race date, start time, and either a pasted schedule or
// trainings later. The rules read a pasted schedule first; workouts they could
// not read (or read with doubt) go to Apple Intelligence.

struct NewEventView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hasRaceDate = false
    @State private var raceDate = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now
    @State private var startTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now

    @State private var text = ""
    @State private var planNow = true
    @State private var promptCopied = false
    @State private var saveError: String?
    @State private var weekStart = WorkoutText.defaultWeekStart()

    // Second reading by Apple Intelligence, per doubtful workout.
    @State private var aiWorkouts: [String: PlannedWorkout] = [:]
    @State private var thinking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam", text: $name, prompt: Text(parsed?.schedule.name ?? "Bijvoorbeeld Zevenheuvelenloop"))
                        .font(.headline)
                    Toggle("Wedstrijddatum", isOn: $hasRaceDate.animation())
                    if hasRaceDate {
                        DatePicker("Datum", selection: $raceDate, in: Calendar.current.startOfDay(for: .now)...,
                                   displayedComponents: .date)
                    }
                    DatePicker("Starttijd trainingen", selection: $startTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Event")
                } footer: {
                    if !finalName.isEmpty, store.event(named: finalName) != nil {
                        Text("Er is al een event met deze naam. Kies een andere naam.").foregroundStyle(.orange)
                    }
                }

                pasteSections

                if let saveError {
                    Section {
                        Text("Opslaan lukt niet: \(saveError)").foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Nieuw event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Maak event", action: create)
                        .bold()
                        .disabled(event == nil || thinking)
                }
            }
            .task(id: "\(text)|\(weekStart)") { await askAI() }
        }
    }

    // MARK: - Paste

    @ViewBuilder
    private var pasteSections: some View {
        Section {
            HStack {
                PasteButton(payloadType: String.self) { strings in
                    text = strings.first ?? ""
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
                Spacer()
                Button(promptCopied ? "Gekopieerd" : "Prompt voor Claude",
                       systemImage: promptCopied ? "checkmark" : "sparkles") {
                    UIPasteboard.general.string = WorkoutText.claudePrompt(
                        event: finalName, raceDate: hasRaceDate ? raceDate : nil, startTime: timeString)
                    promptCopied = true
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            TextEditor(text: $text)
                .font(.callout)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Plak of typ je schema, bijvoorbeeld:\n\nWeek 1\nDinsdag: 10 min inlopen, 6 keer 2 min stevig met 1 min rust, uitlopen\nZondag: 12 km rustig")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("Schema (optioneel)")
        } footer: {
            Text(footer)
        }

        if WorkoutText.usesDayNames(text) {
            Section {
                DatePicker("Week 1 begint op", selection: $weekStart, displayedComponents: .date)
            } footer: {
                Text("Je schema noemt dagen in plaats van datums. Kies de maandag waarop je begint.")
            }
        }

        if let result {
            switch result {
            case .success(let e) where !e.workouts.isEmpty:
                preview(e)
            case .success:
                EmptyView()
            case .failure(let error):
                Section {
                    if thinking {
                        thinkingRow
                    } else {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }

        if !text.isEmpty {
            Section {
                Toggle("Meteen op Watch zetten", isOn: $planNow)
            }
        }
    }

    private var footer: String {
        var t = "Laat leeg om later trainingen toe te voegen. Of kopieer de prompt, plak hem in Claude en plak het antwoord hier. Je eigen schema werkt ook."
        if let reason = WorkoutAI.unavailableReason { t += " " + reason }
        return t
    }

    private var thinkingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Apple Intelligence leest mee...")
                .foregroundStyle(.secondary)
        }
    }

    private func preview(_ event: TrainingSchedule) -> some View {
        Section {
            if thinking { thinkingRow }
            if !aiWorkouts.isEmpty {
                Label("\(aiWorkouts.count) gelezen met Apple Intelligence: \(aiWorkouts.values.map(\.name).sorted().joined(separator: ", ")). Check even of ze kloppen.",
                      systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !skipped.isEmpty && !thinking {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(skipped.count) overgeslagen", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.bold())
                    ForEach(skipped, id: \.self) { Text($0).font(.footnote) }
                    Text("Voeg die later zelf toe in het event, of pas de tekst hierboven aan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.orange)
            }
            ForEach(event.workouts) { w in
                WorkoutRow(workout: w, kind: WorkoutKind(w, scheduleName: event.name, raceDate: event.raceDate),
                           isPast: ScheduleDates.isPast(w.date))
            }
        } header: {
            Text("\(event.workouts.count) trainingen gevonden")
        }
    }

    // MARK: - Reading

    private var finalName: String {
        let typed = name.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? parsed?.schedule.name ?? "" : typed
    }

    private var timeString: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return String(format: "%02d:%02d", c.hour ?? 7, c.minute ?? 0)
    }

    private var raceDateString: String? {
        guard hasRaceDate else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: raceDate)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// What the rules make of the text.
    private var parsed: (schedule: TrainingSchedule, doubts: [WorkoutText.Doubt])? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? WorkoutText.programWithWarnings(text, weekStart: weekStart)
    }

    /// Rules plus Apple Intelligence.
    private var result: Result<TrainingSchedule, Error>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Result {
            let p = try WorkoutText.programWithWarnings(text, weekStart: weekStart)
            var e = p.schedule
            for d in p.doubts {
                guard let w = aiWorkouts[d.key] else { continue }
                if let id = d.workoutID, let i = e.workouts.firstIndex(where: { $0.id == id }) {
                    e.workouts[i] = w
                } else if !e.workouts.contains(where: { $0.id == w.id }) {
                    e.workouts.append(w)
                }
            }
            e.workouts.sort { $0.date < $1.date }
            if e.workouts.isEmpty {
                throw WorkoutText.ParseError(message: p.doubts.compactMap(\.problem).first ?? "Ik vond geen trainingen.")
            }
            return e
        }
    }

    /// Workouts that neither the rules nor Apple Intelligence could read.
    private var skipped: [String] {
        (parsed?.doubts ?? []).filter { $0.problem != nil && aiWorkouts[$0.key] == nil }.compactMap(\.problem)
    }

    /// The event to save, or nil while something is missing.
    private var event: TrainingSchedule? {
        let name = finalName
        guard !name.isEmpty, store.event(named: name) == nil else { return nil }
        var workouts: [PlannedWorkout] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard case .success(let e) = result else { return nil }
            workouts = e.workouts
        }
        return TrainingSchedule(name: name, defaultTime: timeString, workouts: workouts, raceDate: raceDateString)
    }

    private func askAI() async {
        aiWorkouts = [:]
        thinking = false
        guard WorkoutAI.isAvailable, let doubts = parsed?.doubts, !doubts.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(700)) // wait until typing pauses
        guard !Task.isCancelled else { return }
        thinking = true
        defer { thinking = false }
        for d in doubts {
            guard !Task.isCancelled else { return }
            guard let r = try? await WorkoutAI.workout(date: d.date, name: d.name.isEmpty ? "x" : d.name, text: d.text),
                  r.usedAI else { continue }
            var w = r.workout
            if d.name.isEmpty { w.name = WorkoutText.autoName(date: d.date, for: w, text: d.text) }
            guard !Task.isCancelled else { return }
            aiWorkouts[d.key] = w
        }
    }

    private func create() {
        guard let event else { return }
        do {
            try store.upsert(event)
            if planNow && !event.workouts.isEmpty {
                Task { await planner.put(event.workouts, time: event.defaultTime, title: "\(event.name) toegevoegd", events: store.events) }
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Edit name, race date and time

struct EditEventView: View {
    let original: TrainingSchedule
    var onSave: (_ newName: String) -> Void = { _ in }

    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hasRaceDate = false
    @State private var raceDate = Date()
    @State private var startTime = Date()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam", text: $name)
                        .font(.headline)
                    Toggle("Wedstrijddatum", isOn: $hasRaceDate.animation())
                    if hasRaceDate {
                        DatePicker("Datum", selection: $raceDate, displayedComponents: .date)
                    }
                    DatePicker("Starttijd trainingen", selection: $startTime, displayedComponents: .hourAndMinute)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    } else {
                        Text("Een nieuwe starttijd geldt voor trainingen die je daarna op je Watch zet.")
                    }
                }
            }
            .navigationTitle("Event wijzigen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", action: save)
                        .bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        name = original.name
        if let day = original.raceDate.flatMap(ScheduleDates.day) {
            hasRaceDate = true
            raceDate = day
        } else {
            raceDate = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now
        }
        let t = ScheduleDates.time(original.defaultTime) ?? (7, 0)
        startTime = Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: .now) ?? .now
    }

    private func save() {
        var e = original
        e.name = name.trimmingCharacters(in: .whitespaces)
        let t = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        e.defaultTime = String(format: "%02d:%02d", t.hour ?? 7, t.minute ?? 0)
        if hasRaceDate {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: raceDate)
            e.raceDate = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        } else {
            e.raceDate = nil
        }
        do {
            try store.update(original.name, to: e)
            onSave(e.name)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
