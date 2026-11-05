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
    var lastDoneAt: Date?               // ticked today = done in this workout
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

    /// Tick it off: saves what you did today to the history.
    func complete(in context: ModelContext) {
        let log = ExerciseLog(weight: weight, sets: sets, reps: reps)
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
    var exercise: Exercise?

    init(date: Date = .now, weight: Double?, sets: Int, reps: Int) {
        self.date = date
        self.weight = weight
        self.sets = sets
        self.reps = reps
    }
}

enum Gym {
    /// The day after the one you finished most recently (wrapping around), or the first day.
    static func nextDay(in days: [WorkoutDay]) -> WorkoutDay? {
        let ordered = days.sorted { $0.order < $1.order }
        guard let last = ordered.filter({ $0.lastCompletedAt != nil })
                .max(by: { $0.lastCompletedAt! < $1.lastCompletedAt! }),
              let index = ordered.firstIndex(of: last) else { return ordered.first }
        return ordered[(index + 1) % ordered.count]
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
