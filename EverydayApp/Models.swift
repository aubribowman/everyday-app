import Foundation
import SwiftData

@Model
final class TaskList {
    var name: String = ""
    var icon: String = "checklist"
    var tint: String = "sage"
    var countPhrase: String = "things to do"   // "6 books to explore"
    var isFeatured: Bool = false               // show the full list on the Lists tab
    var createdAt: Date = Date.now

    // Items that live in this list. Deleting the list deletes them.
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.list)
    var items: [TaskItem]? = []

    // Tasks that point at this list, e.g. "Pick up groceries" → Grocery shopping.
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.linkedList)
    var linkedTasks: [TaskItem]? = []

    init(name: String, icon: String = "checklist", tint: CardTint = .sage,
         isFeatured: Bool = false, countPhrase: String = "things to do") {
        self.name = name
        self.icon = icon
        self.tint = tint.rawValue
        self.isFeatured = isFeatured
        self.countPhrase = countPhrase
        self.createdAt = .now
    }
}

extension TaskList {
    var tintStyle: CardTint { CardTint(rawValue: tint) ?? .sage }

    var sortedItems: [TaskItem] { (items ?? []).sorted { $0.createdAt < $1.createdAt } }
    var openItems: [TaskItem] { sortedItems.filter { !$0.isDone } }
    var doneItems: [TaskItem] { sortedItems.filter { $0.isDone } }

    var remainingCount: Int { openItems.count }
    var doneCount: Int { doneItems.count }
    var totalCount: Int { sortedItems.count }
    var progress: Double { totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount) }

    /// Section names in the order they first appear ("" = no section).
    var sections: [String] {
        var seen: [String] = []
        for item in openItems where !seen.contains(item.section) {
            seen.append(item.section)
        }
        return seen
    }

    /// Every named section in this list, checked items included (for the section picker).
    var allSections: [String] {
        var seen: [String] = []
        for item in sortedItems where !item.section.isEmpty && !seen.contains(item.section) {
            seen.append(item.section)
        }
        return seen
    }

    func openItems(in section: String) -> [TaskItem] {
        openItems.filter { $0.section == section }
    }

    var doneLabel: String {
        (icon == "basket" || icon == "cart") ? "In the basket" : "Done"
    }

    /// The next unfinished task linked to this list (shown as the green banner).
    var nextReminder: TaskItem? {
        (linkedTasks ?? []).filter { !$0.isDone && $0.dueDate != nil }.byDue.first
    }
}

@Model
final class TaskItem {
    var title: String = ""
    var isDone: Bool = false
    var quantity: String = ""         // "2 pcs"
    var section: String = ""          // "Produce"
    var icon: String = ""             // SF Symbol shown on task rows
    var dueDate: Date?
    var remindMinutesBefore: Int = 0
    var repeatRule: String = "never"
    var location: String = ""         // "Greenway Market"
    var locationDetail: String = ""   // "48 Willow Street"
    var notes: String = ""
    var createdAt: Date = Date.now
    var addToCalendar: Bool = false   // also put this task on a real calendar (Google, Outlook...)
    var calendarID: String = ""       // which calendar ("" = the phone's default)
    var calendarEventID: String = ""  // the calendar event made for it ("" = none yet)

    var list: TaskList?               // nil = a standalone task
    var linkedList: TaskList?

    init(title: String, quantity: String = "", section: String = "") {
        self.title = title
        self.quantity = quantity
        self.section = section
        self.createdAt = .now
    }
}

extension TaskItem {
    var place: String { location.isEmpty ? (linkedList?.name ?? "") : location }

    /// "5:00 PM · Grocery shopping"
    var detailLine: String {
        var parts: [String] = []
        if let dueDate {
            parts.append(Calendar.current.isDateInToday(dueDate) ? dueDate.timeText : dueDate.dayTimeText)
        }
        if let name = linkedList?.name {
            parts.append(name)
        } else if !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }

    /// "5:00 PM · Greenway Market": just the time you picked, plus the place if there is one.
    var timeLine: String {
        guard let dueDate else { return "" }
        var line = dueDate.timeText
        if !place.isEmpty { line += " · \(place)" }
        return line
    }

    /// True for a task with a date and a Repeat setting other than "Does not repeat".
    var repeats: Bool { repeatRule != "never" && dueDate != nil }

    /// The next time this task comes around after now, keeping the same time of day.
    /// e.g. "Every week" on Tuesday 5 PM → next Tuesday 5 PM.
    func nextDueDate(after now: Date = .now) -> Date? {
        guard var date = dueDate else { return nil }
        let cal = Calendar.current
        func step(_ d: Date) -> Date? {
            switch repeatRule {
            case "daily":    return cal.date(byAdding: .day, value: 1, to: d)
            case "weekly":   return cal.date(byAdding: .weekOfYear, value: 1, to: d)
            case "monthly":  return cal.date(byAdding: .month, value: 1, to: d)
            case "weekdays":
                // Next day that's Monday–Friday (weekday 2–6; Sunday is 1).
                var next = cal.date(byAdding: .day, value: 1, to: d)
                while let n = next, !(2...6).contains(cal.component(.weekday, from: n)) {
                    next = cal.date(byAdding: .day, value: 1, to: n)
                }
                return next
            default:         return nil
            }
        }
        // Always move at least once; keep going if the task was overdue for a while.
        repeat {
            guard let next = step(date) else { return nil }
            date = next
        } while date <= now
        return date
    }

