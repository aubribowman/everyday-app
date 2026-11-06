// The app's starting point. Opens the SwiftData database, connects the calendar,
// and applies the Light/Dark setting. Everything else starts from ContentView.

import SwiftUI
import SwiftData

/// The app itself. Shares the database (`container`) and the calendar
/// (`CalendarStore`) with every screen through the SwiftUI environment.
@main
struct EverydayApp: App {
    @State private var calendarStore = CalendarStore()
    // The Light / Dark / System choice from the Settings sheet (see Sheets.swift).
    @AppStorage("appearance") private var appearance = AppearanceSetting.system

    // Made here (rather than with `.modelContainer(for:)`) so reminders can use it too:
    // tapping "Done" on a habit notification checks it in without opening the app.
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: TaskList.self, TaskItem.self, LibraryItem.self,
                                           WorkoutDay.self, Exercise.self, ExerciseLog.self,
                                           Habit.self, HabitCheckIn.self)
        } catch {
            fatalError("Couldn't open the app's data: \(error)")
        }
        Reminders.shared.container = container
        AppFonts.register()   // Instrument Serif + Sans (see Theme.swift)
    }

    var body: some Scene {
        WindowGroup {
            // Colors adapt via Theme.swift. Re-apply the Light/Dark choice at launch
            // and whenever it changes in Settings.
            ContentView()
                .environment(calendarStore)
                .font(.sans())   // Instrument Sans for any text without its own font
                .onChange(of: appearance, initial: true) { _, setting in setting.apply() }
        }
        .modelContainer(container)
    }
}
