// The backup file: everything in the app as one JSON file. Used by Create a backup /
// Import a backup in Settings, and by the sync folder (SyncFolder.swift), which keeps
// a copy of the same file in a folder you pick, like one in iCloud Drive.
//
// Things that belong together are nested: a list holds its items, a workout day holds its
// exercises (and their logs), a habit holds its check-ins. So the file needs no IDs.
//
// If you add a field to a model, add it here too (as optional, so older backups still load).

import Foundation
import SwiftData
import CryptoKit

struct EverydayBackup: Codable {
    /// Marks the file as an EverydayApp backup, so importing some other JSON file is refused.
    var app = EverydayBackup.appName
    var version = 1
    /// When this copy was last changed. The sync folder keeps whichever copy is newer.
    var savedAt: Date = .now

    var lists: [List] = []
    var tasks: [Task] = []          // tasks not in a list
    var library: [LibraryEntry] = []
    var workouts: [Workout] = []
    var habits: [HabitEntry] = []
    var settings = Settings()

    static let appName = "EverydayApp"

    struct List: Codable {
        var name: String
        var icon: String
        var tint: String
        var countPhrase: String
        var isFeatured: Bool
        var createdAt: Date
        var items: [Task]
    }

    struct Task: Codable {
        var title: String
        var isDone: Bool
        var quantity: String
        var section: String
        var icon: String
        var dueDate: Date?
        var remindMinutesBefore: Int
        var repeatRule: String
        var location: String
        var locationDetail: String
        var notes: String
        var createdAt: Date
        var addToCalendar: Bool
        var calendarID: String
        var calendarEventID: String
        /// The list this task opens (its position in `lists`), if it's linked to one.
        var linkedList: Int?
    }

    struct LibraryEntry: Codable {
        var title: String
        var creator: String
        var kind: String
        var status: String
        var genre: String
        var rating: Int
        var notes: String
        var createdAt: Date
        var statusChangedAt: Date
        var coverURL: String
        var link: String
        var ingredients: String
        var steps: String
        var minutes: Int
    }

    struct Workout: Codable {
        var name: String
        var icon: String
        var order: Int
        var lastCompletedAt: Date?
        var startedAt: Date?
        var createdAt: Date
        var exercises: [ExerciseEntry]
    }

    struct ExerciseEntry: Codable {
        var name: String
        var order: Int
        var sets: Int
        var reps: Int
        var isTimed: Bool
        var weight: Double?
        var lastDoneAt: Date?
        var setsDone: Int
        var setsDoneOn: Date?
        var setReps: [Int]
        var logs: [Log]
    }

    struct Log: Codable {
        var date: Date
        var weight: Double?
        var sets: Int
        var reps: Int
        var setReps: [Int]
    }

    struct HabitEntry: Codable {
        var name: String
        var icon: String
        var tint: String
        var target: Int
        var order: Int
        var createdAt: Date
        var remindAt: Date?
        var checkIns: [CheckIn]
    }

    struct CheckIn: Codable {
        var day: Date
        var count: Int
        var target: Int
    }

    /// The few settings worth carrying to another device: your name and your gym days.
    struct Settings: Codable {
        var userName: String?
        var gymDays: String?
        var gymRemind: Bool?
        var gymRemindMinutes: Int?
    }
}

// MARK: Making a backup

extension EverydayBackup {
    /// Everything in the app right now.
    @MainActor
    init(from context: ModelContext) throws {
        let allLists = try context.fetch(FetchDescriptor<TaskList>()).sorted(by: Self.listOrder)
        let listIndex = Dictionary(uniqueKeysWithValues: allLists.enumerated().map { ($1.persistentModelID, $0) })

        func task(_ t: TaskItem) -> Task {
            Task(title: t.title, isDone: t.isDone, quantity: t.quantity, section: t.section, icon: t.icon,
                 dueDate: t.dueDate, remindMinutesBefore: t.remindMinutesBefore, repeatRule: t.repeatRule,
                 location: t.location, locationDetail: t.locationDetail, notes: t.notes, createdAt: t.createdAt,
                 addToCalendar: t.addToCalendar, calendarID: t.calendarID, calendarEventID: t.calendarEventID,
                 linkedList: t.linkedList.flatMap { listIndex[$0.persistentModelID] })
        }

        lists = allLists.map { list in
            List(name: list.name, icon: list.icon, tint: list.tint, countPhrase: list.countPhrase,
                 isFeatured: list.isFeatured, createdAt: list.createdAt,
                 items: (list.items ?? []).sorted(by: Self.taskOrder).map(task))
        }
        tasks = try context.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.list == nil }
            .sorted(by: Self.taskOrder)
            .map(task)

