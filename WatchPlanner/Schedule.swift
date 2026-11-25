import Foundation
import Observation

// The JSON training schedule, as stored in schedule.json.

struct TrainingSchedule: Codable, Equatable {
    var name: String
    var defaultTime: String
    var workouts: [PlannedWorkout]
}

struct PlannedWorkout: Codable, Equatable, Identifiable {
    var date: String
    var name: String
    var warmup: StepSpec?
    var blocks: [BlockSpec]?
    var cooldown: StepSpec?

    var id: String { "\(date) \(name)" }
}

struct BlockSpec: Codable, Equatable {
    var iterations: Int
    var steps: [IntervalSpec]
}

struct IntervalSpec: Codable, Equatable {
    var purpose: Purpose
    var goal: GoalSpec
    var zone: Int?

    enum Purpose: String, Codable { case work, recovery }
}

struct StepSpec: Codable, Equatable {
    var goal: GoalSpec
    var zone: Int?
}

struct GoalSpec: Codable, Equatable {
    var type: GoalType
    var value: Double?
    var unit: String?

    enum GoalType: String, Codable { case time, distance, open }
}

// MARK: - Dates

enum ScheduleDates {
    static let calendar = Calendar.current

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ string: String) -> Date? {
        dayFormatter.date(from: string)
    }

    /// "07:00" -> (7, 0)
    static func time(_ string: String) -> (hour: Int, minute: Int)? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    /// Date plus default time, as the components WorkoutScheduler wants.
    static func components(day: String, time: String) -> DateComponents? {
        guard let date = self.day(day), let t = self.time(time) else { return nil }
        var c = calendar.dateComponents([.year, .month, .day], from: date)
        c.hour = t.hour
        c.minute = t.minute
        return c
    }

    static func isPast(_ day: String, now: Date = .now) -> Bool {
        guard let date = self.day(day) else { return true }
        return date < calendar.startOfDay(for: now)
    }
}

// MARK: - Validation

struct ScheduleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension TrainingSchedule {
    /// Decodes and checks a schedule. Throws a ScheduleError with a Dutch message.
    static func decode(_ data: Data) throws -> TrainingSchedule {
        let schedule: TrainingSchedule
        do {
            schedule = try JSONDecoder().decode(TrainingSchedule.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw ScheduleError(message: "Veld \"\(key.stringValue)\" ontbreekt\(path(ctx)).")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw ScheduleError(message: "Geen geldige JSON\(path(ctx)).")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw ScheduleError(message: "Verkeerd type\(path(ctx)).")
        } catch let DecodingError.valueNotFound(_, ctx) {
            throw ScheduleError(message: "Waarde ontbreekt\(path(ctx)).")
        } catch {
            throw ScheduleError(message: "Geen geldige JSON.")
        }
        try schedule.validate()
        return schedule
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        let p = ctx.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        return p.isEmpty ? "" : " bij \(p)"
    }

    func validate() throws {
        guard ScheduleDates.time(defaultTime) != nil else {
            throw ScheduleError(message: "defaultTime moet zoiets zijn als \"07:00\".")
        }
        guard !workouts.isEmpty else {
            throw ScheduleError(message: "Er staan geen trainingen in het schema.")
        }
        for w in workouts {
            let label = "\"\(w.name)\""
            guard ScheduleDates.day(w.date) != nil else {
                throw ScheduleError(message: "\(label): datum moet yyyy-mm-dd zijn.")
            }
            let blocks = w.blocks ?? []
            if blocks.isEmpty {
                throw ScheduleError(message: "\(label): voeg minstens een block toe.")
            }
            try w.warmup.map { try $0.validate(label) }
            try w.cooldown.map { try $0.validate(label) }
            for b in blocks {
                guard b.iterations >= 1 else {
                    throw ScheduleError(message: "\(label): iterations moet minstens 1 zijn.")
                }
                guard !b.steps.isEmpty else {
                    throw ScheduleError(message: "\(label): een block heeft geen stappen.")
                }
                for s in b.steps {
                    try s.goal.validate(label)
                    try validateZone(s.zone, label)
                }
            }
        }
    }
}

private func validateZone(_ zone: Int?, _ label: String) throws {
    if let zone, !(1...5).contains(zone) {
        throw ScheduleError(message: "\(label): zone moet tussen 1 en 5 liggen.")
    }
}

extension StepSpec {
    func validate(_ label: String) throws {
        try goal.validate(label)
        try validateZone(zone, label)
    }
}

extension GoalSpec {
    func validate(_ label: String) throws {
        switch type {
        case .open:
            return
        case .time:
            guard unit == "sec" || unit == "min" else {
                throw ScheduleError(message: "\(label): tijd heeft unit \"sec\" of \"min\" nodig.")
            }
        case .distance:
            guard unit == "km" else {
                throw ScheduleError(message: "\(label): afstand heeft unit \"km\" nodig.")
            }
        }
        guard let value, value > 0 else {
            throw ScheduleError(message: "\(label): een doel heeft een waarde groter dan 0 nodig.")
        }
    }

    /// Short Dutch label, like "3 min" or "12 km".
    var label: String {
        switch type {
        case .open: return "open"
        default:
            let v = value ?? 0
            let number = v == v.rounded() ? String(Int(v)) : String(v)
            return "\(number) \(unit ?? "")"
        }
    }
}

// MARK: - Store


// Holds the current schedule. A pasted schedule is saved in Documents
// and wins over the bundled default.

@MainActor
@Observable
final class ScheduleStore {
    private(set) var schedule: TrainingSchedule?
    private(set) var loadError: String?

    private var savedURL: URL {
        URL.documentsDirectory.appending(path: "schedule.json")
    }

    init() { load() }

    func load() {
        do {
            let url = FileManager.default.fileExists(atPath: savedURL.path())
                ? savedURL
                : Bundle.main.url(forResource: "schedule", withExtension: "json")
            guard let url else { throw ScheduleError(message: "schedule.json ontbreekt in de app.") }
            schedule = try TrainingSchedule.decode(Data(contentsOf: url))
            loadError = nil
        } catch {
            schedule = nil
            loadError = error.localizedDescription
        }
    }

    /// Validates the text and replaces the current schedule.
    func replace(with text: String) throws {
        let data = Data(text.utf8)
        let new = try TrainingSchedule.decode(data)
        try data.write(to: savedURL, options: .atomic)
        schedule = new
        loadError = nil
    }
}
