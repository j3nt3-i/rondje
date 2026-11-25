import CryptoKit
import Foundation
import HealthKit
import WorkoutKit

// Turns a PlannedWorkout from the JSON into a WorkoutKit plan.

enum WorkoutBuilder {
    static func plan(for workout: PlannedWorkout) -> WorkoutPlan {
        let custom = CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: workout.name,
            warmup: workout.warmup.map(step),
            blocks: (workout.blocks ?? []).map(block),
            cooldown: workout.cooldown.map(step)
        )
        return WorkoutPlan(.custom(custom), id: stableID(for: workout))
    }

    private static func step(_ spec: StepSpec) -> WorkoutStep {
        WorkoutStep(goal: goal(spec.goal), alert: alert(spec.zone))
    }

    private static func block(_ spec: BlockSpec) -> IntervalBlock {
        let steps = spec.steps.map { s in
            IntervalStep(s.purpose == .work ? .work : .recovery, goal: goal(s.goal), alert: alert(s.zone))
        }
        return IntervalBlock(steps: steps, iterations: spec.iterations)
    }

    static func goal(_ spec: GoalSpec) -> WorkoutGoal {
        let value = spec.value ?? 0
        switch (spec.type, spec.unit) {
        case (.time, "sec"): return .time(value, .seconds)
        case (.time, _): return .time(value, .minutes)
        case (.distance, _): return .distance(value, .kilometers)
        case (.open, _): return .open
        }
    }

    private static func alert(_ zone: Int?) -> (any WorkoutAlert)? {
        zone.map { HeartRateZoneAlert(zone: $0) }
    }

    /// Same date and name give the same id, so a rerun replaces cleanly.
    private static func stableID(for workout: PlannedWorkout) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(workout.id.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
