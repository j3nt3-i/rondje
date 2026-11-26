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

    private let store = HKHealthStore()
    private var events: [TrainingSchedule] = []

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.heartRate)]
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
        guard asked else { return }
        await load()
    }

    /// Shows Apple's permission sheet, then reads your runs.
    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
        await refresh(events)
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
