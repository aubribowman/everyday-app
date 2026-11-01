import SwiftUI
import SwiftData

@main
struct EverydayApp: App {
    @State private var calendarStore = CalendarStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(calendarStore)
                .preferredColorScheme(.light)   // the design is light-only for now
        }
        .modelContainer(for: [TaskList.self, TaskItem.self])
    }
}
