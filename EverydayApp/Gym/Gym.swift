// The gym models (workout days, exercises and their history) and the logic
// behind them: the rotation, personal bests, gym days, and reading a routine
// pasted from the Notes app. The screens are in GymView.swift.

import Foundation
import SwiftData

// MARK: Gym routine (workout days, exercises and what you lifted)

/// One day of your routine, like "Leg x Glutes Day". Days take turns in order.
@Model
final class WorkoutDay {
    var name: String = ""
    var icon: String = "dumbbell"
    var order: Int = 0                  // position in the rotation
    var lastCompletedAt: Date?          // when you last tapped Finish workout
    var startedAt: Date?                // your first set of the latest workout (for Apple Health)
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Exercise.day)
    var exercises: [Exercise]? = []

    init(name: String, icon: String = "dumbbell", order: Int = 0) {
        self.name = name
        self.icon = icon
        self.order = order
        self.createdAt = .now
    }

    var sortedExercises: [Exercise] { (exercises ?? []).sorted { $0.order < $1.order } }
    var exerciseCount: Int { exercises?.count ?? 0 }
    var isFinishedToday: Bool { lastCompletedAt.map(Calendar.current.isDateInToday) ?? false }

    /// "6 exercises · last time Oct 28"
    var summary: String {
        let count = "\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")"
        guard let last = lastCompletedAt else { return count }
        let when = Calendar.current.isDateInToday(last)
            ? "done today"
            : "last time \(last.formatted(.dateTime.month(.abbreviated).day()))"
        return "\(count) · \(when)"
    }

    /// A picture for the day, guessed from its name.
    static func icon(for name: String) -> String {
        let text = name.lowercased()
        if text.contains("core") || text.contains("abs") { return "figure.core.training" }
        if text.contains("leg") || text.contains("glute") { return "figure.strengthtraining.functional" }
        if text.contains("back") || text.contains("chest") { return "figure.strengthtraining.traditional" }
        if text.contains("cardio") || text.contains("run") { return "figure.run" }
        if text.contains("stretch") || text.contains("yoga") { return "figure.yoga" }
        return "dumbbell"
    }
}

