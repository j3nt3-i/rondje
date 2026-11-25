import SwiftUI

// Edit a goal's name and big day.

struct EditEventView: View {
    let original: TrainingSchedule
    var onSave: (_ newName: String) -> Void = { _ in }

    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hasRaceDate = false
    @State private var raceDate = Date()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam", text: $name)
                        .font(.headline)
                    Toggle("De grote dag", isOn: $hasRaceDate.animation())
                    if hasRaceDate {
                        DatePicker("Datum", selection: $raceDate, displayedComponents: .date)
                    }
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Doel wijzigen")
            .keyboardDoneButton()
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
    }

    private func save() {
        var e = original
        e.name = name.trimmingCharacters(in: .whitespaces)
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