    /// Checking off a task. A repeating task moves to its next date and stays open;
    /// anything else is simply marked done (or undone).
    func toggleDone() {
        if !isDone, repeats, let next = nextDueDate() {
            dueDate = next
        } else {
            isDone.toggle()
        }
    }

    var nudgeDate: Date? {
        dueDate?.addingTimeInterval(TimeInterval(-remindMinutesBefore * 60))
    }
}

extension Array where Element == TaskItem {
    var byDue: [TaskItem] {
        sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}

// MARK: Library (books, TV shows and restaurants)

/// The three sections of the Library tab.
enum LibraryKind: String, CaseIterable, Identifiable {
    case book, show, restaurant
    var id: String { rawValue }

    var label: String {
        switch self {
        case .book: "Books"
        case .show: "TV shows"
        case .restaurant: "Restaurants"
        }
    }
    /// Used in titles like "New book" / "Edit restaurant".
    var singular: String {
        switch self {
        case .book: "book"
        case .show: "show"
        case .restaurant: "restaurant"
        }
    }
    var emptyIcon: String {
        switch self {
        case .book: "books.vertical"
        case .show: "tv"
        case .restaurant: "fork.knife"
        }
    }
    var emptyMessage: String {
        switch self {
        case .book: "Tap + to save a book you want to read."
        case .show: "Tap + to save a show you want to watch."
        case .restaurant: "Tap + to save a place you want to try."
        }
    }
    /// The second text field: who wrote it, where to watch it, or where the place is.
    var creatorPrompt: String {
        switch self {
        case .book: "Author (optional)"
        case .show: "Where to watch, e.g. Netflix (optional)"
        case .restaurant: "Neighborhood or address (optional)"
        }
    }
    var notesPrompt: String {
        switch self {
        case .book: "Who recommended it, why it caught your eye…"
        case .show: "Which season you're on, who recommended it…"
        case .restaurant: "What to order, who to go with…"
        }
    }
    /// "Genre" for books and shows, "Cuisine" for restaurants.
    var genreLabel: String { self == .restaurant ? "Cuisine" : "Genre" }

    /// Ready-made choices; you can also type your own.
    var genres: [String] {
        switch self {
        case .book:
            ["Fiction", "Mystery & thriller", "Romance", "Sci-fi & fantasy", "Historical fiction",
             "Literary fiction", "Memoir & biography", "Nonfiction", "Self-help", "Poetry"]
        case .show:
            ["Drama", "Comedy", "Crime", "Sci-fi & fantasy", "Thriller", "Documentary",
             "Reality", "Animation", "Romance", "Horror"]
        case .restaurant:
            ["American", "Italian", "Mexican", "Japanese", "Chinese", "Thai", "Indian",
             "Mediterranean", "French", "Korean", "Vietnamese", "Café & bakery", "Brunch", "Bar"]
        }
    }

    /// Restaurants skip the middle step: you either want to try a place or you've been.
    var statuses: [LibraryStatus] {
        self == .restaurant ? [.want, .done] : LibraryStatus.allCases
    }
}

/// Where you are with something.
enum LibraryStatus: String, CaseIterable, Identifiable {
    case want, active, done
    var id: String { rawValue }

    /// "Want to read" / "Reading" / "Finished", and the versions for shows and restaurants.
    func label(for kind: LibraryKind) -> String {
        switch (self, kind) {
        case (.want, .book):         "Want to read"
        case (.want, .show):         "Want to watch"
        case (.want, .restaurant):   "Want to try"
        case (.active, .book):       "Reading"
        case (.active, .show):       "Watching"
        case (.active, .restaurant): "Going soon"
        case (.done, .restaurant):   "Been there"
        case (.done, _):             "Finished"
        }
    }
}

/// One book, TV show or restaurant on the Library tab.
@Model
final class LibraryItem {
    var title: String = ""
    var creator: String = ""       // author, streaming service, or neighborhood
    var kind: String = "book"      // LibraryKind raw value
    var status: String = "want"    // LibraryStatus raw value
    var genre: String = ""         // genre or cuisine ("" = none)
    var rating: Int = 0            // 1–5 stars, 0 = not rated
    var notes: String = ""
    var createdAt: Date = Date.now
    var statusChangedAt: Date = Date.now   // newest-first ordering within each section

    init(title: String, creator: String = "", kind: LibraryKind, status: LibraryStatus = .want,
         genre: String = "", rating: Int = 0) {
        self.title = title
        self.creator = creator
        self.kind = kind.rawValue
        self.status = status.rawValue
        self.genre = genre
        self.rating = rating
        self.createdAt = .now
        self.statusChangedAt = .now
    }

    var kindValue: LibraryKind { LibraryKind(rawValue: kind) ?? .book }
    var statusValue: LibraryStatus {
        get { LibraryStatus(rawValue: status) ?? .want }
        set {
            status = newValue.rawValue
            statusChangedAt = .now
        }
    }

    /// "Andy Weir · Sci-fi & fantasy"
    var detailLine: String {
        [creator, genre].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
