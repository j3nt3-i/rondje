import SwiftUI

@main
struct WatchPlannerApp: App {
    @State private var store = ScheduleStore()
    @State private var planner = Planner()
    @State private var health = HealthLog()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EventsView()
                .environment(store)
                .environment(planner)
                .environment(health)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // Here, so the message also shows while an event or workout is open.
                .alert(item: $planner.message) { m in Alert(title: Text(m.title), message: Text(m.text)) }
                .task(id: store.events) { await planner.refresh(store.events) }
                .task(id: store.events) { await health.refresh(store.events) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await planner.refresh(store.events) }
                        // You may just be back from a run.
                        Task { await health.refresh(store.events) }
                    }
                }
        }
    }
}
