import Foundation
import HealthKit
import Observation
import WorkoutKit

// What you really ran, read from Apple Health, to tick off your planned workouts.
// Rondje only reads. Without permission it sees nothing, and everything else works as before.

/// One run from Apple Health.
struct DoneRun: Equatable {
    var start: Date
    var minutes: Double
    var km: Double?
    var heartRate: Double?

    /// "5:42 /km", when the distance is known.
    var pace: String? {
        guard let km, km > 0.05 else { return nil }
        let seconds = Int((minutes * 60 / km).rounded())
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }

    /// "8,2 km", or the time when Health has no distance.
    var short: String {
        if let km, km > 0.05 { return DoneRun.kmText(km) }
        return DoneRun.timeText(minutes)
    }

    static func kmText(_ km: Double) -> String {
        km.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "nl_NL"))) + " km"
    }

    static func timeText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) u \(m % 60) min" : "\(m) min"
    }
}

/// How you have been running lately, read from Apple Health for the "Nieuw doel" chat.
/// Only measured facts, nothing estimated. Rondje shows them and never stores them.
struct RunLevel: Equatable {
    /// Runs in the last 4 weeks, and their distance together.
    var runs: Int
    var km: Double
    /// Your longest run in the last 12 weeks.
    var longestKm: Double?
    /// Average pace over the last 4 weeks, like "5:42 /km".
    var pace: String?
    /// Your latest VO2max from the last 12 weeks, in ml/kg/min.
    var vo2Max: Double?

    private var kmPerWeek: String { DoneRun.kmText(km / 4) }

    /// What Rondje says in the chat.
    var said: String {
        var parts: [String] = []
        if runs == 0 {
            parts.append("De laatste 4 weken zie ik geen loopjes.")
        } else if km > 0.05 {
            parts.append("De laatste 4 weken liep je \(runs) keer, samen \(DoneRun.kmText(km)). Dat is zo'n \(kmPerWeek) per week.")
        } else {
            parts.append("De laatste 4 weken liep je \(runs) keer.")
        }
        if let longestKm { parts.append("Je langste loop in 3 maanden was \(DoneRun.kmText(longestKm)).") }
        switch (pace, vo2Max.map(RunLevel.vo2Text)) {
        case let (pace?, vo2?): parts.append("Je tempo is gemiddeld \(pace) en je VO2max \(vo2).")
        case let (pace?, nil): parts.append("Je tempo is gemiddeld \(pace).")
        case let (nil, vo2?): parts.append("Je VO2max is \(vo2).")
        case (nil, nil): break
        }
        return parts.joined(separator: " ")
    }

    /// The same facts for the prompt, written from your side.
    var prompt: String {
        var parts: [String] = []
        if runs == 0 {
            parts.append("de laatste 4 weken geen loopjes")
        } else if km > 0.05 {
            parts.append("de laatste 4 weken \(runs) loopjes, samen \(DoneRun.kmText(km)) (ongeveer \(kmPerWeek) per week)")
        } else {
            parts.append("de laatste 4 weken \(runs) loopjes")
        }
        if let longestKm { parts.append("langste loop in de laatste 3 maanden \(DoneRun.kmText(longestKm))") }
        if let pace { parts.append("gemiddeld tempo \(pace)") }
        if let vo2Max { parts.append("VO2max \(RunLevel.vo2Text(vo2Max))") }
        return parts.joined(separator: ", ") + "."
    }

    /// Short, for the summary before you copy the prompt.
    var short: String {
        var parts: [String] = []
        if runs > 0, km > 0.05 { parts.append("\(kmPerWeek) per week") }
        if let longestKm { parts.append("langste \(DoneRun.kmText(longestKm))") }
        if let pace { parts.append(pace) }
        if parts.isEmpty, let vo2Max { parts.append("VO2max \(RunLevel.vo2Text(vo2Max))") }
        return parts.isEmpty ? "Geen loopjes in 4 weken" : parts.joined(separator: " · ")
    }

    static func vo2Text(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0)))
    }
}

@MainActor
@Observable
final class HealthLog {
    /// Planned workout id -> the run you did for it.
    private(set) var done: [String: DoneRun] = [:]
    /// True while Rondje has not asked for Apple Health yet: the home screen offers it.
    private(set) var canAsk = false
    /// True while Apple's permission sheet can still be shown, also after "Niet nu".
    private(set) var canConnect = false
    /// True once Rondje has asked. It cannot see whether you said yes: Health keeps that private.
    private(set) var asked = false
    /// True while there is still something to ask for the chat: everything, or only your VO2max.
    private(set) var canAskLevel = false

