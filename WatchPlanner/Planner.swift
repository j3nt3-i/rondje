import SwiftUI

// Shared Watch state for all screens: what is on the Watch, and the plan action.

@MainActor
@Observable
final class Planner {
    var watchItems: [WatchItem] = []
    var isBusy = false
    var message: Message?

    fileprivate let service = ScheduleService()

    var onWatchIDs: Set<String> { Set(watchItems.compactMap(\.workoutID)) }

    func refresh(_ events: [TrainingSchedule]) async {
        watchItems = await service.watchItems(events: events)
    }

    func remove(_ workouts: [PlannedWorkout], time: String, events: [TrainingSchedule]) async {
        for w in workouts where onWatchIDs.contains(w.id) {
            await service.remove(w, time: time)
        }
        await refresh(events)
    }
}

extension Planner {
    /// Puts these workouts on the Watch, next to what is already there.
    func put(_ workouts: [PlannedWorkout], time: String, title: String, events: [TrainingSchedule]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let r = try await service.add(workouts, time: time)
            await refresh(events)
            var m = Message(r)
            m.title = title
            message = m
        } catch {
            message = Message(title: "Klaarzetten lukt niet", text: error.localizedDescription)
        }
    }

    func clearWatch(events: [TrainingSchedule]) async {
        await service.removeAll()
        await refresh(events)
    }
}

struct Message: Identifiable {
    let id = UUID()
    var title: String
    var text: String
}

extension Message {
    init(_ r: ScheduleResult) {
        var lines = ["\(r.scheduled) trainingen toegevoegd.",
                     "Elke training staat op de dag zelf bovenaan in Workout op je Watch, in het blok Rondje."]
        if r.skippedPast > 0 {
            lines.append("\(r.skippedPast) overgeslagen omdat ze al geweest zijn.")
        }
        if r.overLimit > 0 {
            lines.append("Let op: je Watch kan er maar \(r.limit) tegelijk hebben. De eerste \(r.limit) staan erop, \(r.overLimit) nog niet. Plan later opnieuw.")
        }
        if !r.missing.isEmpty {
            lines.append("Niet gelukt: \(r.missing.joined(separator: ", ")).")
        }
        self.init(title: r.missing.isEmpty ? "Toegevoegd" : "Deels gelukt", text: lines.joined(separator: "\n\n"))
    }
}
