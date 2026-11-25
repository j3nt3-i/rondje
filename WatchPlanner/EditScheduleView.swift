import SwiftUI

// Change a whole event's schedule as text in one go: edit it, or paste a new one over it.
// Name and race date stay; the Watch is updated for what was removed, changed or added.

struct EditScheduleView: View {
    let event: TrainingSchedule

    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var filled = false
    @State private var updateWatch = true
    @State private var aiWorkouts: [String: PlannedWorkout] = [:]
    @State private var thinking = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.first ?? ""
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.accent)
                    TextEditor(text: $text)
                        .font(.callout)
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Schema")
                } footer: {
                    Text("Pas de tekst aan, of plak een nieuw schema eroverheen. Elke training begint met een datum, zoals 1 dec 2026: Heuvels."
                         + (WorkoutAI.unavailableReason.map { " " + $0 } ?? ""))
                }

                if thinking {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Apple Intelligence leest mee...").foregroundStyle(.secondary)
                        }
                    }
                }

                switch result {
                case .success(let new):
                    changesSection(new)
                case .failure(let error) where !thinking:
                    Section {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                default:
                    EmptyView()
                }

                if wasOnWatch {
                    Section {
                        Toggle("Werk ook je Watch bij", isOn: $updateWatch)
                    } footer: {
                        Text("Wat weg of veranderd is gaat van je Watch, nieuwe en veranderde trainingen komen erop.")
                    }
                }

                if let saveError {
                    Section { Text("Opslaan lukt niet: \(saveError)").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Wijzig schema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", action: save)
                        .bold()
                        .disabled(newWorkouts == nil || thinking || changes.isEmpty)
                }
            }
            .onAppear {
                guard !filled else { return }
                filled = true
                text = WorkoutText.programText(for: event)
            }
            .task(id: text) { await askAI() }
        }
    }

    // MARK: - Changes

    private struct Changes {
        var added: [PlannedWorkout] = []
        var changed: [PlannedWorkout] = []
        var removed: [PlannedWorkout] = []
        var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }
    }

    private var changes: Changes {
        guard let new = newWorkouts else { return Changes() }
        let old = Dictionary(event.workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var c = Changes()
        for w in new {
            if let before = old[w.id] {
                if before != w { c.changed.append(w) }
            } else {
                c.added.append(w)
            }
        }
        c.removed = event.workouts.filter { now[$0.id] == nil }
        return c
    }

    private func changesSection(_ new: TrainingSchedule) -> some View {
        let c = changes
        let summary = [
            c.added.isEmpty ? nil : "\(c.added.count) nieuw",
            c.changed.isEmpty ? nil : "\(c.changed.count) gewijzigd",
            c.removed.isEmpty ? nil : "\(c.removed.count) weg",
        ].compactMap { $0 }
        return Section {
            if c.isEmpty {
                Text("Nog niets veranderd.").foregroundStyle(.secondary)
            }
            ForEach(c.added) { row($0, "Nieuw", Theme.accent) }
            ForEach(c.changed) { row($0, "Gewijzigd", .orange) }
            ForEach(c.removed) { row($0, "Weg", .red) }
            if !skipped.isEmpty && !thinking {
                ForEach(skipped, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(summary.isEmpty ? "\(new.workouts.count) trainingen" : summary.joined(separator: " · "))
        }
    }

    private func row(_ w: PlannedWorkout, _ tag: String, _ color: Color) -> some View {
        HStack {
            WorkoutRow(workout: w, kind: WorkoutKind(w, scheduleName: event.name, raceDate: event.raceDate),
                       isPast: ScheduleDates.isPast(w.date))
            Text(tag).font(.caption.bold()).foregroundStyle(color)
        }
    }

    // MARK: - Reading

    private var parsed: (schedule: TrainingSchedule, doubts: [WorkoutText.Doubt])? {
        try? WorkoutText.programWithWarnings(text)
    }

    private var result: Result<TrainingSchedule, Error>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Result { try WorkoutAI.merge(try WorkoutText.programWithWarnings(text), aiWorkouts) }
    }

    private var newWorkouts: [PlannedWorkout]? {
        if case .success(let e) = result { return e.workouts }
        return nil
    }

    private var skipped: [String] {
        (parsed?.doubts ?? []).filter { $0.problem != nil && aiWorkouts[$0.key] == nil }.compactMap(\.problem)
    }

    private var wasOnWatch: Bool {
        event.workouts.contains { planner.onWatchIDs.contains($0.id) }
    }

    private func askAI() async {
        aiWorkouts = [:]
        thinking = false
        guard WorkoutAI.isAvailable, let doubts = parsed?.doubts, !doubts.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        thinking = true
        let found = await WorkoutAI.readDoubts(doubts)
        guard !Task.isCancelled else { return }
        aiWorkouts = found
        thinking = false
    }

    // MARK: - Save

    private func save() {
        guard let new = newWorkouts else { return }
        let c = changes
        var updated = event
        updated.workouts = new
        do {
            try store.update(event.name, to: updated)
        } catch {
            saveError = error.localizedDescription
            return
        }
        for w in c.removed { planner.setCustom(w.id, false) }
        if wasOnWatch && updateWatch {
            let oldByID = Dictionary(event.workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let outdated = c.removed + c.changed.compactMap { oldByID[$0.id] }
            let toPut = (c.added + c.changed).filter { !ScheduleDates.isPast($0.date) }
            Task {
                await planner.remove(outdated, time: event.defaultTime, events: store.events)
                if !toPut.isEmpty {
                    await planner.put(toPut, time: event.defaultTime, title: "Schema bijgewerkt", events: store.events)
                }
            }
        }
        dismiss()
    }
}
