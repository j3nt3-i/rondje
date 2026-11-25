import Foundation

// Short text format for typing a workout, one part per line (or split with ";"):
//
//   warmup 10 min z2
//   5x 3 min z4 / 2 min z2
//   cooldown
//
// A line without a keyword or "Nx" is a single run, like "12 km z2".
// Units: sec / s, min, km / k, m (meters). Zone: z1 to z5, optional.

enum WorkoutText {
    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func workout(date: String, name: String, text: String) throws -> PlannedWorkout {
        var warmup: StepSpec?
        var cooldown: StepSpec?
        var blocks: [BlockSpec] = []

        let lines = text
            .split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.lowercased()
            if let rest = strip(lower, prefixes: ["warming-up", "warmingup", "warmup", "inlopen", "wu"]) {
                let s = try step(rest, line: line)
                warmup = StepSpec(goal: s.goal, zone: s.zone)
            } else if let rest = strip(lower, prefixes: ["cooling-down", "coolingdown", "cooldown", "uitlopen", "cd"]) {
                let s = try step(rest, line: line)
                cooldown = StepSpec(goal: s.goal, zone: s.zone)
            } else if let m = match(#"^(\d+)\s*[x×]\s*(.+)$"#, lower), let n = Int(m[1]) {
                guard (1...99).contains(n) else { throw ParseError(message: "\"\(line)\": herhaal 1 tot 99 keer.") }
                let body = m[2].trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                let parts = body.split(whereSeparator: { $0 == "/" || $0 == "+" }).map(String.init)
                var steps: [IntervalSpec] = []
                for (i, part) in parts.enumerated() {
                    let s = try step(part, line: line)
                    steps.append(IntervalSpec(purpose: purpose(part, index: i), goal: s.goal, zone: s.zone))
                }
                blocks.append(BlockSpec(iterations: n, steps: steps))
            } else {
                let s = try step(lower, line: line)
                if s.goal.type == .open && !lower.contains("open") {
                    throw ParseError(message: "\"\(line)\": snap ik niet. Bedoel je iets als \"8 km z2\" of \"30 min z2\"?")
                }
                blocks.append(BlockSpec(iterations: 1, steps: [IntervalSpec(purpose: .work, goal: s.goal, zone: s.zone)]))
            }
        }