/// One exercise in a day: "Leg Press, 130 lbs, 3 × 12".
@Model
final class Exercise {
    var name: String = ""
    var order: Int = 0
    var sets: Int = 3
    var reps: Int = 10
    var isTimed: Bool = false           // reps are seconds, e.g. a 30-second plank
    var weight: Double?                 // pounds; nil for bodyweight exercises
    var lastDoneAt: Date?               // all sets done today = done in this workout
    var setsDone: Int = 0               // sets finished so far, on `setsDoneOn`
    var setsDoneOn: Date?
    var setReps: [Int] = []             // reps (or seconds) you got in each of those sets
    var day: WorkoutDay?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.exercise)
    var logs: [ExerciseLog]? = []

    init(name: String, sets: Int = 3, reps: Int = 10, isTimed: Bool = false,
         weight: Double? = nil, order: Int = 0) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.isTimed = isTimed
        self.weight = weight
        self.order = order
    }

    var isDoneToday: Bool { lastDoneAt.map(Calendar.current.isDateInToday) ?? false }

    /// Sets finished today (starts over each day).
    var setsDoneToday: Int {
        if isDoneToday { return sets }
        guard let setsDoneOn, Calendar.current.isDateInToday(setsDoneOn) else { return 0 }
        return min(setsDone, sets)
    }

    /// What you got in each set finished today: [12, 12, 10]. Sets ticked before the app
    /// kept track of reps count as all of them.
    var repsToday: [Int] {
        let count = setsDoneToday
        guard count > 0 else { return [] }
        let saved = setsDoneOn.map(Calendar.current.isDateInToday) == true ? setReps : []
        let known = Array(saved.prefix(count))
        return known + Array(repeating: reps, count: count - known.count)
    }

    /// True when a set today came up short of the goal.
    var missedRepsToday: Bool { repsToday.contains { $0 < reps } }

    /// One more set done, with all the reps unless you say otherwise.
    /// After the last set the whole exercise counts as done.
    func finishSet(in context: ModelContext, reps got: Int? = nil) {
        setReps = repsToday + [got ?? reps]
        setsDone = setReps.count
        setsDoneOn = .now
        if setsDone >= sets { complete(in: context) }
    }

    /// Changes what you got in one set today ("only 10 of 12").
    func changeReps(ofSet index: Int, to value: Int) {
        var current = repsToday
        guard current.indices.contains(index) else { return }
        current[index] = max(value, 0)
        setReps = current
        setsDoneOn = .now
        // Already in the history? Keep it in step.
        for log in logs ?? [] where Calendar.current.isDateInToday(log.date) { log.setReps = current }
    }

    /// Takes back the most recent set.
    func undoSet(in context: ModelContext) {
        let remaining = Array(repsToday.dropLast())
        if isDoneToday { uncomplete(in: context) }
        setReps = remaining
        setsDone = remaining.count
        setsDoneOn = .now
    }

    /// All sets at once.
    func finishAllSets(in context: ModelContext) {
        guard !isDoneToday else { return }
        setReps = repsToday + Array(repeating: reps, count: max(sets - setsDoneToday, 0))
        setsDone = sets
        setsDoneOn = .now
        complete(in: context)
    }

    /// Back to no sets done today.
    func resetSets(in context: ModelContext) {
        if isDoneToday { uncomplete(in: context) }
        setReps = []
        setsDone = 0
        setsDoneOn = .now
    }

    /// "3 × 12 · 80 lbs" or "3 × 30 sec"
    var planLine: String {
        let amount = "\(sets) × \(reps)\(isTimed ? " sec" : "")"
        guard let weight else { return amount }
        return "\(amount) · \(Self.pounds(weight))"
    }

    /// History, newest first.
    var sortedLogs: [ExerciseLog] { (logs ?? []).sorted { $0.date > $1.date } }

    /// "80 lbs", "82.5 lbs"
    static func pounds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) lbs"
    }

    /// Your heaviest time, the first time you lifted it.
    var personalBest: ExerciseLog? {
        (logs ?? []).filter { $0.weight != nil }
            .sorted { $0.date < $1.date }
            .max { ($0.weight ?? 0) < ($1.weight ?? 0) }
    }

    /// Today's entry, when it's heavier than every time before.
    var isNewBestToday: Bool {
        let all = logs ?? []
        guard let today = all.first(where: { Calendar.current.isDateInToday($0.date) }),
              let weight = today.weight else { return false }
        let before = all.filter { !Calendar.current.isDateInToday($0.date) }.compactMap(\.weight)
        return !before.isEmpty && weight > (before.max() ?? 0)
    }

    /// Tick it off: saves what you did today to the history.
    func complete(in context: ModelContext) {
        let log = ExerciseLog(weight: weight, sets: sets, reps: reps)
        log.setReps = repsToday
        context.insert(log)
        log.exercise = self
        lastDoneAt = .now
    }

    /// Untick: removes today's entry from the history.
    func uncomplete(in context: ModelContext) {
        for log in logs ?? [] where Calendar.current.isDateInToday(log.date) {
            context.delete(log)
        }
        lastDoneAt = (logs ?? []).filter { !Calendar.current.isDateInToday($0.date) }
            .map(\.date).max()
    }
}

/// What you did on one day: the weight, sets and reps at the time.
@Model
final class ExerciseLog {
    var date: Date = Date.now
    var weight: Double?
    var sets: Int = 0
    var reps: Int = 0
    var setReps: [Int] = []             // what you got in each set; empty = all the reps
    var exercise: Exercise?

    init(date: Date = .now, weight: Double?, sets: Int, reps: Int) {
        self.date = date
        self.weight = weight
        self.sets = sets
        self.reps = reps
    }

    /// You got every rep in every set.
    var hitAllReps: Bool { setReps.allSatisfy { $0 >= reps } }

    /// "3 × 12", or "12 · 10 · 9" when some sets came up short.
    var repsLine: String {
        hitAllReps || setReps.isEmpty ? "\(sets) × \(reps)" : setReps.map(String.init).joined(separator: " · ")
    }
}

/// Gym logic that works across all your workout days.
enum Gym {
    /// The day after the one you finished most recently (wrapping around), or the first day.
    static func nextDay(in days: [WorkoutDay]) -> WorkoutDay? {
        let ordered = days.sorted { $0.order < $1.order }
        guard let last = ordered.filter({ $0.lastCompletedAt != nil })
                .max(by: { $0.lastCompletedAt! < $1.lastCompletedAt! }),
              let index = ordered.firstIndex(of: last) else { return ordered.first }
        return ordered[(index + 1) % ordered.count]
    }

    // MARK: Progress

