import SwiftUI

// Shared Watch state for all screens: what is on the Watch, and adding or removing workouts.

@MainActor
@Observable
final class Planner {
    var watchItems: [WatchItem] = []
    var isBusy = false
    var message: Message?

    private let service = ScheduleService()

    var onWatchIDs: Set<String> { Set(watchItems.compactMap(\.workoutID)) }

    /// Workouts added without a date through Apple's preview. The app cannot see the
    /// Watch's own workouts, so this is what the user told us.
    private(set) var customIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "customWorkouts") ?? [])

    func setCustom(_ id: String, _ added: Bool) {
        if added { customIDs.insert(id) } else { customIDs.remove(id) }
        UserDefaults.standard.set(Array(customIDs), forKey: "customWorkouts")
    }

    func refresh(_ events: [TrainingSchedule]) async {
        watchItems = await service.watchItems(events: events)
    }

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
            message = Message(title: "Toevoegen lukt niet", text: error.localizedDescription)
        }
    }

    func remove(_ workouts: [PlannedWorkout], time: String, events: [TrainingSchedule]) async {
        for w in workouts where onWatchIDs.contains(w.id) {
            await service.remove(w, time: time)
        }
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
                     "Op je Watch zie je in Workout, in het blok Rondje, de trainingen van de komende 7 dagen. Latere komen er vanzelf bij."]
        if r.skippedPast > 0 {
            lines.append("\(r.skippedPast) overgeslagen omdat ze al geweest zijn.")
        }
        if r.overLimit > 0 {
            lines.append("Let op: je Watch kan er maar \(r.limit) tegelijk hebben. De eerste \(r.limit) staan erop, \(r.overLimit) nog niet. Voeg de rest later toe.")
        }
        if !r.missing.isEmpty {
            lines.append("Niet gelukt: \(r.missing.joined(separator: ", ")).")
        }
        self.init(title: r.missing.isEmpty ? "Toegevoegd" : "Deels gelukt", text: lines.joined(separator: "\n\n"))
    }
}
