// Period tracking: one CycleDay per day you log (flow, symptoms, a note), and CycleSummary,
// which works out your periods, cycle lengths and the predictions from them.
// The screens are in CycleView.swift.

import Foundation
import SwiftData

/// One day you logged: how heavy the flow was, any symptoms, and a note.
@Model
final class CycleDay {
    var day: Date = Date.now        // start of the day
    var flow: String = ""           // Flow raw value; "" = no bleeding
    var symptoms: [String] = []     // names from CycleSymptom.all
    var note: String = ""

    init(day: Date, flow: Flow? = nil) {
        self.day = Calendar.current.startOfDay(for: day)
        self.flow = flow?.rawValue ?? ""
    }

    var flowValue: Flow? { Flow(rawValue: flow) }

    /// A period day. Spotting is logged but doesn't start or extend a period.
    var isPeriod: Bool { flowValue.map { $0 != .spotting } ?? false }

    /// Nothing worth keeping (so the day can be deleted).
    var isEmpty: Bool { flow.isEmpty && symptoms.isEmpty && note.trimmingCharacters(in: .whitespaces).isEmpty }
}

enum Flow: String, CaseIterable, Identifiable {
    case spotting, light, medium, heavy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// How many drops to show: spotting 0 (a dot), light 1 … heavy 3.
    var drops: Int {
        switch self {
        case .spotting: 0
        case .light: 1
        case .medium: 2
        case .heavy: 3
        }
    }
}

/// Symptoms you can tick on a day, with an SF Symbol for each.
enum CycleSymptom {
    static let all: [(name: String, icon: String)] = [
        ("Cramps", "bolt"),
        ("Headache", "brain.head.profile"),
        ("Bloating", "circle.dashed"),
        ("Tired", "bed.double"),
        ("Back pain", "figure.stand"),
        ("Tender breasts", "heart"),
        ("Acne", "face.dashed"),
        ("Cravings", "fork.knife"),
        ("Low mood", "cloud.rain"),
        ("Irritable", "flame"),
    ]

    static func icon(for name: String) -> String {
        all.first { $0.name == name }?.icon ?? "circle"
    }
}

/// The settings for cycle tracking, kept in UserDefaults (and in backups).
enum CycleSettings {
    static let cycleLengthKey = "cycleLength"     // typical days from one period to the next
    static let periodLengthKey = "periodLength"   // typical days of bleeding
    static let showOnTodayKey = "cycleOnToday"    // show the card on the Today tab

    static let defaultCycle = 28
    static let defaultPeriod = 5
}

/// A period: from its first to its last day of bleeding.
struct Period: Hashable {
    var start: Date
    var end: Date
    var length: Int { (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }
}

/// Everything worked out from your logged days: your periods, average cycle and period
/// lengths, which day of your cycle it is, and the predicted next period and fertile window.
///
/// Until you've logged two periods, the averages use your typical lengths from the settings.
/// Predictions are estimates, not medical advice or birth control.
struct CycleSummary {
    let periods: [Period]           // oldest first
    let averageCycle: Int
    let averagePeriod: Int
    /// How many whole cycles (period to period) the averages come from.
    let cyclesLogged: Int

    private let calendar = Calendar.current

    init(days: [CycleDay], typicalCycle: Int = CycleSettings.defaultCycle,
         typicalPeriod: Int = CycleSettings.defaultPeriod) {
        let calendar = Calendar.current
        // Group period days into periods. One missing day in the middle doesn't split a period.
        let periodDays = Set(days.filter(\.isPeriod).map(\.day)).sorted()
        var periods: [Period] = []
        for day in periodDays {
            if let last = periods.last,
               let gap = calendar.dateComponents([.day], from: last.end, to: day).day, gap <= 2 {
                periods[periods.count - 1].end = day
            } else {
                periods.append(Period(start: day, end: day))
            }
        }
        self.periods = periods

        // Cycle lengths between the last few period starts, leaving out ones that look like a
        // missed log (shorter than 15 days or longer than 60).
        let starts = periods.map(\.start)
        let lengths = zip(starts, starts.dropFirst())
            .compactMap { calendar.dateComponents([.day], from: $0, to: $1).day }
            .filter { (15...60).contains($0) }
            .suffix(6)
        cyclesLogged = lengths.count
        averageCycle = lengths.isEmpty ? typicalCycle
            : Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())

