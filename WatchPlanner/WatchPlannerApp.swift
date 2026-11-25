import SwiftUI

@main
struct WatchPlannerApp: App {
    @State private var store = ScheduleStore()

    var body: some Scene {
        WindowGroup {
            ScheduleListView()
                .environment(store)
        }
    }
}
