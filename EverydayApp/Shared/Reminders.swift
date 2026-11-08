import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// Sends a notification for each task at its "Remind me" time, for each habit
/// with a daily reminder, an evening habit check-in, on your gym days ("Arm x Shoulder
/// Day today"), for your cycle (before your period, and to log it while it's on), and to
/// reinstall the app from Xcode before it stops opening (see AppExpiry.swift).
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
    private static let cycleCategory = "cycle-log"          // Log today
    nonisolated private static let logPeriodAction = "cycle.log"

    override init() {
        super.init()
        center.delegate = self   // lets reminders show while the app is open (see the bottom)
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done",
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let allDone = UNNotificationAction(identifier: Self.doneAction, title: "All done",
                                           icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let addOne = UNNotificationAction(identifier: Self.addOneAction, title: "Add one",
                                          icon: UNNotificationActionIcon(systemImageName: "plus"))
        let logPeriod = UNNotificationAction(identifier: Self.logPeriodAction, title: "Log today",
                                             icon: UNNotificationActionIcon(systemImageName: "drop.fill"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.habitCategory, actions: [done], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.countedHabitCategory, actions: [addOne, allDone],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.cycleCategory, actions: [logPeriod], intentIdentifiers: []),
        ])
    }

    /// Replaces every scheduled notification with a fresh set for these tasks, habits, gym days
    /// and cycle days.
    /// Asks for notification permission the first time there's something to schedule.
    /// Task reminders come first. If there are more than `limit`, the latest ones wait
    /// until the next update.
    func update(for tasks: [TaskItem], habits: [Habit] = [], workouts: [WorkoutDay] = [],
                cycleDays: [CycleDay] = []) async {
        let due = tasks.filter(needsReminder)
            .sorted { ($0.nudgeDate ?? .distantFuture) < ($1.nudgeDate ?? .distantFuture) }
        let expiry = expiryRequests()
        // Habits, gym days and your cycle share whatever room tasks leave, soonest first.
        let habitRequests = (requests(for: habits) + checkInRequests(for: habits)
                             + gymRequests(for: workouts) + cycleRequests(for: cycleDays))
            .sorted { $0.date < $1.date }.map(\.request)

        // Ask for permission the first time there's something to remind you about.
        if !due.isEmpty || !habitRequests.isEmpty || !expiry.isEmpty,
           await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        // Clear old task reminders, but leave a running rest timer's alert alone.
        let old = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0 != RestTimer.notificationID }
        center.removePendingNotificationRequests(withIdentifiers: old)
        var scheduled = 0
        // The reinstall reminders come first: missing them locks you out of the app.
        for request in expiry {
            try? await center.add(request)
            scheduled += 1
        }
        for task in due {
            for request in requests(for: task) where scheduled < limit {
                try? await center.add(request)
                scheduled += 1
            }
        }
        // Habits and gym days fill whatever room is left, soonest first.
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
    private func requests(for habits: [Habit]) -> [(date: Date, request: UNNotificationRequest)] {
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
        return found
    }

    /// The evening check-in: "Still to log: Read, Water" at the time you picked, for the
    /// next week. Today's is skipped once every habit is done.
    private func checkInRequests(for habits: [Habit]) -> [(date: Date, request: UNNotificationRequest)] {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: HabitNudge.remindKey), !habits.isEmpty else { return [] }
        let minutes = defaults.object(forKey: HabitNudge.minutesKey) as? Int ?? HabitNudge.defaultMinutes
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var found: [(date: Date, request: UNNotificationRequest)] = []

        for offset in 0..<habitDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let fire = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Log today's habits"
            if offset == 0 {
                let left = habits.filter { !$0.isDoneToday }
                if left.isEmpty { continue }   // all done today
                content.body = left.count == 1 ? "\(left[0].name) isn't logged yet."
                    : "Still to log: " + left.map(\.name).formatted(.list(type: .and))
            } else {
                content.body = "Did you water your garden today? Tap to log your habits."
            }
            content.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            found.append((fire, UNNotificationRequest(identifier: "habit-checkin-\(offset)", content: content,
                                                      trigger: trigger)))
        }
        return found
    }

    // MARK: Cycle

    /// Your cycle reminders, if they're on:
    /// - two days before each of the next two predicted periods, a heads-up
    /// - once it's due, "Has your period started?" for three days, with a Log today button
    /// - while you're on it, "Still on your period?" each day until it's likely over
    /// None for today once today is logged.
    private func cycleRequests(for days: [CycleDay]) -> [(date: Date, request: UNNotificationRequest)] {
        let defaults = UserDefaults.standard
        let before = defaults.bool(forKey: CycleSettings.remindBeforeKey)
        let logging = defaults.bool(forKey: CycleSettings.remindLogKey)
        guard before || logging, !days.isEmpty else { return [] }
        let minutes = defaults.object(forKey: CycleSettings.remindMinutesKey) as? Int ?? CycleSettings.defaultRemindMinutes
        let summary = CycleSummary(
            days: days,
            typicalCycle: defaults.object(forKey: CycleSettings.cycleLengthKey) as? Int ?? CycleSettings.defaultCycle,
            typicalPeriod: defaults.object(forKey: CycleSettings.periodLengthKey) as? Int ?? CycleSettings.defaultPeriod)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let loggedToday = days.contains { cal.isDate($0.day, inSameDayAs: today) && !$0.flow.isEmpty }
        var found: [(date: Date, request: UNNotificationRequest)] = []

        func add(_ day: Date, id: String, title: String, body: String, logButton: Bool) {
            if logButton && loggedToday && cal.isDate(day, inSameDayAs: today) { return }
            guard let fire = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > .now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if logButton { content.categoryIdentifier = Self.cycleCategory }
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            found.append((fire, UNNotificationRequest(identifier: id, content: content, trigger: trigger)))
        }

        if before {
            for (n, period) in summary.predictedPeriods.prefix(2).enumerated() {
                guard let day = cal.date(byAdding: .day, value: -2, to: period.lowerBound) else { continue }
                let date = period.lowerBound.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                add(day, id: "cycle-soon-\(n)", title: "Period in about 2 days",
                    body: "Based on your cycle, it may start around \(date).", logButton: false)
            }
        }

        if logging {
            if summary.isOnPeriod, let start = summary.lastPeriod?.start,
               let lastDay = cal.date(byAdding: .day, value: summary.averagePeriod, to: start) {
                // Each day until it's likely over, plus one more.
                var day = today
                var n = 0
                while day <= lastDay, n < 10 {
                    add(day, id: "cycle-log-\(n)", title: "Still on your period?",
                        body: "Tap Log today to keep your cycle up to date.", logButton: true)
                    day = cal.date(byAdding: .day, value: 1, to: day) ?? lastDay.addingTimeInterval(86_400)
                    n += 1
                }
            } else if let next = summary.nextStart {
                // From the day it's due (or today, if it's late), for three days.
                let from = max(cal.startOfDay(for: next), today)
                for n in 0..<3 {
                    guard let day = cal.date(byAdding: .day, value: n, to: from) else { continue }
                    add(day, id: "cycle-start-\(n)", title: "Has your period started?",
                        body: "It was expected around \(next.monthDay). Log it to keep your predictions accurate.",
                        logButton: true)
                }
            }
        }
        return found
    }

    // MARK: Reinstalling

    /// "Reinstall EverydayApp soon": at 7 PM two days and one day before this copy of the
    /// app stops opening, and three hours before. Nothing in the simulator.
    private func expiryRequests() -> [UNNotificationRequest] {
        guard let expiry = AppExpiry.date else { return [] }
        let cal = Calendar.current
        let when = AppExpiry.text(expiry)
        let body = "Connect your iPhone to your Mac and press Run in Xcode before \(when). Your data stays."
        var found: [UNNotificationRequest] = []

        func add(_ fire: Date?, id: String, title: String) {
            guard let fire, fire > .now, fire < expiry else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            found.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        for days in [2, 1] {
            let day = cal.date(byAdding: .day, value: -days, to: expiry) ?? expiry
            add(cal.date(bySettingHour: 19, minute: 0, second: 0, of: day), id: "expiry-\(days)",
                title: days == 1 ? "Reinstall EverydayApp by tomorrow" : "Reinstall EverydayApp soon")
        }
        add(expiry.addingTimeInterval(-3 * 3600), id: "expiry-last",
            title: "EverydayApp stops opening at \(expiry.formatted(date: .omitted, time: .shortened))")
        return found
    }

    // MARK: Gym days

    /// "Arm x Shoulder Day today" on each of your gym days for the next two weeks,
    /// with the workout that's up next. None today once you've finished a workout.
    private func gymRequests(for workouts: [WorkoutDay]) -> [(date: Date, request: UNNotificationRequest)] {
        let schedule = Gym.Schedule.current
        guard schedule.remind, !workouts.isEmpty else { return [] }
        let cal = Calendar.current
        var found: [(date: Date, request: UNNotificationRequest)] = []

        for (date, day) in Gym.plan(workouts, weekdays: schedule.weekdays, count: 10) {
            guard let fire = cal.date(bySettingHour: schedule.minutes / 60, minute: schedule.minutes % 60,
                                      second: 0, of: date), fire > .now, fire < .now.addingTimeInterval(15 * 86_400)
            else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(day.name) today"
            content.body = day.summary
            content.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = "gym-" + date.formatted(.iso8601.year().month().day())
            found.append((fire, UNNotificationRequest(identifier: id, content: content, trigger: trigger)))
        }
        return found
    }

    /// Open tasks with a date. Skips tasks on your calendar, since the Calendar app
    /// already alerts you about those (otherwise you'd get two notifications).
    private func needsReminder(_ task: TaskItem) -> Bool {
        guard !task.isDone, !task.addToCalendar, let nudge = task.nudgeDate else { return false }
        return task.repeatRule != "never" || nudge > .now
    }

    /// The notification for one task. A repeating task gets a notification that repeats
    /// (weekdays need one for each day, Monday to Friday).
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
        await updateAll(in: context)
    }

    /// "Log today" tapped on a cycle notification: marks today as a period day, with the
    /// same flow as yesterday (or medium), then sets up reminders again.
    private func logPeriodToday() async {
        guard let container else { return }
        let context = container.mainContext
        let cal = Calendar.current
        let days = (try? context.fetch(FetchDescriptor<CycleDay>())) ?? []
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let flow = days.first { cal.isDate($0.day, inSameDayAs: yesterday) && $0.isPeriod }?.flowValue ?? .medium
        if let log = days.first(where: { cal.isDate($0.day, inSameDayAs: today) }) {
            if !log.isPeriod { log.flow = flow.rawValue }
        } else {
            context.insert(CycleDay(day: today, flow: flow))
        }
        try? context.save()
        await updateAll(in: context)
    }

    /// Sets up every reminder again from what's saved.
    private func updateAll(in context: ModelContext) async {
        await update(for: (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [],
                     habits: (try? context.fetch(FetchDescriptor<Habit>())) ?? [],
                     workouts: (try? context.fetch(FetchDescriptor<WorkoutDay>())) ?? [],
                     cycleDays: (try? context.fetch(FetchDescriptor<CycleDay>())) ?? [])
    }

    /// Called when you tap a button under a habit notification ("Done" or "Add one").
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        if action == Self.logPeriodAction {
            await logPeriodToday()
            return
        }
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

extension Binding where Value == Int {
    /// Minutes after midnight as a time of day, for a DatePicker showing hours and minutes.
    var timeOfDay: Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: wrappedValue / 60, minute: wrappedValue % 60,
                                      second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}

extension Int {
    /// 1230 minutes → "8:30 PM"
    var timeOfDayText: String {
        let date = Calendar.current.date(bySettingHour: self / 60, minute: self % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
