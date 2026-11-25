import SwiftUI

struct AddWorkoutView: View {
    let existingIDs: Set<String>
    let onAdd: (PlannedWorkout, _ planNow: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var name = ""
    @State private var text = ""
    @State private var planNow = true

    private struct Example: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    private let examples = [
        Example(title: "Duurloop", text: "10 km z2"),
        Example(title: "Intervallen", text: "warmup 10 min z2\n5x 3 min z4 / 2 min z2\ncooldown"),
        Example(title: "Heuvels", text: "warmup 15 min z2\n6x 45 sec / 90 sec z2\ncooldown"),
        Example(title: "Baan", text: "warmup 2 km z2\n8x 400 m z4 / 200 m z1\ncooldown"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, in: Calendar.current.startOfDay(for: .now)...,
                               displayedComponents: .date)
                    TextField("Naam (mag leeg)", text: $name, prompt: Text(autoName))
                }

                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("warmup 10 min z2\n5x 3 min z4 / 2 min z2\ncooldown")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Training")
                } footer: {
                    Text("Eén deel per regel. Eenheden: sec, min, km of m. Zone met z1 tot z5. Bij herhalingen is het eerste deel hard en het tweede herstel.")
                }

                Section("Voorbeelden") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(examples) { ex in
                                Button(ex.title) { text = ex.text }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.accent)
                            }
                        }
                    }
                }

                if let result {
                    Section("Zo wordt hij") {
                        switch result {
                        case .success(let w):
                            HStack(spacing: 12) {
                                KindIcon(kind: WorkoutKind(w, scheduleName: nil), size: 36)
                                Text(w.name).font(.headline)
                            }
                            ForEach(w.stepLines) { StepLineView(line: $0) }
                        case .failure(let error):
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Toggle("Meteen op Watch zetten", isOn: $planNow)
                        .tint(Theme.accent)
                }
            }
            .navigationTitle("Nieuwe training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Voeg toe") {
                        if case .success(let w) = result {
                            onAdd(w, planNow)
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
        }
    }

    // MARK: - Parsing

    private var dayString: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var autoName: String {
        guard let w = try? WorkoutText.workout(date: dayString, name: "x", text: text) else {
            return "\(Format.shortWeekday(date)) training"
        }
        return WorkoutText.autoName(date: dayString, for: w)
    }

    private var result: Result<PlannedWorkout, Error>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? autoName : name
        do {
            let w = try WorkoutText.workout(date: dayString, name: title, text: text)
            if existingIDs.contains(w.id) {
                throw ScheduleError(message: "Er staat al een training met deze naam op die dag.")
            }
            return .success(w)
        } catch {
            return .failure(error)
        }
    }

    private var isValid: Bool {
        if case .success = result { return true }
        return false
    }
}
