import SwiftUI

@main
struct WatchPlannerApp: App {
    @State private var store = ScheduleStore()
    @State private var planner = Planner()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EventsView()
                .environment(store)
                .environment(planner)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // Here, so the message also shows while an event or workout is open.
                .alert(item: $planner.message) { m in Alert(title: Text(m.title), message: Text(m.text)) }
                .task(id: store.events) { await planner.refresh(store.events) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await planner.refresh(store.events) } }
                }
        }
    }
}
