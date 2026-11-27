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
    @Environment(HealthLog.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    // What Apple Health shows about your running. Only kept while this chat is open, never stored.
    @State private var healthLevel: RunLevel?
    // It was there before Rondje asked for your level, so the question itself shows it.
    @State private var healthFirst: RunLevel?
    // "Gebruik dit niet": Apple Health stays out of your prompt.
    @State private var skipHealth = false
    // Rondje looked and found nothing, so it does not offer to look again.
    @State private var healthEmpty = false
    @State private var ownAim = ""
    @State private var aimTime = ""
    @State private var wantsTime = false   // you want a time and Rondje asked which
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
    // Questions you already answered inside another answer ("Polar Bear Trail op 10 januari"):
    // Rondje says what it read and does not ask them again.
    @State private var answeredAlong: Set<Step> = []

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
    @State private var saveError: String?
    // Your pasted text turning into workouts, one by one.
    @State private var sources: [String: String] = [:]   // workout id -> the lines it came from
    @State private var morphedText: String?              // the pasted text that is done turning
    @State private var morphed = 0                       // workouts counted as turned so far
    @State private var sweep: CGFloat = 0                // how far down the layer of cards has come
    @State private var sweeping = false                  // the lime edge of that layer shows
    @State private var listHeight: CGFloat = 0           // the part of the list you can see
    @ScaledMetric(relativeTo: .headline) private var rowHeight: CGFloat = 88
    // The show after pasting: the chat field grows to the whole screen and your schedule
    // turns into workouts there.
    private enum ShowPhase { case off, bubble, blocks, done }
    @State private var show: ShowPhase = .off
    @State private var showWorkouts: [PlannedWorkout] = []   // read right at pasting, for the parts on screen
    @State private var showRun = 0                  // counts pastes, so the same text can run again
    @State private var showStarted = Date()
    @State private var skipShow = false
    @State private var neutral = false              // the panel is up and its lime glow is on
    @State private var landed = false               // your schedule's parts have slid in
    @State private var readText: String?            // the text the last reading belongs to

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
                        ForEach(pastSteps.filter { !answeredAlong.contains($0) }, id: \.self) { s in
                            botBubbles(question(s), at: s)
                            correctionBubbles(at: s)
                            userBubble(typedAnswers[s] ?? answer(s)) { jump(to: s) }
                        }
                        if streaming {
                            botBubbles(streamed, at: step)
                        } else if botTyping && pending == nil {
                            typingBubble
                        } else {
                            botBubbles(question(step), at: step)
                            correctionBubbles(at: step)
                            if step == .review { readingStatus }
                            if let pending {
                                userBubble(pending) {}
                                typingBubble
                            } else {
                                suggestions
                                    .transition(.opacity)
                                stepCard
                                if step == .review { reviewResult }
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
                // An answer that came from a pill, like "Kijk in Apple Health": down to what Rondje says back.
                .onChange(of: corrections.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: streamed) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: streaming) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: isReading) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: morphedText) {
                    // The show is over: down to the result.
                    withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
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
                // The reaction is its own message: a short beat before the question starts.
                let reactionLength = path.firstIndex(of: step).flatMap { $0 > 0 ? reaction(to: path[$0 - 1]) : nil }?.count
                for i in 1...max(full.count, 1) {
                    guard !Task.isCancelled else { return }
                    streamed = String(full.prefix(i))
                    try? await Task.sleep(for: .seconds(i == reactionLength ? 0.45 : pause))
                }
                streaming = false
                // Keep the keyboard up where you can type an answer.
                composerFocused = typingStep
            }
            .task(id: "\(text)|\(weekStart)") { await read() }
            .task { WorkoutAI.prewarm() }
            .task {
                // Only while the question is still to come: a question on screen never changes under you,
                // and nothing goes into your prompt that Rondje has not shown you.
                guard let found = await health.level(), step != .level, !pastSteps.contains(.level) else { return }
                healthLevel = found
                healthFirst = found
            }
            .task(id: morphTrigger) { await runShow() }
            .onChange(of: scenePhase) { _, phase in
                // Back from the AI app: the next step is pasting the answer.
                if phase == .active && openedApp && step == .openApp { step = .paste }
            }
        }
        .overlay { showOverlay }
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
            guard let i = path.firstIndex(of: step),
                  let next = path[(i + 1)...].first(where: { !answeredAlong.contains($0) }) else { return }
            step = next
        }
        keepKeyboardOnlyWhenTyping()
    }

    private func goBack() {
        guard let i = path.firstIndex(of: step),
              let before = path[..<i].last(where: { !answeredAlong.contains($0) }) else { return }
        step = before
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
    /// Rondje's reaction to your last answer and the next question, as two messages,
    /// so a longer reaction never hides the question. Works on a half-streamed text too.
    @ViewBuilder
    private func botBubbles(_ text: String, at s: Step) -> some View {
        if let i = path.firstIndex(of: s), i > 0, let r = reaction(to: path[i - 1]), text.hasPrefix(r) {
            botBubble(r)
            if text.count > r.count + 1 {
                botBubble(String(text.dropFirst(r.count + 1)))
                    .transition(.opacity)
            }
        } else {
            botBubble(text)
        }
    }

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
            // When it came along with your goal, say both: the name and the day.
            let day = answeredAlong.contains(.date)
                ? "\(trimmedName.prefix(1).uppercased() + trimmedName.dropFirst()) op \(Format.day(dayString(bigDay)).lowercased())"
                : Format.day(dayString(bigDay))
            if n < 21 { return "\(day), nog maar \(n) dagen. We gaan ervoor." }
            if n < 120 { return "\(day), nog \(n) dagen. Mooi op tijd." }
            return "\(day), nog \(n) dagen. Lekker veel tijd om op te bouwen."
        case .method:
            switch method { case .ai: return "Leuk! Ik stel je een paar vragen en maak daar een prompt van. Die kopieer je naar je eigen AI, zoals Claude of ChatGPT. Het antwoord plak je hier terug, en dan zet ik je trainingen klaar."; case .paste: return "Top, dan plak je hem zo hier."; case .later: return "Prima, dan doen we dat later." }
        case .perWeek: return "\(perWeek)x per week, mooi."
        case .level: return "Dank je, dan weet ik waar je staat."
        case .aim:
            let time = aimTime.trimmingCharacters(in: .whitespaces)
            if !time.isEmpty { return "\(time), mooi doel!" }
            return wantsTime ? "Prima, een tijd kun je later nog kiezen." : "Mooi doel!"
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
        case .level:
            // Rondje says what it read, so you can see it and say whether it still holds.
            if let healthFirst { return "In Apple Health zie ik dit. \(healthFirst.said) \(NewGoalView.healthCheck)" }
            return "Wat lukt je nu? En hoe zwaar voelt dat?"
        case .aim: return "Wat wil je bereiken? Bijvoorbeeld uitlopen, een tijd neerzetten of sneller worden."
        case .wishes: return "Nog wensen voor je schema? Bijvoorbeeld een lange duurloop in het weekend, heuvels, of nooit op woensdag."
        case .copy: return "Je prompt is klaar. Kopieer hem, dan open je zo je AI-app."
        case .openApp: return "Welke AI gebruik je? Plak de prompt daar en verstuur hem."
        case .paste: return method == .ai ? "Plak hier het antwoord als je terug bent." : "Plak of typ hier je schema."
        case .review:
            return method == .later ? "Klaar om je doel te maken. Trainingen voeg je later toe." : "Dank je! Ik ga je schema lezen."
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
        case .level: return level.isEmpty && measured != nil ? "Klopt" : level
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
                    .font(text.count > 200 ? .callout : .body)
                    .lineLimit(text.count > 200 ? 8 : nil) // a pasted schedule: Rondje shows it whole below
                    .multilineTextAlignment(.leading)
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
                if let measured { summaryRow("heart", measured.short) }
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

    private var morphDone: Bool { morphedText == text }

    /// Set once the pasted text is read: starts the text turning into workouts.
    private var morphTrigger: String {
        step == .review && method != .later && reading != nil && readText == text && !isReading && !thinking
            ? "\(showRun)|\(text)" : ""
    }

    /// Right when you paste: an empty black panel grows up from the bottom edge to the whole
    /// screen. Only when it is there does your schedule slide in, already in parts per workout.
    /// Nothing of the pasted text shows before that, in the chat or on the panel.
    private func startShow() {
        showRun += 1
        morphedText = nil
        guard !reduceMotion else { return }
        // Read at once, so the parts are there while the screen grows. Not a schedule: the chat says so.
        guard let parsed = try? WorkoutText.programWithSources(text, weekStart: weekStart),
              !parsed.schedule.workouts.isEmpty else { return }
        sources = parsed.sources
        showWorkouts = parsed.schedule.workouts
        composerFocused = false
        morphed = 0
        sweep = 0
        sweeping = false
        skipShow = false
        neutral = false
        landed = false
        showStarted = .now
        show = .bubble
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.spring(duration: 0.5, bounce: 0)) { show = .blocks }
            // The panel is up: now the glow, the header and your schedule come in.
            try? await Task.sleep(for: .milliseconds(460))
            withAnimation(.easeOut(duration: 0.5)) { neutral = true }
            landed = true // each part animates in with its own small delay
        }
    }

    /// Once the text is read: a layer of workout cards comes down over your text in one
    /// smooth pass, top to bottom. Halfway, the top is cards and the bottom still text.
    /// It ends with the button to add the goal. Tap to skip.
    private func runShow() async {
        guard !morphTrigger.isEmpty, morphedText != text else { return }
        guard case .success(let e) = result, !e.workouts.isEmpty else {
            // The chat says what went wrong, with a button to paste again.
            withAnimation(.easeInOut(duration: 0.35)) {
                show = .off
                morphedText = text
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard show != .off else {
            withAnimation(.snappy) { morphedText = text }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        let n = e.workouts.count
        morphed = 0
        // The screen has grown and your schedule has landed: a moment to take it in.
        await showPause(max(0, 2.1 - Date().timeIntervalSince(showStarted)))
        // The layer comes all the way down, past the last row. A list longer than the
        // screen scrolls along, so you see every workout turn.
        func rowEnd(_ i: Int) -> CGFloat { Self.listTop + CGFloat(i) * rowHeight + CGFloat(i - 1) * Self.rowGap }
        let end = rowEnd(n) + 30
        let long = listHeight > 0 && listContentHeight(n) > listHeight
        // More workouts take longer, but not in step: the first ones go slowly, the rest faster.
        let duration = min(9, max(1.8, 1.2 * Double(n).squareRoot()))
        if !skipShow, show != .off {
            let c = Self.sweepCurve
            sweeping = true
            withAnimation(.timingCurve(c.x1, c.y1, c.x2, c.y2, duration: duration)) { sweep = end }
            // Count along, each time the edge passes the end of a row.
            let tap = UIImpactFeedbackGenerator(style: .soft)
            let started = Date()
            for i in 1...n {
                let at = duration * Self.sweepTime(for: Double(rowEnd(i) / end))
                await showPause(max(0, at - Date().timeIntervalSince(started)))
                if skipShow || Task.isCancelled || show == .off { break }
                withAnimation(.snappy(duration: 0.2)) { morphed = i }
                tap.impactOccurred(intensity: 0.45)
            }
            await showPause(max(0, duration - Date().timeIntervalSince(started)))
        }
        if Task.isCancelled { show = .off; return }
        guard show != .off else { return }
        // All made. The list stays where the edge ended: at the last workout.
        let cutShort = skipShow
        withAnimation(.easeInOut(duration: 0.3)) {
            sweep = end
            sweeping = false
            morphed = .max
        }
        // Skipped halfway through a long list: let it run on to the end first.
        if cutShort && long { try? await Task.sleep(for: .seconds(0.3)) }
        if Task.isCancelled { show = .off; return }
        guard show != .off else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
            show = .done
            morphedText = text
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// How high the whole list of rows is.
    private func listContentHeight(_ n: Int) -> CGFloat {
        Self.listTop + CGFloat(n) * rowHeight + CGFloat(max(0, n - 1)) * Self.rowGap + 24
    }

    private static let listTop: CGFloat = 12
    private static let rowGap: CGFloat = 10
    /// The pace of the layer coming down: a slow start, then steady.
    private static let sweepCurve = (x1: 0.4, y1: 0.0, x2: 0.75, y2: 0.8)

    /// The moment (0...1) at which the layer, on its curve, has come this far (0...1).
    private static func sweepTime(for progress: Double) -> Double {
        func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        for i in 0...400 {
            let s = Double(i) / 400
            if bezier(s, sweepCurve.y1, sweepCurve.y2) >= progress { return bezier(s, sweepCurve.x1, sweepCurve.x2) }
        }
        return 1
    }

    /// The cross: closes the screen, back to the chat with everything that was read.
    private func closeShow() {
        skipShow = true
        withAnimation(.easeInOut(duration: 0.35)) {
            show = .off
            sweeping = false
            if reading != nil, !isReading, !thinking { morphedText = text }
        }
    }

    /// A pause in the show, skipped when you tapped to skip.
    private func showPause(_ seconds: Double) async {
        guard !skipShow else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// The workouts on the show screen: as read at pasting, then as finally read.
    private var showList: [PlannedWorkout] {
        if readText == text, !isReading, case .success(let e) = result { return e.workouts }
        return showWorkouts
    }

    /// The full-screen show, growing out of the chat field.
    @ViewBuilder
    private var showOverlay: some View {
        if show != .off {
            GeometryReader { outer in
                GeometryReader { g in
                    // The panel is as wide as the screen and stands on its bottom edge:
                    // it starts with no height and grows straight up.
                    let grown = show != .bubble
                    let f = grown
                        ? CGRect(origin: .zero, size: g.size)
                        : CGRect(x: 0, y: g.size.height, width: g.size.width, height: 0)
                    showContent(grown: grown, size: f.size, full: g.size, insets: outer.safeAreaInsets)
                        .position(x: f.midX, y: f.midY)
                }
                .ignoresSafeArea()
            }
            .transition(.opacity)
        }
    }

    /// The growing panel: plain black, nothing on it while it grows. The screen's content has
    /// its full size and final place from the start (it hangs on the panel's fixed bottom edge),
    /// so nothing moves or reflows; it only comes in once the panel is up.
    private func showContent(grown: Bool, size: CGSize, full: CGSize, insets: EdgeInsets) -> some View {
        let done = show == .done
        let corner: CGFloat = grown ? 0 : 28
        return Rectangle()
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .topLeading) {
                    // A soft lime glow at the top, like the launch video.
                    RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
                        .opacity(neutral ? 1 : 0)
                        .allowsHitTesting(false)
                    showScreen(insets: insets)
                }
                .frame(width: full.width, height: full.height, alignment: .topLeading)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner))
            .contentShape(Rectangle())
            .onTapGesture { if !done { skipShow = true } }
            .accessibilityLabel(done ? "" : "Rondje maakt je trainingen. Tik om over te slaan.")
    }

    /// The screen itself: progress, your schedule in parts turning into cards, and the end.
    private func showScreen(insets: EdgeInsets) -> some View {
        let workouts = showList
        let done = show == .done
        let count = min(morphed, workouts.count)
        return VStack(alignment: .leading, spacing: 0) {
            // Header: what happens, and how far along.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "sparkles")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, isActive: !done)
                    Text(done ? "\(workouts.count) trainingen klaar" : "Trainingen maken")
                        .font(.title2.bold())
                        .contentTransition(.opacity)
                    Spacer()
                    Button(action: closeShow) {
                        Image(systemName: "xmark")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Sluit")
                }
                GeometryReader { bar in
                    Capsule().fill(.white.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accent)
                                .frame(width: bar.size.width * (workouts.isEmpty ? 0 : CGFloat(count) / CGFloat(workouts.count)))
                                .shadow(color: Theme.accent.opacity(0.6), radius: 6)
                        }
                }
                .frame(height: 4)
                HStack {
                    Text(goalName + (hasDate ? " · \(Format.day(dayString(bigDay)))" : ""))
                        .lineLimit(1)
                    Spacer()
                    if !done {
                        Text("\(count) van \(workouts.count)")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(count)))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, insets.top + 28)
            .padding(.bottom, 6)
            .opacity(landed ? 1 : 0)
            .offset(y: landed ? 0 : 14)
            .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.12), value: landed)

            if done {
                // Made: a list to scroll through and check. A long one starts where the
                // sweep left it, at the last workout.
                ScrollView {
                    cardRows(workouts)
                        .padding(.bottom, 24)
                }
                .defaultScrollAnchor(listHeight > 0 && listContentHeight(workouts.count) > listHeight ? .bottom : .top)
                .scrollIndicators(.hidden)
                .transition(.identity)
            } else {
                // Two layers with the same rows: your text below, the cards on top. The cards
                // show above the edge that comes down, your text below it. A list longer
                // than the screen scrolls along under the edge.
                let most = listHeight > 0 ? max(0, listContentHeight(workouts.count) - listHeight) : 0
                Color.clear
                    .overlay(alignment: .top) {
                        ZStack(alignment: .top) {
                            textRows(workouts)
                                .modifier(SweepLayer(y: sweep, hold: listHeight * 0.55, most: most, height: listHeight, part: .text))
                                .accessibilityHidden(true)
                            cardRows(workouts)
                                .modifier(SweepLayer(y: sweep, hold: listHeight * 0.55, most: most, height: listHeight, part: .cards))
                            sweepEdge
                                .modifier(SweepLayer(y: sweep, hold: listHeight * 0.55, most: most, height: listHeight, part: .edge))
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    .transition(.identity)
            }

            if done {
                showFooter(bottom: insets.bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Your pasted text, one row per workout.
    private func textRows(_ workouts: [PlannedWorkout]) -> some View {
        VStack(spacing: Self.rowGap) {
            ForEach(Array(workouts.enumerated()), id: \.element.id) { i, w in
                sourceText(w)
                    // Your schedule slides in line by line once the screen is open.
                    .opacity(landed ? 1 : 0)
                    .offset(y: landed ? 0 : 22)
                    .animation(.spring(duration: 0.5, bounce: 0.12).delay(0.2 + min(Double(i), 10) * 0.05), value: landed)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, Self.listTop)
    }

    /// The same rows as workout cards.
    private func cardRows(_ workouts: [PlannedWorkout]) -> some View {
        VStack(spacing: Self.rowGap) {
            ForEach(workouts) { w in
                workoutCard(w, height: rowHeight)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, Self.listTop)
    }

    /// The edge of the layer of cards: a lime line with a short trail above it.
    private var sweepEdge: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Theme.accent.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                .frame(height: 44)
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
                .shadow(color: Theme.accent.opacity(0.9), radius: 8)
        }
        .opacity(sweeping ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The end of the show: what to check, and the button that adds the goal.
    private func showFooter(bottom: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !aiWorkouts.isEmpty {
                Label("\(aiWorkouts.count) gelezen met Apple Intelligence. Check even of ze kloppen.", systemImage: "sparkles")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(skipped, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
            if WorkoutText.usesDayNames(text) {
                DatePicker("Week 1 begint op", selection: $weekStart, displayedComponents: .date)
                    .font(.subheadline)
            }
            if let saveError {
                Text("Opslaan lukt niet: \(saveError)").font(.footnote).foregroundStyle(.orange)
            }
            bigButton("Voeg doel toe", "checkmark") { create() }
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, bottom + 8)
        .background(Color.black.shadow(.drop(color: .black, radius: 16, y: -8)))
    }

    /// While Rondje reads the pasted schedule.
    @ViewBuilder
    private var readingStatus: some View {
        if method != .later, isReading || thinking {
            HStack(spacing: 10) {
                typingBubble
                Text(isReading ? "Schema lezen..." : "Apple Intelligence leest mee...")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// How it went, once every workout has turned.
    @ViewBuilder
    private var reviewResult: some View {
        if method != .later, morphDone, !isReading, !thinking {
            switch result {
            case .success(let e):
                botBubble("Gelukt! Ik vond \(e.workouts.count) trainingen. Kijk even of ze kloppen.")
                    .transition(.opacity)
            case .failure(let error):
                botBubble("Sorry, daar kwam ik niet uit. \(error.localizedDescription) Plak je het hele antwoord nog een keer?")
            default:
                EmptyView()
            }
        }
    }

    /// Your own lines for one workout, as you pasted them: plain text with a thin bar,
    /// like a quote. As high as a card, so the layer of cards fits right over it.
    private func sourceText(_ w: PlannedWorkout) -> some View {
        let lines = (sources[w.id] ?? WorkoutText.written(for: w)).split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return HStack(spacing: 12) {
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(width: 2)
                .padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(lines.first.map(String.init) ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if lines.count > 1 {
                    Text(String(lines[1]))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: rowHeight)
    }

    /// The workout as Rondje made it: icon, name, day and the main part in its zone color.
    private func workoutCard(_ w: PlannedWorkout, height: CGFloat? = nil) -> some View {
        let kind = WorkoutKind(w, scheduleName: trimmedName, raceDate: hasDate ? dayString(bigDay) : nil)
        let main = (w.blocks ?? []).first { $0.iterations > 1 } ?? w.blocks?.first
        let summary = main.flatMap { b in
            b.steps.first.map { st in
                [(b.iterations > 1 ? "\(b.iterations)x " : "") + st.goal.label, st.zone.map { "zone \($0)" }]
                    .compactMap { $0 }.joined(separator: " · ")
            }
        }
        return HStack(spacing: 12) {
            KindIcon(kind: kind, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.shownName).font(.headline).lineLimit(1)
                Text(Format.shortDay(w.date)).font(.subheadline).foregroundStyle(.secondary)
                if let summary {
                    Text(summary).font(.caption.bold()).foregroundStyle(kind.color).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: height)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
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
                switch isReading || thinking ? nil : result {
                case .success(let e):
                    Text(morphDone ? "\(e.workouts.count) trainingen" : "Je schema")
                        .font(.subheadline.bold())
                        .contentTransition(.opacity)
                    if morphDone, !aiWorkouts.isEmpty {
                        Label("\(aiWorkouts.count) gelezen met Apple Intelligence. Check even of ze kloppen.", systemImage: "sparkles")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if morphDone {
                        ForEach(skipped, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    if morphDone {
                        ForEach(e.workouts) { w in workoutCard(w) }
                    }
                case .failure:
                    Button("Opnieuw plakken", systemImage: "doc.on.clipboard") { step = .paste }
                        .bold()
                        .foregroundStyle(Theme.accent)
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
            if measured != nil {
                GoalPill(icon: "checkmark", title: "Klopt", isOn: false) { level = ""; typedAnswers[.level] = "Klopt"; goNext() }
                GoalPill(title: "Gebruik dit niet", isOn: false) { dropHealth("Gebruik dit niet") }
                if health.canAskLevel {
                    GoalPill(icon: "heart.fill", title: "Neem ook mijn VO2max mee", isOn: false) {
                        Task { await lookInHealth("Neem ook mijn VO2max mee") }
                    }
                }
            } else {
                ForEach(levels, id: \.self) { l in
                    GoalPill(title: l, isOn: false) { level = l; typedAnswers[.level] = nil; goNext() }
                }
                if !healthEmpty, health.canAskLevel || health.asked {
                    GoalPill(icon: "heart.fill", title: "Kijk in Apple Health", isOn: false) {
                        Task { await lookInHealth("Kijk in Apple Health") }
                    }
                }
            }
        case .wishes:
            GoalPill(title: "Geen wensen", isOn: false) { ownWish = ""; typedAnswers[.wishes] = "Geen wensen"; goNext() }
        case .paste:
            PasteButton(payloadType: String.self) { strings in
                guard let s = strings.first, !s.isEmpty else { return }
                Task { @MainActor in
                    text = s
                    typedAnswers[.paste] = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    clearComposer()
                    startShow()
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
        case .level: return measured != nil ? "Of vertel er iets bij, bijv. het voelt zwaar" : "Of vertel het zelf, bijv. 2x per week 6 km"
        case .aim: return askedTime ? "Bijv. 1:55 of onder de 2 uur" : "Bijv. uitlopen, of onder de 2 uur"
        case .wishes: return "Bijv. nooit op woensdag"
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
            typedAnswers[.paste] = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            startShow()
            goNext()
            return
        }
        // Plain answers ("4", "14 december", a goal from the list) need no Apple Intelligence.
        if isPlainAnswer(t) {
            act(on: take(t), said: t)
            return
        }
        // Rondje just asked something more ("Welke tijd?", "Welke 13e?"): your message answers that,
        // unless you clearly change something else ("o nee, ik bedoelde...").
        if followingUp, !NewGoalView.soundsLikeChange(t), !t.contains("?") {
            let taken = take(t)
            if case .no = taken {} else {
                act(on: taken, said: t)
                return
            }
        }
        // Your level, aim and wishes go into the prompt in your own words. There is nothing to
        // understand there, so nothing to ask again: only a question back or a clear change is read.
        if [.level, .aim, .wishes].contains(step), !t.isEmpty, !t.contains("?"), !NewGoalView.soundsLikeChange(t) {
            act(on: take(t), said: t)
            return
        }
        if !t.isEmpty, WorkoutAI.isAvailable, let field = NewGoalView.aiFields[step] {
            let earlier = pastSteps.compactMap { s in NewGoalView.aiFields[s].map { ($0, answer(s)) } }
            let turn = await understand { await WorkoutAI.readTurn(t, question: lastAsked, current: field, earlier: earlier) } ?? nil
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
            explainAgain(t)
            return
        }
        act(on: take(t), said: t)
    }

    /// Moves on after an answer, asks more about a half answer, or explains the question.
    private func act(on taken: Taken, said t: String) {
        switch taken {
        case .ok:
            typedAnswers[step] = t.isEmpty ? nil : t
            goNext()
        case .ask(let more): reply(t, more)
        case .no: explainAgain(t)
        }
    }

    private static let yesNo: [String: String] = [
        "ja": "Ja", "jaa": "Ja", "jep": "Ja", "yes": "Ja", "ok": "Ja", "oké": "Ja",
        "okay": "Ja", "prima": "Ja", "goed": "Ja", "is goed": "Ja", "zeker": "Ja",
        "nee": "Nee", "neen": "Nee", "nope": "Nee", "no": "Nee", "niet": "Nee",
    ]

    /// Answers the rules read without doubt, so they go through without waiting.
    private func isPlainAnswer(_ t: String) -> Bool {
        switch step {
        case .name: return goalPresets.contains { $0.title.lowercased() == t.lowercased() }
        case .method: return NewGoalView.yesNo[t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))] != nil
        case .perWeek: return t.range(of: #"^[1-7]\s*(x|keer)?(\s*per week)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
        case .date: return NewGoalView.date(from: t) != nil || NewGoalView.dayNumber(t) != nil || NewGoalView.monthNumber(t) != nil
        case .level: return measured != nil && NewGoalView.agrees(t) != nil
        default: return false
        }
    }

    /// "klopt", "ja" -> true; "klopt niet", "nee" -> false; anything else is not a yes or a no.
    static func agrees(_ t: String) -> Bool? {
        let l = t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if ["klopt", "dat klopt", "ja klopt", "ja dat klopt", "klopt wel", "klopt nog"].contains(l) { return true }
        if ["klopt niet", "dat klopt niet", "nee klopt niet", "klopt niet meer"].contains(l) { return false }
        return yesNo[l].map { $0 == "Ja" }
    }

    // MARK: - Apple Health

    /// The Health facts that are on screen and go into your prompt.
    private var measured: RunLevel? { skipHealth ? nil : healthLevel }

    private static let healthCheck = "Klopt dat nog? Dan zet ik het in je prompt."
    private static let healthDropped = "Prima, dan laat ik Apple Health erbuiten. Wat lukt je nu? En hoe zwaar voelt dat?"

    /// Asks Apple Health (with Apple's own sheet when that is still needed) and says what it shows.
    private func lookInHealth(_ said: String) async {
        let shown = measured
        if health.canAskLevel { await health.connect() }
        guard let found = await health.level() else {
            healthEmpty = true
            reply(said, "Ik zie in Apple Health geen loopjes van de laatste 3 maanden. Vertel het zelf maar: wat lukt je nu?")
            return
        }
        healthLevel = found
        skipHealth = false
        if shown != nil {
            // The rest was already on screen: only say what is new.
            reply(said, found.vo2Max.map { "Je VO2max is \(RunLevel.vo2Text($0)). Die zet ik er ook bij." }
                  ?? "Ik zie geen VO2max in Apple Health. De rest blijft staan.")
        } else {
            reply(said, "\(found.said) \(NewGoalView.healthCheck)")
        }
    }

    /// Apple Health stays out of the prompt; Rondje asks for your level the usual way.
    private func dropHealth(_ said: String) {
        skipHealth = true
        reply(said, NewGoalView.healthDropped)
    }

    private static let aiFields: [Step: WorkoutAI.Field] = [
        .name: .goalName, .trail: .trail, .date: .raceDate, .method: .scheduleHelp, .perWeek: .runsPerWeek,
        .level: .level, .aim: .aim, .wishes: .wishes,
    ]

    /// Acts on what Apple Intelligence read. Be generous: anything that can be read as an answer
    /// counts. Only a clear change to an earlier answer, a real question, or nonsense as a goal name
    /// gets something else.
    private func handle(_ turn: WorkoutAI.Turn, said t: String) async {
        let target = turn.field.flatMap { f in NewGoalView.aiFields.first { $0.value == f }?.key }
        let gives = turn.kind == .answer || turn.kind == .correction
        let free: Set<Step> = [.name, .level, .aim, .wishes]

        // A change to an earlier answer. Without a new value, ask that question again,
        // but only when you clearly talk about it ("de datum klopt niet").
        // Only when you say so yourself ("o nee", "eigenlijk", "de datum..."): an earlier answer
        // never changes because Apple Intelligence thought so.
        if gives, let target, target != step, pastSteps.contains(target),
           NewGoalView.soundsLikeChange(t) || mentionsTopic(of: target, in: t) {
            if let said = change(target, to: free.contains(target) ? [turn.value] : [t, turn.value]) {
                reply(t, "\(said) \(ask(step))")
                return
            }
            if mentionsTopic(of: target, in: t) {
                jump(to: target)
                reply(t, "Geen probleem, dan pas ik dat aan.")
                return
            }
            // Not clearly about that earlier question: read it as an answer to this one.
        }
        // A real question back ("lopen?", "wat raad je aan?"): explain, with choices where that helps.
        if t.contains("?"), turn.kind == .question || turn.kind == .other {
            explainAgain(t)
            return
        }
        // "Weet ik nog niet" on what you train for: help choose.
        if step == .name, NewGoalView.saysNo(t) {
            reply(t, "Geen probleem! Kies hieronder iets, bijvoorbeeld Fit blijven. Je kunt het later nog veranderen.")
            return
        }
        // Nonsense as a goal or a level, like "Pizza". Sending the same again means you mean it.
        if [.name, .level].contains(step), !turn.fits, !NewGoalView.saysNo(t), turn.kind != .correction, doubted != t {
            doubted = t
            explainAgain(t, sorry: true)
            return
        }
        // Read it as an answer here. Free answers keep your own words;
        // a name only uses what Apple Intelligence picked out when it is really in your message.
        let tries: [String] = switch step {
        case .level, .aim, .wishes: [t]
        case .name: !turn.value.isEmpty && t.lowercased().contains(turn.value.lowercased()) ? [turn.value] : [t]
        default: [t, turn.value].filter { !$0.isEmpty }
        }
        for v in tries {
            let taken = take(v)
            if case .no = taken { continue }
            act(on: taken, said: t)
            return
        }
        explainAgain(t, sorry: turn.kind == .other)
    }

    /// Explains the question again, with choices to tap where that helps.
    private func explainAgain(_ t: String, sorry: Bool = false) {
        options = switch step {
        case .trail: ["Weet ik niet"]
        case .date: ["Nog geen datum"]
        case .method: ["Help me ermee", "Ik heb er al een", "Doe ik later"]
        case .perWeek: ["2x per week", "3x per week", "4x per week"]
        default: []
        }
        reply(t, (sorry ? "Sorry, daar kom ik niet uit. " : "") + explain(step))
    }

    /// What Rondje asked last on this question: a follow-up like "Welke tijd?", or the question itself.
    private var lastAsked: String {
        corrections.last { $0.at == step }?.reply ?? ask(step)
    }

    /// Rondje asked for the missing part of your answer and waits for it.
    private var followingUp: Bool {
        askedTime || trailMissing != nil || heldDay != nil || heldMonth != nil
    }

    /// Words that say you change something you said before: "o nee", "eigenlijk", "ik bedoelde".
    static func soundsLikeChange(_ t: String) -> Bool {
        let l = t.lowercased()
        return ["eigenlijk", "oeps", "verkeerd", "fout", "klopt niet", "toch", "sorry", "verander", "aanpas",
                "moet zijn", "bedoel", "o nee", "oh nee", "wacht", "in plaats van", "ipv", "vergis"]
            .contains(where: l.contains)
    }

    /// Whether you clearly talk about an earlier question: "de datum klopt niet".
    private func mentionsTopic(of s: Step, in t: String) -> Bool {
        let l = t.lowercased()
        return topics.first { $0.0 == s }?.1.contains(where: l.contains) ?? false
    }

    private enum Taken { case ok, no, ask(String) }
    private enum TrailPart { case km, up }

    /// Reads an answer to the current question with the rules. Nothing is guessed:
    /// a half answer ("13", "december", "3 of 4") gets a follow-up question instead.
    private func take(_ t: String) -> Taken {
        switch step {
        case .name:
            let match = goalPresets.first { $0.title.lowercased() == t.lowercased() }
            // A day in the same message ("Polar Bear Trail op 10 januari") answers the next question too.
            // Look in what you typed, also when Apple Intelligence picked out only the name.
            let found = match == nil ? NewGoalView.dateInText(pending ?? t) : nil
            let bare = found == nil ? t : NewGoalView.withoutDate(t)
            guard !bare.trimmingCharacters(in: .whitespaces).isEmpty else {
                // Only a day, no goal: keep the question open.
                return .no
            }
            ownName = match == nil
            name = match?.title ?? bare
            guard nameOK else { return .no }
            if let found {
                bigDay = found
                hasDate = true
                answeredAlong.insert(.date)
            }
            return .ok
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
            // "Klopt" or "nee" about what Apple Health shows is not your level in your own words.
            if measured != nil, let yes = NewGoalView.agrees(t) {
                guard yes else {
                    skipHealth = true
                    return .ask(NewGoalView.healthDropped)
                }
                level = ""
            } else {
                level = t
            }
        case .aim where askedTime:
            // The answer to "welke tijd?" is the time, in your own words.
            // "Weet ik nog niet" is fine: a time can come later, and it is not stored as the time.
            guard !t.isEmpty else { return .no }
            aimTime = NewGoalView.saysNo(t) ? "" : t
        case .aim:
            // Your aim stays in your own words. Only a time without a number gets a question.
            ownAim = t
            aimTime = ""
            wantsTime = false
            let l = t.lowercased()
            if l.contains("tijd"), !l.contains(where: \.isNumber), !NewGoalView.saysNo(t) {
                wantsTime = true
                askedTime = true
                return .ask("Welke tijd wil je neerzetten? Typ bijvoorbeeld 1:55 of onder de 2 uur.")
            }
        case .wishes:
            // "nee", "geen", "niks": no wishes.
            let none = ["nee", "geen", "niks", "nope", "geen wensen", "nee hoor", "niet echt"]
            let l = t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            ownWish = none.contains(l) || l.hasPrefix("geen idee") || l.hasPrefix("weet ik") ? "" : t
        default:
            return .no
        }
        return .ok
    }

    /// "Oeps, het is eigenlijk 15 december": changes an earlier answer and stays on this question.
    /// Returns what Rondje says back, or nil when this is not a correction of an earlier answer.
    private func correct(_ t: String) -> String? {
        let l = t.lowercased()
        guard NewGoalView.soundsLikeChange(t) else { return nil }
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
        (.method, ["schema", "hulp", "helpen"]),
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
            ownAim = value
            aimTime = ""
            wantsTime = false
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
        case .perWeek: return "Hoe vaak per week wil je hardlopen? Twijfel je, dan is 3 keer een mooi begin."
        case .level:
            if measured != nil { return "Klopt wat ik in Apple Health zie? Tik dan op Klopt. Je mag er ook bij vertellen hoe zwaar het lopen nu voelt." }
            return "Hoe ver kun je nu lopen, en hoe zwaar voelt dat? Bijvoorbeeld: 5 km lukt, maar het is zwaar."
        case .aim: return "Wat wil je halen? Bijvoorbeeld uitlopen, een tijd neerzetten of sneller worden. Zeg het gerust in je eigen woorden."
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
    private static let datePatterns = [
        #"\b\d{1,2}\s+(?:jan|feb|mrt|maa|apr|mei|jun|jul|aug|sep|okt|nov|dec)[a-z]*(?:\s+\d{4})?"#,
        #"\b\d{1,2}[-/]\d{1,2}(?:[-/]\d{4})?\b"#,
    ]

    static func dateInText(_ text: String, now: Date = .now) -> Date? {
        let l = text.lowercased()
        for p in datePatterns {
            if let r = l.range(of: p, options: .regularExpression), let d = date(from: String(l[r]), now: now) { return d }
        }
        return nil
    }

    /// "Polar Bear Trail op 10 januari" -> "Polar Bear Trail": the name without the day in it.
    static func withoutDate(_ text: String) -> String {
        var t = text
        for p in datePatterns {
            // With the little words that lead up to the day: "op", "is op", "van", a comma.
            t = t.replacingOccurrences(of: #"[\s,]*(?:\b(?:is|die|dat|en|het)\s+)?(?:\b(?:op|van|rond|rondom)\s+)?"# + p,
                                       with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.")))
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
        // "over 3 maanden" or "18 km" is not a day: only small words may stand around it.
        let filler: Set<String> = ["de", "op", "rond", "ongeveer", "het", "is", "om", "e", "ste", "eigenlijk", "toch"]
        let words = l.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard words.allSatisfy(filler.contains) else { return nil }
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

    /// Your level is exactly the pill you tap, nothing added.
    private let levels = ["Net begonnen", "5 km lukt", "5 km gaat makkelijk", "10 km lukt", "10 km gaat makkelijk", "Langer dan 10 km"]

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

    /// Your aim as you said it, with the time after it when Rondje asked for one: "een tijd neerzetten: 1:55".
    private var aimText: String {
        let own = ownAim.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = aimTime.trimmingCharacters(in: .whitespacesAndNewlines)
        return time.isEmpty ? own : "\(own): \(time)"
    }

    private var wishText: String {
        ownWish.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var prompt: String {
        WorkoutText.claudePrompt(event: trimmedName, raceDate: hasDate ? bigDay : nil, perWeek: perWeek,
                                 level: level, health: measured?.prompt ?? "", goal: aimText, wishes: wishText, details: details)
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
            Result { try WorkoutText.programWithSources(current, weekStart: start) }
        }.value
        guard !Task.isCancelled else { return }
        if case .success(let p) = r { sources = p.sources }
        reading = r.map { ($0.schedule, $0.doubts) }
        readText = current
        isReading = false
        guard WorkoutAI.isAvailable, case .success(let p) = reading, !p.doubts.isEmpty else { return }
        thinking = true
        let found = await WorkoutAI.readDoubts(p.doubts)
        guard !Task.isCancelled else { return }
        aiWorkouts = found
        thinking = false
    }

    // MARK: - Create

    private var canCreate: Bool {
        guard nameOK, !isReading, !thinking, method == .later || morphDone else { return false }
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
        // New workouts always go to the Watch right away.
        if !workouts.isEmpty {
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


/// One part of the sweep: your text (shows below the edge), the cards (above it) or the
/// edge itself. The edge comes down the list; once it is past the middle of the screen, a
/// longer list scrolls up under it instead, until its end is in sight.
private struct SweepLayer: ViewModifier, Animatable {
    enum Part { case text, cards, edge }

    var y: CGFloat          // the edge, measured down the whole list
    let hold: CGFloat       // where on screen the edge stays while the list scrolls
    let most: CGFloat       // how far the list can scroll
    let height: CGFloat     // the part of the list you can see
    let part: Part

    var animatableData: CGFloat {
        get { y }
        set { y = newValue }
    }

    func body(content: Content) -> some View {
        let scroll = min(max(0, y - hold), most)
        let line = y - scroll // the edge on screen
        switch part {
        case .edge:
            content
                .offset(y: line - 46)
                .frame(height: height, alignment: .top)
                .clipped()
        case .text, .cards:
            let above = part == .cards
            let band: CGFloat = 6 // the two fade into each other just above the edge
            content
                .offset(y: -scroll)
                .frame(height: height, alignment: .top)
                .clipped()
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        (above ? Color.black : Color.clear)
                            .frame(height: max(0, line - band))
                        LinearGradient(colors: above ? [.black, .clear] : [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: band)
                        (above ? Color.clear : Color.black)
                    }
                }
        }
    }
}
