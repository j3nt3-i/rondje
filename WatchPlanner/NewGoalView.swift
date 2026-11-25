import SwiftUI
import UIKit

// New goal as a wizard: one question per screen, big choices, a progress bar.
// name -> big day -> how to make the schedule ->
//   with AI: runs per week, level, aim, wishes -> copy prompt -> open AI app -> paste -> review
//   paste:   paste or type -> review
//   later:   review

struct NewGoalView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private enum Step { case name, date, method, perWeek, level, aim, wishes, copy, openApp, paste, review }
    private enum Method { case ai, paste, later }

    @State private var step: Step = .name
    @State private var method: Method = .ai

    // Goal
    @State private var name = ""
    @State private var ownName = false
    @FocusState private var nameFocused: Bool
    @FocusState private var timeFocused: Bool
    @State private var hasDate = true
    @State private var bigDay = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now

    // AI questions (runs per week and level are remembered on this phone)
    @AppStorage("prompt.perWeek") private var perWeek = 3
    @AppStorage("prompt.level") private var level = ""
    @State private var aim = ""
    @State private var aimTime = ""
    @State private var wishes: Set<String> = []
    @State private var ownWish = ""
    @State private var openedApp = false

    // Schedule text and how it reads
    @State private var text = ""
    @State private var reading: Result<(schedule: TrainingSchedule, doubts: [WorkoutText.Doubt]), Error>?
    @State private var isReading = false
    @State private var aiWorkouts: [String: PlannedWorkout] = [:]
    @State private var thinking = false
    @State private var weekStart = WorkoutText.defaultWeekStart()
    @State private var planNow = true
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) { progress }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .name {
                        Button("Annuleer") { dismiss() }
                    } else {
                        Button("Terug", systemImage: "chevron.left") { goBack() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Klaar") { hideKeyboard() }.bold()
                }
            }
            .animation(.snappy, value: step)
            .task(id: "\(text)|\(weekStart)") { await read() }
            .onChange(of: scenePhase) { _, phase in
                // Back from the AI app: the next step is pasting the answer.
                if phase == .active && openedApp && step == .openApp { step = .paste }
            }
        }
    }

    // MARK: - Flow

    private var path: [Step] {
        switch method {
        case .ai: return [.name, .date, .method, .perWeek, .level, .aim, .wishes, .copy, .openApp, .paste, .review]
        case .paste: return [.name, .date, .method, .paste, .review]
        case .later: return [.name, .date, .method, .review]
        }
    }

    private func goNext() {
        hideKeyboard()
        guard let i = path.firstIndex(of: step), i + 1 < path.count else { return }
        step = path[i + 1]
    }

    private func goBack() {
        hideKeyboard()
        guard let i = path.firstIndex(of: step), i > 0 else { return }
        step = path[i - 1]
    }

    private var progress: some View {
        let i = path.firstIndex(of: step) ?? 0
        return HStack(spacing: 5) {
            ForEach(0..<path.count, id: \.self) { k in
                Capsule().fill(k <= i ? Theme.accent : Color(white: 0.25)).frame(height: 5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .accessibilityElement()
        .accessibilityLabel("Stap \(i + 1) van \(path.count)")
    }

    // MARK: - Screens

    @ViewBuilder
    private var content: some View {
        switch step {
        case .name:
            header("Waar train je voor?", "Kies een doel, of geef je eigen wedstrijd een naam.")
            if ownName {
                TextField("Naam van je doel, bijv. Devil's Trail", text: $name)
                    .font(.title3.bold())
                    .focused($nameFocused)
                    .task { nameFocused = true }
                    .submitLabel(.next)
                    .onSubmit { if nameOK { goNext() } }
                    .padding(18)
                    .background(Theme.pill, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent, lineWidth: 2))
            }
            FlowLayout(spacing: 10) {
                ForEach(goalPresets, id: \.title) { g in
                    GoalPill(icon: g.icon, title: g.title, isOn: !ownName && name == g.title) {
                        ownName = false
                        name = g.title
                        nameFocused = false
                    }
                }
                GoalPill(icon: "plus", title: "Anders, namelijk...", isOn: ownName) {
                    if !ownName { name = "" }
                    ownName = true
                    nameFocused = true
                }
            }
            if !trimmedName.isEmpty, store.event(named: trimmedName) != nil {
                Text("Er is al een doel met deze naam. Kies een andere naam.").foregroundStyle(.orange)
            }

        case .date:
            header("Wanneer is de grote dag?", "Rondje telt met je af. Geen vaste dag? Dat kan ook.")
            DatePicker("Datum", selection: $bigDay, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.accent)
                .padding(8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))

        case .method:
            header("Hoe maak je je schema?", "Je kunt het later altijd nog aanpassen.")
            FlowLayout(spacing: 10) {
                GoalPill(icon: "sparkles", title: "Met AI", isOn: method == .ai) { method = .ai }
                GoalPill(icon: "doc.on.clipboard", title: "Zelf plakken of typen", isOn: method == .paste) { method = .paste }
                GoalPill(icon: "clock", title: "Later", isOn: method == .later) { method = .later }
            }
            helper(method == .ai ? "Je beantwoordt een paar vragen. Je eigen AI, zoals Claude of ChatGPT, maakt het schema."
                   : method == .paste ? "Je hebt al een schema, van een trainer, website of AI."
                   : "Je maakt eerst het doel. Trainingen voeg je later toe.")

        case .perWeek:
            header("Hoe vaak wil je lopen?", "Per week.")
            FlowLayout(spacing: 10) {
                ForEach(2...6, id: \.self) { n in
                    GoalPill(title: "\(n)x", isOn: perWeek == n) { perWeek = n }
                }
            }

        case .level:
            header("Wat lukt je nu?", "Hoe ver je loopt, en hoe zwaar dat voelt. Zo begint je schema op het goede niveau.")
            FlowLayout(spacing: 10) {
                ForEach(levels, id: \.title) { l in
                    GoalPill(title: l.title, isOn: level == levelValue(l)) { level = levelValue(l) }
                }
            }
            if let chosen = levels.first(where: { level == levelValue($0) }) {
                helper(chosen.sub)
            }
            ownField("Of vertel het zelf, bijv. 2x per week 6 km, rustig", text: Binding(
                get: { levels.contains { level == levelValue($0) } ? "" : level },
                set: { level = $0 }))

        case .aim:
            header("Wat wil je bereiken?", nil)
            FlowLayout(spacing: 10) {
                ForEach(["Uitlopen", "Een tijd neerzetten", "Sneller worden", "Fit blijven"], id: \.self) { choice in
                    GoalPill(title: choice, isOn: aim == choice) {
                        aim = choice
                        if choice != "Een tijd neerzetten" { timeFocused = false }
                    }
                }
            }
            if aim == "Een tijd neerzetten" {
                TextField("Welke tijd? Bijv. 1:20 of onder de 50 min", text: $aimTime)
                    .font(.title3.bold())
                    .focused($timeFocused)
                    .task { timeFocused = true }
                    .submitLabel(.next)
                    .onSubmit { goNext() }
                    .padding(16)
                    .background(Theme.pill, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent, lineWidth: 2))
            }

        case .wishes:
            header("Nog wensen?", "Kies wat je wilt, of sla deze stap over.")
            FlowLayout(spacing: 10) {
                ForEach(["Lange duurloop in het weekend", "Heuvels", "Geen intervallen", "Rustig opbouwen", "Vaste trainingsdagen"], id: \.self) { w in
                    GoalPill(title: w, isOn: wishes.contains(w)) {
                        if wishes.contains(w) { wishes.remove(w) } else { wishes.insert(w) }
                    }
                }
            }
            ownField("Iets anders, bijv. nooit op woensdag", text: $ownWish)

        case .copy:
            header("Je prompt is klaar", "Kopieer hem. In de volgende stap open je je AI-app.")
            VStack(alignment: .leading, spacing: 10) {
                summaryRow("flag.checkered", trimmedName)
                if hasDate { summaryRow("calendar", Format.day(dayString(bigDay))) }
                summaryRow("figure.run", "\(perWeek)x per week")
                if !level.isEmpty { summaryRow("chart.bar", level) }
                if !aimText.isEmpty { summaryRow("target", aimText) }
                if !wishText.isEmpty { summaryRow("star", wishText) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            DisclosureGroup("Bekijk de prompt") {
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
            .tint(Theme.accent)

        case .openApp:
            bigIcon("arrow.up.forward.app.fill")
            header("Open je AI-app", "De prompt staat op je klembord. Plak hem in je AI-app en verstuur.")
            ForEach(apps, id: \.name) { app in
                bigButton(app.name, "arrow.up.right") {
                    if let url = URL(string: app.url) {
                        openedApp = true
                        openURL(url)
                    }
                }
            }

        case .paste:
            if method == .ai {
                bigIcon("doc.on.clipboard.fill")
                header("Plak het antwoord", "Kopieer het hele antwoord van je AI-app en plak het hier.")
            } else {
                header("Plak je schema", "Met datums, of met weken en dagen. Je kunt het ook typen.")
            }
            PasteButton(payloadType: String.self) { strings in
                guard let s = strings.first, !s.isEmpty else { return }
                Task { @MainActor in
                    text = s
                    step = .review
                }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .tint(Theme.accent)
            .scaleEffect(1.4)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            if method == .paste {
                TextEditor(text: $text)
                    .font(.callout)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            } else {
                Button("Prompt nog een keer kopiëren") { UIPasteboard.general.string = prompt }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }

        case .review:
            reviewScreen
        }
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewScreen: some View {
        header(trimmedName, hasDate ? "De grote dag: \(Format.day(dayString(bigDay)))" : "Geen vaste dag")
        if method == .later {
            Text("Je maakt het doel nu. Trainingen voeg je later toe, met + in het doel.")
                .foregroundStyle(.secondary)
        } else {
            if WorkoutText.usesDayNames(text) {
                DatePicker("Week 1 begint op", selection: $weekStart, displayedComponents: .date)
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            }
            if isReading || thinking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(isReading ? "Schema lezen..." : "Apple Intelligence leest mee...").foregroundStyle(.secondary)
                }
            }
            switch isReading ? nil : result {
            case .success(let e):
                Text("\(e.workouts.count) trainingen").font(.headline)
                if !aiWorkouts.isEmpty {
                    Label("\(aiWorkouts.count) gelezen met Apple Intelligence. Check even of ze kloppen.", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(skipped, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
                VStack(spacing: 0) {
                    ForEach(e.workouts) { w in
                        WorkoutRow(workout: w, kind: WorkoutKind(w, scheduleName: trimmedName, raceDate: hasDate ? dayString(bigDay) : nil),
                                   isPast: ScheduleDates.isPast(w.date))
                            .padding(.vertical, 10)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                Toggle("Meteen op Watch zetten", isOn: $planNow)
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            case .failure(let error) where !thinking:
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button("Opnieuw plakken") { step = .paste }.bold()
            default:
                EmptyView()
            }
        }
        if let saveError {
            Text("Opslaan lukt niet: \(saveError)").foregroundStyle(.orange)
        }
    }

    // MARK: - Bottom button

    @ViewBuilder
    private var bottomBar: some View {
        switch step {
        case .openApp, .paste:
            if step == .openApp {
                Button("Ik heb het antwoord al") { step = .paste }
                    .font(.subheadline.bold())
                    .padding()
            } else {
                EmptyView()
            }
        case .copy:
            bar { bigButton("Kopieer prompt", "doc.on.doc") { UIPasteboard.general.string = prompt; goNext() } }
        case .wishes:
            bar { bigButton(wishes.isEmpty && ownWish.isEmpty ? "Overslaan" : "Volgende", nil) { goNext() } }
        case .date:
            bar {
                VStack(spacing: 10) {
                    bigButton("Volgende", nil) { hasDate = true; goNext() }
                    Button("Nog geen datum") { hasDate = false; goNext() }.font(.subheadline.bold())
                }
            }
        case .review:
            bar { bigButton("Maak doel", "checkmark") { create() }.disabled(!canCreate).opacity(canCreate ? 1 : 0.4) }
        default:
            bar { bigButton("Volgende", nil) { goNext() }.disabled(!canContinue).opacity(canContinue ? 1 : 0.4) }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .name: return nameOK
        case .level: return !level.trimmingCharacters(in: .whitespaces).isEmpty
        case .aim: return !aim.isEmpty
        default: return true
        }
    }

    // MARK: - Pieces

    private func header(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.largeTitle, design: .rounded).bold())
            if let text { Text(text).foregroundStyle(.secondary) }
        }
    }

    private func bigIcon(_ symbol: String) -> some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.15)).frame(width: 120, height: 120)
            Image(systemName: symbol).font(.system(size: 50, weight: .semibold)).foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func levelValue(_ l: (title: String, sub: String)) -> String {
        "\(l.title), \(l.sub.prefix(1).lowercased() + l.sub.dropFirst())"
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .transition(.opacity)
    }

    private let levels: [(title: String, sub: String)] = [
        ("Net begonnen", "Ik loop nog geen 5 km achter elkaar"),
        ("5 km lukt", "Maar het kost nog flink moeite"),
        ("5 km gaat makkelijk", "Ik kan nog wel verder"),
        ("10 km lukt", "Met wat moeite"),
        ("10 km gaat makkelijk", "Ook in een rustig tempo"),
        ("Langer dan 10 km", "Ik loop regelmatig lange afstanden"),
    ]

    private let goalPresets: [(icon: String, title: String)] = [
        ("figure.run", "5 km"),
        ("figure.run", "10 km"),
        ("medal", "Halve marathon"),
        ("trophy", "Marathon"),
        ("mountain.2", "Trailrun"),
        ("sparkles", "Beginnen met hardlopen"),
        ("heart", "Fit blijven"),
    ]

    private func ownField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .padding(16)
            .background(Theme.pill, in: RoundedRectangle(cornerRadius: 18))
    }

    private func summaryRow(_ icon: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Theme.accent) }
    }

    private func bar<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
    }

    private func bigButton(_ title: String, _ icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon { Label(title, systemImage: icon) } else { Text(title) }
            }
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent, in: Capsule())
        }
    }

    private let apps: [(name: String, url: String)] = [
        ("Claude", "https://claude.ai/new"),
        ("ChatGPT", "https://chatgpt.com/"),
        ("Gemini", "https://gemini.google.com/app"),
    ]

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Values

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameOK: Bool { !trimmedName.isEmpty && store.event(named: trimmedName) == nil }

    private func dayString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var aimText: String {
        let time = aimTime.trimmingCharacters(in: .whitespaces)
        return aim == "Een tijd neerzetten" && !time.isEmpty ? "Een tijd neerzetten: \(time)" : aim
    }

    private var wishText: String {
        let own = ownWish.trimmingCharacters(in: .whitespaces)
        return (wishes.sorted() + (own.isEmpty ? [] : [own])).joined(separator: ", ")
    }

    private var prompt: String {
        WorkoutText.claudePrompt(event: trimmedName, raceDate: hasDate ? bigDay : nil, perWeek: perWeek,
                                 level: level, goal: aimText, wishes: wishText)
    }

    // MARK: - Reading the schedule

    private var result: Result<TrainingSchedule, Error>? {
        guard let reading else { return nil }
        return reading.flatMap { p in Result { try WorkoutAI.merge(p, aiWorkouts) } }
    }

    private var skipped: [String] {
        guard case .success(let p) = reading else { return [] }
        return p.doubts.filter { $0.problem != nil && aiWorkouts[$0.key] == nil }.compactMap(\.problem)
    }

    private func read() async {
        aiWorkouts = [:]
        thinking = false
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reading = nil; isReading = false; return }
        isReading = true
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let current = text, start = weekStart
        let r = await Task.detached(priority: .userInitiated) {
            Result { try WorkoutText.programWithWarnings(current, weekStart: start) }
        }.value
        guard !Task.isCancelled else { return }
        reading = r
        isReading = false
        guard WorkoutAI.isAvailable, case .success(let p) = r, !p.doubts.isEmpty else { return }
        thinking = true
        let found = await WorkoutAI.readDoubts(p.doubts)
        guard !Task.isCancelled else { return }
        aiWorkouts = found
        thinking = false
    }

    // MARK: - Create

    private var canCreate: Bool {
        guard nameOK, !isReading, !thinking else { return false }
        if method == .later { return true }
        if case .success = result { return true }
        return false
    }

    private func create() {
        var workouts: [PlannedWorkout] = []
        if method != .later, case .success(let e) = result { workouts = e.workouts }
        let goal = TrainingSchedule(name: trimmedName, defaultTime: "07:00", workouts: workouts,
                                    raceDate: hasDate ? dayString(bigDay) : nil)
        do {
            try store.upsert(goal)
        } catch {
            saveError = error.localizedDescription
            return
        }
        if planNow && !workouts.isEmpty {
            Task { await planner.put(workouts, time: goal.defaultTime, title: "\(goal.name) toegevoegd", events: store.events) }
        }
        dismiss()
    }
}

// MARK: - Goal pill

/// A goal to pick: icon and name in a pill a little lighter than the background; lime when chosen.
struct GoalPill: View {
    var icon: String? = nil
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isOn ? .black : Theme.accent)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isOn ? .black : .primary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(isOn ? Theme.accent : Theme.pill, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(isOn ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(BounceStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Shrinks a little while pressed.
struct BounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Chips that wrap onto new lines

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
