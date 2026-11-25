import SwiftUI
import UIKit

// Paste a whole program as text (for example from Claude) and turn it into an event.

struct ImportView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var planNow = true
    @State private var promptCopied = false
    @State private var saveError: String?

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
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                } footer: {
                    Text("Kopieer de prompt, plak hem in Claude met je doel eronder, en plak het antwoord hier. JSON werkt ook.")
                }

                if let result {
                    switch result {
                    case .success(let event):
                        preview(event)
                    case .failure(let error):
                        Section {
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
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
                        .disabled(event == nil)
                }
            }
        }
    }

    private func preview(_ event: TrainingSchedule) -> some View {
        Section {
            HStack(spacing: 12) {
                KindIcon(kind: .race)
                VStack(alignment: .leading) {
                    Text(event.name).font(.headline)
                    Text("\(event.workouts.count) trainingen · start \(event.defaultTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.event(named: event.name) != nil {
                Label("Vervangt het bestaande event met deze naam.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ForEach(event.workouts) { w in
                WorkoutRow(workout: w, kind: WorkoutKind(w, scheduleName: event.name),
                           isPast: ScheduleDates.isPast(w.date), onWatch: false)
            }
        } header: {
            Text("Gevonden")
        }
    }

    private var result: Result<TrainingSchedule, Error>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Result { try WorkoutText.program(text) }
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