        library = try context.fetch(FetchDescriptor<LibraryItem>())
            .sorted { ($0.createdAt, $0.title) < ($1.createdAt, $1.title) }
            .map {
                LibraryEntry(title: $0.title, creator: $0.creator, kind: $0.kind, status: $0.status,
                             genre: $0.genre, rating: $0.rating, notes: $0.notes, createdAt: $0.createdAt,
                             statusChangedAt: $0.statusChangedAt, coverURL: $0.coverURL, link: $0.link,
                             ingredients: $0.ingredients, steps: $0.steps, minutes: $0.minutes)
            }

        workouts = try context.fetch(FetchDescriptor<WorkoutDay>())
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
            .map { day in
                Workout(name: day.name, icon: day.icon, order: day.order, lastCompletedAt: day.lastCompletedAt,
                        startedAt: day.startedAt, createdAt: day.createdAt,
                        exercises: (day.exercises ?? [])
                            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
                            .map { e in
                                ExerciseEntry(name: e.name, order: e.order, sets: e.sets, reps: e.reps,
                                              isTimed: e.isTimed, weight: e.weight, lastDoneAt: e.lastDoneAt,
                                              setsDone: e.setsDone, setsDoneOn: e.setsDoneOn, setReps: e.setReps,
                                              logs: (e.logs ?? []).sorted { $0.date < $1.date }.map {
                                                  Log(date: $0.date, weight: $0.weight, sets: $0.sets,
                                                      reps: $0.reps, setReps: $0.setReps)
                                              })
                            })
            }

        habits = try context.fetch(FetchDescriptor<Habit>())
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
            .map { h in
                HabitEntry(name: h.name, icon: h.icon, tint: h.tint, target: h.target, order: h.order,
                           createdAt: h.createdAt, remindAt: h.remindAt,
                           checkIns: (h.checkIns ?? []).sorted { $0.day < $1.day }.map {
                               CheckIn(day: $0.day, count: $0.count, target: $0.target)
                           })
            }

        let defaults = UserDefaults.standard
        settings = Settings(userName: defaults.string(forKey: "userName"),
                            gymDays: defaults.string(forKey: Gym.Schedule.daysKey),
                            gymRemind: defaults.object(forKey: Gym.Schedule.remindKey) as? Bool,
                            gymRemindMinutes: defaults.object(forKey: Gym.Schedule.minutesKey) as? Int)
    }

    // A steady order, so the same data always makes the same file (see `fingerprint`).
    private static func listOrder(_ a: TaskList, _ b: TaskList) -> Bool {
        (a.createdAt, a.name) < (b.createdAt, b.name)
    }
    private static func taskOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        (a.createdAt, a.title) < (b.createdAt, b.title)
    }
}

// MARK: Restoring