        guard !blocks.isEmpty else {
            throw ParseError(message: "Zet er minstens één loop of herhaling in, zoals \"8 km z2\" of \"5x 3 min z4 / 2 min z2\".")
        }
        let workout = PlannedWorkout(date: date, name: name, warmup: warmup, blocks: blocks, cooldown: cooldown)
        try TrainingSchedule(name: "", defaultTime: "07:00", workouts: [workout]).validate()
        return workout
    }

    /// Name like "Do 5x3 min" or "Zo 12 km", when none is given.
    static func autoName(date: String, for w: PlannedWorkout) -> String {
        let weekday = ScheduleDates.day(date).map(Format.shortWeekday) ?? "Training"
        let blocks = w.blocks ?? []
        guard let main = blocks.first(where: { $0.iterations > 1 }) ?? blocks.first else { return weekday }
        let goal = main.steps[0].goal
        if main.iterations == 1 { return "\(weekday) \(goal.type == .open ? "loop" : goal.label)" }
        return "\(weekday) \(main.iterations)x \(goal.label)"
    }

    /// The same format back, so a workout can be copied and edited.
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

    // MARK: - Whole program

    // Program format:
    //
    //   Devil's Trail 15 km
    //   tijd 07:00
    //
    //   2026-11-26 Do 5x3 stevig
    //   warmup 10 min z2
    //   5x 3 min z4 / 2 min z2
    //   cooldown
    //
    // A line starting with a date starts a new workout. Lines before the first
    // date hold the event name (the last one counts) and an optional start time. "//" starts a note.
    // JSON in the old format works too.

    static func program(_ text: String) throws -> TrainingSchedule {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return try TrainingSchedule.decode(Data(trimmed.utf8))
        }

        var eventName: String?
        var time = "07:00"
        var workouts: [PlannedWorkout] = []
        var current: (date: String, name: String, lines: [String])?

        func finish() throws {
            guard let c = current else { return }
            let label = c.name.isEmpty ? c.date : c.name
            do {
                var w = try workout(date: c.date, name: c.name.isEmpty ? "x" : c.name, text: c.lines.joined(separator: "\n"))
                if c.name.isEmpty { w.name = autoName(date: c.date, for: w) }
                workouts.append(w)
            } catch {
                throw ParseError(message: "\(label): \(error.localizedDescription)")
            }
            current = nil
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = clean(raw)
            if line.isEmpty { continue }
            if let m = match(#"^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{4})\b\s*[:,]?\s*(.*)$"#, line) {
                try finish()
                guard let date = isoDate(m[1]) else {
                    throw ParseError(message: "\"\(m[1])\" is geen geldige datum.")
                }
                current = (date, m[2].trimmingCharacters(in: CharacterSet(charactersIn: " -:")), [])
            } else if current != nil {
                current?.lines.append(line)
            } else if let m = match(#"^(?:tijd|starttijd|time)\s*:?\s*(\d{1,2})[:.](\d{2})$"#, line) {
                time = String(format: "%02d:%@", Int(m[1]) ?? 7, m[2])
            } else if workouts.isEmpty {
                // Chatbots often start with an intro line, so the last line before the first date wins.
                eventName = line.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            }
        }
        try finish()

        guard let eventName, !eventName.isEmpty else {
            throw ParseError(message: "Zet de naam van het event op de eerste regel.")
        }
        guard !workouts.isEmpty else {
            throw ParseError(message: "Geen trainingen gevonden. Begin elke training met een datum, zoals 2026-12-01.")
        }
        let schedule = TrainingSchedule(name: eventName, defaultTime: time, workouts: workouts.sorted { $0.date < $1.date })
        try schedule.validate()
        return schedule
    }

    static func programText(for e: TrainingSchedule) -> String {
        var parts = ["\(e.name)\ntijd \(e.defaultTime)"]
        for w in e.workouts {
            parts.append("\(w.date) \(w.name)\n" + text(for: w))
        }
        return parts.joined(separator: "\n\n")
    }

    /// Prompt to give Claude (or any chatbot) so it answers in this format.
    static let claudePrompt = """
    Maak een hardloopschema voor mij en geef het ALLEEN in dit tekstformaat, zonder uitleg ervoor of erna, zodat ik het in mijn app kan plakken:

    Naam van het event
    tijd 07:00

    2026-12-01 Di intervallen
    warmup 10 min z2
    5x 3 min z4 / 2 min z2
    cooldown

    2026-12-03 Do duurloop
    10 km z2

    Regels:
    - Eerste regel: naam van het event (bijvoorbeeld de wedstrijd). Daarna "tijd HH:MM" voor de starttijd.
    - Elke training begint met een datum (yyyy-mm-dd) en een korte naam.
    - Daaronder één onderdeel per regel:
      - "warmup <doel>" en "cooldown" of "cooldown <doel>"
      - herhalingen: "<aantal>x <hard> / <herstel>"
      - een gewone loop: "<doel>"
    - Doel: "45 sec", "3 min", "8 km", "400 m" of "open".
    - Hartslagzone optioneel met z1 tot z5 achter het doel.
    - Geen andere tekst, geen opsommingstekens, geen markdown.

    Mijn doel:
    """

    // MARK: - Helpers

    /// Strips markdown that chatbots like to add.
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

    private static func purpose(_ part: String, index: Int) -> IntervalSpec.Purpose {
        let p = part.lowercased()
        if ["herstel", "rust", "dribbel", "jog", "wandel"].contains(where: p.contains) { return .recovery }
        if ["hard", "snel", "stevig"].contains(where: p.contains) { return .work }
        return index.isMultiple(of: 2) ? .work : .recovery
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

        let unitPattern = #"(\d+(?:[.,]\d+)?)\s*(km|k|minuten|minuut|min|m|seconden|sec|s|'|")(?![a-z])"#
        if let m = match(unitPattern, s), let value = Double(m[1].replacingOccurrences(of: ",", with: ".")) {
            switch m[2] {
            case "km", "k": goal = GoalSpec(type: .distance, value: value, unit: "km")
            case "m": goal = GoalSpec(type: .distance, value: value / 1000, unit: "km")
            case "minuten", "minuut", "min", "'": goal = GoalSpec(type: .time, value: value, unit: "min")
            default: goal = GoalSpec(type: .time, value: value, unit: "sec")
            }
            s = s.replacingOccurrences(of: m[0], with: " ")
        }

        // Words like "hard" or "rustig" are fine. Leftover numbers mean a typo.
        if s.contains(where: \.isNumber) {
            throw ParseError(message: "\"\(line)\": snap ik niet. Schrijf het als \"3 min\", \"45 sec\", \"5 km\" of \"400 m\".")
        }
        return (goal, zone)
    }

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }
}
