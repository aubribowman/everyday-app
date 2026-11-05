import Foundation
import SwiftData
import UserNotifications

/// Sends a notification for each task at its "Remind me" time, and for each habit
/// with a daily reminder.
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

    /// The app's data, so the buttons on habit notifications can check a habit in.
    /// Set by EverydayApp when it starts.
    var container: ModelContainer?

    // The buttons under a habit notification (long-press it, or swipe down on it).
    private static let habitCategory = "habit"              // once a day: Done
    private static let countedHabitCategory = "habit-count" // several times a day: Add one, All done
    nonisolated private static let doneAction = "habit.done"
    nonisolated private static let addOneAction = "habit.one"

    override init() {
        super.init()
        center.delegate = self   // lets reminders show while the app is open (see the bottom)
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done",
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let allDone = UNNotificationAction(identifier: Self.doneAction, title: "All done",
                                           icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let addOne = UNNotificationAction(identifier: Self.addOneAction, title: "Add one",
                                          icon: UNNotificationActionIcon(systemImageName: "plus"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.habitCategory, actions: [done], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.countedHabitCategory, actions: [addOne, allDone],
                                   intentIdentifiers: []),
        ])
    }

    func update(for tasks: [TaskItem], habits: [Habit] = []) async {
        let due = tasks.filter(needsReminder)
            .sorted { ($0.nudgeDate ?? .distantFuture) < ($1.nudgeDate ?? .distantFuture) }
        let habitRequests = requests(for: habits)

        // Ask for permission the first time there's something to remind you about.
        if !due.isEmpty || !habitRequests.isEmpty,
           await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        // Clear old task reminders, but leave a running rest timer's alert alone.
        let old = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0 != RestTimer.notificationID }
        center.removePendingNotificationRequests(withIdentifiers: old)
        var scheduled = 0
        for task in due {
            for request in requests(for: task) where scheduled < limit {
                try? await center.add(request)
                scheduled += 1
            }
        }
        // Habits fill whatever room is left, soonest first.
        for request in habitRequests where scheduled < limit {
            try? await center.add(request)
            scheduled += 1
        }
    }

    // MARK: Habits

    /// How many days ahead habit reminders are set up. The app sets them up again
    /// every time it opens, so this only matters if you don't open it for a week.
    private let habitDays = 7

    /// One notification per habit per day, soonest first. Each day is its own notification
    /// (rather than one that repeats) so today's can be skipped once you've checked in.
    private func requests(for habits: [Habit]) -> [UNNotificationRequest] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var found: [(date: Date, request: UNNotificationRequest)] = []

        for habit in habits {
            guard let remindAt = habit.remindAt else { continue }
            let time = cal.dateComponents([.hour, .minute], from: remindAt)
            let id = "habit-" + String(describing: habit.persistentModelID)

            for offset in 0..<habitDays {
                guard let day = cal.date(byAdding: .day, value: offset, to: today),
                      let fire = cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day),
                      fire > .now else { continue }
                if offset == 0 && habit.isDoneToday { continue }   // already done today

                let content = UNMutableNotificationContent()
                content.title = habit.name
                if offset == 0 && habit.target > 1 && habit.countToday > 0 {
                    content.body = "\(habit.countToday) of \(habit.target) so far today."
                } else if offset == 0 && habit.streak > 0 {
                    content.body = "Keep your \(habit.streak)-day streak going."
                } else {
                    content.body = "A little reminder for today."
                }
                content.sound = .default
                content.categoryIdentifier = habit.target > 1 ? Self.countedHabitCategory : Self.habitCategory
                if let key = Self.key(for: habit) { content.userInfo = ["habit": key] }

                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                found.append((fire, UNNotificationRequest(identifier: "\(id)-\(offset)", content: content, trigger: trigger)))
            }
        }
        return found.sorted { $0.date < $1.date }.map(\.request)
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

    // MARK: Checking in from a notification

    /// A habit's ID as text, to tuck inside its notification.
    private static func key(for habit: Habit) -> String? {
        (try? JSONEncoder().encode(habit.persistentModelID))?.base64EncodedString()
    }

    /// "Done" / "Add one" tapped on a habit notification: check the habit in,
    /// then set up reminders again (today's goes away once the habit is done).
    private func checkIn(habitKey key: String, allTheWay: Bool) async {
        guard let container,
              let data = Data(base64Encoded: key),
              let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) else { return }
        let context = container.mainContext
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        guard let habit = try? context.fetch(descriptor).first else { return }   // deleted since

        if allTheWay {
            while !habit.isDoneToday { habit.addOne(in: context) }
        } else if !habit.isDoneToday {
            habit.addOne(in: context)
        }
        try? context.save()

        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        await update(for: tasks, habits: habits)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action == Self.doneAction || action == Self.addOneAction,
              let key = response.notification.request.content.userInfo["habit"] as? String else { return }
        await checkIn(habitKey: key, allTheWay: action == Self.doneAction)
    }

    // Without this, iOS hides notifications that arrive while the app is on screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