        // Finished periods only: the latest one may still be going.
        let finished = periods.filter { calendar.dateComponents([.day], from: $0.end, to: .now).day ?? 0 >= 2 }
            .suffix(6).map(\.length)
        averagePeriod = finished.isEmpty ? typicalPeriod
            : Int((Double(finished.reduce(0, +)) / Double(finished.count)).rounded())
    }

    // MARK: Today

    var lastPeriod: Period? { periods.last }

    private var today: Date { calendar.startOfDay(for: .now) }

    /// Day 1 is the first day of your latest period. Nil before you've logged one.
    var dayOfCycle: Int? {
        guard let start = lastPeriod?.start else { return nil }
        return (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
    }

    /// Your latest period includes today or yesterday, so it's probably still going.
    var isOnPeriod: Bool {
        guard let end = lastPeriod?.end else { return false }
        return (calendar.dateComponents([.day], from: end, to: today).day ?? 99) <= 1
    }

    /// When the next period should start.
    var nextStart: Date? {
        lastPeriod.flatMap { calendar.date(byAdding: .day, value: averageCycle, to: $0.start) }
    }

    /// Days until the next period: negative once it's late.
    var daysUntilNext: Int? {
        nextStart.flatMap { calendar.dateComponents([.day], from: today, to: $0).day }
    }

    /// "Period in 16 days", "Period · day 2", "Period may start today", "3 days late".
    var headline: String {
        guard let days = daysUntilNext else { return "Log your period to start" }
        if isOnPeriod, let day = dayOfCycle { return "Period · day \(day)" }
        switch days {
        case 1...: return "Period in \(days) \(days == 1 ? "day" : "days")"
        case 0: return "Period may start today"
        default: return "\(-days) \(days == -1 ? "day" : "days") late"
        }
    }

    // MARK: Predictions

    /// The next three predicted periods, each as its days. A late period is shown from today.
    var predictedPeriods: [ClosedRange<Date>] {
        guard let next = nextStart else { return [] }
        return (0..<3).compactMap { n in
            guard var start = calendar.date(byAdding: .day, value: averageCycle * n, to: next) else { return nil }
            if n == 0 && isOnPeriod { return nil }        // this one has already started
            if start < today { start = today }            // late: expect it any day now
            guard let end = calendar.date(byAdding: .day, value: max(averagePeriod, 1) - 1, to: start) else { return nil }
            return start...end
        }
    }

    /// The likely ovulation day before each predicted period: about 14 days before it.
    var ovulationDays: [Date] {
        guard let next = nextStart else { return [] }
        return (0..<3).compactMap {
            calendar.date(byAdding: .day, value: averageCycle * $0 - 14, to: next)
        }
    }

    /// The fertile window: the five days before ovulation and the day after.
    var fertileWindows: [ClosedRange<Date>] {
        ovulationDays.compactMap { day in
            guard let start = calendar.date(byAdding: .day, value: -5, to: day),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return start...end
        }
    }

    /// The next fertile window that hasn't ended yet.
    var nextFertileWindow: ClosedRange<Date>? {
        fertileWindows.first { $0.upperBound >= today }
    }

    /// "Fertile window now, until Nov 11" or "Fertile Nov 5 – Nov 11".
    var fertileLine: String? {
        guard let window = nextFertileWindow else { return nil }
        if window.contains(today) { return "Fertile window now, until \(window.upperBound.monthDay)" }
        return "Fertile \(window.lowerBound.monthDay) – \(window.upperBound.monthDay)"
    }

    // MARK: One day on the calendar

    enum Mark { case period, predicted, ovulation, fertile, none }

    /// What to show for a day: a logged period, a predicted one, or the fertile window.
    func mark(for date: Date) -> Mark {
        let day = calendar.startOfDay(for: date)
        if periods.contains(where: { $0.start <= day && day <= $0.end }) { return .period }
        guard day >= today else { return .none }
        if predictedPeriods.contains(where: { $0.contains(day) }) { return .predicted }
        if ovulationDays.contains(day) { return .ovulation }
        if fertileWindows.contains(where: { $0.contains(day) }) { return .fertile }
        return .none
    }
}

extension Date {
    /// "Nov 24"
    var monthDay: String { formatted(.dateTime.month(.abbreviated).day()) }
}
