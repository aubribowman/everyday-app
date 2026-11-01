import SwiftUI
import SwiftData

@main
struct EverydayApp: App {
    @State private var calendarStore = CalendarStore()
    // The Light / Dark / System choice from the Settings sheet (see Sheets.swift).
    @AppStorage("appearance") private var appearance = AppearanceSetting.system

    var body: some Scene {
        WindowGroup {
            // Colors adapt via Theme.swift. Re-apply the Light/Dark choice at launch
            // and whenever it changes in Settings.
            ContentView()
                .environment(calendarStore)
                .onChange(of: appearance, initial: true) { _, setting in setting.apply() }
        }
        .modelContainer(for: [TaskList.self, TaskItem.self])
    }
}
