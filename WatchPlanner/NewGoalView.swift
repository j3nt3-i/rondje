import SwiftUI
import UIKit

// New goal as a conversation: Rondje asks one thing at a time in chat bubbles, your
// answers show up on the right (tap one to change it), and the answer controls sit at the bottom.
// name -> (trail) -> big day -> how to make the schedule ->
//   with AI: runs per week, level, aim, wishes -> copy prompt -> open AI app -> paste -> review
//   paste:   paste or type -> review
//   later:   review

struct NewGoalView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private enum Step { case name, trail, date, method, perWeek, level, aim, wishes, copy, openApp, paste, review }
    private enum Method { case ai, paste, later }

    @State private var step: Step = .name
    @State private var method: Method = .ai
    @State private var botTyping = true

    // Goal
    @State private var name = ""
    @State private var ownName = false
    @State private var trailKm = ""
    @State private var trailUp = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var timeFocused: Bool
    @State private var hasDate = true
    @State private var bigDay = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now

    // AI questions (runs per week and level are remembered on this phone)
    @AppStorage("prompt.perWeek") private var perWeek = 3
    @AppStorage("prompt.level") private var level = ""
    @State private var ownLevel = ""
    @State private var aims: Set<String> = []
    @State private var aimTime = ""
    @State private var ownAimOn = false
    @State private var ownAim = ""
    @FocusState private var ownAimFocused: Bool
    @State private var wishes: Set<String> = []
    @State private var ownWish = ""
    @State private var openedApp = false
    @State private var chosenApp: String?

    // The chat input at the bottom
    @State private var composer = ""
    @State private var composerError: String?
    @State private var showCalendar = false
    @State private var understanding = false
    @FocusState private var composerFocused: Bool

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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(pastSteps, id: \.self) { s in
                            botBubble(question(s))
                            userBubble(answer(s)) { jump(to: s) }
                        }
                        if botTyping || understanding {
                            typingBubble
                        } else {
                            botBubble(question(step))
                            suggestions
                                .padding(.leading, 36)
                                .transition(.opacity)
                            stepCard
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: botTyping) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: isReading) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) {
                if !botTyping && step != .method {
                    dock
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Nieuw doel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !pastSteps.isEmpty {
                        Button("Terug", systemImage: "arrow.uturn.backward") { goBack() }
                    }
                }
            }
            .animation(.snappy, value: step)
            .animation(.snappy, value: botTyping)
            .task(id: step) {
                // A short "typing" moment before each question.
                botTyping = true
                try? await Task.sleep(for: .milliseconds(450))
                botTyping = false
                // Keep the keyboard up where you can type an answer.
                composerFocused = typingStep && !showCalendar
            }
            .task(id: "\(text)|\(weekStart)") { await read() }
            .onChange(of: scenePhase) { _, phase in
                // Back from the AI app: the next step is pasting the answer.
                if phase == .active && openedApp && step == .openApp { step = .paste }
            }
        }
    }

    // MARK: - Flow

    private var path: [Step] {
        let start: [Step] = isTrail ? [.name, .trail, .date, .method] : [.name, .date, .method]
        switch method {
        case .ai: return start + [.perWeek, .level, .aim, .wishes, .copy, .openApp, .paste, .review]
        case .paste: return start + [.paste, .review]
        case .later: return start + [.review]
        }
    }

    private var pastSteps: [Step] {
        guard let i = path.firstIndex(of: step) else { return [] }
        return Array(path.prefix(i))
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

    private func jump(to s: Step) {
        hideKeyboard()
        step = s
    }

    // MARK: - The conversation

    /// The question, with a short reaction to the answer just before it.
    private func question(_ s: Step) -> String {
        guard let i = path.firstIndex(of: s), i > 0, let r = reaction(to: path[i - 1]) else { return ask(s) }
        return r + " " + ask(s)
    }

    /// Warm, fixed reactions that use what you answered.
    private func reaction(to s: Step) -> String? {
        switch s {
        case .name:
            if ownName { return "Mooi, \(trimmedName)!" }
            switch name {
            case "5 km": return "Mooi, 5 km!"
            case "10 km": return "10 km, een klassieker!"
            case "Halve marathon": return "Een halve marathon, stoer!"
            case "Marathon": return "Een marathon, respect!"
            case "Beginnen met hardlopen": return "Leuk dat je begint!"
            case "Fit blijven": return "Fijn doel."
            default: return nil
            }
        case .trail:
            if let up = Int(trailUp), up >= 500 { return "\(up) hoogtemeters, dat wordt klimmen!" }
            return trailKm.isEmpty && trailUp.isEmpty ? "Geen probleem." : "Helder."
        case .date:
            guard hasDate else { return "Prima, dan houden we het flexibel." }
            let cal = Calendar.current
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: bigDay)).day ?? 0
            if n < 21 { return "Nog maar \(n) dagen, we gaan ervoor." }
            if n < 120 { return "Nog \(n) dagen, mooi op tijd." }
            return "Nog \(n) dagen, lekker veel tijd om op te bouwen."
        case .method:
            switch method { case .ai: return "Fijn, dan stel ik je een paar vragen."; case .paste: return "Top."; case .later: return "Prima." }
        case .perWeek: return "\(perWeek)x per week, mooi."
        case .level: return "Duidelijk."
        case .aim:
            let time = aimTime.trimmingCharacters(in: .whitespaces)
            return aims.contains("Een tijd neerzetten") && !time.isEmpty ? "Een tijd van \(time), mooi doel!" : "Mooi."
        default: return nil
        }
    }

    private func ask(_ s: Step) -> String {
        switch s {
        case .name: return "Hoi! Waar train je voor?"
        case .trail: return "Een trail, mooi! Hoe ver is hij, en hoeveel hoogtemeters?"
        case .date: return "Wanneer is de grote dag?"
        case .method: return "Hoe wil je je schema maken?"
        case .perWeek: return "Hoe vaak per week wil je lopen?"
        case .level: return "Wat lukt je nu? En hoe zwaar voelt dat?"
        case .aim: return "Wat wil je bereiken? Kies er gerust meer."
        case .wishes: return "Nog wensen voor je schema?"
        case .copy: return "Je prompt is klaar. Kopieer hem, dan open je zo je AI-app."
        case .openApp: return "Welke AI gebruik je? Plak de prompt daar en verstuur hem."
        case .paste: return method == .ai ? "Plak hier het antwoord als je terug bent." : "Plak of typ hier je schema."
        case .review:
            return method == .later ? "Klaar om je doel te maken. Trainingen voeg je later toe." : "Gelukt! Dit zijn je trainingen."
        }
    }

    private func answer(_ s: Step) -> String {
        switch s {
        case .name: return trimmedName
        case .trail:
            let km = trailKm.trimmingCharacters(in: .whitespaces), up = trailUp.trimmingCharacters(in: .whitespaces)
            let parts = [km.isEmpty ? nil : "\(km) km", up.isEmpty ? nil : "\(up) hoogtemeters"].compactMap { $0 }
            return parts.isEmpty ? "Weet ik nog niet" : parts.joined(separator: ", ")
        case .date: return hasDate ? Format.day(dayString(bigDay)) : "Nog geen datum"
        case .method:
            switch method { case .ai: return "Met AI"; case .paste: return "Ik plak of typ het zelf"; case .later: return "Later" }
        case .perWeek: return "\(perWeek)x per week"
        case .level: return level
        case .aim: return aimText
        case .wishes: return wishText.isEmpty ? "Geen" : wishText
        case .copy: return "Gekopieerd"
        case .openApp: return chosenApp.map { "Ik gebruik \($0)" } ?? "Ik heb het antwoord al"
        case .paste: return method == .ai ? "Geplakt" : "Hier is mijn schema"
        case .review: return ""
        }
    }

    private func botBubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "figure.run")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.pill, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
            Spacer(minLength: 40)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func userBubble(_ text: String, edit: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 60)
            Button(action: edit) {
                Text(text)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.accent, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20))
            }
            .buttonStyle(BounceStyle())
            .accessibilityHint("Tik om dit antwoord te veranderen")
        }
    }

    private var typingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "figure.run")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle().fill(.secondary)
                            .frame(width: 7, height: 7)
                            .opacity(0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.8)))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.pill, in: Capsule())
            Spacer()
        }
        .accessibilityLabel("Rondje typt")
    }

    // MARK: - Cards in the conversation

    @ViewBuilder
    private var stepCard: some View {
        switch step {
        case .copy:
            VStack(alignment: .leading, spacing: 10) {
                summaryRow("flag.checkered", trimmedName)
                if hasDate { summaryRow("calendar", Format.day(dayString(bigDay))) }
                summaryRow("figure.run", "\(perWeek)x per week")
                if !level.isEmpty { summaryRow("chart.bar", level) }
                if !aimText.isEmpty { summaryRow("target", aimText) }
                if !wishText.isEmpty { summaryRow("star", wishText) }
                DisclosureGroup("Bekijk de prompt") {
                    Text(prompt).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 6)
                }
                .tint(Theme.accent)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .padding(.leading, 36)
        case .date where showCalendar:
            VStack(spacing: 10) {
                DatePicker("Datum", selection: $bigDay, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                bigButton("Kies \(Format.day(dayString(bigDay)).lowercased())", "checkmark") {
                    hasDate = true
                    showCalendar = false
                    goNext()
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .padding(.leading, 36)
        case .review:
            reviewCard
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                KindIcon(kind: .race, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goalName).font(.headline)
                    Text(hasDate ? "De grote dag: \(Format.day(dayString(bigDay)))" : "Geen vaste dag")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if method != .later {
                if WorkoutText.usesDayNames(text) {
                    DatePicker("Week 1 begint op", selection: $weekStart, displayedComponents: .date).font(.subheadline)
                }
                if isReading || thinking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(isReading ? "Schema lezen..." : "Apple Intelligence leest mee...").foregroundStyle(.secondary)
                    }
                }
                switch isReading ? nil : result {
                case .success(let e):
                    Text("\(e.workouts.count) trainingen").font(.subheadline.bold())
                    if !aiWorkouts.isEmpty {
                        Label("\(aiWorkouts.count) gelezen met Apple Intelligence. Check even of ze kloppen.", systemImage: "sparkles")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(skipped, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                    }
                    ForEach(e.workouts) { w in
                        WorkoutRow(workout: w, kind: WorkoutKind(w, scheduleName: trimmedName, raceDate: hasDate ? dayString(bigDay) : nil),
                                   isPast: ScheduleDates.isPast(w.date))
                    }
                    Toggle("Meteen op Watch zetten", isOn: $planNow)
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
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.leading, 36)
    }

    // MARK: - Answer controls at the bottom

    /// Most steps: option chips above an always-visible chat field. Action steps keep their buttons.
    @ViewBuilder
    private var dock: some View {
        switch step {
        case .copy:
            bigButton("Kopieer prompt", "doc.on.doc") {
                UIPasteboard.general.string = prompt
                goNext()
            }

        case .openApp:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(apps, id: \.name) { app in
                        Button {
                            if let url = URL(string: app.url) {
                                chosenApp = app.name
                                openedApp = true
                                openURL(url)
                            }
                        } label: {
                            Label(app.name, systemImage: "arrow.up.right")
                                .font(.subheadline.bold())
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent, in: Capsule())
                        }
                        .buttonStyle(BounceStyle())
                    }
                }
                Button("Ik heb het antwoord al") { chosenApp = nil; goNext() }
                    .font(.subheadline.bold())
            }

        case .method:
            EmptyView()

        case .review:
            bigButton("Maak doel", "checkmark") { create() }
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.4)

        default:
            VStack(alignment: .leading, spacing: 10) {
                if let composerError {
                    Text(composerError).font(.footnote).foregroundStyle(.orange)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(placeholder, text: $composer, axis: .vertical)
                        .focused($composerFocused)
                        .submitLabel(.send)
                        .onSubmit { if canSend { Task { await send() } } }
                        .lineLimit(1...(step == .paste ? 8 : 4))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Theme.pill, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                        .onChange(of: composer) { composerError = nil }
                    sendButton(enabled: canSend && !understanding) { Task { await send() } }
                }
            }
        }
    }

    /// Tappable options above the chat field. One-choice steps answer right away;
    /// multi-choice steps toggle, and the send button sends them.
    private var suggestions: some View {
        FlowLayout(spacing: 8) { suggestionChips }
    }

    @ViewBuilder
    private var suggestionChips: some View {
        switch step {
        case .name:
            ForEach(goalPresets, id: \.title) { g in
                GoalPill(icon: g.icon, title: g.title, isOn: false) { answerName(g.title, preset: true) }
            }
        case .trail:
            GoalPill(title: "Weet ik nog niet", isOn: false) { trailKm = ""; trailUp = ""; goNext() }
        case .date:
            GoalPill(icon: "calendar", title: "Kies in kalender", isOn: showCalendar) {
                showCalendar.toggle()
                composerFocused = !showCalendar
            }
            GoalPill(title: "Nog geen datum", isOn: false) { hasDate = false; showCalendar = false; goNext() }
        case .method:
            GoalPill(icon: "sparkles", title: "Met AI", isOn: false) { method = .ai; goNext() }
            GoalPill(icon: "doc.on.clipboard", title: "Zelf plakken of typen", isOn: false) { method = .paste; goNext() }
            GoalPill(icon: "clock", title: "Later", isOn: false) { method = .later; goNext() }
        case .perWeek:
            ForEach(2...6, id: \.self) { n in
                GoalPill(title: "\(n)x", isOn: false) { perWeek = n; goNext() }
            }
        case .level:
            ForEach(levels, id: \.title) { l in
                GoalPill(title: l.title, isOn: false) { level = levelValue(l); goNext() }
            }
        case .aim:
            ForEach(aimChoices, id: \.self) { choice in
                GoalPill(title: choice, isOn: aims.contains(choice)) {
                    if aims.contains(choice) { aims.remove(choice) } else { aims.insert(choice) }
                }
            }
        case .wishes:
            ForEach(wishChoices, id: \.self) { w in
                GoalPill(title: w, isOn: wishes.contains(w)) {
                    if wishes.contains(w) { wishes.remove(w) } else { wishes.insert(w) }
                }
            }
            GoalPill(title: "Geen wensen", isOn: false) { wishes = []; ownWish = ""; goNext() }
        case .paste:
            PasteButton(payloadType: String.self) { strings in
                guard let s = strings.first, !s.isEmpty else { return }
                Task { @MainActor in
                    text = s
                    composer = ""
                    step = .review
                }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .tint(Theme.accent)
            if method == .ai {
                GoalPill(icon: "doc.on.doc", title: "Prompt nog een keer kopiëren", isOn: false) { UIPasteboard.general.string = prompt }
            }
        default:
            EmptyView()
        }
    }

    private var placeholder: String {
        switch step {
        case .name: return "Of typ je eigen doel, bijv. Devil's Trail"
        case .trail: return "Bijv. 15 km, 400 hoogtemeters"
        case .date: return "Bijv. 13 december"
        case .method: return "Kies hierboven"
        case .perWeek: return "Bijv. 4"
        case .level: return "Of vertel het zelf, bijv. 2x per week 6 km"
        case .aim: return aims.contains("Een tijd neerzetten") ? "Welke tijd? Bijv. 1:55" : "Kies hierboven, of typ het zelf"
        case .wishes: return "Kies hierboven, of typ bijv. nooit op woensdag"
        case .paste: return method == .ai ? "Of plak het antwoord hier" : "Plak of typ je schema"
        default: return ""
        }
    }

    /// Steps answered in the chat field; the others are buttons.
    private var typingStep: Bool {
        switch step {
        case .copy, .openApp, .review, .method: return false
        default: return true
        }
    }

    private var typed: String { composer.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        switch step {
        case .aim: return !typed.isEmpty || !aims.isEmpty
        case .wishes: return !typed.isEmpty || !wishes.isEmpty
        default: return !typed.isEmpty
        }
    }

    /// Reads what was typed for the current question. The rules first; for loose answers
    /// ("een uurtje of vijftien km met wat klimmen") Apple Intelligence gets a try.
    private func send() async {
        composerError = nil
        let t = typed
        switch step {
        case .name:
            answerName(t, preset: false)
            return
        case .trail:
            var r = NewGoalView.trail(from: t)
            if r.km == nil && r.up == nil {
                let ai = await understand { await WorkoutAI.readTrail(t) }
                r = (ai?.km.map { String(format: "%g", $0).replacingOccurrences(of: ".", with: ",") }, ai?.up.map(String.init))
            }
            guard r.km != nil || r.up != nil else { composerError = "Dat snap ik niet. Typ bijv. 15 km, 400 hoogtemeters."; return }
            trailKm = r.km ?? ""
            trailUp = r.up ?? ""
        case .date:
            var parsed = NewGoalView.date(from: t)
            if parsed == nil { parsed = await understand { await WorkoutAI.readDate(t) } ?? nil }
            guard let d = parsed else { composerError = "Die datum snap ik niet. Typ bijv. 13 december of 13-12-2026."; return }
            bigDay = d
            hasDate = true
            showCalendar = false
        case .method:
            let l = t.lowercased()
            if l.contains("ai") || l.contains("claude") || l.contains("chatgpt") { method = .ai }
            else if l.contains("later") { method = .later }
            else if l.contains("plak") || l.contains("zelf") || l.contains("typ") { method = .paste }
            else { composerError = "Kies Met AI, Zelf plakken of typen, of Later."; return }
        case .perWeek:
            var parsed = NewGoalView.count(from: t)
            if parsed == nil { parsed = await understand { await WorkoutAI.readCount(t) } ?? nil }
            guard let n = parsed, (1...7).contains(n) else { composerError = "Typ een aantal van 1 tot 7."; return }
            perWeek = n
        case .level:
            level = t
        case .aim:
            if let time = t.range(of: #"\d{1,2}[:.]\d{2}(?:[:.]\d{2})?"#, options: .regularExpression) {
                aims.insert("Een tijd neerzetten")
                aimTime = String(t[time])
                let rest = t.replacingCharacters(in: time, with: "").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                ownAimOn = !rest.isEmpty
                ownAim = rest
            } else {
                ownAimOn = !t.isEmpty
                ownAim = t
            }
        case .wishes:
            ownWish = t
        case .paste:
            text = composer
        default:
            break
        }
        composer = ""
        goNext()
    }

    /// Shows Rondje typing while Apple Intelligence reads the answer.
    private func understand<T>(_ work: () async -> T) async -> T? {
        guard WorkoutAI.isAvailable else { return nil }
        understanding = true
        defer { understanding = false }
        return await work()
    }

    private func answerName(_ value: String, preset: Bool) {
        let match = goalPresets.first { $0.title.lowercased() == value.lowercased() }
        ownName = match == nil
        name = match?.title ?? value
        guard nameOK else { return }
        composer = ""
        goNext()
    }

    private let wishChoices = ["Lange duurloop in het weekend", "Heuvels", "Geen intervallen", "Rustig opbouwen", "Vaste trainingsdagen"]

    // MARK: - Reading typed answers

    private static let numberWords: [(String, Int)] = [
        ("een", 1), ("één", 1), ("twee", 2), ("drie", 3), ("vier", 4), ("vijf", 5), ("zes", 6), ("zeven", 7),
    ]

    /// "4", "4x", "vier keer", "een keer of vier", "om de dag" -> runs per week
    static func count(from text: String) -> Int? {
        let l = text.lowercased()
        if l.contains("elke dag") || l.contains("dagelijks") { return 7 }
        if l.contains("om de dag") || l.contains("om de andere dag") { return 3 }
        if let r = l.range(of: #"\d+"#, options: .regularExpression) { return Int(l[r]) }
        // The first number word, skipping "een" when another one follows ("een keer of vier").
        var found: [(pos: String.Index, n: Int, word: String)] = []
        for (word, n) in numberWords {
            if let r = l.range(of: #"\b\#(word)\b"#, options: .regularExpression) { found.append((r.lowerBound, n, word)) }
        }
        found.sort { $0.pos < $1.pos }
        return (found.first { $0.n != 1 } ?? found.first)?.n
    }

    /// "15 km, 400 hoogtemeters", "15 km", "400 hm" -> (km, up)
    static func trail(from text: String) -> (km: String?, up: String?) {
        let l = text.lowercased().replacingOccurrences(of: ",", with: ".")
        func grab(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)),
                  let r = Range(m.range(at: 1), in: l) else { return nil }
            return String(l[r]).replacingOccurrences(of: ".", with: ",")
        }
        let up = grab(#"(\d+)\s*(?:hm|hoogtemeters?|m\b|meter)"#)
        var km = grab(#"(\d+(?:\.\d+)?)\s*(?:km|k\b|kilometer)"#)
        if km == nil, up == nil { km = grab(#"(\d+(?:\.\d+)?)"#) }
        return (km, up)
    }

    private static let months = ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus",
                                 "september", "oktober", "november", "december"]
    private static let weekdays = ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"]

    /// "13 december", "13 dec 2026", "13-12-2026", "13/12", "half december", "eind januari",
    /// "zaterdag", "volgende week zaterdag" -> the next such day from today
    static func date(from text: String, now: Date = .now) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var t = text.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")
        t = t.replacingOccurrences(of: #"^(?:ergens|rond|rondom|ongeveer|zo'n|op|het is|de race is)\s+"#, with: "", options: .regularExpression)

        // "begin / half / midden / eind <maand>"
        if let m = t.range(of: #"^(begin|half|halverwege|midden|eind|einde)\s+([a-z]+)"#, options: .regularExpression) {
            let parts = t[m].split(separator: " ").map(String.init)
            if let mi = months.firstIndex(where: { $0.hasPrefix(parts[1].prefix(3)) }) {
                var c = DateComponents(year: cal.component(.year, from: today), month: mi + 1, day: 1)
                guard var first = cal.date(from: c) else { return nil }
                if cal.date(byAdding: .month, value: 1, to: first)! <= today { c.year! += 1; first = cal.date(from: c) ?? first }
                let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
                let day = parts[0] == "begin" ? 3 : parts[0].hasPrefix("eind") ? days : 15
                return cal.date(byAdding: .day, value: day - 1, to: first)
            }
        }

        // "zaterdag", "deze zaterdag", "volgende week zaterdag"
        if let wi = weekdays.firstIndex(where: { t.hasSuffix($0) }), !t.contains(where: \.isNumber) {
            let target = (wi + 1) % 7 + 1 // Calendar weekday: Sunday 1, Monday 2
            var d = cal.nextDate(after: today, matching: DateComponents(weekday: target), matchingPolicy: .nextTime) ?? today
            if t.contains("volgende week") {
                let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
                let nextWeek = cal.date(byAdding: .day, value: 7, to: thisWeek) ?? today
                while d < nextWeek { d = cal.date(byAdding: .day, value: 7, to: d) ?? d }
            }
            return d
        }

        t = t.replacingOccurrences(of: #"^(?:maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag|ma|di|wo|do|vr|za|zo)\s+"#,
                                   with: "", options: .regularExpression)
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        for format in ["d MMMM yyyy", "d MMM yyyy", "d-M-yyyy", "d/M/yyyy", "yyyy-M-d"] {
            f.dateFormat = format
            if let d = f.date(from: t) { return cal.startOfDay(for: d) }
        }
        for format in ["d MMMM", "d MMM", "d-M", "d/M"] {
            f.dateFormat = format
            guard let d = f.date(from: t) else { continue }
            var c = cal.dateComponents([.month, .day], from: d)
            c.year = cal.component(.year, from: today)
            guard var date = cal.date(from: c) else { continue }
            if date < today { date = cal.date(byAdding: .year, value: 1, to: date) ?? date }
            return date
        }
        return nil
    }

    // MARK: - Pieces

    private func sendButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: Circle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel("Verstuur")
    }

    private func levelValue(_ l: (title: String, sub: String)) -> String {
        "\(l.title), \(l.sub.prefix(1).lowercased() + l.sub.dropFirst())"
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

    private func summaryRow(_ icon: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Theme.accent) }
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

    private var isTrail: Bool { !ownName && name == "Trailrun" }

    /// "Trailrun" becomes "Trailrun 15 km" once the distance is filled in.
    private var trimmedName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        let km = trailKm.trimmingCharacters(in: .whitespaces)
        return isTrail && !km.isEmpty ? "\(n) \(km) km" : n
    }

    /// Extra lines for the prompt: trail details, and for a named race, ask the AI to look it up.
    private var details: String {
        var lines: [String] = []
        if isTrail { lines.append(trailDetails) }
        if ownName && !trimmedName.isEmpty {
            lines.append("Zoek de datum, afstand en hoogtemeters van \(trimmedName) op als je die niet weet, en houd daar rekening mee in het schema.")
        }
        return lines.joined(separator: "\n")
    }

    /// "Het is een trailrun van 15 km met 400 hoogtemeters."
    private var trailDetails: String {
        let km = trailKm.trimmingCharacters(in: .whitespaces), up = trailUp.trimmingCharacters(in: .whitespaces)
        switch (km.isEmpty, up.isEmpty) {
        case (false, false): return "Het is een trailrun van \(km) km met \(up) hoogtemeters."
        case (false, true): return "Het is een trailrun van \(km) km."
        case (true, false): return "Het is een trailrun met \(up) hoogtemeters."
        default: return "Het is een trailrun."
        }
    }

    private func numberField(_ label: String, _ placeholder: String, unit: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.bold()).foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(placeholder, text: text)
                    .font(.title2.bold())
                    .keyboardType(keyboard)
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.pill, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
    private var nameOK: Bool { !trimmedName.isEmpty }

    /// The name to save: made unique when that name is taken, with the big day or a number.
    private var goalName: String {
        let base = trimmedName
        guard store.event(named: base) != nil else { return base }
        if hasDate {
            let withDay = "\(base) \(Format.shortDay(dayString(bigDay)).split(separator: " ").dropFirst().joined(separator: " "))"
            if store.event(named: withDay) == nil { return withDay }
        }
        var n = 2
        while store.event(named: "\(base) \(n)") != nil { n += 1 }
        return "\(base) \(n)"
    }

    private func dayString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private let aimChoices = ["Uitlopen", "Een tijd neerzetten", "Sneller worden", "Fit blijven"]

    /// "Uitlopen, Een tijd neerzetten: 1:20, plezier houden"
    private var aimText: String {
        let time = aimTime.trimmingCharacters(in: .whitespaces)
        var parts = aimChoices.filter { aims.contains($0) }.map { choice in
            choice == "Een tijd neerzetten" && !time.isEmpty ? "\(choice): \(time)" : choice
        }
        let own = ownAim.trimmingCharacters(in: .whitespacesAndNewlines)
        if ownAimOn && !own.isEmpty { parts.append(own) }
        return parts.joined(separator: ", ")
    }

    private var wishText: String {
        let own = ownWish.trimmingCharacters(in: .whitespaces)
        return (wishes.sorted() + (own.isEmpty ? [] : [own])).joined(separator: ", ")
    }

    private var prompt: String {
        WorkoutText.claudePrompt(event: trimmedName, raceDate: hasDate ? bigDay : nil, perWeek: perWeek,
                                 level: level, goal: aimText, wishes: wishText, details: details)
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
        let goal = TrainingSchedule(name: goalName, defaultTime: "07:00", workouts: workouts,
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
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isOn ? .black : Theme.accent)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? .black : .primary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
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

// MARK: - Radio row

/// One choice of a few, with a short explanation: a radio circle, title and text.
struct RadioRow: View {
    let icon: String
    let title: String
    let text: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().strokeBorder(isOn ? Theme.accent : Color(white: 0.45), lineWidth: 2)
                    if isOn { Circle().fill(Theme.accent).padding(5) }
                }
                .frame(width: 24, height: 24)
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.pill, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isOn ? Theme.accent : .white.opacity(0.08), lineWidth: isOn ? 2 : 1))
        }
        .buttonStyle(BounceStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
