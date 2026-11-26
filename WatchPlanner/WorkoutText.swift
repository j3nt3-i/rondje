import Foundation

// Reads workouts written the way runners write them, for example:
//
//   10 min inlopen, dan 5 keer 3 minuten hard met 2 minuten rust, uitlopen
//   duurloop van een uur rustig
//
// and the short format the app writes itself:
//
//   warmup 10 min z2
//   5x 3 min z4 / 2 min z2
//   cooldown
//
// Free text is first rewritten to the short format (normalize), then parsed.

enum WorkoutText {
    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - One workout

    static func workout(date: String, name: String, text: String) throws -> PlannedWorkout {
        try read(date: date, name: name, text: text).workout
    }

    /// Like workout, and says whether some numbers in the text were not used.
    /// Then the result may be wrong, and Apple Intelligence gets a try.
    static func read(date: String, name: String, text: String) throws -> (workout: PlannedWorkout, unsure: Bool) {
        var warmup: StepSpec?
        var cooldown: StepSpec?
        var blocks: [BlockSpec] = []

        let lines = normalize(text)
        let numbersIn = numberCount(lines.joined(separator: " "))
        let numbersInText = numberCount(normalizeNumbersOnly(text))
        var ignored = numbersInText > numbersIn

        for line in lines {
            if let rest = strip(line, prefixes: ["warmup"]) {
                let s = try step(rest, line: line)
                if s.ignored { ignored = true }
                warmup = StepSpec(goal: s.goal, zone: s.zone)
            } else if let rest = strip(line, prefixes: ["cooldown"]) {
                let s = try step(rest, line: line)
                if s.ignored { ignored = true }
                cooldown = StepSpec(goal: s.goal, zone: s.zone)
            } else if let m = match(#"^(\d+)x\s*(.+)$"#, line), let n = Int(m[1]) {
                guard (1...99).contains(n) else { throw ParseError(message: "\"\(line)\": herhaal 1 tot 99 keer.") }
                var parts: [String] = []
                for part in m[2].split(separator: "/").map(String.init) {
                    let hasGoal = part.contains(where: \.isNumber) || part.contains("open")
                    if !hasGoal, !parts.isEmpty {
                        parts[parts.count - 1] += " " + part // "heuvel op brug/dijk"
                    } else if hasGoal {
                        parts.append(part)
                    }
                }
                var steps: [IntervalSpec] = []
                for (i, part) in parts.enumerated() {
                    let s = try step(part, line: line)
                    if s.ignored { ignored = true }
                    steps.append(IntervalSpec(purpose: purpose(part, index: i), goal: s.goal, zone: s.zone))
                }
                guard !steps.isEmpty else { continue }
                blocks.append(BlockSpec(iterations: n, steps: steps))
            } else {
                let s = try step(line, line: line)
                if s.ignored { ignored = true }
                if s.goal.type == .open && !line.contains("open") {
                    throw ParseError(message: "\"\(line)\": hoe lang of hoe ver? Bijvoorbeeld 8 km of 30 min.")
                }
                blocks.append(BlockSpec(iterations: 1, steps: [IntervalSpec(purpose: .work, goal: s.goal, zone: s.zone)]))
            }
        }

        guard !blocks.isEmpty else {
            throw ParseError(message: "Ik mis nog hoe lang of hoe ver je loopt. Bijvoorbeeld \"8 km rustig\" of \"5 keer 3 min hard met 2 min rust\".")
        }
        let workout = PlannedWorkout(date: date, name: name, warmup: warmup, blocks: blocks, cooldown: cooldown)
        try TrainingSchedule(name: "", defaultTime: "07:00", workouts: [workout]).validate()
        return (workout, ignored)
    }

