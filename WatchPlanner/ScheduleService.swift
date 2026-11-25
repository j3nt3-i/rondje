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

@MainActor
final class ScheduleService {
    private let scheduler = WorkoutScheduler.shared

    /// Workout ids (PlannedWorkout.id) that are on the Watch right now.
    func scheduledIDs(in schedule: TrainingSchedule) async -> Set<String> {
        guard WorkoutScheduler.isSupported,
              await Self.isAuthorized() else { return [] }
        let planIDs = Set(await scheduler.scheduledWorkouts.map(\.plan.id))
        return Set(schedule.workouts
            .filter { planIDs.contains(WorkoutBuilder.plan(for: $0).id) }
            .map(\.id))
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

    func planOnWatch(_ schedule: TrainingSchedule) async throws -> ScheduleResult {
        guard WorkoutScheduler.isSupported else { throw ScheduleServiceError.notSupported }

        guard await Self.authorize() else { throw ScheduleServiceError.notAuthorized }

        let upcoming = schedule.workouts
            .filter { !ScheduleDates.isPast($0.date) }
            .sorted { $0.date < $1.date }
        guard !upcoming.isEmpty else { throw ScheduleServiceError.nothingToSchedule }

        let limit = WorkoutScheduler.maxAllowedScheduledWorkoutCount
        let toSchedule = Array(upcoming.prefix(limit))

        // Build everything first, so a bad date does not leave the Watch half empty.
        var plans: [(PlannedWorkout, WorkoutPlan, DateComponents)] = []
        for w in toSchedule {
            guard let when = ScheduleDates.components(day: w.date, time: schedule.defaultTime) else {
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
            skippedPast: schedule.workouts.count - upcoming.count,
            overLimit: upcoming.count - toSchedule.count,
            limit: limit,
            missing: missing
        )
    }
}
