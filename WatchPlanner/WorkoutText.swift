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
        var warmup: StepSpec?
        var cooldown: StepSpec?
        var blocks: [BlockSpec] = []

        for line in normalize(text) {
            if let rest = strip(line, prefixes: ["warmup"]) {
                let s = try step(rest, line: line)
                warmup = StepSpec(goal: s.goal, zone: s.zone)
            } else if let rest = strip(line, prefixes: ["cooldown"]) {
                let s = try step(rest, line: line)
                cooldown = StepSpec(goal: s.goal, zone: s.zone)
            } else if let m = match(#"^(\d+)x\s*(.+)$"#, line), let n = Int(m[1]) {
                guard (1...99).contains(n) else { throw ParseError(message: "\"\(line)\": herhaal 1 tot 99 keer.") }
                let parts = m[2].split(separator: "/").map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                var steps: [IntervalSpec] = []
                for (i, part) in parts.enumerated() {
                    let s = try step(part, line: line)
                    steps.append(IntervalSpec(purpose: purpose(part, index: i), goal: s.goal, zone: s.zone))
                }
                guard !steps.isEmpty else { continue }
                blocks.append(BlockSpec(iterations: n, steps: steps))
            } else {
                let s = try step(line, line: line)
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
        return workout
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

    // MARK: - Free text to short format

    /// Rewrites a free description to one short-format line per part.
    static func normalize(_ text: String) -> [String] {
        var s = text.lowercased()
        s = replace(s, #"(\d),(\d)"#, "$1.$2")
        for (pattern, template) in wordRules { s = replace(s, pattern, template) }
        s = hoursToMinutes(s)
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
            } else if seg.contains(where: \.isNumber) || seg.contains("open") {
                if pending != nil {
                    pending?.steps.append(seg)
                } else if match(recoveryWords, seg) != nil, let last = lines.last, !isPlain(last), last.first?.isNumber == true {
                    // "5x 3 min hard, 2 min rust ertussen": the rest belongs to the repeat.
                    lines[lines.count - 1] = last + " / " + seg
                } else {
                    lines.append(seg)
                }
            }
            // Anything else ("lekker genieten!") is a note and is skipped.
        }
        flush()
        return lines
    }

    /// "herhaal 3x", "repeat 3 x", "en dat 4x", "5x herhalen": a count without a time or distance.
    private static func repeatCount(_ seg: String) -> Int? {
        let m = match(#"\b(?:herhaal|herhalen|repeat|repeats)\b\D*?(\d+)"#, seg) ?? match(#"(\d+)\s*x\b"#, seg)
        guard let m, let n = Int(m[1]), (1...99).contains(n) else { return nil }
        let rest = seg.replacingOccurrences(of: m[0], with: " ")
        return rest.contains(where: \.isNumber) ? nil : n
    }

    private static let wordRules: [(String, String)] = [
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
        (#"\b(?:(?:5|10|15|21)\s*k|halve\s+marathon|marathon|race|wedstrijd)[\s-]*tempo\b"#, "tempo"),
        (#"\bin-?\s*en\s+uit\s*lopen\b([^,\n;]*)"#, "inlopen$1, uitlopen$1"),
    ]

    private static let warmupWords = #"\b(?:warming[- ]?up|warmup|inlopen|inloop|warm\s?lopen|opwarmen|warm|wu)\b"#
    private static let cooldownWords = #"\b(?:cooling[- ]?down|cooldown|uitlopen|uitloop|uitdribbelen|cd|(?:terug\s+)?naar\s+huis)\b"#
    private static let recoveryWords = #"\b(?:rust|pauze|dribbel\w*|wandel\w*|herstel\w*|jog\w*|zacht\w*|langzaam|sloom|uitblazen|ertussen|tussendoor)\b"#

    private static func hoursToMinutes(_ s: String) -> String {
        var s = s
        while let m = match(#"(\d+(?:\.\d+)?)\s*uur\b"#, s), let h = Double(m[1]) {
            s = s.replacingOccurrences(of: m[0], with: "\(Int((h * 60).rounded())) min")
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return try TrainingSchedule.decode(Data(trimmed.utf8))
        }

        let cal = ScheduleDates.calendar
        var eventName: String?
        var time: String?
        var week: Int?
        var lastDate = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: weekStart)) ?? weekStart
        var workouts: [PlannedWorkout] = []
        var current: (date: String, rest: String, lines: [String])?

        func finish() throws {
            guard let c = current else { return }
            current = nil
            let bodyText = c.lines.isEmpty ? c.rest : c.lines.joined(separator: "\n")
            let name = c.lines.isEmpty ? "" : c.rest
            guard bodyText.contains(where: \.isNumber) || bodyText.lowercased().contains("open") else {
                return // rest day or a note
            }
            do {
                var w = try workout(date: c.date, name: name.isEmpty ? "x" : name, text: bodyText)
                if name.isEmpty { w.name = autoName(date: c.date, for: w, text: bodyText) }
                workouts.append(w)
            } catch {
                throw ParseError(message: "\(Format.shortDay(c.date)): \(error.localizedDescription)")
            }
        }

        func start(on date: Date, rest: String) throws {
            try finish()
            lastDate = date
            current = (isoFormatter.string(from: date), rest.trimmingCharacters(in: CharacterSet(charactersIn: " -:")), [])
        }

        func handle(_ line: String) throws {
            if let m = match(#"^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{4})\b\s*[:,]?\s*(.*)$"#, line) {
                guard let iso = isoDate(m[1]), let date = ScheduleDates.day(iso) else {
                    throw ParseError(message: "\"\(m[1])\" is geen geldige datum.")
                }
                try start(on: date, rest: m[2])
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
            if !line.isEmpty { try handle(line) }
        }
        try finish()

        guard !workouts.isEmpty else {
            throw ParseError(message: "Ik vond geen trainingen. Zet bij elke training een datum (1-12-2026) of een dag (dinsdag), met hoe lang of hoe ver.")
        }
        let name = (eventName ?? "").isEmpty ? "Mijn schema" : eventName!
        let schedule = TrainingSchedule(name: name, defaultTime: time ?? "07:00",
                                        workouts: dedupe(workouts).sorted { $0.date < $1.date })
        try schedule.validate()
        return schedule
    }

    /// True when dates come from day names, so the user should pick when week 1 starts.
    static func usesDayNames(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { line in
            let l = clean(line)
            return weekday(l) != nil || match(#"^week\s*\d+"#, l) != nil
        }
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

    static func programText(for e: TrainingSchedule) -> String {
        var parts = ["\(e.name)\ntijd \(e.defaultTime)"]
        for w in e.workouts {
            parts.append("\(w.date) \(w.name)\n" + text(for: w))
        }
        return parts.joined(separator: "\n\n")
    }

    /// Prompt for Claude. The parser also reads free text, but this keeps it exact.
    static let claudePrompt = """
    Maak een hardloopschema voor mij. Geef het schema zonder uitleg, zodat ik het in mijn app kan plakken. Gebruik dit formaat:

    Naam van het event
    tijd 07:00

    2026-12-01 Di intervallen
    warmup 10 min z2
    5x 3 min z4 / 2 min z2
    cooldown

    2026-12-03 Do duurloop
    10 km z2

    Elke training begint met een datum en een korte naam. Daaronder per regel een warmup, herhalingen ("5x hard / herstel"), een gewone loop of een cooldown. Doelen als 45 sec, 3 min, 8 km, 400 m of open. Hartslagzone z1 tot z5 erachter.

    Mijn doel:
    """

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
        t = replace(t, #"^(?:mijn\s+)?(?:(?:trainings|hardloop|loop)?schema|plan|programma|training)\s+(?:voor|naar|richting)\s+(?:de|het)?\s*"#, "")
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

    private static func step(_ raw: String, line: String) throws -> (goal: GoalSpec, zone: Int?) {
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

        // Words are fine. Leftover numbers mean something we could not read.
        if s.contains(where: \.isNumber) {
            throw ParseError(message: "\"\(line.trimmingCharacters(in: .whitespaces))\": dit snap ik nog niet. Noem tijden en afstanden zoals 3 min, 45 sec, 5 km of 400 m.")
        }
        if zone == nil { zone = inferredZone(s) }
        return (goal, zone)
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
