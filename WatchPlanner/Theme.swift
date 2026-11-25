import SwiftUI

// Dark look in the style of the Fitness app.

enum Theme {
    static let accent = Color(red: 0.66, green: 1.0, blue: 0.0)   // Fitness lime
    static let card = Color(white: 0.11)
    static let background = Color.black

    static func zone(_ zone: Int?) -> Color {
        switch zone {
        case 1: .blue
        case 2: .cyan
        case 3: .green
        case 4: .orange
        case 5: .red
        default: Color(white: 0.35)
        }
    }
}

// MARK: - Workout kind and icon

enum WorkoutKind {
    case easy, intervals, hills, race

    init(_ w: PlannedWorkout, scheduleName: String?) {
        let name = w.name.lowercased()
        let blocks = w.blocks ?? []
        if w.name == scheduleName || name.contains("wedstrijd") {
            self = .race
        } else if name.contains("heuvel") {
            self = .hills
        } else if blocks.count == 1, blocks[0].iterations == 1, blocks[0].steps.count == 1, w.warmup == nil {
            self = .easy
        } else {
            self = .intervals
        }
    }

    var icon: String {
        switch self {
        case .easy: "figure.run"
        case .intervals: "stopwatch.fill"
        case .hills: "mountain.2.fill"
        case .race: "flag.checkered"
        }
    }

    var color: Color {
        switch self {
        case .easy: .cyan
        case .intervals: .orange
        case .hills: .green
        case .race: Theme.accent
        }
    }
}

struct KindIcon: View {
    let kind: WorkoutKind
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(kind.color)
            .frame(width: size, height: size)
            .background(kind.color.opacity(0.18), in: Circle())
    }
}

struct ZoneChip: View {
    let zone: Int?

    var body: some View {
        if let zone {
            Text("Z\(zone)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.zone(zone), in: Capsule())
        }
    }
}

// MARK: - Steps as rows

struct StepLine: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let zone: Int?
    var isRepeat = false
    var indented = false
}

extension PlannedWorkout {
    var stepLines: [StepLine] {
        var lines: [StepLine] = []
        func add(_ title: String, _ goal: GoalSpec?, _ zone: Int?, isRepeat: Bool = false, indented: Bool = false) {
            let detail = goal.map { $0.type == .open ? "Open" : $0.label } ?? ""
            lines.append(StepLine(id: lines.count, title: title, detail: detail, zone: zone,
                                  isRepeat: isRepeat, indented: indented))
        }
        if let wu = warmup { add("Warming-up", wu.goal, wu.zone) }
        for b in blocks ?? [] {
            if b.iterations == 1 && b.steps.count == 1 {
                add("Loop", b.steps[0].goal, b.steps[0].zone)
            } else {
                add("\(b.iterations)x herhalen", nil, nil, isRepeat: true)
                for s in b.steps {
                    add(s.purpose == .work ? "Hard" : "Herstel", s.goal, s.zone, indented: true)
                }
            }
        }
        if let cd = cooldown { add("Cooling-down", cd.goal, cd.zone) }
        return lines
    }
}

struct StepLineView: View {
    let line: StepLine

    var body: some View {
        if line.isRepeat {
            Label(line.title, systemImage: "repeat")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.accent)
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.zone(line.zone))
                    .frame(width: 4, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(line.detail)
                        .font(.system(.title3, design: .rounded).bold())
                }
                Spacer()
                if line.zone == nil {
                    Text("Geen alert").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ZoneChip(zone: line.zone)
                }
            }
            .padding(.leading, line.indented ? 16 : 0)
        }
    }
}

// MARK: - Formatting

enum Format {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = format
        return f
    }

    private static let long = formatter("EEEE d MMMM")
    private static let short = formatter("EEE d MMM")
    private static let weekday = formatter("EEE")
    private static let dayMonth = formatter("d MMMM")

    /// "Donderdag 26 november"
    static func day(_ string: String) -> String {
        guard let date = ScheduleDates.day(string) else { return string }
        return capitalized(long.string(from: date))
    }

    /// "Do 26 nov"
    static func shortDay(_ date: Date) -> String {
        capitalized(short.string(from: date).replacingOccurrences(of: ".", with: ""))
    }

    static func shortDay(_ string: String) -> String {
        ScheduleDates.day(string).map(shortDay) ?? string
    }

    /// "Do"
    static func shortWeekday(_ date: Date) -> String {
        capitalized(weekday.string(from: date).replacingOccurrences(of: ".", with: ""))
    }

    /// "26 november"
    static func dayMonth(_ date: Date) -> String {
        dayMonth.string(from: date)
    }

    private static func capitalized(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }
}

// MARK: - Workout row

struct WorkoutRow: View {
    let workout: PlannedWorkout
    let kind: WorkoutKind
    let isPast: Bool
    /// Nil hides the Watch status (for example in the import preview).
    var onWatch: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            KindIcon(kind: kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.headline)
                Text(Format.shortDay(workout.date))
                    .font(.subheadline)
                    .foregroundStyle(kind.color)
                Text(WorkoutText.text(for: workout, zones: false, separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let status {
                Text(status.text)
                    .font(.caption.bold())
                    .foregroundStyle(status.color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
        }
        .opacity(isPast ? 0.45 : 1)
        .padding(.vertical, 2)
    }

    private var status: (text: String, color: Color)? {
        if isPast { return ("Geweest", .secondary) }
        guard let onWatch else { return nil }
        guard onWatch else { return ("Niet op Watch", .secondary) }
        // The Watch shows a week ahead, so later workouts appear 7 days before.
        let cal = ScheduleDates.calendar
        if let day = ScheduleDates.day(workout.date),
           let visible = cal.date(byAdding: .day, value: -7, to: day),
           visible > cal.startOfDay(for: .now) {
            return ("Op Watch vanaf \(Format.shortDay(visible).lowercased())", Theme.accent.opacity(0.75))
        }
        return ("Op Watch", Theme.accent)
    }
}