    /// A line on the progress card, like "New best: 120 lbs, up 10 since Oct 2".
    struct Highlight: Identifiable {
        enum Kind { case best, gain }
        var kind: Kind
        var exercise: String
        var detail: String          // "Up 30 lbs since September"
        var amount: Double          // for sorting
        var date: Date
        var id: String { "\(kind)-\(exercise)" }
    }

    /// What's worth celebrating: new personal bests from the last two weeks,
    /// then the exercises that have gone up the most since you started.
    static func highlights(in days: [WorkoutDay], limit: Int = 4) -> [Highlight] {
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: .now) ?? .now
        var bests: [Highlight] = []
        var gains: [Highlight] = []

        for exercise in days.flatMap(\.sortedExercises) {
            let logs = (exercise.logs ?? []).filter { $0.weight != nil }.sorted { $0.date < $1.date }
            guard let first = logs.first, let latest = logs.last, logs.count >= 2,
                  let start = first.weight, let now = latest.weight else { continue }

            let before = logs.dropLast().compactMap(\.weight).max() ?? 0
            if now > before, latest.date >= twoWeeksAgo {
                // "New best: 130 lbs, up 20 since September", or "… on Nov 4" when it's your first gain.
                let detail = now - start > now - before
                    ? "New best: \(Exercise.pounds(now)), up \((now - start).formatted(.number.precision(.fractionLength(0...1)))) since \(since(first.date))"
                    : "New best: \(Exercise.pounds(now)) on \(shortDate(latest.date))"
                bests.append(Highlight(kind: .best, exercise: exercise.name, detail: detail,
                                       amount: now - before, date: latest.date))
            }
            if now > start {
                gains.append(Highlight(kind: .gain, exercise: exercise.name,
                                       detail: "Up \(Exercise.pounds(now - start)) since \(since(first.date))",
                                       amount: now - start, date: first.date))
            }
        }
        // One line per exercise: a new best says more than the overall gain.
        let bestNames = Set(bests.map(\.exercise))
        gains.removeAll { bestNames.contains($0.exercise) }
        return Array((bests.sorted { $0.date > $1.date } + gains.sorted { $0.amount > $1.amount }).prefix(limit))
    }

    /// "Oct 28"
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "September", "Oct 3" this month, or "September 2025" for another year.
    static func since(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, equalTo: .now, toGranularity: .month) { return shortDate(date) }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: Schedule

    /// Your gym days and reminder, saved in the app's settings.
    struct Schedule {
        static let daysKey = "gymDays"              // weekdays, 1 = Sunday … 7 = Saturday: "2,4,6"
        static let remindKey = "gymRemind"
        static let minutesKey = "gymRemindMinutes"  // minutes after midnight

        var weekdays: Set<Int>
        var remind: Bool
        var minutes: Int

        static var current: Schedule {
            let defaults = UserDefaults.standard
            return Schedule(weekdays: parse(defaults.string(forKey: daysKey) ?? ""),
                            remind: defaults.bool(forKey: remindKey),
                            minutes: defaults.object(forKey: minutesKey) as? Int ?? 7 * 60)
        }

        /// "2,4,6" → [2, 4, 6]. Ignores anything that isn't 1–7.
        static func parse(_ text: String) -> Set<Int> {
            Set(text.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
        }

        /// [2, 4, 6] → "2,4,6", the format saved in settings.
        static func text(_ days: Set<Int>) -> String {
            days.sorted().map(String.init).joined(separator: ",")
        }

        /// "Mon, Wed, Fri" (Monday first).
        static func summary(_ days: Set<Int>) -> String {
            let names = Calendar.current.shortWeekdaySymbols   // Sun, Mon, …
            return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { names[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// Which workout falls on each of your coming gym days, taking turns from the one up next.
    /// Today counts if it's a gym day and you haven't worked out yet.
    static func plan(_ days: [WorkoutDay], weekdays: Set<Int>, count: Int = 14) -> [(date: Date, day: WorkoutDay)] {
        let ordered = days.sorted { $0.order < $1.order }
        guard !weekdays.isEmpty, let next = nextDay(in: ordered),
              let start = ordered.firstIndex(of: next) else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let finishedToday = ordered.contains(where: \.isFinishedToday)

        var result: [(Date, WorkoutDay)] = []
        var offset = finishedToday ? 1 : 0
        while result.count < count, offset < 7 * 8 {
            if let date = cal.date(byAdding: .day, value: offset, to: today),
               weekdays.contains(cal.component(.weekday, from: date)) {
                result.append((date, ordered[(start + result.count) % ordered.count]))
            }
            offset += 1
        }
        return result
    }

    /// Adds parsed days to the end of your routine.
    static func importDays(_ parsed: [RoutineParser.Day], after existing: Int, into context: ModelContext) {
        for (dayIndex, parsedDay) in parsed.enumerated() {
            let day = WorkoutDay(name: parsedDay.name, icon: WorkoutDay.icon(for: parsedDay.name),
                                 order: existing + dayIndex)
            context.insert(day)
            for (index, item) in parsedDay.exercises.enumerated() {
                let exercise = Exercise(name: item.name, sets: item.sets, reps: item.reps,
                                        isTimed: item.isTimed, weight: item.weight, order: index)
                context.insert(exercise)
                exercise.day = day
            }
        }
    }
}

// MARK: Reading a routine pasted from Notes

/// Turns text like this into workout days:
///
///     PF Leg x Glutes Day
///     1. Hip Adduction (80 lbs) 3x12
///     4. Plank 3x30 secs
///
/// A line with a number or "3x12" is an exercise; any other line starts a new day.
enum RoutineParser {
    /// One exercise as read from the text, before it's saved. Weights are in lbs (kg are converted).
    struct Exercise: Equatable {
        var name: String
        var weight: Double?
        var sets = 3
        var reps = 10
        var isTimed = false
    }
    struct Day: Equatable {
        var name: String
        var exercises: [Exercise] = []
    }

    private static let numbered = try! NSRegularExpression(pattern: #"^\d+\s*[.)]\s*"#)
    private static let setsReps = try! NSRegularExpression(
        pattern: #"(\d+)\s*[x×X]\s*(\d+)\s*(seconds?|secs?|s|minutes?|mins?|m)?\b"#)
    private static let weightPattern = try! NSRegularExpression(
        pattern: #"\(?\s*(\d+(?:\.\d+)?)\s*(lbs?|pounds?|kg)\s*\)?"#, options: .caseInsensitive)

    /// Reads the whole pasted routine. Exercises before any day name go into a day called "Workout".
    static func parse(_ text: String) -> [Day] {
        var days: [Day] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = clean(rawLine)
            guard line.contains(where: \.isLetter) else { continue }

            if let exercise = exercise(from: line) {
                if days.isEmpty { days.append(Day(name: "Workout")) }
                days[days.count - 1].exercises.append(exercise)
            } else {
                days.append(Day(name: line))
            }
        }
        // Drops titles like "workout plan" that have no exercises under them.
        return days.filter { !$0.exercises.isEmpty }
    }

    /// Removes bullets, tabs and extra spaces: "•\t\t5.\tMountain Kicks" → "5. Mountain Kicks".
    private static func clean(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "\t", with: " ")
        text = text.trimmingCharacters(in: .whitespaces)
        while let first = text.first, "•-*–—▪◦".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// Reads one exercise line, or returns nil if the line is a day name.
    /// The line needs a number in front ("1.") or sets × reps ("3x12") to count as an exercise.
    private static func exercise(from line: String) -> Exercise? {
        var text = line
        let isNumbered = firstMatch(numbered, in: text) != nil
        if let match = firstMatch(numbered, in: text) { text = remove(match.range, from: text) }

        var result = Exercise(name: "")
        var hasSets = false
        if let match = lastMatch(setsReps, in: text) {
            hasSets = true
            result.sets = Int(group(1, match, text)) ?? 3
            result.reps = Int(group(2, match, text)) ?? 10
            let unit = group(3, match, text).lowercased()
            if unit.hasPrefix("m") { result.isTimed = true; result.reps *= 60 }   // minutes → seconds
            else if unit.hasPrefix("s") { result.isTimed = true }
            text = remove(match.range, from: text)
        }
        guard isNumbered || hasSets else { return nil }

        if let match = firstMatch(weightPattern, in: text), let value = Double(group(1, match, text)) {
            let isKilos = group(2, match, text).lowercased() == "kg"
            result.weight = isKilos ? (value * 2.20462).rounded() : value
            text = remove(match.range, from: text)
        }

        result.name = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–:,()"))
        return result.name.isEmpty ? nil : result
    }

    // Small helpers around NSRegularExpression.
    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func lastMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last
    }
    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String {
        guard let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
    }
    private static func remove(_ range: NSRange, from text: String) -> String {
        guard let range = Range(range, in: text) else { return text }
        var copy = text
        copy.replaceSubrange(range, with: " ")
        return copy.split(separator: " ").joined(separator: " ")
    }
}
