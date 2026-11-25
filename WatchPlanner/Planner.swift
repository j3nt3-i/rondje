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

    func plan(_ events: [TrainingSchedule]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await service.planOnWatch(events)
            await refresh(events)
            message = Message(result)
        } catch {
            message = Message(title: "Plannen lukt niet", text: error.localizedDescription)
        }
    }

    func remove(_ workouts: [PlannedWorkout], time: String, events: [TrainingSchedule]) async {
        for w in workouts where onWatchIDs.contains(w.id) {
            await service.remove(w, time: time)
        }
        await refresh(events)
    }
}

extension Planner {
    func removeFromWatch(_ item: WatchItem, events: [TrainingSchedule]) async {
        await service.remove(item)
        await refresh(events)
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
        var lines = ["\(r.scheduled) trainingen klaargezet voor je Watch.",
                     "Open Workout op je Watch. Bovenaan staat Rondje met de training van vandaag, en via ... de komende 7 dagen."]
        if r.skippedPast > 0 {
            lines.append("\(r.skippedPast) overgeslagen omdat ze al geweest zijn.")
        }
        if r.overLimit > 0 {
            lines.append("Let op: je Watch kan er maar \(r.limit) tegelijk hebben. De eerste \(r.limit) staan erop, \(r.overLimit) nog niet. Plan later opnieuw.")
        }
        if !r.missing.isEmpty {
            lines.append("Niet gelukt: \(r.missing.joined(separator: ", ")).")
        }
        self.init(title: r.missing.isEmpty ? "Klaargezet" : "Deels gelukt", text: lines.joined(separator: "\n\n"))
    }
}

struct PlanButton: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner

    var body: some View {
        Button {
            Task { await planner.plan(store.events) }
        } label: {
            HStack(spacing: 8) {
                if planner.isBusy {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "applewatch")
                }
                Text(planner.isBusy ? "Bezig..." : "Plan op Watch")
            }
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent, in: Capsule())
        }
        .disabled(planner.isBusy || store.events.allSatisfy(\.workouts.isEmpty))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.black.opacity(0.85))
    }
}