extension EverydayBackup {
    /// Replaces everything in the app with this backup.
    @MainActor
    func restore(into context: ModelContext) throws {
        try context.fetch(FetchDescriptor<TaskItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<TaskList>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<LibraryItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ExerciseLog>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Exercise>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<WorkoutDay>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<HabitCheckIn>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Habit>()).forEach(context.delete)
        try context.save()

        var newLists: [TaskList] = []
        var links: [(TaskItem, Int)] = []

        func insert(_ t: Task, into list: TaskList?) {
            let item = TaskItem(title: t.title)
            item.isDone = t.isDone
            item.quantity = t.quantity
            item.section = t.section
            item.icon = t.icon
            item.dueDate = t.dueDate
            item.remindMinutesBefore = t.remindMinutesBefore
            item.repeatRule = t.repeatRule
            item.location = t.location
            item.locationDetail = t.locationDetail
            item.notes = t.notes
            item.createdAt = t.createdAt
            item.addToCalendar = t.addToCalendar
            item.calendarID = t.calendarID
            item.calendarEventID = t.calendarEventID
            context.insert(item)
            item.list = list
            if let link = t.linkedList { links.append((item, link)) }
        }

        for l in lists {
            let list = TaskList(name: l.name)
            list.icon = l.icon
            list.tint = l.tint
            list.countPhrase = l.countPhrase
            list.isFeatured = l.isFeatured
            list.createdAt = l.createdAt
            context.insert(list)
            newLists.append(list)
            l.items.forEach { insert($0, into: list) }
        }
        tasks.forEach { insert($0, into: nil) }
        for (item, index) in links where newLists.indices.contains(index) {
            item.linkedList = newLists[index]
        }

        for entry in library {
            let item = LibraryItem(title: entry.title, kind: .book)   // the real kind is set below
            item.creator = entry.creator
            item.kind = entry.kind
            item.status = entry.status
            item.genre = entry.genre
            item.rating = entry.rating
            item.notes = entry.notes
            item.createdAt = entry.createdAt
            item.statusChangedAt = entry.statusChangedAt
            item.coverURL = entry.coverURL
            item.link = entry.link
            item.ingredients = entry.ingredients
            item.steps = entry.steps
            item.minutes = entry.minutes
            context.insert(item)
        }

        for w in workouts {
            let day = WorkoutDay(name: w.name, icon: w.icon, order: w.order)
            day.lastCompletedAt = w.lastCompletedAt
            day.startedAt = w.startedAt
            day.createdAt = w.createdAt
            context.insert(day)
            for e in w.exercises {
                let exercise = Exercise(name: e.name, sets: e.sets, reps: e.reps, isTimed: e.isTimed,
                                        weight: e.weight, order: e.order)
                exercise.lastDoneAt = e.lastDoneAt
                exercise.setsDone = e.setsDone
                exercise.setsDoneOn = e.setsDoneOn
                exercise.setReps = e.setReps
                context.insert(exercise)
                exercise.day = day
                for l in e.logs {
                    let log = ExerciseLog(date: l.date, weight: l.weight, sets: l.sets, reps: l.reps)
                    log.setReps = l.setReps
                    context.insert(log)
                    log.exercise = exercise
                }
            }
        }

        for h in habits {
            let habit = Habit(name: h.name, icon: h.icon, target: h.target, order: h.order)
            habit.tint = h.tint
            habit.createdAt = h.createdAt
            habit.remindAt = h.remindAt
            context.insert(habit)
            for c in h.checkIns {
                let checkIn = HabitCheckIn(day: c.day, count: c.count, target: c.target)
                context.insert(checkIn)
                checkIn.habit = habit
            }
        }

        try context.save()

        let defaults = UserDefaults.standard
        if let name = settings.userName { defaults.set(name, forKey: "userName") }
        if let days = settings.gymDays { defaults.set(days, forKey: Gym.Schedule.daysKey) }
        if let remind = settings.gymRemind { defaults.set(remind, forKey: Gym.Schedule.remindKey) }
        if let minutes = settings.gymRemindMinutes { defaults.set(minutes, forKey: Gym.Schedule.minutesKey) }
    }
}

// MARK: The file

extension EverydayBackup {
    /// The backup as a readable JSON file.
    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Reads a backup file. Returns nil if it isn't an EverydayApp backup.
    static func decode(_ data: Data) -> EverydayBackup? {
        guard let backup = try? decoder.decode(EverydayBackup.self, from: data),
              backup.app == appName else { return nil }
        return backup
    }

    /// A short summary of the contents, ignoring `savedAt`. Two copies with the same
    /// fingerprint hold the same data. The sync folder uses it to notice your changes.
    var fingerprint: String {
        var copy = self
        copy.savedAt = .distantPast
        let data = (try? Self.encoder.encode(copy)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// "12 tasks · 3 habits · 4 workouts"
    var summary: String {
        let taskCount = tasks.count + lists.reduce(0) { $0 + $1.items.count }
        var parts = ["\(lists.count) \(lists.count == 1 ? "list" : "lists")",
                     "\(taskCount) \(taskCount == 1 ? "task" : "tasks")"]
        if !library.isEmpty { parts.append("\(library.count) in your library") }
        if !habits.isEmpty { parts.append("\(habits.count) \(habits.count == 1 ? "habit" : "habits")") }
        if !workouts.isEmpty { parts.append("\(workouts.count) \(workouts.count == 1 ? "workout" : "workouts")") }
        return parts.joined(separator: " · ")
    }

    var isEmpty: Bool {
        lists.isEmpty && tasks.isEmpty && library.isEmpty && workouts.isEmpty && habits.isEmpty
    }

    // Dates as readable text, to the millisecond: "2026-11-08T14:03:12.481Z".
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not a date: \(text)"))
        }
        return decoder
    }()
}