    private let store = HKHealthStore()
    private var events: [TrainingSchedule] = []

    /// What ticking off needs.
    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.heartRate)]
    }

    /// The same, and your VO2max for the chat. Asked in one go, so Apple's sheet shows once.
    private var allTypes: Set<HKObjectType> {
        readTypes.union([HKQuantityType(.vo2Max)])
    }

    /// "Niet nu" on the home screen: do not offer it again.
    var declined: Bool {
        get { UserDefaults.standard.bool(forKey: "healthDeclined") }
        set {
            UserDefaults.standard.set(newValue, forKey: "healthDeclined")
            if newValue { canAsk = false }
        }
    }

    /// Looks up which planned workouts you have done. Call when the app opens and when your goals change.
    func refresh(_ events: [TrainingSchedule]) async {
        self.events = events
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        asked = status == .unnecessary
        canConnect = status == .shouldRequest
        canAsk = canConnect && !declined
        canAskLevel = (try? await store.statusForAuthorizationRequest(toShare: [], read: allTypes)) == .shouldRequest
        guard asked else { return }
        await load()
    }

    /// Shows Apple's permission sheet, then reads your runs.
    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: allTypes)
        await refresh(events)
    }

    /// How you have been running lately, or nil when Health shows nothing from the last 12 weeks.
    /// Rondje cannot tell "no access" from "no runs": Health keeps that private.
    func level(now: Date = .now) async -> RunLevel? {
        guard HKHealthStore.isHealthDataAvailable(), asked else { return nil }
        let cal = ScheduleDates.calendar
        let today = cal.startOfDay(for: now)
        guard let month = cal.date(byAdding: .day, value: -28, to: today),
              let quarter = cal.date(byAdding: .day, value: -84, to: today) else { return nil }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: quarter, end: nil),
        ])
        let runs = (try? await HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                       sortDescriptors: [SortDescriptor(\.startDate)])
            .result(for: store)) ?? []

        // Your VO2max is asked separately, so it can be missing while the rest is there.
        let vo2Query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.vo2Max),
                                         predicate: HKQuery.predicateForSamples(withStart: quarter, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        let vo2 = (try? await vo2Query.result(for: store))?.first?
            .quantity.doubleValue(for: .literUnit(with: .milli)
                .unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())))

        guard !runs.isEmpty || vo2 != nil else { return nil }

        func km(_ w: HKWorkout) -> Double? {
            (w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() ?? w.totalDistance)?
                .doubleValue(for: .meterUnit(with: .kilo))
        }
        let recent = runs.filter { $0.startDate >= month }
        // Pace only over runs with a distance, so a treadmill run without one does not slow you down.
        let measured = recent.compactMap { w in km(w).flatMap { $0 > 0.05 ? (km: $0, minutes: w.duration / 60) : nil } }
        let total = measured.reduce(0) { $0 + $1.km }
        let minutes = measured.reduce(0) { $0 + $1.minutes }
        return RunLevel(
            runs: recent.count,
            km: total,
            longestKm: runs.compactMap(km).max().flatMap { $0 > 0.05 ? $0 : nil },
            pace: DoneRun(start: now, minutes: minutes, km: total).pace,
            vo2Max: vo2
        )
    }

    private func load() async {
        let planned = events.flatMap(\.workouts)
        guard let first = planned.compactMap({ ScheduleDates.day($0.date) }).min() else {
            done = [:]
            return
        }
        // A day early too: a run started from Rondje on your Watch counts whenever you did it.
        let from = ScheduleDates.calendar.date(byAdding: .day, value: -1, to: first) ?? first
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: from, end: nil),
        ])
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let workouts = try? await query.result(for: store) else { return }

        let byPlan = Dictionary(planned.map { (WorkoutBuilder.stableID(for: $0), $0.id) }) { a, _ in a }
        var found: [String: DoneRun] = [:]
        var loose: [(day: String, run: DoneRun)] = []
        for w in workouts {
            let run = DoneRun(
                start: w.startDate,
                minutes: w.duration / 60,
                km: (w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() ?? w.totalDistance)?
                    .doubleValue(for: .meterUnit(with: .kilo)),
                heartRate: w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            )
            // Started from Rondje on your Watch: Health knows exactly which workout it was.
            if let plan = try? await w.workoutPlan, let id = byPlan[plan.id], found[id] == nil {
                found[id] = run
            } else {
                loose.append((ScheduleDates.string(w.startDate), run))
            }
        }
        // Any other run counts for the workout planned on that day.
        for (day, run) in loose {
            if let w = planned.first(where: { $0.date == day && found[$0.id] == nil }) {
                found[w.id] = run
            }
        }
        done = found
    }
}
