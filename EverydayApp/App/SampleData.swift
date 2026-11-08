import Foundation
import SwiftData

/// Fills the app with data that mirrors the mockup. Used by the
/// "Load sample data" button and by Xcode previews.
enum SampleData {
    /// Adds sample lists, tasks, Library items, habits and workouts. Doesn't remove anything first.
    static func load(into context: ModelContext) {
        let cal = Calendar.current

        /// A date `daysFromNow` days away, at the given time.
        func at(_ hour: Int, _ minute: Int = 0, daysFromNow: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: daysFromNow, to: .now) ?? .now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        // Lists
        let weekend = TaskList(name: "Weekend to-dos", icon: "house", tint: .peach,
                               countPhrase: "things to do")
        let reading = TaskList(name: "Reading nook", icon: "book", tint: .lavender,
                               countPhrase: "books to explore")
        let grocery = TaskList(name: "Grocery shopping", icon: "basket", tint: .sage,
                               isFeatured: true, countPhrase: "items to grab")
        for list in [weekend, reading, grocery] { context.insert(list) }

        func add(_ title: String, _ qty: String = "", _ section: String = "",
                 done: Bool = false, to list: TaskList) {
            let item = TaskItem(title: title, quantity: qty, section: section)
            item.isDone = done
            context.insert(item)
            item.list = list
        }

        add("Avocados", "2 pcs", "Produce", to: grocery)
        add("Baby spinach", "1 bag", "Produce", to: grocery)
        add("Lemons", "3 pcs", "Produce", to: grocery)
        add("Oat milk", "1 L", "Pantry & fridge", to: grocery)
        add("Sourdough bread", "1 loaf", "Pantry & fridge", to: grocery)
        add("Greek yogurt", "500 g", "Pantry & fridge", done: true, to: grocery)
        add("Eggs", "6 pcs", "Pantry & fridge", done: true, to: grocery)
        add("Rolled oats", "1 bag", "Pantry & fridge", done: true, to: grocery)

        add("Wash the car", to: weekend)
        add("Deep-clean the kitchen", to: weekend)
        add("Return library books", to: weekend)
        add("Meal prep for the week", to: weekend)

        add("Book club pick", to: reading)
        add("A cozy mystery", to: reading)
        add("A memoir", to: reading)
        add("Something on design", to: reading)
        add("A short story collection", to: reading)
        add("A classic I skipped", to: reading)

        // Standalone tasks
        func task(_ title: String, at date: Date?, icon: String, location: String = "",
                  address: String = "", notes: String = "", linked: TaskList? = nil,
                  remind: Int = 0, done: Bool = false) {
            let t = TaskItem(title: title)
            t.dueDate = date
            t.icon = icon
            t.location = location
            t.locationDetail = address
            t.notes = notes
            t.remindMinutesBefore = remind
            t.isDone = done
            context.insert(t)
            t.linkedList = linked
        }

        task("Morning walk", at: at(7, 30), icon: "figure.walk", done: true)
        task("Send proposal to Nora", at: at(11, 30), icon: "briefcase", remind: 15)
        task("Pick up groceries", at: at(17), icon: "basket",
             location: "Greenway Market", address: "48 Willow Street",
             notes: "Bring the canvas bags. Pick up a ripe avocado for tonight's salad.",
             linked: grocery, remind: 30)
        task("Water the plants", at: at(18), icon: "leaf", location: "Home")
        task("Plan the weekend", at: at(10, daysFromNow: 2), icon: "sun.max")
        task("Book a dentist appointment", at: nil, icon: "phone")

        // Library: books, shows and restaurants
        func save(_ title: String, _ creator: String, _ kind: LibraryKind, _ status: LibraryStatus,
                  _ genre: String, rating: Int = 0) {
            context.insert(LibraryItem(title: title, creator: creator, kind: kind, status: status,
                                       genre: genre, rating: rating))
        }
        save("Project Hail Mary", "Andy Weir", .book, .want, "Sci-fi & fantasy")
        save("The Thursday Murder Club", "Richard Osman", .book, .want, "Mystery & thriller")
        save("Tomorrow, and Tomorrow, and Tomorrow", "Gabrielle Zevin", .book, .active, "Literary fiction")
        save("Tom Lake", "Ann Patchett", .book, .done, "Literary fiction", rating: 5)
        save("Severance", "Apple TV", .show, .want, "Sci-fi & fantasy")
        save("The Bear", "Hulu", .show, .want, "Drama")
        save("Slow Horses", "Apple TV", .show, .active, "Thriller")
        save("Abbott Elementary", "Hulu", .show, .done, "Comedy", rating: 4)
        save("Little Olive", "Downtown", .restaurant, .want, "Mediterranean")
        save("Sora Ramen", "Eastside", .restaurant, .want, "Japanese")
        save("Casa Verde", "Old Town", .restaurant, .done, "Mexican", rating: 4)

        // Habits, with a few weeks of history so the streaks and 7-day bars have something to show.
        func habit(_ name: String, _ icon: String, _ tint: CardTint, target: Int = 1, order: Int,
                   today: Int, doneDaysAgo: [Int]) {
            let h = Habit(name: name, icon: icon, tint: tint, target: target, order: order)
            context.insert(h)
            var counts = Dictionary(uniqueKeysWithValues: doneDaysAgo.map { ($0, target) })
            if today > 0 { counts[0] = today }
            for (daysAgo, count) in counts {
                let checkIn = HabitCheckIn(day: at(12, daysFromNow: -daysAgo), count: count, target: target)
                context.insert(checkIn)
                checkIn.habit = h
            }
        }
        habit("Drink water", "drop", .lavender, target: 8, order: 0, today: 3,
              doneDaysAgo: [1, 2, 4, 5] + Array(9...17))
        habit("Stretch", "figure.yoga", .peach, order: 1, today: 1,
              doneDaysAgo: Array(1...4) + Array(8...19))
        habit("Read 20 minutes", "book", .lemon, order: 2, today: 0,
              doneDaysAgo: [2, 4, 5, 6] + Array(10...12))

        // Cycle: three periods four weeks apart. The latest ended 8 days ago, so the
        // fertile window is coming up and the next period is about two weeks out.
        for (startDaysAgo, flows) in [(68, [3, 3, 2, 1, 1]), (40, [2, 3, 2, 1, 1]), (12, [3, 3, 2, 1])] {
            for (offset, drops) in flows.enumerated() {
                let flow: Flow = drops == 3 ? .heavy : drops == 2 ? .medium : .light
                let day = CycleDay(day: at(12, daysFromNow: -(startDaysAgo - offset)), flow: flow)
                if offset == 0 { day.symptoms = ["Cramps", "Tired"] }
                if offset == 1 { day.symptoms = ["Cramps"] }
                context.insert(day)
            }
        }
        let headache = CycleDay(day: at(12, daysFromNow: -14))
        headache.symptoms = ["Headache", "Bloating"]
        context.insert(headache)

        // Gym: four workout days. Core was finished yesterday, so Leg x Glutes is today's,
        // and it's half done: one exercise finished (a new best) and two sets of the next.
        func workout(_ name: String, _ icon: String, order: Int,
                     _ moves: [(String, Int, Int, Double?, Bool)]) -> WorkoutDay {
            let day = WorkoutDay(name: name, icon: icon, order: order)
            context.insert(day)
            for (index, move) in moves.enumerated() {
                let e = Exercise(name: move.0, sets: move.1, reps: move.2, isTimed: move.4,
                                 weight: move.3, order: index)
                context.insert(e)
                e.day = day
            }
            return day
        }
        let legs = workout("PF Leg x Glutes Day", "figure.strengthtraining.functional", order: 0, [
            ("Hip Adduction", 3, 12, 85, false),
            ("Leg Press", 3, 12, 180, false),
            ("Romanian Deadlift", 3, 10, 65, false),
            ("Hip Thrust", 3, 10, 135, false),
            ("Plank", 3, 30, nil, true),
        ])
        _ = workout("PF Arm x Shoulder Day", "dumbbell", order: 1, [
            ("Shoulder Press", 3, 12, 30, false),
            ("Bicep Curls", 3, 12, 20, false),
            ("Lateral Raises", 3, 15, 12.5, false),
            ("Tricep Pushdown", 3, 12, 40, false),
        ])
        _ = workout("PF Back x Chest Day", "figure.strengthtraining.traditional", order: 2, [
            ("Lat Pulldown", 3, 12, 90, false),
            ("Chest Press", 3, 12, 65, false),
            ("Seated Row", 3, 12, 85, false),
        ])
        let core = workout("PF Core Day", "figure.core.training", order: 3, [
            ("Dead Bug", 3, 12, nil, false),
            ("Side Plank", 3, 30, nil, true),
        ])
        core.lastCompletedAt = at(18, daysFromNow: -1)

        let moves = legs.sortedExercises
        // Hip Adduction: 80 lbs last week, 85 today, so it shows "Best!".
        let earlier = ExerciseLog(date: at(18, daysFromNow: -7), weight: 80, sets: 3, reps: 12)
        context.insert(earlier)
        earlier.exercise = moves[0]
        for _ in 0..<3 { moves[0].finishSet(in: context) }
        // Leg Press: two sets in, the second came up short.
        moves[1].finishSet(in: context)
        moves[1].finishSet(in: context, reps: 10)
        legs.startedAt = .now.addingTimeInterval(-20 * 60)
    }
}