    /// Number groups, not counting zones like "z2".
    private static func numberCount(_ s: String) -> Int {
        let withoutZones = replace(s, #"\bz[1-5]\b"#, " ")
        return (try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#))?
            .numberOfMatches(in: withoutZones, range: NSRange(withoutZones.startIndex..., in: withoutZones)) ?? 0
    }

    /// The same number clean-up as normalize, without dropping anything.
    private static func normalizeNumbersOnly(_ text: String) -> String {
        var s = replace(text.lowercased(), #"(\d),(\d)"#, "$1.$2")
        s = numbersFromWords(s)
        for (pattern, template) in wordRules { s = replace(s, pattern, template) }
        return milesToKilometers(hoursToMinutes(s))
    }

    /// Name like "Do 5x 3 min" or "Za wedstrijd 15 km", when none is given.
    static func autoName(date: String, for w: PlannedWorkout, text: String = "") -> String {
        let weekday = ScheduleDates.day(date).map(Format.shortWeekday) ?? "Training"
        let blocks = w.blocks ?? []
        let hint = hintWord(text)
        guard let main = blocks.first(where: { $0.iterations > 1 }) ?? blocks.first else { return weekday }
        let goal = main.steps[0].goal
        let summary = main.iterations == 1
            ? (goal.type == .open ? "loop" : goal.label)
            : "\(main.iterations)x \(goal.label)"
        return [weekday, hint, summary].compactMap { $0 }.joined(separator: " ")
    }

    /// The short format, so a workout can be copied and edited.
    static func text(for w: PlannedWorkout, zones: Bool = true, separator: String = "\n") -> String {
        var lines: [String] = []
        if let wu = w.warmup { lines.append("warmup " + step(wu.goal, wu.zone, zones)) }
        for b in w.blocks ?? [] {
            let steps = b.steps.map { step($0.goal, $0.zone, zones) }.joined(separator: " / ")
            lines.append(b.iterations == 1 && b.steps.count == 1 ? steps : "\(b.iterations)x \(steps)")
        }
        if let cd = w.cooldown {
            lines.append(cd.goal.type == .open && cd.zone == nil ? "cooldown" : "cooldown " + step(cd.goal, cd.zone, zones))
        }
        return lines.joined(separator: separator)
    }

    /// Readable version for people, which the parser reads back the same:
    /// "Warming-up 15 min in zone 2", "6x 45 sec in zone 4 / 90 sec in zone 2", "Cooling-down".
    static func written(for w: PlannedWorkout, separator: String = "\n") -> String {
        func part(_ goal: GoalSpec, _ zone: Int?) -> String {
            [goal.type == .open ? "open" : goal.label, zone.map { "in zone \($0)" }].compactMap { $0 }.joined(separator: " ")
        }
        var lines: [String] = []
        if let wu = w.warmup {
            lines.append(wu.goal.type == .open && wu.zone == nil ? "Warming-up" : "Warming-up " + part(wu.goal, wu.zone))
        }
        for b in w.blocks ?? [] {
            let steps = b.steps.map { part($0.goal, $0.zone) }.joined(separator: " / ")
            lines.append(b.iterations == 1 && b.steps.count == 1 ? steps : "\(b.iterations)x \(steps)")
        }
        if let cd = w.cooldown {
            lines.append(cd.goal.type == .open && cd.zone == nil ? "Cooling-down" : "Cooling-down " + part(cd.goal, cd.zone))
        }
        return lines.joined(separator: separator)
    }

    // MARK: - Free text to short format

    /// Rewrites a free description to one short-format line per part.
    static func normalize(_ text: String) -> [String] {
        var s = text.lowercased()
        s = replace(s, #"(\d),(\d)"#, "$1.$2")
        s = numbersFromWords(s)
        for (pattern, template) in wordRules { s = replace(s, pattern, template) }
        s = hoursToMinutes(s)
        s = milesToKilometers(s)
        s = replace(s, #"[,;](?=[^()\n]*\))"#, " /") // "5x (3 min, 2 min)" stays one repeat

        let separators = #"\n|;|,|\.(?:\s|$)|\s+(?:en\s+)?(?:dan|daarna|vervolgens|gevolgd door|afsluiten met|eindigen met)\s+"#
        var lines: [String] = []
        // "herhaal 5x:" followed by the steps: collect them until something else comes.
        var pending: (count: Int, steps: [String])?

        func flush() {
            if let p = pending, !p.steps.isEmpty { lines.append("\(p.count)x " + p.steps.joined(separator: " / ")) }
            pending = nil
        }
        func isPlain(_ line: String) -> Bool {
            !line.hasPrefix("warmup") && !line.hasPrefix("cooldown") && line.range(of: #"^\d+x "#, options: .regularExpression) == nil
        }

        for raw in split(s, separators) {
            var seg = clean(raw)
            seg = replace(seg, #"^(?:en|eerst|begin met|starten met|tot slot|als laatste|afsluitend)\s+"#, "")
            if seg.isEmpty { continue }

            if let n = repeatCount(seg) {
                // "3 min hard, 2 min zacht, herhaal 3x": wrap the steps just before it.
                flush()
                var tail: [String] = []
                while let last = lines.last, isPlain(last) { tail.insert(lines.removeLast(), at: 0) }
                if tail.isEmpty {
                    pending = (n, [])
                } else {
                    lines.append("\(n)x " + tail.joined(separator: " / "))
                }
                continue
            }

            let isRepeat = match(#"(\d+)\s*x\s*"#, seg) != nil
            if let wu = removing(warmupWords, from: seg), !isRepeat {
                flush()
                lines.append("warmup " + wu)
            } else if let cd = removing(cooldownWords, from: seg), !isRepeat {
                flush()
                lines.append("cooldown " + cd)
            } else if let m = match(#"(\d+)\s*x\s*(.+)$"#, seg) {
                flush()
                var body = replace(m[2], #"\s+(?:met|en|plus|afgewisseld met)\s+"#, " / ")
                // "3 min hard 2 min zacht" has two steps without a separator.
                body = replace(body, #"(\d+(?:\.\d+)?\s*(?:km|min|sec|m|s|k)\b[^/\d]*?)\s+(?=\d)"#, "$1 / ")
                lines.append("\(m[1])x \(body)")
            } else if match(goalPattern, seg) == nil && !seg.contains("open") {
                // "wandelend terug" right after a repeat: recovery until you press on.
                if match(recoveryWords, seg) != nil, pending == nil, let last = lines.last,
                   last.range(of: #"^\d+x "#, options: .regularExpression) != nil, !last.contains(" / ") {
                    lines[lines.count - 1] = last + " / open " + seg
                }
                // Anything else ("rustdag", "hartslag laag") is a note and is skipped.
            } else {
                if pending != nil {
                    pending?.steps.append(seg)
                } else if match(recoveryWords, seg) != nil, let last = lines.last, !isPlain(last), last.first?.isNumber == true {
                    // "5x 3 min hard, 2 min rust ertussen": the rest belongs to the repeat.
                    lines[lines.count - 1] = last + " / " + seg
                } else {
                    lines.append(seg)
                }
            }
        }
        flush()
        return lines
    }

    /// "herhaal 3x", "repeat 3 x", "en dat 4x", "5x herhalen": a count without a time or distance.
    private static func repeatCount(_ seg: String) -> Int? {
        let m = match(#"\b(?:herhaal|herhalen|repeat|repeats)\b\D*?(\d+)"#, seg) ?? match(#"(\d+)\s*x\b"#, seg)
        guard let m, let n = Int(m[1]), (1...99).contains(n) else { return nil }
        let rest = seg.replacingOccurrences(of: m[0], with: " ")
        if rest.contains(where: \.isNumber) || match(#"\b(?:min|sec|km|m)\b"#, rest) != nil { return nil }
        return n
    }

    private static let numberWords: [(String, Int)] = [
        ("twintig", 20), ("dertig", 30), ("veertig", 40), ("vijftig", 50), ("zestig", 60),
        ("twaalf", 12), ("vijftien", 15), ("elf", 11), ("tien", 10), ("negen", 9), ("acht", 8),
        ("zeven", 7), ("zes", 6), ("vijf", 5), ("vier", 4), ("drie", 3), ("twee", 2),
    ]

    /// "vierhonderd" -> "400", "tweemaal" -> "2x", "een minuut" -> "1 minuut", "zes keer" -> "6 keer".
    private static func numbersFromWords(_ s: String) -> String {
        var s = replace(s, #"\bhonderd\b"#, "100")
        for (word, n) in numberWords {
            s = replace(s, #"\b\#(word)honderd\b"#, "\(n * 100)")
            s = replace(s, #"\b\#(word)maal\b"#, "\(n)x")
            s = replace(s, #"\b\#(word)\b"#, "\(n)")
        }
        s = replace(s, #"\b(?:een|één|1)\s+(?=(?:minuut|minuutje|kilometer|km|seconde|halve\s+)\b)"#, "1 ")
        return s
    }

    private static let wordRules: [(String, String)] = [
        (#"(\d+(?:\.\d+)?)\s*(?:miles?|mijl)\b"#, "$1 mi"),
        (#"(\d+)\s*(?:keer|maal|×|times)\b"#, "$1x"),
        (#"(\d+)\s*x(?=\d)"#, "$1x "),
        (#"(\d+)\s+(?:versnellingen|sprintjes|sprints|strides|herhalingen|stukken|stukjes|blokken|intervallen|heuveltjes|heuvels|reps)\b\s*(?:van\s+)?"#, "$1x "),
        (#"\banderhalf\s*uur(?:tje)?\b"#, "90 min"),
        (#"\b(?:een\s+)?half\s*uur(?:tje)?\b"#, "30 min"),
        (#"\b(?:een|1)\s+uur(?:tje)?\b"#, "60 min"),
        (#"\b(?:een\s+)?kwartier(?:tje)?\b"#, "15 min"),
        (#"\b(?:minuten|minuutjes?|minuut|mins|minutes?)\b"#, "min"),
        (#"\b(?:seconden|seconde|secs|seconds?)\b"#, "sec"),
        (#"\b(?:kilometers?|kms)\b"#, "km"),
        (#"(\d)\s*(?:meters?|mtr)\b"#, "$1 m"),
        (#"\bzone\s*(\d)"#, "z$1"),
        (#"\d+(?:\.\d+)?\s*%"#, " "),
        (#"\b\d+[:.]\d{2}\s*(?:min)?\s*(?:/|per)\s*(?:km|kilometer)\b"#, " "),
        (#"\b\d+\s*(?:min|sec)\s*(?:/|per)\s*(?:km|kilometer)\b"#, " "),
        (#"\b(?:hartslag|hr|pols|rpe)\b[^,;\n/]*"#, " "),
        (#"\b\d+\s*(?:bpm|slagen)\b"#, " "),
        (#"\b(?:(?:5|10|15|21)\s*k|halve\s+marathon|marathon|race|wedstrijd)[\s-]*tempo\b"#, "tempo"),
        (#"\bin-?\s*en\s+uit\s*lopen\b([^,\n;]*)"#, "inlopen$1, uitlopen$1"),
    ]

    private static let goalPattern = #"\d+(?:\.\d+)?\s*(?:km|k|min|m|sec|s|'|")(?![a-z])"#

    private static let warmupWords = #"\b(?:warming[- ]?up|warm[- ]?up|inlopen|inloop|warm\s?lopen|opwarmen|warm|wu)\b"#
    private static let cooldownWords = #"\b(?:cooling[- ]?down|cool[- ]?down|uitlopen|uitloop|uitdribbelen|cd|(?:terug\s+)?naar\s+huis)\b"#
    private static let recoveryWords = #"\b(?:rust|pauze|dribbel\w*|wandel\w*|herstel\w*|jog\w*|zacht\w*|langzaam|sloom|uitblazen|ertussen|tussendoor)\b"#

    private static func hoursToMinutes(_ s: String) -> String {
        var s = s
        // "3 min 30 sec" or "3:30 min" -> "210 sec"
        while let m = match(#"(\d+)\s*min\s*(?:en\s*)?(\d+)\s*sec"#, s) ?? match(#"\b(\d+):(\d{2})\s*min"#, s),
              let mm = Int(m[1]), let ss = Int(m[2]) {
            s = s.replacingOccurrences(of: m[0], with: "\(mm * 60 + ss) sec")
        }
        while let m = match(#"(\d+(?:\.\d+)?)\s*uur\b"#, s), let h = Double(m[1]) {
            s = s.replacingOccurrences(of: m[0], with: "\(Int((h * 60).rounded())) min")
        }
        return s
    }

    private static func milesToKilometers(_ s: String) -> String {
        var s = s
        while let m = match(#"(\d+(?:\.\d+)?)\s*mi\b"#, s), let mi = Double(m[1]) {
            s = s.replacingOccurrences(of: m[0], with: String(format: "%.1f km", mi * 1.609))
        }
        return s
    }

    // MARK: - Whole program

    // A program is a list of workouts. A workout starts with a line holding
    //   a date:      "2026-12-01 Di intervallen" or "1-12-2026: 8 km rustig"
    //   or a day:    "Dinsdag: 10 min inlopen, 6x 2 min stevig, uitlopen"
    // optionally under "Week 2" headers. Lines before the first workout hold
    // the event name and maybe a start time. Days without distance or time
    // (rest days) are skipped. JSON in the old format works too.

    static func program(_ text: String, weekStart: Date = defaultWeekStart()) throws -> TrainingSchedule {
        let r = try programWithWarnings(text, weekStart: weekStart)
        if r.schedule.workouts.isEmpty, let problem = r.doubts.compactMap(\.problem).first {
            throw ParseError(message: problem)
        }
        return r.schedule
    }

    /// A workout in a program that the rules could not read, or read with numbers left over.
    struct Doubt: Hashable {
        let date: String
        let name: String
        let text: String
        let problem: String?    // set when it was skipped
        let workoutID: String?  // set when it was read but may be wrong
        var note: String? = nil
        var key: String { date + "|" + text }
    }

    private static let noteLabel = #"^(?:uitleg|toelichting|beschrijving|omschrijving|inleiding|notitie|tip|tips|note|notes|info|description|why)\s*:\s*"#

    /// Takes the "uitleg: ..." lines out of a workout's lines. Several are joined into one note.
    static func splitNote(_ lines: [String]) -> (lines: [String], note: String?) {
        var rest: [String] = []
        var notes: [String] = []
        for line in lines {
            if let r = line.range(of: noteLabel, options: [.regularExpression, .caseInsensitive]) {
                let text = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { notes.append(text) }
            } else {
                rest.append(line)
            }
        }
        return (rest, notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    /// Like program, but keeps going past workouts it cannot read and lists them.
    static func programWithWarnings(_ text: String, weekStart: Date = defaultWeekStart()) throws
        -> (schedule: TrainingSchedule, doubts: [Doubt]) {
        let r = try programWithSources(text, weekStart: weekStart)
        return (r.schedule, r.doubts)
    }

    /// Like programWithWarnings, plus the lines each workout came from, by workout id,
    /// so the app can show your own text turning into the workout.
    static func programWithSources(_ text: String, weekStart: Date = defaultWeekStart()) throws
        -> (schedule: TrainingSchedule, doubts: [Doubt], sources: [String: String]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return (try TrainingSchedule.decode(Data(trimmed.utf8)), [], [:])
        }
        var sources: [String: String] = [:]
        var lastLine = ""

        let cal = ScheduleDates.calendar
        var doubts: [Doubt] = []
        var eventName: String?
        var time: String?
        var week: Int?
        var lastDate = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: weekStart)) ?? weekStart
        var workouts: [PlannedWorkout] = []
        var current: (date: String, rest: String, lines: [String], header: String)?

        func finish() throws {
            guard var c = current else { return }
            current = nil
            let source = ([c.header] + c.lines).joined(separator: "\n")
            // "uitleg: Zoek een heuvel..." is the note for this workout, not part of it.
            let split = splitNote(c.lines)
            c.lines = split.lines
            let note = split.note
            // The rest of the header line is the name, unless the lines below hold no
            // workout ("Succes!") and the header line itself does ("Di: 8 km rustig").
            let below = c.lines.joined(separator: "\n")
            let headerIsBody = c.lines.isEmpty || (!below.contains(where: \.isNumber) && c.rest.contains(where: \.isNumber))
            let bodyText = headerIsBody ? c.rest : below
            let name = headerIsBody ? "" : c.rest
            guard bodyText.contains(where: \.isNumber) || bodyText.lowercased().contains("open") else {
                return // rest day or a note
            }
            do {
                let r = try read(date: c.date, name: name.isEmpty ? "x" : name, text: bodyText)
                var w = r.workout
                if name.isEmpty { w.name = autoName(date: c.date, for: w, text: bodyText) }
                w.note = note
                workouts.append(w)
                sources[w.id] = source
                if r.unsure { doubts.append(Doubt(date: c.date, name: name, text: bodyText, problem: nil, workoutID: w.id, note: note)) }
            } catch {
                doubts.append(Doubt(date: c.date, name: name, text: bodyText,
                                    problem: "\(Format.shortDay(c.date)): \(error.localizedDescription)", workoutID: nil, note: note))
            }
        }

        func start(on date: Date, rest: String) throws {
            try finish()
            lastDate = date
            current = (isoFormatter.string(from: date), rest.trimmingCharacters(in: CharacterSet(charactersIn: " -:")), [], lastLine)
        }

        func handle(_ line: String) throws {
            if let m = match(#"^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{4})\b\s*[:,]?\s*(.*)$"#, line) {
                guard let iso = isoDate(m[1]), let date = ScheduleDates.day(iso) else {
                    throw ParseError(message: "\"\(m[1])\" is geen geldige datum.")
                }
                try start(on: date, rest: m[2])
            } else if let (date, rest) = textDate(line) {
                try start(on: date, rest: rest)
            } else if let m = match(#"^week\s*(\d+)\b\s*[:.\-]?\s*(.*)$"#, line), let n = Int(m[1]) {
                try finish()
                week = n
                if !m[2].isEmpty { try handle(m[2]) }
            } else if let (day, rest) = weekday(line) {
                let date: Date
                if let week {
                    let offset = (week - 1) * 7 + day
                    date = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: weekStart)) ?? weekStart
                } else {
                    date = next(weekday: day, after: lastDate)
                }
                try start(on: date, rest: rest)
            } else if current != nil {
                current?.lines.append(line)
            } else if let t = startTime(line) {
                time = t
                if !isOnlyTime(line), eventName == nil { eventName = eventTitle(line) }
            } else if workouts.isEmpty {
                // Chatbots often start with an intro, so the last line before the first workout wins.
                eventName = eventTitle(line)
            }
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = clean(raw)
            if !line.isEmpty {
                lastLine = line
                try handle(line)
            }
        }
        try finish()

        guard !workouts.isEmpty || !doubts.isEmpty else {
            throw ParseError(message: "Ik vond geen trainingen. Zet bij elke training een datum (1-12-2026) of een dag (dinsdag), met hoe lang of hoe ver.")
        }
        let name = (eventName ?? "").isEmpty ? "Mijn schema" : eventName!
        let schedule = TrainingSchedule(name: name, defaultTime: time ?? "07:00",
                                        workouts: dedupe(workouts).sorted { $0.date < $1.date })
        try schedule.validate()
        return (schedule, doubts, sources)
    }

    /// True when dates come from day names, so the user should pick when week 1 starts.
    /// True when some workouts have only a weekday ("Di: intervallen"), so week 1 needs a start date.
    /// "Week 1" headers above dated workouts ("Di 1 dec: ...") do not count.
    static func usesDayNames(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).map(clean)
        let dated = { (l: String) in
            match(#"\b\d{1,2}\s+(?:jan|feb|mrt|maa|apr|mei|jun|jul|aug|sep|okt|nov|dec)|\b\d{1,2}[-/]\d{1,2}"#, l) != nil
        }
        if lines.contains(where: { weekday($0) != nil && !dated($0) }) { return true }
        return !lines.contains(where: dated) && lines.contains { match(#"^week\s*\d+"#, $0) != nil }
    }

    /// Next Monday, or today when it is Monday.
    static func defaultWeekStart(from now: Date = .now) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday, 2 = Monday
        let days = (9 - weekday) % 7
        return cal.date(byAdding: .day, value: days, to: today) ?? today
    }

    /// The whole event as readable text: "1 dec 2026: Heuvels" and the parts below it.
    static func programText(for e: TrainingSchedule) -> String {
        var parts = [e.name]
        for w in e.workouts {
            let note = w.note.map { "uitleg: \($0)\n" } ?? ""
            parts.append("\(dayLine(w.date)): \(w.name)\n" + note + written(for: w))
        }
        return parts.joined(separator: "\n\n")
    }

    private static let monthNames = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]

    /// "2026-12-01" -> "1 dec 2026"
    private static func dayLine(_ iso: String) -> String {
        let n = iso.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3, (1...12).contains(n[1]) else { return iso }
        return "\(n[2]) \(monthNames[n[1] - 1]) \(n[0])"
    }

    /// Prompt for Claude with what we know about the event and the runner.
    static func claudePrompt(event: String, raceDate: Date?, perWeek: Int = 3,
                             level: String = "", goal: String = "", wishes: String = "",
                             details: String = "", today: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = "EEEE d MMMM yyyy"
        let name = event.trimmingCharacters(in: .whitespaces)

        var about: [String] = []
        if name.isEmpty {
            about.append("Ik train voor een hardloopdoel.")
        } else if let raceDate {
            about.append("Ik train voor \(name) op \(f.string(from: raceDate)).")
        } else {
            about.append("Ik train voor \(name).")
        }
        if !details.isEmpty { about.append(details) }
        about.append("Vandaag is het \(f.string(from: today)). Begin het schema vanaf morgen.")
        about.append("Ik wil \(perWeek) keer per week lopen.")
        for (label, value) in [("Mijn niveau nu", level), ("Mijn doel", goal), ("Wensen", wishes)] {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { about.append("\(label): \(v)") }
        }

        return """
        Maak een hardloopschema voor mij.
        \(about.joined(separator: "\n"))

        Geef alleen het schema, zonder tekst ervoor of erna, zodat ik het in mijn app kan plakken. Gebruik dit formaat:

        \(name.isEmpty ? "Naam van je doel" : name)

        2026-12-01 Di heuvels
        uitleg: Zoek een heuvel waar je ongeveer een minuut tegenop kunt lopen. Loop stevig omhoog met korte passen en actieve armen, en jog rustig terug naar beneden. Zo worden je benen sterker voor het klimmen.
        warmup 10 min z2
        6x 1 min z4 / 2 min z2
        cooldown

        2026-12-03 Do duurloop
        uitleg: Rustig en lang, je moet makkelijk kunnen praten. Dit bouwt je uithoudingsvermogen op.
        10 km z2

        Elke training begint met een datum en een korte naam. Dan een regel die begint met uitleg: met in 2 of 3 zinnen wat ik ga doen, hoe het moet voelen en waarom. Noem praktische dingen, zoals waar ik heuvels of een baan zoek. Daaronder per regel een warmup, herhalingen ("5x hard / herstel"), een gewone loop of een cooldown. Doelen als 45 sec, 3 min, 8 km, 400 m of open. Hartslagzone z1 tot z5 erachter.
        """
    }

    // MARK: - Helpers

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayNames: [(String, Int)] = [
        ("maandag", 0), ("dinsdag", 1), ("woensdag", 2), ("donderdag", 3), ("vrijdag", 4), ("zaterdag", 5), ("zondag", 6),
        ("ma", 0), ("di", 1), ("wo", 2), ("do", 3), ("vr", 4), ("za", 5), ("zo", 6),
    ]

    private static let months = ["jan": 1, "feb": 2, "mrt": 3, "maa": 3, "apr": 4, "mei": 5, "jun": 6,
                                 "jul": 7, "aug": 8, "sep": 9, "okt": 10, "nov": 11, "dec": 12]

    /// "Di 1 dec - Heuvels" or "3 december 2026: 8 km". Without a year: the next one from today.
    private static func textDate(_ line: String) -> (Date, String)? {
        let pattern = #"^(?:[a-z]{2,9}\.?\s+)?(\d{1,2})\s+(jan|feb|mrt|maa|apr|mei|jun|jul|aug|sep|okt|nov|dec)[a-z]*\.?(?:\s+(\d{4}))?(?![a-z])\s*[:,\-]?\s*(.*)$"#
        guard let m = match(pattern, line.lowercased()),
              let day = Int(m[1]), let month = months[m[2]] else { return nil }
        let cal = ScheduleDates.calendar
        let today = cal.startOfDay(for: .now)
        var year = Int(m[3]) ?? cal.component(.year, from: today)
        func make(_ y: Int) -> Date? { cal.date(from: DateComponents(year: y, month: month, day: day)) }
        if m[3].isEmpty, let d = make(year), d < cal.date(byAdding: .day, value: -60, to: today)! { year += 1 }
        guard let date = make(year), cal.component(.day, from: date) == day else { return nil }
        // Keep the original casing of the rest of the line.
        let rest = String(line.suffix(m[4].count))
        return (date, rest)
    }

    /// "dinsdag: 8 km" -> (1, "8 km"). Monday is 0.
    private static func weekday(_ line: String) -> (Int, String)? {
        let l = line.lowercased()
        for (name, index) in dayNames where l.hasPrefix(name) {
            let rest = l.dropFirst(name.count)
            if name.count > 2 {
                guard rest.first.map({ !$0.isLetter }) ?? true else { continue }
            } else {
                // Short names only with "di:", "di." or "di 8 km", so "zo rustig" stays text.
                guard rest.isEmpty || rest.first == ":" || rest.first == "."
                        || rest.range(of: #"^\s+\d"#, options: .regularExpression) != nil else { continue }
            }
            let text = String(line.dropFirst(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: " .:-"))
            return (index, text)
        }
        return nil
    }

    private static func next(weekday: Int, after date: Date) -> Date {
        let cal = ScheduleDates.calendar
        var d = cal.date(byAdding: .day, value: 1, to: date) ?? date
        for _ in 0..<7 {
            let w = (cal.component(.weekday, from: d) + 5) % 7 // Monday 0
            if w == weekday { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    private static func startTime(_ line: String) -> String? {
        let l = line.lowercased()
        if let m = match(#"\b(?:tijd|starttijd|om|start|time)\s*:?\s*(\d{1,2})[:.](\d{2})\b"#, l),
           let h = Int(m[1]), let mm = Int(m[2]), h < 24, mm < 60 {
            return String(format: "%02d:%02d", h, mm)
        }
        if let m = match(#"\bhalf\s+(\d{1,2})\b"#, l), let h = Int(m[1]), (1...24).contains(h) {
            return String(format: "%02d:30", h - 1)
        }
        if let m = match(#"\bom\s+(\d{1,2})\s*uur\b"#, l), let h = Int(m[1]), h < 24 {
            return String(format: "%02d:00", h)
        }
        return nil
    }

    private static func isOnlyTime(_ line: String) -> Bool {
        match(#"^(?:tijd|starttijd|start|time)\b"#, line.lowercased()) != nil
    }

    /// "Schema voor de Zevenheuvelenloop (15 km), we lopen om half 7" -> "Zevenheuvelenloop (15 km)"
    private static func eventTitle(_ line: String) -> String {
        var t = line
        t = replace(t, #"^(?:hier\s+is|hierbij|dit\s+is)\s+"#, "")
        t = replace(t, #"^(?:je|jouw|mijn|een|het)\s+"#, "")
        t = replace(t, #"^(?:(?:trainings|hardloop|loop)?schema|plan|programma|training)\s+(?:voor|naar|richting|tot)\s+(?:de|het)?\s*"#, "")
        if let r = t.range(of: #",|\.\s|\s-\s|!|:"#, options: .regularExpression) { t = String(t[..<r.lowerBound]) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .:"))
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private static func hintWord(_ text: String) -> String? {
        if match(#"\b(?:wedstrijd|race)\b"#, text) != nil { return "wedstrijd" }
        if match(#"\bheuvel"#, text) != nil { return "heuvels" }
        if match(#"\b(?:duurloop|lange)\b"#, text) != nil { return "duurloop" }
        return nil
    }

    private static func dedupe(_ workouts: [PlannedWorkout]) -> [PlannedWorkout] {
        var seen = Set<String>()
        return workouts.filter { seen.insert($0.id).inserted }
    }

    /// Strips markdown and notes that chatbots like to add.
    private static func clean(_ raw: String) -> String {
        var line = raw
        if let r = line.range(of: "//") { line = String(line[..<r.lowerBound]) }
        line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        line = line.trimmingCharacters(in: .whitespaces)
        while let first = line.first, "#-*•>".contains(first) {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    /// "2026-12-1" or "1-12-2026" to "2026-12-01".
    private static func isoDate(_ s: String) -> String? {
        let n = s.split(whereSeparator: { "-/.".contains($0) }).compactMap { Int($0) }
        guard n.count == 3 else { return nil }
        let (y, m, d) = n[0] > 31 ? (n[0], n[1], n[2]) : (n[2], n[1], n[0])
        let iso = String(format: "%04d-%02d-%02d", y, m, d)
        guard ScheduleDates.day(iso) != nil, (1...12).contains(m), (1...31).contains(d) else { return nil }
        return iso
    }

    private static func step(_ goal: GoalSpec, _ zone: Int?, _ zones: Bool) -> String {
        guard zones, let zone else { return goal.label }
        return "\(goal.label) z\(zone)"
    }

    private static func strip(_ line: String, prefixes: [String]) -> String? {
        for p in prefixes where line.hasPrefix(p) {
            let rest = line.dropFirst(p.count)
            if let next = rest.first, next.isLetter { continue }
            return rest.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        }
        return nil
    }

    private static func removing(_ pattern: String, from s: String) -> String? {
        guard match(pattern, s) != nil else { return nil }
        return replace(s, pattern, " ").trimmingCharacters(in: .whitespaces)
    }

    private static func purpose(_ part: String, index: Int) -> IntervalSpec.Purpose {
        if match(recoveryWords, part) != nil { return .recovery }
        if match(#"\b(?:hard|snel|stevig|tempo|sprint\w*)\b"#, part) != nil { return .work }
        return index.isMultiple(of: 2) ? .work : .recovery
    }

    /// Zone from words when none is given: "rustig" 2, "tempo" 3, "hard" 4, "sprint" 5.
    private static func inferredZone(_ s: String) -> Int? {
        if match(#"\b(?:sprint\w*|maximaal|alles)\b"#, s) != nil { return 5 }
        if match(#"\b(?:stevig|drempel\w*|hard|snel|threshold)\b"#, s) != nil { return 4 }
        if match(#"\b(?:tempo|racetempo|duurtempo|matig)\b"#, s) != nil { return 3 }
        if match(#"\b(?:rustig\w*|zacht\w*|langzaam|easy|duurloop|ontspannen|kalm|lsd)\b"#, s) != nil { return 2 }
        return nil
    }

    private static func step(_ raw: String, line: String) throws -> (goal: GoalSpec, zone: Int?, ignored: Bool) {
        var s = " " + raw.lowercased() + " "
        var zone: Int?
        var goal = GoalSpec(type: .open)

        if let m = match(#"\b(?:zone|z)\s*(\d+)\b"#, s) {
            guard let z = Int(m[1]), (1...5).contains(z) else {
                throw ParseError(message: "\"\(line)\": zone moet tussen 1 en 5 liggen.")
            }
            zone = z
            s = s.replacingOccurrences(of: m[0], with: " ")
        }

        let unitPattern = #"(\d+(?:[.,]\d+)?)\s*(km|k|min|m|sec|s|'|")(?![a-z])"#
        if let m = match(unitPattern, s), let value = Double(m[1].replacingOccurrences(of: ",", with: ".")) {
            switch m[2] {
            case "km", "k": goal = GoalSpec(type: .distance, value: value, unit: "km")
            case "m": goal = GoalSpec(type: .distance, value: value / 1000, unit: "km")
            case "min", "'": goal = GoalSpec(type: .time, value: value, unit: "min")
            default: goal = GoalSpec(type: .time, value: value, unit: "sec")
            }
            s = s.replacingOccurrences(of: m[0], with: " ")
        }

        // Extra numbers next to a goal (pace, heart rate) are fine. Numbers without a goal are not.
        if goal.type == .open, s.contains(where: \.isNumber) {
            throw ParseError(message: "\"\(line.trimmingCharacters(in: .whitespaces))\": hier mis ik een tijd of afstand, zoals 3 min, 45 sec, 5 km of 400 m.")
        }
        if zone == nil { zone = inferredZone(s) }
        return (goal, zone, s.contains(where: \.isNumber))
    }

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private static func split(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [s] }
        var parts: [String] = []
        var start = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            parts.append(String(s[start..<r.lowerBound]))
            start = r.upperBound
        }
        parts.append(String(s[start...]))
        return parts
    }
}
