import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case today, calendar, lists, tasks
}

struct ContentView: View {
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            TodayView(tab: $tab)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)

            ListsView()
                .tabItem { Label("Lists", systemImage: "checklist") }
                .tag(AppTab.lists)

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
                .tag(AppTab.tasks)
        }
        .tint(Theme.forest)
        .onChange(of: scenePhase) { _, phase in
            // Each time you open the app: pick up changes made in iPhone Settings,
            // and ask iOS to fetch the latest events from your calendar accounts.
            if phase == .active {
                calendarStore.refreshAccess()
                calendarStore.refresh()
            }
        }
    }
}

#Preview("Light") {
    previewContent().preferredColorScheme(.light)
}

#Preview("Dark") {
    previewContent().preferredColorScheme(.dark)
}

/// The app filled with sample data, for Xcode previews.
private func previewContent() -> some View {
    let container = try! ModelContainer(
        for: TaskList.self, TaskItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    SampleData.load(into: container.mainContext)
    return ContentView()
        .modelContainer(container)
        .environment(CalendarStore())
}
