import Foundation
import SwiftData
import UserNotifications

/// Sends a notification for each task at its "Remind me" time.
///
/// Rather than adding and removing notifications one by one, `update(for:)` clears
/// everything and schedules again from the full task list. ContentView calls it whenever
/// any task changes, so adding, editing, finishing or deleting a task is always reflected.
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    private let center = UNUserNotificationCenter.current()

    // iOS keeps at most 64 waiting notifications per app; stay safely under that.
    private let limit = 60

    override init() {
        super.init()
        center.delegate = self   // lets reminders show while the app is open (see the bottom)
    }

    func update(for tasks: [TaskItem]) async {
        let due = tasks.filter(needsReminder)
            .sorted { ($0.nudgeDate ?? .distantFuture) < ($1.nudgeDate ?? .distantFuture) }

        // Ask for permission the first time there's something to remind you about.
        if !due.isEmpty, await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        center.removeAllPendingNotificationRequests()
        var scheduled = 0
        for task in due {
            for request in requests(for: task) where scheduled < limit {
                try? await center.add(request)
                scheduled += 1
            }
        }
    }

    /// Open tasks with a date. Skips tasks on your calendar, since the Calendar app
    /// already alerts you about those (otherwise you'd get two notifications).
    private func needsReminder(_ task: TaskItem) -> Bool {
        guard !task.isDone, !task.addToCalendar, let nudge = task.nudgeDate else { return false }
        return task.repeatRule != "never" || nudge > .now
    }

    private func requests(for task: TaskItem) -> [UNNotificationRequest] {
        guard let nudge = task.nudgeDate else { return [] }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.timeLine.isEmpty ? "Reminder" : task.timeLine
        content.sound = .default

        // Which parts of the date must match for the notification to fire.
        let cal = Calendar.current
        let id = String(describing: task.persistentModelID)
        func request(_ parts: Set<Calendar.Component>, weekday: Int? = nil, suffix: String = "") -> UNNotificationRequest {
            var components = cal.dateComponents(parts, from: nudge)
            if let weekday { components.weekday = weekday }
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: task.repeatRule != "never")
            return UNNotificationRequest(identifier: id + suffix, content: content, trigger: trigger)
        }

        switch task.repeatRule {
        case "daily":   return [request([.hour, .minute])]
        case "weekly":  return [request([.weekday, .hour, .minute])]
        case "monthly": return [request([.day, .hour, .minute])]
        case "weekdays":
            // Monday (2) through Friday (6), each its own weekly notification.
            return (2...6).map { (day: Int) in request([.hour, .minute], weekday: day, suffix: "-\(day)") }
        default:        return [request([.year, .month, .day, .hour, .minute])]
        }
    }

    // Without this, iOS hides notifications that arrive while the app is on screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
