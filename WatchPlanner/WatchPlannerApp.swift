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
                .task(id: store.events) { await planner.refresh(store.events) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await planner.refresh(store.events) } }
                }
        }
    }
}
