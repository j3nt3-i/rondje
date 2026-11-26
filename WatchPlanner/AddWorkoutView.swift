import SwiftUI

struct AddWorkoutView: View {
    let existingIDs: Set<String>
    /// Names of workouts already planned per day ("2026-12-01"), to show dots and a hint.
    var busyDays: [String: [String]] = [:]
    /// Set to change an existing workout instead of adding one.
    var editing: PlannedWorkout? = nil
    var planNowDefault = true
    let onAdd: (PlannedWorkout, _ planNow: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var name = ""
    @State private var text = ""
    @State private var note = ""
    @State private var planNow = true
    @State private var reading: Result<(workout: PlannedWorkout, usedAI: Bool), Error>?
    @State private var thinking = false
    @State private var filled = false

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
                    dayStrip
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    DatePicker("Andere datum", selection: $date, in: min(today, Calendar.current.startOfDay(for: date))..., displayedComponents: .date)
                    if let names = busyDays[dayString], !names.isEmpty {
                        Label("Deze dag staat al: \(names.joined(separator: ", "))", systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Wanneer · \(Format.day(dayString))")
                }

                Section {
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
                    Text("Schrijf het op zoals je het zou zeggen. Rustig, tempo, hard en sprint worden hartslagzones, en je kunt ook zelf een zone noemen, zoals z2." + (WorkoutAI.unavailableReason.map { " " + $0 } ?? ""))
                }

                Section {
                    TextField("Mag leeg", text: $note, axis: .vertical)
                        .lineLimit(2...8)
                } header: {
                    Text("Uitleg")
                } footer: {
                    Text("Wat je gaat doen en waarom, bijvoorbeeld wat voor heuvel je zoekt. Staat bovenaan bij de training.")
                }

                if result != nil || thinking {
                    Section("Zo wordt hij") {
                        if thinking {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Apple Intelligence leest mee...").foregroundStyle(.secondary)
                            }
                        }
                        switch result {
                        case .success(let w):
                            HStack(spacing: 12) {
                                KindIcon(kind: WorkoutKind(w, scheduleName: nil), size: 36)
                                Text(w.name).font(.headline)
                            }
                            ForEach(w.stepLines) { StepLineView(line: $0) }
                            if case .success(let r) = reading, r.usedAI {
                                Label("Gelezen met Apple Intelligence. Check even of het klopt.", systemImage: "sparkles")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        case .failure(let error):
                            if !thinking {
                                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        case nil:
                            EmptyView()
                        }
                    }
                }

                Section {
                    Toggle("Meteen op Watch zetten", isOn: $planNow)
                        .tint(Theme.accent)
                }
            }
            .navigationTitle(editing == nil ? "Nieuwe training" : "Training wijzigen")
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Voeg toe" : "Bewaar") {
                        if case .success(let w) = result {
                            onAdd(w, planNow)
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(!isValid || thinking)
                }
            }
            .task(id: "\(text)|\(dayString)") { await read() }
            .onAppear(perform: fill)
        }
    }

    /// When editing: start from the workout as it is, in the short text format.
    private func fill() {
        guard !filled else { return }
        filled = true
        planNow = planNowDefault
        guard let w = editing else { return }
        date = ScheduleDates.day(w.date) ?? date
        name = w.name
        note = w.note ?? ""
        text = WorkoutText.written(for: w)
    }

    // MARK: - Day strip

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    private var stripDays: [Date] {
        (0..<28).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stripDays, id: \.self) { day in
                        dayChip(day)
                            .id(day)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: date) { _, new in
                withAnimation { proxy.scrollTo(Calendar.current.startOfDay(for: new), anchor: .center) }
            }
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let cal = Calendar.current
        let selected = cal.isDate(day, inSameDayAs: date)
        let iso = String(format: "%04d-%02d-%02d", cal.component(.year, from: day),
                         cal.component(.month, from: day), cal.component(.day, from: day))
        let busy = !(busyDays[iso] ?? []).isEmpty
        return Button {
            date = day
        } label: {
            VStack(spacing: 3) {
                Text(cal.isDateInToday(day) ? "Vandaag" : Format.shortWeekday(day))
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(cal.component(.day, from: day))")
                    .font(.system(.title3, design: .rounded).bold())
                Circle()
                    .fill(busy ? (selected ? Color.black : Theme.accent) : .clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(selected ? .black : .primary)
            .frame(width: 48, height: 66)
            .background(selected ? Theme.accent : Color(white: 0.17), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.day(iso) + (busy ? ", er staat al een training" : ""))
    }

    // MARK: - Parsing

    private var dayString: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var autoName: String {
        guard case .success(let r) = reading else { return "\(Format.shortWeekday(date)) training" }
        return WorkoutText.autoName(date: dayString, for: r.workout, text: text)
    }

    private var result: Result<PlannedWorkout, Error>? {
        guard let reading else { return nil }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? autoName : name
        return reading.flatMap { r in
            var w = r.workout
            w.name = title
            let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
            w.note = n.isEmpty ? nil : n
            if existingIDs.contains(w.id) {
                return .failure(ScheduleError(message: "Er staat al een training met deze naam op die dag."))
            }
            return .success(w)
        }
    }

    /// Rules right away; when they fail or doubt, Apple Intelligence after a short pause.
    private func read() async {
        thinking = false
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reading = nil; return }
        let rules = Result { try WorkoutText.read(date: dayString, name: "x", text: text) }
        reading = rules.map { ($0.workout, false) }
        if case .success(let r) = rules, !r.unsure { return }
        guard WorkoutAI.isAvailable else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        thinking = true
        let ai = try? await WorkoutAI.workout(date: dayString, name: "x", text: text)
        guard !Task.isCancelled else { return }
        thinking = false
        if let ai, ai.usedAI { reading = .success((ai.workout, true)) }
    }

    private var isValid: Bool {
        if case .success = result { return true }
        return false
    }
}
