import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case today, calendar, lists, library, tasks
}

struct ContentView: View {
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today
    @Query private var allTasks: [TaskItem]

    // A summary of everything that affects reminders. When any of it changes
    // (a task is added, edited, checked off or deleted), the reminders are rebuilt.
    private var reminderKey: [String] {
        allTasks.map {
            "\($0.title)|\($0.nudgeDate?.timeIntervalSince1970 ?? 0)|\($0.isDone)|\($0.repeatRule)|\($0.addToCalendar)|\($0.location)"
        }
    }

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

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
                .tag(AppTab.tasks)
        }
        .tint(Theme.forest)
        // Schedule task notifications at launch and after every task change (see Reminders.swift).
        .task(id: reminderKey) { await Reminders.shared.update(for: allTasks) }
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
        for: TaskList.self, TaskItem.self, LibraryItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    SampleData.load(into: container.mainContext)
    return ContentView()
        .modelContainer(container)
        .environment(CalendarStore())
}
