import Foundation

/// The summary the app saves for the widget (see EverydayApp/WidgetSync.swift).
/// This is a copy of the app's struct, because the widget is built separately; keep them the same.
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

    /// Reads the latest summary from the shared App Group folder (nil until the app has run).
    static func load() -> WidgetSnapshot? {
        guard let folder = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }
        guard let data = try? Data(contentsOf: folder.appending(path: fileName)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Example content for the widget gallery and Xcode previews.
    static var sample: WidgetSnapshot {
        let cal = Calendar.current
        func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: days, to: .now) ?? .now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        return WidgetSnapshot(
            events: [
                Event(title: "Team standup", start: at(23), end: at(23, 30), isAllDay: false, location: "Zoom"),
                Event(title: "Dinner with Sam", start: at(19, days: 1), end: at(21, days: 1), isAllDay: false,
                      location: "Little Olive"),
            ],
            tasks: [
                Task(title: "Pick up groceries", due: at(23, 15), icon: "basket"),
                Task(title: "Water the plants", due: at(23, 45), icon: "leaf"),
            ],
            openTaskCount: 2,
            savedAt: .now
        )
    }
}
