import Foundation
import WorkoutKit

// Talks to WorkoutScheduler: authorize, clear, schedule, and read back.

struct ScheduleResult {
    var scheduled: Int
    var skippedPast: Int
    var overLimit: Int
    var limit: Int
    var missing: [String]
}

enum ScheduleServiceError: LocalizedError {
    case notSupported
    case notAuthorized
    case nothingToSchedule
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Plannen werkt hier niet. Je hebt een iPhone met een gekoppelde Apple Watch nodig."
        case .notAuthorized:
            return "Geen toestemming om trainingen te plannen. Zet het aan in Instellingen > Watch Planner."
        case .nothingToSchedule:
            return "Er staan geen trainingen meer op de planning vanaf vandaag."
        case .invalidDate(let name):
            return "\"\(name)\" heeft een ongeldige datum of tijd."
        }
    }
}

/// One workout as WorkoutKit reports it on the Watch.
struct WatchItem: Identifiable {
    let id: String
    let name: String
    let date: Date?
    let complete: Bool
    let workoutID: String?   // matching PlannedWorkout.id, if we still have it
    let plan: WorkoutPlan
    let components: DateComponents
}

@MainActor
final class ScheduleService {
    private let scheduler = WorkoutScheduler.shared

    /// What is on the Watch right now (only workouts this app scheduled),
    /// matched against our events where possible.
    func watchItems(events: [TrainingSchedule]) async -> [WatchItem] {
        guard WorkoutScheduler.isSupported, await Self.isAuthorized() else { return [] }
        var byPlanID: [UUID: PlannedWorkout] = [:]
        for w in events.flatMap(\.workouts) {
            byPlanID[WorkoutBuilder.plan(for: w).id] = w
        }
        return await scheduler.scheduledWorkouts.map { item in
            let known = byPlanID[item.plan.id]
            var name = known?.name ?? "Training"
            if case .custom(let custom) = item.plan.workout, let display = custom.displayName {
                name = display
            }
            return WatchItem(
                id: "\(item.plan.id)-\(item.date.year ?? 0)-\(item.date.month ?? 0)-\(item.date.day ?? 0)",
                name: name,
                date: ScheduleDates.calendar.date(from: item.date),
                complete: item.complete,
                workoutID: known?.id,
                plan: item.plan,
                components: item.date
            )
        }
        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    // WorkoutKit's AuthorizationState is not Sendable, so keep it off the main actor.
    nonisolated private static func isAuthorized() async -> Bool {
        await WorkoutScheduler.shared.authorizationState == .authorized
    }

    nonisolated private static func authorize() async -> Bool {
        let scheduler = WorkoutScheduler.shared
        if await scheduler.authorizationState == .notDetermined {
            return await scheduler.requestAuthorization() == .authorized
        }
        return await scheduler.authorizationState == .authorized
    }

    /// Takes one workout off the Watch, for example after deleting it.
    func remove(_ workout: PlannedWorkout, time: String) async {
        guard let when = ScheduleDates.components(day: workout.date, time: time) else { return }
        await remove(plan: WorkoutBuilder.plan(for: workout), at: when)
    }

    /// Takes one item off the Watch, as listed by watchItems.
    func remove(_ item: WatchItem) async {
        await remove(plan: item.plan, at: item.components)
    }

    /// remove(_:at:) needs the exact plan and date it was scheduled with, and says
    /// nothing when it finds no match. So remove with a clean date, check, and if
    /// it is still there, clear everything and put the others back.
    private func remove(plan: WorkoutPlan, at date: DateComponents) async {
        guard WorkoutScheduler.isSupported, await Self.isAuthorized() else { return }
        let clean = Self.clean(date)
        await scheduler.remove(plan, at: clean)

        func isTarget(_ s: ScheduledWorkoutPlan) -> Bool {
            s.plan.id == plan.id && Self.clean(s.date) == clean
        }
        let remaining = await scheduler.scheduledWorkouts
        guard remaining.contains(where: isTarget) else { return }

        let others = remaining.filter { !isTarget($0) }
        await scheduler.removeAllWorkouts()
        for other in others {
            await scheduler.schedule(other.plan, at: Self.clean(other.date))
        }
    }

    /// Only year, month, day, hour and minute.
    private static func clean(_ c: DateComponents) -> DateComponents {
        DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    func removeAll() async {
        guard WorkoutScheduler.isSupported, await Self.isAuthorized() else { return }
        await scheduler.removeAllWorkouts()
    }

    /// Adds these workouts to the Watch without touching the rest. Replaces them if they were there.
    func add(_ workouts: [PlannedWorkout], time: String) async throws -> ScheduleResult {
        guard WorkoutScheduler.isSupported else { throw ScheduleServiceError.notSupported }
        guard await Self.authorize() else { throw ScheduleServiceError.notAuthorized }

        let upcoming = workouts.filter { !ScheduleDates.isPast($0.date) }.sorted { $0.date < $1.date }
        guard !upcoming.isEmpty else { throw ScheduleServiceError.nothingToSchedule }

        var plans: [(PlannedWorkout, WorkoutPlan, DateComponents)] = []
        for w in upcoming {
            guard let when = ScheduleDates.components(day: w.date, time: time) else {
                throw ScheduleServiceError.invalidDate(w.name)
            }
            plans.append((w, WorkoutBuilder.plan(for: w), when))
        }

        let ids = Set(plans.map(\.1.id))
        let current = await scheduler.scheduledWorkouts
        let others = current.filter { !ids.contains($0.plan.id) }.count
        let limit = WorkoutScheduler.maxAllowedScheduledWorkoutCount
        let room = max(0, limit - others)

        for s in current where ids.contains(s.plan.id) {
            await scheduler.remove(s.plan, at: Self.clean(s.date))
        }
        for (_, plan, when) in plans.prefix(room) {
            await scheduler.schedule(plan, at: when)
        }

        let landed = Set(await scheduler.scheduledWorkouts.map(\.plan.id))
        let tried = Array(plans.prefix(room))
        let missing = tried.filter { !landed.contains($0.1.id) }.map(\.0.name)
        return ScheduleResult(
            scheduled: tried.count - missing.count,
            skippedPast: workouts.count - upcoming.count,
            overLimit: plans.count - tried.count,
            limit: limit,
            missing: missing
        )
    }

    /// Replaces everything on the Watch with the upcoming workouts of all events.
    func planOnWatch(_ events: [TrainingSchedule]) async throws -> ScheduleResult {
        guard WorkoutScheduler.isSupported else { throw ScheduleServiceError.notSupported }
        guard await Self.authorize() else { throw ScheduleServiceError.notAuthorized }

        let all = events.flatMap { e in e.workouts.map { (workout: $0, time: e.defaultTime) } }
        let upcoming = all
            .filter { !ScheduleDates.isPast($0.workout.date) }
            .sorted { $0.workout.date < $1.workout.date }
        guard !upcoming.isEmpty else { throw ScheduleServiceError.nothingToSchedule }

        let limit = WorkoutScheduler.maxAllowedScheduledWorkoutCount
        let toSchedule = Array(upcoming.prefix(limit))

        // Build everything first, so a bad date does not leave the Watch half empty.
        var plans: [(PlannedWorkout, WorkoutPlan, DateComponents)] = []
        for (w, time) in toSchedule {
            guard let when = ScheduleDates.components(day: w.date, time: time) else {
                throw ScheduleServiceError.invalidDate(w.name)
            }
            plans.append((w, WorkoutBuilder.plan(for: w), when))
        }

        await scheduler.removeAllWorkouts()
        for (_, plan, when) in plans {
            await scheduler.schedule(plan, at: when)
        }

        // schedule(_:at:) does not throw, so check what actually landed.
        let landed = Set(await scheduler.scheduledWorkouts.map(\.plan.id))
        let missing = plans.filter { !landed.contains($0.1.id) }.map(\.0.name)

        return ScheduleResult(
            scheduled: plans.count - missing.count,
            skippedPast: all.count - upcoming.count,
            overLimit: upcoming.count - toSchedule.count,
            limit: limit,
            missing: missing
        )
    }
}
