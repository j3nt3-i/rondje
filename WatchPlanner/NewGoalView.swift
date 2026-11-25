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
    /// The question as it is being "typed" out, letter by letter.
    @State private var streamed = ""
    @State private var streaming = false

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
    @State private var understanding = false
    @FocusState private var composerFocused: Bool
    /// Things you corrected along the way ("eigenlijk 15 december") and what Rondje changed.
    @State private var corrections: [Correction] = []
    /// After changing an earlier answer, carry on at the question you were on.
    @State private var resumeAt: Step?
    // What you just sent, shown right away while Rondje reads it.
    @State private var pending: String?
    // Rondje already showed it was thinking, so the next question comes without another pause.
    @State private var skipPause = false
    // A half answer Rondje asks more about: "13" (which month?) or "december" (which day?).
    @State private var heldDay: Int?
    @State private var heldMonth: Int?
    // Choices for that follow-up question, shown as pills; tapping one sends it.
    @State private var options: [String] = []
    // A trail answer with only the distance or only the climb: Rondje asks for the other part.
    @State private var trailMissing: TrailPart?
    // An answer Rondje could not use; sending it again means you mean it.
    @State private var doubted: String?
    // "Een tijd neerzetten" was chosen without a time, and Rondje asked which.
    @State private var askedTime = false
    // Your answers exactly as you typed them. Your bubbles show these, never a rewritten version.
    @State private var typedAnswers: [Step: String] = [:]

    private struct Correction: Identifiable {
        let id = UUID()
        let at: Step   // the question you were on when you said it
        let said: String
        let reply: String
    }

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
                        if let off = WorkoutAI.chatOffReason {
                            Label(off, systemImage: "apple.intelligence")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }
                        ForEach(pastSteps, id: \.self) { s in
                            botBubble(question(s))
                            correctionBubbles(at: s)
                            userBubble(typedAnswers[s] ?? answer(s)) { jump(to: s) }
                        }
                        if streaming {
                            botBubble(streamed)
                        } else if botTyping && pending == nil {
                            typingBubble
                        } else {
                            botBubble(question(step))
                            correctionBubbles(at: step)
                            if let pending {
                                userBubble(pending) {}
                                typingBubble
                            } else {
                                suggestions
                                    .transition(.opacity)
                                stepCard
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: botTyping) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: pending) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: streamed) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: streaming) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: isReading) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) {
                if dockReady {
                    dock
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
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
                options = []
                heldDay = nil
                heldMonth = nil
                trailMissing = nil
                doubted = nil
                askedTime = false
                // A short "typing" moment before each question.
                // A moment of "thinking", then the question appears letter by letter.
                streamed = ""
                if skipPause {
                    skipPause = false
                } else {
                    botTyping = true
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                }
                let full = question(step)
                botTyping = false
                streaming = true
                let pause = min(0.018, 0.9 / Double(max(full.count, 1)))
                for i in 1...max(full.count, 1) {
                    guard !Task.isCancelled else { return }
                    streamed = String(full.prefix(i))
                    try? await Task.sleep(for: .seconds(pause))
                }
                streaming = false
                // Keep the keyboard up where you can type an answer.
                composerFocused = typingStep
            }
            .task(id: "\(text)|\(weekStart)") { await read() }
            .task { WorkoutAI.prewarm() }
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
        if let resume = resumeAt, path.contains(resume) {
            resumeAt = nil
            step = resume
        } else {
            resumeAt = nil
            guard let i = path.firstIndex(of: step), i + 1 < path.count else { return }
            step = path[i + 1]
        }
        keepKeyboardOnlyWhenTyping()
    }

    private func goBack() {
        guard let i = path.firstIndex(of: step), i > 0 else { return }
        step = path[i - 1]
        keepKeyboardOnlyWhenTyping()
    }

    /// Back to an earlier question; once answered, the chat carries on where you were.
    private func jump(to s: Step) {
        if let here = path.firstIndex(of: step), let there = path.firstIndex(of: s), there < here {
            resumeAt = resumeAt ?? step
        }
        step = s
        keepKeyboardOnlyWhenTyping()
    }

    /// The keyboard stays open between questions; it only closes for button steps.
    private func keepKeyboardOnlyWhenTyping() {
        if !typingStep { hideKeyboard() }
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
            return trailKm.isEmpty && trailUp.isEmpty ? "Geen probleem, dat zoeken we later uit." : "\(answer(.trail)), helder."
        case .date:
            guard hasDate else { return "Prima, dan houden we het flexibel." }
            let cal = Calendar.current
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: bigDay)).day ?? 0
            // Say the full date back, so you can see it was read right.
            let day = Format.day(dayString(bigDay))
            if n < 21 { return "\(day), nog maar \(n) dagen. We gaan ervoor." }
            if n < 120 { return "\(day), nog \(n) dagen. Mooi op tijd." }
            return "\(day), nog \(n) dagen. Lekker veel tijd om op te bouwen."
        case .method:
            switch method { case .ai: return "Leuk! Ik stel je een paar vragen en maak daar een prompt van. Die kopieer je naar je eigen AI, zoals Claude of ChatGPT. Het antwoord plak je hier terug, en dan zet ik je trainingen klaar."; case .paste: return "Top, dan plak je hem zo hier."; case .later: return "Prima, dan doen we dat later." }
        case .perWeek: return "\(perWeek)x per week, mooi."
        case .level: return "Dank je, dan weet ik waar je staat."
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
        case .method: return "Zal ik je helpen met een schema? Of heb je er al een?"
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
            switch method { case .ai: return "Help me ermee"; case .paste: return "Ik plak of typ het zelf"; case .later: return "Doe ik later" }
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

    /// Rondje's text: no bubble and no icon, like an AI assistant's answer.
    private func botBubble(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 24)
            .padding(.vertical, 4)
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

    /// Corrections you made while on this question, and what Rondje changed.
    @ViewBuilder
    private func correctionBubbles(at s: Step) -> some View {
        ForEach(corrections.filter { $0.at == s }) { c in
            userBubble(c.said) {}
            botBubble(c.reply)
        }
    }

    /// A pulsing dot while Rondje "thinks", like Claude and ChatGPT.
    private var typingBubble: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(Theme.accent)
                .frame(width: 12, height: 12)
                .scaleEffect(0.75 + 0.25 * sin(t * 6))
        }
        .frame(height: 24)
        .padding(.vertical, 4)
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
                        .onSubmit { if canSend && pending == nil && !botTyping && !streaming { Task { await send() } } }
                        .lineLimit(1...(step == .paste ? 8 : 4))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Theme.pill, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                        .onChange(of: composer) { composerError = nil }
                    sendButton(enabled: canSend && pending == nil && !botTyping && !streaming) { Task { await send() } }
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
        if !options.isEmpty {
            ForEach(options, id: \.self) { o in
                GoalPill(title: o, isOn: false) {
                    composer = o
                    Task { await send() }
                }
            }
        } else {
            stepChips
        }
    }

    @ViewBuilder
    private var stepChips: some View {
        switch step {
        case .name:
            ForEach(goalPresets, id: \.title) { g in
                GoalPill(icon: g.icon, title: g.title, isOn: false) { answerName(g.title, preset: true) }
            }
        case .level:
            ForEach(levels, id: \.title) { l in
                GoalPill(title: l.title, isOn: false) { level = levelValue(l); typedAnswers[.level] = nil; goNext() }
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
            GoalPill(title: "Geen wensen", isOn: false) { wishes = []; ownWish = ""; typedAnswers[.wishes] = nil; goNext() }
        case .paste:
            PasteButton(payloadType: String.self) { strings in
                guard let s = strings.first, !s.isEmpty else { return }
                Task { @MainActor in
                    text = s
                    clearComposer()
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
        case .trail: return "Bijv. 15 km, 400 hoogtemeters, of weet ik niet"
        case .date: return "Bijv. 13 december, of nog geen datum"
        case .method: return "Bijv. ja graag, ik heb er al een, of later"
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
        case .copy, .openApp, .review: return false
        default: return true
        }
    }

    /// The chat field stays put while Rondje types, so the keyboard does not close and reopen.
    /// Button steps show their buttons once the question is there.
    private var dockReady: Bool {
        typingStep || (!botTyping && !streaming)
    }

    private var typed: String { composer.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        switch step {
        case .aim: return !typed.isEmpty || !aims.isEmpty
        case .wishes: return !typed.isEmpty || !wishes.isEmpty
        default: return !typed.isEmpty
        }
    }

    /// Reads what was typed. With Apple Intelligence on, it reads every message first: an answer,
    /// a change to an earlier answer ("o nee, ik bedoelde 10 december"), or a question.
    /// The rules then read the values. Without Apple Intelligence the rules do it all.
    private func send() async {
        composerError = nil
        let t = typed
        let raw = composer
        // Your message moves into the chat at once; Rondje "types" while reading it.
        pending = t.isEmpty ? nil : t
        clearComposer()
        defer { pending = nil }
        if step == .paste {
            text = raw
            goNext()
            return
        }
        // Plain answers ("4", "14 december", a goal from the list) need no Apple Intelligence.
        if isPlainAnswer(t) {
            act(on: take(t), said: t)
            return
        }
        if !t.isEmpty, WorkoutAI.isAvailable, let field = NewGoalView.aiFields[step] {
            let earlier = pastSteps.compactMap { s in NewGoalView.aiFields[s].map { ($0, answer(s)) } }
            let turn = await understand { await WorkoutAI.readTurn(t, question: ask(step), current: field, earlier: earlier) } ?? nil
            if let turn {
                let before = step
                await handle(turn, said: t)
                skipPause = step != before
                return
            }
        }
        let here = step
        if let fixed = correct(t) {
            // Changed in place: ask the open question again, so the chat carries on.
            reply(t, step == here ? "\(fixed) \(ask(step))" : fixed)
            return
        }
        // "lopen?" is a question back, not an answer: explain instead of guessing.
        if t.hasSuffix("?") {
            reply(t, explain(step))
            return
        }
        act(on: take(t), said: t)
    }

    /// Moves on after an answer, asks more about a half answer, or explains the question.
    private func act(on taken: Taken, said t: String) {
        switch taken {
        case .ok:
            // With pills chosen, the bubble shows those too, unless this was the answer to a follow-up.
            let pills = (step == .aim && !aims.isEmpty && !askedTime) || (step == .wishes && !wishes.isEmpty)
            typedAnswers[step] = t.isEmpty || pills ? nil : t
            goNext()
        case .ask(let more): reply(t, more)
        case .no: reply(t, explain(step))
        }
    }

    private static let yesNo: [String: String] = [
        "ja": "Ja", "jaa": "Ja", "jep": "Ja", "yes": "Ja", "ja graag": "Ja", "graag": "Ja", "ok": "Ja", "oké": "Ja",
        "okay": "Ja", "prima": "Ja", "goed": "Ja", "is goed": "Ja", "zeker": "Ja",
        "nee": "Nee", "neen": "Nee", "nope": "Nee", "no": "Nee", "niet": "Nee",
    ]

    /// Answers the rules read without doubt, so they go through without waiting.
    private func isPlainAnswer(_ t: String) -> Bool {
        switch step {
        case .name: return goalPresets.contains { $0.title.lowercased() == t.lowercased() }
        case .method: return NewGoalView.yesNo[t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))] != nil
        case .perWeek: return t.range(of: #"^[1-7]\s*(x|keer)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
        case .date: return NewGoalView.date(from: t) != nil || NewGoalView.dayNumber(t) != nil || NewGoalView.monthNumber(t) != nil
        default: return false
        }
    }

    private static let aiFields: [Step: WorkoutAI.Field] = [
        .name: .goalName, .trail: .trail, .date: .raceDate, .method: .scheduleHelp, .perWeek: .runsPerWeek,
        .level: .level, .aim: .aim, .wishes: .wishes,
    ]

    /// Acts on what Apple Intelligence read: answer this question, change an earlier answer, or explain.
    private func handle(_ turn: WorkoutAI.Turn, said t: String) async {
        let target = turn.field.flatMap { f in NewGoalView.aiFields.first { $0.value == f }?.key }
        let gives = turn.kind == .answer || turn.kind == .correction

        // A change to an earlier answer. Without a usable new value, ask that question again.
        if gives, let target, target != step, pastSteps.contains(target) {
            // Read your own words first; for a name or a free answer, the part Apple Intelligence picked out.
            let free: Set<Step> = [.name, .level, .aim, .wishes]
            if let said = change(target, to: free.contains(target) ? [turn.value] : [t, turn.value]) {
                reply(t, "\(said) \(ask(step))")
            } else {
                jump(to: target)
                reply(t, "Geen probleem, dan pas ik dat aan.")
            }
            return
        }
        // An answer to this question. Apple Intelligence sometimes calls "Pizza" or "weet ik nog niet"
        // a question; without a question mark those count as answers.
        let answers = target == step || (target == nil && step == .name)
        let unsure = step == .name || NewGoalView.saysNo(t)
        let asks = turn.kind == .question && (t.contains("?") || !unsure)
        let ok = answers && !asks && (gives || unsure)
        // Nonsense, like "Pizza" as a goal. Sending the same again means you mean it.
        if ok, !turn.fits, turn.kind != .correction, doubted != t {
            doubted = t
            reply(t, "Sorry, daar kom ik niet uit. \(explain(step))")
            return
        }
        if ok {
            // Free answers keep your own words; a name only when Apple Intelligence did not make it up.
            let tries: [String] = switch step {
            case .level, .aim, .wishes: [t]
            case .name: t.lowercased().contains(turn.value.lowercased()) && !turn.value.isEmpty ? [turn.value] : [t]
            default: [t, turn.value].filter { !$0.isEmpty }
            }
            for v in tries {
                let taken = take(v)
                if case .no = taken { continue }
                act(on: taken, said: t)
                return
            }
        }
        reply(t, turn.kind == .other || !turn.fits ? "Sorry, daar kom ik niet uit. \(explain(step))" : explain(step))
    }

    private enum Taken { case ok, no, ask(String) }
    private enum TrailPart { case km, up }

    /// Reads an answer to the current question with the rules. Nothing is guessed:
    /// a half answer ("13", "december", "3 of 4") gets a follow-up question instead.
    private func take(_ t: String) -> Taken {
        switch step {
        case .name:
            let match = goalPresets.first { $0.title.lowercased() == t.lowercased() }
            ownName = match == nil
            name = match?.title ?? t
            return nameOK ? .ok : .no
        case .trail where trailMissing != nil:
            // The follow-up: "weet ik niet" keeps what you said, a number fills the missing part.
            if NewGoalView.saysNo(t) { break }
            let r = NewGoalView.trail(from: t)
            let n = t.split(whereSeparator: { !$0.isNumber && $0 != "," && $0 != "." }).first.map(String.init)
            if trailMissing == .up { guard let up = r.up ?? n else { return .no }; trailUp = up }
            else { guard let km = r.km ?? n else { return .no }; trailKm = km.replacingOccurrences(of: ".", with: ",") }
        case .trail where NewGoalView.saysNo(t):
            trailKm = ""
            trailUp = ""
        case .trail:
            let r = NewGoalView.trail(from: t)
            guard r.km != nil || r.up != nil else { return .no }
            trailKm = r.km ?? ""
            trailUp = r.up ?? ""
            if r.up == nil {
                trailMissing = .up
                return .ask("En hoeveel hoogtemeters heeft hij? Weet je het niet, ook goed.")
            }
            if r.km == nil {
                trailMissing = .km
                return .ask("En hoeveel kilometer is hij?")
            }
        case .date where NewGoalView.saysNo(t):
            hasDate = false
        case .date:
            if let d = NewGoalView.date(from: t) ?? NewGoalView.dateInText(t) {
                bigDay = d
                hasDate = true
                break
            }
            let day = NewGoalView.dayNumber(t) ?? heldDay
            let month = NewGoalView.monthNumber(t) ?? heldMonth
            switch (day, month) {
            case let (d?, m?):
                guard let date = NewGoalView.date(from: "\(d) \(NewGoalView.months[m - 1])") else { return .no }
                bigDay = date
                hasDate = true
            case let (d?, nil):
                heldDay = d
                let next = NewGoalView.nextDays(d, count: 2)
                guard next.count == 2 else { return .no }
                options = next.map { "\(d) \(NewGoalView.months[Calendar.current.component(.month, from: $0) - 1])" }
                return .ask("Welke \(d)e bedoel je? \(Format.day(dayString(next[0]))) of \(Format.day(dayString(next[1])).lowercased())?")
            case let (nil, m?):
                heldMonth = m
                return .ask("Welke dag in \(NewGoalView.months[m - 1]) precies?")
            default:
                return .no
            }
        case .method:
            let l = t.lowercased()
            // "Zal ik je helpen? Of heb je er al een?" asks two things, so a bare ja or nee is unclear.
            let bare = l.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if let word = NewGoalView.yesNo[bare] {
                options = ["Help me ermee", "Ik heb er al een", "Doe ik later"]
                return .ask("Sorry, ik stelde twee vragen tegelijk. Wil je hulp met een schema, of heb je er al een?")
            }
            if ["heb er al", "heb al", "heb ik al", "zelf", "plak", "typ"].contains(where: l.contains) { method = .paste }
            else if ["later", "nee", "nog niet", "niet nu"].contains(where: l.contains) { method = .later }
            else if ["ja", "graag", "help", "maak", "ai", "claude", "chatgpt", "prima", "oké", "ok"].contains(where: l.contains) { method = .ai }
            else { return .no }
        case .perWeek:
            let numbers = Set(t.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { (1...7).contains($0) })
            if numbers.count > 1 {
                let both = numbers.sorted()
                options = both.map { "\($0)x per week" }
                return .ask("Wordt het \(both.map(String.init).joined(separator: " of ")) keer per week? Je kunt het later altijd nog aanpassen.")
            }
            guard let n = NewGoalView.count(from: t), (1...7).contains(n) else { return .no }
            perWeek = n
        case .level:
            level = t
        case .aim where askedTime:
            // The answer to "welke tijd?" is the time, in your own words.
            guard !t.isEmpty else { return .no }
            aimTime = t
        case .aim:
            if let time = t.range(of: #"\d{1,2}[:.]\d{2}(?:[:.]\d{2})?|\d+\s*(?:uur|u)\b(?:\s*\d+)?|\d+\s*min(?:uten)?"#,
                                  options: .regularExpression) {
                aims.insert("Een tijd neerzetten")
                aimTime = String(t[time])
                let rest = t.replacingCharacters(in: time, with: "").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                ownAimOn = !rest.isEmpty
                ownAim = rest
            } else {
                ownAimOn = !t.isEmpty
                ownAim = t
            }
            if aims.contains("Een tijd neerzetten"), aimTime.trimmingCharacters(in: .whitespaces).isEmpty {
                askedTime = true
                return .ask("Welke tijd wil je neerzetten? Typ bijvoorbeeld 1:55 of onder de 2 uur.")
            }
        case .wishes:
            ownWish = t
        default:
            return .no
        }
        return .ok
    }

    /// "Oeps, het is eigenlijk 15 december": changes an earlier answer and stays on this question.
    /// Returns what Rondje says back, or nil when this is not a correction of an earlier answer.
    private func correct(_ t: String) -> String? {
        let l = t.lowercased()
        let markers = ["eigenlijk", "oeps", "verkeerd", "fout", "klopt niet", "toch", "sorry", "verander", "aanpassen", "moet zijn"]
        guard markers.contains(where: l.contains) else { return nil }
        let done = Set(pastSteps)

        if done.contains(.date), let d = NewGoalView.dateInText(t) {
            bigDay = d
            hasDate = true
            return "Helemaal goed, de grote dag is nu \(Format.day(dayString(d)).lowercased())."
        }
        if done.contains(.perWeek), l.contains("week"), let n = NewGoalView.count(from: t), (1...7).contains(n) {
            perWeek = n
            return "Helemaal goed, ik heb het aangepast naar \(n)x per week."
        }
        if done.contains(.trail), isTrail {
            let r = NewGoalView.trail(from: t)
            if r.km != nil || r.up != nil {
                if let km = r.km { trailKm = km }
                if let up = r.up { trailUp = up }
                return "Helemaal goed, ik heb het aangepast naar \(answer(.trail))."
            }
        }
        if done.contains(.name), let m = l.range(of: #"(?:heet|naam is|noem het)\s+(?:eigenlijk\s+)?"#, options: .regularExpression),
           m.upperBound < l.endIndex {
            let new = String(t[m.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !new.isEmpty else { return nil }
            ownName = goalPresets.first { $0.title.lowercased() == new.lowercased() } == nil
            name = goalPresets.first { $0.title.lowercased() == new.lowercased() }?.title ?? new
            return "Helemaal goed, je doel heet nu \(trimmedName)."
        }

        // "De datum klopt niet" without a new date: ask that question again, then carry on here.
        if let target = topics.first(where: { done.contains($0.0) && $0.1.contains(where: l.contains) })?.0 {
            jump(to: target)
            return "Geen probleem, dan pas ik dat aan."
        }
        return nil
    }

    private let topics: [(Step, [String])] = [
        (.date, ["datum", "dag", "wanneer"]),
        (.perWeek, ["per week", "hoe vaak", "keer"]),
        (.name, ["naam", "heet"]),
        (.trail, ["afstand", "hoogte", "kilometer"]),
        (.level, ["niveau", "lukt"]),
        (.aim, ["bereiken"]),
        (.wishes, ["wens"]),
    ]

    /// Puts a new value in an earlier answer, trying each text in turn ("4" from Apple Intelligence,
    /// then your own words). Nil when none can be read, or nothing changes.
    private func change(_ s: Step, to values: [String]) -> String? {
        for v in values where !v.isEmpty {
            if let said = change(s, to: v) { return said }
        }
        return nil
    }

    private func change(_ s: Step, to value: String) -> String? {
        let before = answer(s)
        switch s {
        case .date:
            guard let d = NewGoalView.date(from: value) ?? NewGoalView.dateInText(value) else { return nil }
            bigDay = d
            hasDate = true
        case .perWeek:
            guard let n = NewGoalView.count(from: value), (1...7).contains(n) else { return nil }
            perWeek = n
        case .trail:
            let r = NewGoalView.trail(from: value)
            guard r.km != nil || r.up != nil else { return nil }
            if let km = r.km { trailKm = km }
            if let up = r.up { trailUp = up }
        case .name:
            let match = goalPresets.first { $0.title.lowercased() == value.lowercased() }
            ownName = match == nil
            name = match?.title ?? value
        case .level:
            level = value
        case .aim:
            ownAimOn = true
            ownAim = value
        case .wishes:
            ownWish = value
        default:
            return nil
        }
        guard answer(s) != before else { return nil }
        switch s {
        case .date: return "Helemaal goed, de grote dag is nu \(answer(.date).lowercased())."
        case .name: return "Helemaal goed, je doel heet nu \(trimmedName)."
        default: return "Helemaal goed, ik heb het aangepast: \(answer(s))."
        }
    }

    /// Empties the chat field, and again just after: the keyboard's autocorrect can put the
    /// text back right after sending ("devember" becomes "december").
    private func clearComposer() {
        composer = ""
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            composer = ""
        }
    }

    /// Adds what you said and Rondje's answer to the chat, and stays on this question.
    private func reply(_ said: String, _ answer: String) {
        // Sent with only pills chosen: your bubble shows what you picked.
        let said = said.isEmpty ? self.answer(step) : said
        corrections.append(Correction(at: step, said: said, reply: answer))
        clearComposer()
    }

    /// What Rondje says when you ask back, or when your answer did not fit the question.
    private func explain(_ s: Step) -> String {
        switch s {
        case .name: return "Waar train je voor? Een wedstrijd, een afstand, of gewoon fit blijven. Kies hierboven, of typ bijvoorbeeld Devil's Trail."
        case .trail: return "Hoe lang is je trail, en hoeveel hoogtemeters? Typ bijvoorbeeld 15 km, 400 hoogtemeters, of weet ik niet."
        case .date: return "Op welke dag is je wedstrijd of doel? Typ bijvoorbeeld 13 december, of nog geen datum."
        case .method: return "Ik kan je helpen een schema te maken met je eigen AI, zoals Claude of ChatGPT. Wil je dat, of heb je al een schema? Later mag ook."
        case .perWeek: return "Hoe vaak per week wil je hardlopen? Bijvoorbeeld 3 keer."
        case .level: return "Hoe ver kun je nu lopen, en hoe zwaar voelt dat? Bijvoorbeeld: 5 km lukt, maar het is zwaar."
        case .aim: return "Wat wil je halen? Bijvoorbeeld uitlopen of een tijd neerzetten. Kies er een of meer, of typ het zelf."
        case .wishes: return "Heb je wensen voor je schema? Bijvoorbeeld een lange duurloop in het weekend of nooit op woensdag. Geen wensen mag ook."
        case .paste: return "Plak hier het hele antwoord van je AI-app, met alle trainingen erin."
        default: return "Kies gerust een van de knoppen hieronder."
        }
    }

    /// Shows Rondje typing while Apple Intelligence reads the answer.
    private func understand<T>(_ work: () async -> T) async -> T? {
        guard WorkoutAI.isAvailable else { return nil }
        let outer = understanding
        understanding = true
        defer { if !outer { understanding = false } }
        return await work()
    }

    private func answerName(_ value: String, preset: Bool) {
        let match = goalPresets.first { $0.title.lowercased() == value.lowercased() }
        ownName = match == nil
        name = match?.title ?? value
        guard nameOK else { return }
        typedAnswers[.name] = nil
        clearComposer()
        goNext()
    }

    private let wishChoices = ["Lange duurloop in het weekend", "Heuvels", "Geen intervallen", "Rustig opbouwen", "Vaste trainingsdagen"]

    // MARK: - Reading typed answers

    private static let numberWords: [(String, Int)] = [
        ("een", 1), ("één", 1), ("twee", 2), ("drie", 3), ("vier", 4), ("vijf", 5), ("zes", 6), ("zeven", 7),
    ]

    /// "14 devember" -> "14 december": words close to a month name (one or two letters off).
    static func fixMonthTypos(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false).map { raw in
            let w = String(raw)
            guard w.count >= 5, !months.contains(w), w.allSatisfy(\.isLetter) else { return w }
            let best = months.map { ($0, distance(w, $0)) }.min { $0.1 < $1.1 }
            return best.flatMap { $0.1 <= 2 ? $0.0 : nil } ?? w
        }.joined(separator: " ")
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return row[b.count]
    }

    /// Finds a date inside a sentence: "oeps, het is eigenlijk 15 december".
    /// Only explicit dates count here, not a loose weekday ("lange duurloop toch op zondag").
    static func dateInText(_ text: String, now: Date = .now) -> Date? {
        let l = text.lowercased()
        let patterns = [
            #"\b\d{1,2}\s+(?:jan|feb|mrt|maa|apr|mei|jun|jul|aug|sep|okt|nov|dec)[a-z]*(?:\s+\d{4})?"#,
            #"\b\d{1,2}[-/]\d{1,2}(?:[-/]\d{4})?\b"#,
        ]
        for p in patterns {
            if let r = l.range(of: p, options: .regularExpression), let d = date(from: String(l[r]), now: now) { return d }
        }
        return nil
    }

    /// Something that looks like a number: digits or a number word.
    static func mentionsNumber(_ text: String) -> Bool {
        let l = text.lowercased()
        let words = ["een", "één", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien", "elf", "twaalf",
                     "vijftien", "twintig", "dertig", "veertig", "vijftig", "honderd", "dag", "keer"]
        return l.contains(where: \.isNumber) || words.contains { l.range(of: #"\b\#($0)"#, options: .regularExpression) != nil }
    }

    /// Something that looks like a date: a number, a month or a weekday.
    static func mentionsDate(_ text: String) -> Bool {
        let l = text.lowercased()
        return l.contains(where: \.isNumber) || (months + weekdays).contains { l.contains($0.prefix(3)) }
            || ["morgen", "week", "maand", "kerst", "pasen", "zomer", "winter", "voorjaar", "najaar"].contains(where: l.contains)
    }

    /// "weet ik niet", "nog geen datum", "nee" -> true
    static func saysNo(_ text: String) -> Bool {
        let l = text.lowercased()
        guard !l.contains(where: \.isNumber) else { return false }
        return ["weet ik", "weet niet", "geen", "nog niet", "nee", "onbekend"].contains { l.contains($0) }
    }

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

    /// A lone day number: "13", "de 13e", "rond de 13de" -> 13
    static func dayNumber(_ text: String) -> Int? {
        let l = text.lowercased()
        guard let re = try? NSRegularExpression(pattern: #"\b(\d{1,2})(?:e|de|ste)?\b"#) else { return nil }
        let found = re.matches(in: l, range: NSRange(l.startIndex..., in: l))
            .compactMap { Range($0.range(at: 1), in: l).flatMap { Int(l[$0]) } }
        guard found.count == 1, l.filter(\.isNumber).count == String(found[0]).count, (1...31).contains(found[0]) else { return nil }
        return found[0]
    }

    /// A month named in the text, with small typos: "half devember" -> 12
    static func monthNumber(_ text: String) -> Int? {
        let words = fixMonthTypos(text.lowercased()).split(whereSeparator: { !$0.isLetter }).map(String.init)
        return months.firstIndex { m in words.contains { $0.count >= 3 && m.hasPrefix($0) } }.map { $0 + 1 }
    }

    /// The next days with this day number: 13 -> 13 december, 13 januari
    static func nextDays(_ day: Int, count: Int, now: Date = .now) -> [Date] {
        let cal = Calendar.current
        var from = cal.startOfDay(for: now)
        var out: [Date] = []
        while out.count < count, let d = cal.nextDate(after: from, matching: DateComponents(day: day), matchingPolicy: .strict) {
            out.append(d)
            from = d
        }
        return out
    }

    static let months = ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus",
                                 "september", "oktober", "november", "december"]
    private static let weekdays = ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"]

    /// "13 december", "13 dec 2026", "13-12-2026", "13/12",
    /// "zaterdag", "volgende week zaterdag" -> the next such day from today
    static func date(from text: String, now: Date = .now) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var t = text.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")
        t = fixMonthTypos(t)
        t = t.replacingOccurrences(of: #"^(?:ergens|rond|rondom|ongeveer|zo'n|op|het is|de race is)\s+"#, with: "", options: .regularExpression)

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
