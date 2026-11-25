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
        Example(title: "Duurloop", text: "10 km rustig"),
        Example(title: "Intervallen", text: "10 min inlopen, 5 keer 3 min hard met 2 min rustig, uitlopen"),
        Example(title: "Heuvels", text: "15 min inlopen, 6 keer 45 sec heuvel op, 90 sec wandelend terug, uitlopen"),
        Example(title: "Baan", text: "2 km inlopen, 8x 400 m snel met 200 m dribbel, 1 km uitlopen"),
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
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Bijvoorbeeld: 10 min inlopen, 5 keer 3 min hard met 2 min rust, uitlopen")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    if text.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(examples) { ex in
                                    Button(ex.title, systemImage: "sparkle") { text = ex.text }
                                        .font(.footnote)
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                        .tint(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Beschrijf je training")
                } footer: {
                    Text("Schrijf het op zoals je het zou zeggen. Rustig, tempo, hard en sprint worden hartslagzones, en je kunt ook zelf een zone noemen, zoals z2.")
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
        return WorkoutText.autoName(date: dayString, for: w, text: text)
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
