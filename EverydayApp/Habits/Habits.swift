// Daily habits: the Habit model, one HabitCheckIn per habit per day, streaks,
// and the starter ideas. The screens are in HabitsView.swift.

import Foundation
import SwiftData

// MARK: Habits (small things you do every day)

/// Something you want to do every day, like "Stretch" or "Drink water" (8 times).
@Model
final class Habit {
    var name: String = ""
    var icon: String = "leaf"
    var tint: String = CardTint.sage.rawValue
    var target: Int = 1                 // times per day; 1 = just "done"
    var order: Int = 0
    var createdAt: Date = Date.now
    var remindAt: Date?                 // a daily reminder at this time of day; nil = no reminder
    @Relationship(deleteRule: .cascade, inverse: \HabitCheckIn.habit)
    var checkIns: [HabitCheckIn]? = []

    init(name: String, icon: String = "leaf", tint: CardTint = .sage, target: Int = 1, order: Int = 0) {
        self.name = name
        self.icon = icon
        self.tint = tint.rawValue
        self.target = max(target, 1)
        self.order = order
        self.createdAt = .now
    }

    var tintValue: CardTint { CardTint(rawValue: tint) ?? .sage }

    // MARK: Today

    /// That day's check-in, if you checked in at all.
    private func checkIn(on day: Date) -> HabitCheckIn? {
        let start = Calendar.current.startOfDay(for: day)
        return (checkIns ?? []).first { $0.day == start }
    }

    var countToday: Int { checkIn(on: .now)?.count ?? 0 }
    var isDoneToday: Bool { countToday >= target }
    /// Today's progress from 0 to 1.
    var progressToday: Double { min(Double(countToday) / Double(max(target, 1)), 1) }

    /// One more time today ("Drink water": 3 of 8 → 4 of 8).
    func addOne(in context: ModelContext) {
        if let today = checkIn(on: .now) {
            today.count += 1
            today.target = target
        } else {
            let new = HabitCheckIn(day: .now, count: 1, target: target)
            context.insert(new)
            new.habit = self
        }
    }

    /// Takes back one time today.
    func removeOne(in context: ModelContext) {
        guard let today = checkIn(on: .now) else { return }
        if today.count <= 1 {
            context.delete(today)
        } else {
            today.count -= 1
        }
    }

    /// What a tap on the habit does: counts one more time, or takes it back once you're done.
    func tap(in context: ModelContext) {
        if isDoneToday { removeOne(in: context) } else { addOne(in: context) }
    }

    // MARK: Streaks

    /// The days you did it (as many times as you meant to), as start-of-day dates.
    var doneDays: Set<Date> {
        Set((checkIns ?? []).filter(\.isComplete).map(\.day))
    }

    /// Days in a row you've done it. Today counts once it's done;
    /// until then the streak from yesterday still stands.
    var streak: Int {
        let calendar = Calendar.current
        let done = doneDays
        var day = calendar.startOfDay(for: .now)
        if !done.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while done.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// Your longest run ever.
    var bestStreak: Int {
        let calendar = Calendar.current
        var best = 0
        var run = 0
        var previous: Date?
        for day in doneDays.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// The last 7 days, oldest first, and whether you did it on each.
    var lastWeek: [(day: Date, done: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let done = doneDays
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return (day, done.contains(day))
        }
    }

    /// "9:00 AM", or nil without a reminder.
    var reminderLine: String? {
        remindAt?.formatted(date: .omitted, time: .shortened)
    }

    /// "3 of 8" for counted habits, or "Done" / "Not yet".
    var progressLine: String {
        if target > 1 { return "\(min(countToday, target)) of \(target)" }
        return isDoneToday ? "Done" : "Not yet"
    }
}

/// How many times you did a habit on one day.
@Model
final class HabitCheckIn {
    var day: Date = Date.now            // start of the day
    var count: Int = 0
    var target: Int = 1                 // the habit's goal that day, so changing it later doesn't rewrite history
    var habit: Habit?

    init(day: Date, count: Int, target: Int) {
        self.day = Calendar.current.startOfDay(for: day)
        self.count = count
        self.target = target
    }

    var isComplete: Bool { count >= max(target, 1) }
}

/// Ideas to start with, shown when you have no habits yet.
enum HabitIdeas {
    struct Idea: Identifiable {
        var name: String
        var icon: String
        var tint: CardTint
        var target = 1
        var id: String { name }
    }

    static let all: [Idea] = [
        Idea(name: "Drink water", icon: "drop", tint: .lavender, target: 8),
        Idea(name: "Stretch", icon: "figure.yoga", tint: .sage),
        Idea(name: "Read 20 minutes", icon: "book", tint: .lemon),
        Idea(name: "Go for a walk", icon: "figure.walk", tint: .sage),
        Idea(name: "Take vitamins", icon: "pills", tint: .peach),
        Idea(name: "No phone in bed", icon: "moon.stars", tint: .lavender),
    ]

    static let icons = ["drop", "figure.walk", "figure.yoga", "figure.run", "dumbbell",
                        "book", "pencil", "brain.head.profile", "moon.stars", "bed.double",
                        "pills", "leaf", "carrot", "fork.knife", "cup.and.saucer",
                        "sun.max", "heart", "music.note", "dollarsign.circle", "sparkles"]
}
