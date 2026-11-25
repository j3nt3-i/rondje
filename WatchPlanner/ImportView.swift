import SwiftUI
import UIKit

// Paste a whole schedule as text and turn it into an event. The rules read it
// first; workouts they could not read (or read with doubt) go to Apple Intelligence.

struct ImportView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var planNow = true
    @State private var promptCopied = false
    @State private var saveError: String?
    @State private var weekStart = WorkoutText.defaultWeekStart()
    @State private var customName = ""
    @State private var customTime: Date?

    // Second reading by Apple Intelligence, per doubtful workout.
    @State private var aiWorkouts: [String: PlannedWorkout] = [:]
    @State private var thinking = false

    var body: some View {
        NavigationStack {
            Form {
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
                            UIPasteboard.general.string = WorkoutText.claudePrompt
                            promptCopied = true
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                    TextEditor(text: $text)
                        .font(.callout)
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Plak of typ je schema, bijvoorbeeld:\n\nZevenheuvelenloop\nWeek 1\nDinsdag: 10 min inlopen, 6 keer 2 min stevig met 1 min rust, uitlopen\nZondag: 12 km rustig")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Je schema")
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
                    case .success(let event):
                        preview(event)
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

                Section {
                    Toggle("Meteen op Watch zetten", isOn: $planNow)
                } footer: {
                    if let saveError {
                        Text("Opslaan lukt niet: \(saveError)").foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Importeer schema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importeer", action: importEvent)
                        .bold()
                        .disabled(event == nil || thinking)
                }
            }
            .task(id: "\(text)|\(weekStart)") { await askAI() }
        }
    }

    private var footer: String {
        var t = "Zoals je het hebt: met datums, of met weken en dagen. Een schema van Claude werkt ook, met of zonder de prompt."
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
            HStack(spacing: 12) {
                KindIcon(kind: .race)
                TextField("Naam van het event", text: $customName, prompt: Text(parsed?.schedule.name ?? "Naam"))
                    .font(.headline)
            }
            DatePicker("Starttijd", selection: timeBinding(event), displayedComponents: .hourAndMinute)
            Text("\(event.workouts.count) trainingen")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.event(named: event.name) != nil {
                Label("Vervangt het bestaande event met deze naam.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
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
                WorkoutRow(workout: w, kind: WorkoutKind(w, scheduleName: event.name),
                           isPast: ScheduleDates.isPast(w.date))
            }
        } header: {
            Text("Gevonden")
        }
    }

    // MARK: - Reading

    /// What the rules make of the text.
    private var parsed: (schedule: TrainingSchedule, doubts: [WorkoutText.Doubt])? {
        try? WorkoutText.programWithWarnings(text, weekStart: weekStart)
    }

    /// Rules plus Apple Intelligence, with the name and time the user may have changed.
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
            let name = customName.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { e.name = name }
            if let customTime {
                let c = Calendar.current.dateComponents([.hour, .minute], from: customTime)
                e.defaultTime = String(format: "%02d:%02d", c.hour ?? 7, c.minute ?? 0)
            }
            return e
        }
    }

    /// Workouts that neither the rules nor Apple Intelligence could read.
    private var skipped: [String] {
        (parsed?.doubts ?? []).filter { $0.problem != nil && aiWorkouts[$0.key] == nil }.compactMap(\.problem)
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

    private func timeBinding(_ event: TrainingSchedule) -> Binding<Date> {
        Binding {
            if let customTime { return customTime }
            let t = ScheduleDates.time(event.defaultTime) ?? (7, 0)
            return Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: .now) ?? .now
        } set: {
            customTime = $0
        }
    }

    private var event: TrainingSchedule? {
        if case .success(let e) = result { return e }
        return nil
    }

    private func importEvent() {
        guard let event else { return }
        do {
            try store.upsert(event)
            if planNow { Task { await planner.plan(store.events) } }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
