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

    /// "5:00–5:30 · Greenway Market"
    var timeRangeLine: String {
        guard let dueDate else { return "" }
        let end = dueDate.addingTimeInterval(30 * 60)
        var line = "\(dueDate.clock)–\(end.clock)"
        if !place.isEmpty { line += " · \(place)" }
        return line
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
