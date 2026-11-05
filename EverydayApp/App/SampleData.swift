import Foundation
import SwiftData

/// Fills the app with data that mirrors the mockup. Used by the
/// "Load sample data" button and by Xcode previews.
enum SampleData {
    /// Adds sample lists, tasks and Library items. Doesn't remove anything first.
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
    }
}
