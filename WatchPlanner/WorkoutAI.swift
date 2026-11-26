import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Fallback for text the rules in WorkoutText cannot read. Apple Intelligence
// (on device) rewrites it to the short format, and WorkoutText checks the result.

enum WorkoutAI {
    struct AIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// True when Apple Intelligence can be used on this device right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Dutch reason when it cannot be used, for a footnote.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Zet Apple Intelligence aan in Instellingen, dan leest die mee als de app iets niet snapt."
            case .unavailable(.modelNotReady): return "Apple Intelligence wordt nog gedownload."
            case .unavailable: return nil
            }
        }
        #endif
        return nil
    }

    /// Rewrites one workout description to the short format.
    static func rewrite(_ description: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: "Input: \(description)\nOutput:",
                                                         options: GenerationOptions(temperature: 0))
                return cleanOutput(response.content)
            } catch {
                throw AIError(message: "Apple Intelligence kon dit ook niet lezen.")
            }
        }
        #endif
        throw AIError(message: "Apple Intelligence is niet beschikbaar.")
    }

    /// Tries the rules first. When they fail, or had to skip numbers, Apple Intelligence gets a try.
    static func workout(date: String, name: String, text: String) async throws -> (workout: PlannedWorkout, usedAI: Bool) {
        let rules: Result<(workout: PlannedWorkout, unsure: Bool), Error> = Result {
            try WorkoutText.read(date: date, name: name, text: text)
        }
        if case .success(let r) = rules, !r.unsure { return (r.workout, false) }
        if isAvailable, let rewritten = try? await rewrite(text),
           let w = try? WorkoutText.workout(date: date, name: name, text: rewritten) {
            return (w, true)
        }
        return (try rules.get().workout, false)
    }

    /// Second reading for a pasted schedule: Apple Intelligence tries every workout the
    /// rules skipped or doubted. Returns the ones it could read, by Doubt.key.
    static func readDoubts(_ doubts: [WorkoutText.Doubt]) async -> [String: PlannedWorkout] {
        guard isAvailable, !doubts.isEmpty else { return [:] }
        var found: [String: PlannedWorkout] = [:]
        for d in doubts {
            if Task.isCancelled { break }
            guard let r = try? await workout(date: d.date, name: d.name.isEmpty ? "x" : d.name, text: d.text),
                  r.usedAI else { continue }
            var w = r.workout
            if d.name.isEmpty { w.name = WorkoutText.autoName(date: d.date, for: w, text: d.text) }
            w.note = d.note
            found[d.key] = w
        }
        return found
    }

    /// The rules' schedule with Apple Intelligence's readings filled in.
    static func merge(_ parsed: (schedule: TrainingSchedule, doubts: [WorkoutText.Doubt]),
                      _ ai: [String: PlannedWorkout]) throws -> TrainingSchedule {
        var e = parsed.schedule
        for d in parsed.doubts {
            guard let w = ai[d.key] else { continue }
            if let id = d.workoutID, let i = e.workouts.firstIndex(where: { $0.id == id }) {
                e.workouts[i] = w
            } else if !e.workouts.contains(where: { $0.id == w.id }) {
                e.workouts.append(w)
            }
        }
        e.workouts.sort { $0.date < $1.date }
        if e.workouts.isEmpty {
            throw WorkoutText.ParseError(message: parsed.doubts.compactMap(\.problem).first ?? "Ik vond geen trainingen.")
        }
        return e
    }

    // MARK: - Goal chat

    /// Why the goal chat cannot use Apple Intelligence, or nil when it can.
    static var chatOffReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence staat uit. Zet het aan in Instellingen, dan snap ik je beter."
            case .unavailable(.modelNotReady): return "Apple Intelligence wordt nog gedownload. Tot die tijd snap ik je wat minder goed."
            case .unavailable: return "Apple Intelligence werkt niet op dit toestel, dus ik snap je wat minder goed."
            }
        }
        #endif
        return "Voor Apple Intelligence heb je iOS 26 nodig. Tot die tijd snap ik je wat minder goed."
    }

    /// Loads the model ahead of time, so the first chat message does not wait for it.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), isAvailable {
            LanguageModelSession().prewarm()
        }
        #endif
    }

    /// A question in the goal chat, and what it asks for.
    enum Field: String {
        case goalName, raceDate, trail = "trailDetails", scheduleHelp, runsPerWeek, level = "currentLevel", aim, wishes
    }

    enum Kind { case answer, correction, question, other }

    /// What a chat message is. The value is in the runner's own words; the chat's rules read it.
    struct Turn {
        var kind: Kind
        var field: Field?
        var value: String
        /// False for nonsense as an answer, like "Pizza" as a running goal.
        var fits: Bool
    }

    /// Reads one chat message: "o nee, ik bedoelde 10 december" -> correction of raceDate, "10 december".
    static func readTurn(_ message: String, question: String, current: Field, earlier: [(Field, String)]) async -> Turn? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), isAvailable {
            let answers = earlier.isEmpty ? "none yet" : earlier.map { "\($0.0.rawValue): \($0.1)" }.joined(separator: "\n")
            let instructions = """
            You are Rondje, the chat in a running app. You ask a runner questions one by one to set up a training goal.
            The fields:
            goalName: what they train for, a race or a goal. raceDate: the day of the race. trailDetails: distance and climb of the race.
            scheduleHelp: whether they want help making a schedule ('ja graag'), already have one ('heb er al een'), or do it later ('later').
            runsPerWeek: how often per week they want to run in their schedule.
            currentLevel: what they can run now and how hard that feels, like '2x per week 6 km' or '5 km is zwaar'.
            aim: what they want to reach. wishes: wishes for the schedule.
            Earlier answers:
            \(answers)
            Current question: "\(question)" (field: \(current.rawValue))
            Read the runner's latest message and decide what it is.
            A message that only asks something, like 'lopen?' or 'wat bedoel je', is a question, not an answer.
            A message that says an earlier answer was wrong, like 'o nee, ik bedoelde 10 december', is a correction of that field.
            """
            guard let r = try? await LanguageModelSession(instructions: instructions)
                    .respond(to: "Message: \"\(message)\"", generating: GenTurn.self, options: GenerationOptions(temperature: 0)).content
            else { return nil }
            let kind: Kind = switch r.kind {
            case .answer: .answer
            case .correction: .correction
            case .question: .question
            case .other: .other
            }
            let field: Field? = switch r.field {
            case .goalName: .goalName
            case .raceDate: .raceDate
            case .trailDetails: .trail
            case .scheduleHelp: .scheduleHelp
            case .runsPerWeek: .runsPerWeek
            case .currentLevel: .level
            case .aim: .aim
            case .wishes: .wishes
            case .none: nil
            }
            return Turn(kind: kind, field: field, value: r.value.trimmingCharacters(in: .whitespacesAndNewlines), fits: r.fits)
        }
        #endif
        return nil
    }

    private static func cleanOutput(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("Output:") ? String($0.dropFirst(7)).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("Input:") && !$0.hasPrefix("```") }
            .joined(separator: "\n")
    }

    private static let instructions = """
    You rewrite one running workout, written by a runner in Dutch or English, into a strict format. \
    Output only the lines of the format, nothing else.

    Format, one part per line:
    warmup <goal> [zone]
    <count>x <work goal> [zone] / <recovery goal> [zone]
    <goal> [zone]
    cooldown [<goal>] [zone]

    A goal is "<number> sec", "<number> min", "<number> km", "<number> m" or "open".
    A zone is z1 to z5. Only add a zone when the text names one or uses a clear word: \
    rustig or easy is z2, tempo or racetempo is z3, stevig or hard or drempel is z4, sprint is z5.
    Inlopen means warmup. Uitlopen means cooldown. A steady run without repeats is a single goal line.
    Only write parts that are in the text. Never add a warmup or cooldown that is not mentioned.
    Ignore notes like pace, heart rate, terrain or encouragement.
    If the text has no time or distance at all, output only: none

    Input: twee rondjes van 10 minuten inlopen en dan 4 keer een kilometer op racetempo, tussendoor 2 minuten joggen. Afsluiten met 10 minuten uitlopen.
    Output:
    warmup 20 min z2
    4x 1 km z3 / 2 min
    cooldown 10 min

    Input: Easy 45 minutes, then 6 strides of 20 seconds with full recovery
    Output:
    45 min z2
    6x 20 sec / open

    Input: acht keer tweehonderd meter vlot, 200 meter wandelen
    Output:
    8x 200 m z4 / 200 m

    Input: lekker genieten vandaag
    Output:
    none

    Input: piramide: 1-2-3-2-1 minuten hard met steeds 1 minuut rust
    Output:
    1x 1 min z4 / 1 min
    1x 2 min z4 / 1 min
    1x 3 min z4 / 1 min
    1x 2 min z4 / 1 min
    1x 1 min z4 / 1 min
    """
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum GenKind { case answer, correction, question, other }

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum GenField { case goalName, raceDate, trailDetails, scheduleHelp, runsPerWeek, currentLevel, aim, wishes, none }

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GenTurn {
    @Guide(description: "answer: the message answers the current question. correction: the message changes one of the earlier answers. question: the runner asks something. other: anything else, like small talk.")
    var kind: GenKind
    @Guide(description: "The question the message is about. For an answer: the current question. For a correction: the earlier answer it changes. Otherwise none.")
    var field: GenField
    @Guide(description: "For an answer or correction: the value exactly in the runner's words, like '4', '20 december' or 'Kerstloop'. Empty when the runner gave no new value.")
    var value: String
    @Guide(description: "False when the message is nonsense as an answer to the current question, like 'pizza' as a running goal or 'banaan' as how often to run. True for any real answer, also short ones or unusual race names.")
    var fits: Bool
}
#endif
