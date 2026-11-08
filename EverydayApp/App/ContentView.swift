// The tab bar, plus the work that runs in the background while the app is open:
// rebuilding reminders when tasks, habits or workouts change, and keeping the
// home screen widget up to date.

import SwiftUI
import SwiftData

/// The five tabs. TodayView takes a
/// 000binding to this so its cards can switch tabs.
enum AppTab: Hashable {
    case today, calendar, lists, library, tasks
}

/// The root view: a TabView with one NavigationStack per tab.
struct ContentView: View {
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncFolder.self) private var syncFolder
    @State private var tab: AppTab = .today
    @Query private var allTasks: [TaskItem]
    @Query private var allHabits: [Habit]
    @Query private var allWorkouts: [WorkoutDay]
    @AppStorage(Gym.Schedule.daysKey) private var gymDays = ""
    @AppStorage(Gym.Schedule.remindKey) private var gymRemind = false
    @AppStorage(Gym.Schedule.minutesKey) private var gymRemindMinutes = 7 * 60

    // A summary of everything that affects reminders. When any of it changes
    // (a task is added, edited, checked off or deleted), the reminders are rebuilt.
    private var reminderKey: [String] {
        allTasks.map {
            "\($0.title)|\($0.nudgeDate?.timeIntervalSince1970 ?? 0)|\($0.isDone)|\($0.repeatRule)|\($0.addToCalendar)|\($0.location)"
        } + allHabits.map {
            // Checking in changes today's habit reminder (skipped once done).
            "\($0.name)|\($0.remindAt?.timeIntervalSince1970 ?? 0)|\($0.countToday)|\($0.target)"
        } + allWorkouts.map {
            // Finishing a workout moves the rotation along and skips today's gym reminder.
            "\($0.name)|\($0.order)|\($0.lastCompletedAt?.timeIntervalSince1970 ?? 0)|\($0.exerciseCount)"
        } + ["gym|\(gymDays)|\(gymRemind)|\(gymRemindMinutes)"]
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
        .task(id: reminderKey) {
            await Reminders.shared.update(for: allTasks, habits: allHabits, workouts: allWorkouts)
            WidgetSync.update(tasks: allTasks, calendarStore: calendarStore)
        }
        // Keep the home screen widget current when calendars change (see WidgetSync.swift).
        // While the app is open, check the sync folder now and every 30 seconds (see SyncFolder.swift).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await syncFolder.syncNow()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: calendarStore.changeToken) {
            WidgetSync.update(tasks: allTasks, calendarStore: calendarStore)
        }
        .onChange(of: scenePhase) { _, phase in
            // Each time you open the app: pick up changes made in iPhone Settings,
            // and ask iOS to fetch the latest events from your calendar accounts.
            if phase == .active {
                calendarStore.refreshAccess()
                calendarStore.refresh()
                RestTimer.shared.checkExpired()   // a rest that ended while the app was closed
                // A new day: set up the next week of habit reminders again.
                Task { await Reminders.shared.update(for: allTasks, habits: allHabits, workouts: allWorkouts) }
            }
            // Leaving the app: save a fresh summary for the widget (times may have passed).
            if phase == .background {
                Task { await syncFolder.syncNow() }   // send your latest changes before the app sleeps
                WidgetSync.update(tasks: allTasks, calendarStore: calendarStore)
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
        for: TaskList.self, TaskItem.self, LibraryItem.self, WorkoutDay.self, Exercise.self, ExerciseLog.self, Habit.self, HabitCheckIn.self, CycleDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    SampleData.load(into: container.mainContext)
    return ContentView()
        .modelContainer(container)
        .environment(CalendarStore())
        .environment(SyncFolder(container: container))
}
