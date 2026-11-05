import Foundation
import WidgetKit

/// What the home screen widget shows: your next events and today's open tasks.
///
/// The widget runs separately from the app and can't read the app's database or calendars
/// directly, so the app saves this small summary to a folder the two share (an "App Group")
/// and asks the widget to redraw. The widget has its own copy of this struct
/// (EverydayWidget/WidgetSnapshot.swift); keep the two the same.
struct WidgetSnapshot: Codable {
    struct Event: Codable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var location: String
    }
    struct Task: Codable {
        var title: String
        var due: Date?
        var icon: String
    }

    var events: [Event]
    var tasks: [Task]
    var openTaskCount: Int
    var savedAt: Date

    static let appGroup = "group.com.aubribowmanpersonalteam.EverydayApp"
    static let fileName = "widget-snapshot.json"
}

/// Writes `WidgetSnapshot` for the home screen widget.
@MainActor
enum WidgetSync {
    /// Saves the summary and tells the widget to refresh. Called whenever tasks or calendars change.
    static func update(tasks: [TaskItem], calendarStore: CalendarStore) {
        guard let folder = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup
        ) else { return }   // App Group not set up yet: nothing to share

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        let endOfTomorrow = cal.date(byAdding: .day, value: 2, to: startOfToday) ?? .now

        // Events from now through tomorrow (skipping ones the app made for tasks, like elsewhere).
        let taskEventIDs = Set(tasks.map(\.calendarEventID).filter { !$0.isEmpty })
        let events = calendarStore.events(from: startOfToday, to: endOfTomorrow)
            .filter { !taskEventIDs.contains($0.eventID) && ($0.isAllDay || $0.end > .now) }
            .prefix(6)
            .map { WidgetSnapshot.Event(title: $0.title, start: $0.start, end: $0.end,
                                        isAllDay: $0.isAllDay, location: $0.location) }

        // Today's open standalone tasks, soonest first.
        let todayTasks = tasks
            .filter { $0.list == nil && !$0.isDone && ($0.dueDate.map(cal.isDateInToday) ?? false) }
            .byDue
        let snapshot = WidgetSnapshot(
            events: Array(events),
            tasks: todayTasks.prefix(6).map { .init(title: $0.title, due: $0.dueDate, icon: $0.icon) },
            openTaskCount: todayTasks.count,
            savedAt: .now
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: folder.appending(path: WidgetSnapshot.fileName), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Couldn't update the widget:", error)
        }
    }
}
