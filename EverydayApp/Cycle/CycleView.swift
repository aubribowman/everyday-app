// The period tracker's screens: the Cycle card on Today, the Your cycle screen (status,
// a month calendar with predictions, averages and history), and the sheet for logging a day.
// The data and predictions are in Cycle.swift.

import SwiftUI
import SwiftData

/// Opens the Your cycle screen from a NavigationStack.
enum CycleRoute: Hashable { case cycle }

extension View {
    func cycleDestinations() -> some View {
        navigationDestination(for: CycleRoute.self) { _ in CycleView() }
    }
}

/// The colors used for periods, predictions and the fertile window.
enum CycleColors {
    static let period = Theme.terracotta
    static let fertile = Theme.lavender           // Honey tint
    static let ovulation = Theme.honey
    static let fertileInk = Theme.lavenderInk
}

/// A day picked to log, for `.sheet(item:)`.
struct CycleDayPick: Identifiable {
    let day: Date
    var id: Date { day }
}

// MARK: Today card

/// Your cycle at a glance on Today: which day it is, when the next period is due,
/// and a button to log today's period. Tap the card to open Your cycle.
struct CycleCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CycleDay.day) private var days: [CycleDay]
    @AppStorage(CycleSettings.cycleLengthKey) private var typicalCycle = CycleSettings.defaultCycle
    @AppStorage(CycleSettings.periodLengthKey) private var typicalPeriod = CycleSettings.defaultPeriod
    @State private var editing: CycleDayPick?

    let onOpen: () -> Void

    private var summary: CycleSummary {
        CycleSummary(days: days, typicalCycle: typicalCycle, typicalPeriod: typicalPeriod)
    }

    private var todayLog: CycleDay? {
        let today = Calendar.current.startOfDay(for: .now)
        return days.first { $0.day == today }
    }

    var body: some View {
        let summary = summary
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your \(Text("cycle").font(.display(.title3, italic: true)))")
                    .font(.display(.title3))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Open", action: onOpen)
                    .font(.sans(.caption, .semibold))
                    .foregroundStyle(Theme.peachInk)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Theme.surface, in: Capsule())
                    .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                CycleRing(day: summary.dayOfCycle, length: summary.averageCycle, onPeriod: summary.isOnPeriod)
                    .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.headline)
                        .font(.display(.title3))
                        .foregroundStyle(Theme.ink)
                    Text(detail(summary))
                        .font(.sans(.footnote))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fertile = summary.fertileLine {
                        Label(fertile, systemImage: "sparkle")
                            .font(.sans(.footnote, .semibold))
                            .foregroundStyle(CycleColors.fertileInk)
                    }
                }
                Spacer(minLength: 0)
            }

            if let log = todayLog, log.isPeriod {
                Button { editing = CycleDayPick(day: .now) } label: {
                    Label("Logged today · \(log.flowValue?.label ?? "")", systemImage: "checkmark")
                        .font(.sans(.subheadline, .semibold))
                        .foregroundStyle(Theme.peachInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: logToday) {
                    Label(summary.isOnPeriod ? "Still on my period" : "Log period today", systemImage: "drop.fill")
                        .font(.sans(.subheadline, .semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(CycleColors.period, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.peach, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
        .sensoryFeedback(.success, trigger: todayLog?.isPeriod ?? false) { _, logged in logged }
        .sheet(item: $editing) { CycleDaySheet(day: $0.day) }
    }

    /// "Next period Tue, Nov 24"
    private func detail(_ summary: CycleSummary) -> String {
        guard let next = summary.nextStart else {
            return "Tap Log period on the first day of your next period, or add past ones in Your cycle."
        }
        return "Next period \(next.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }

    /// Marks today as a period day (medium flow; change it in Your cycle).
    private func logToday() {
        withAnimation(.snappy) {
            if let log = todayLog {
                log.flow = Flow.medium.rawValue
            } else {
                context.insert(CycleDay(day: .now, flow: .medium))
            }
        }
    }
}

/// A ring that fills as the cycle goes on, with "Day 12" in the middle.
struct CycleRing: View {
    let day: Int?
    let length: Int
    var onPeriod = false
    var lineWidth: CGFloat = 7
    var track = Theme.surface
    var ink = Theme.ink

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if let day {
                Circle()
                    .trim(from: 0, to: min(Double(day) / Double(max(length, 1)), 1))
                    .stroke(CycleColors.period, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("Day")
                        .font(.sans(.caption2, .semibold))
                        .foregroundStyle(ink.opacity(0.7))
                    Text("\(day)")
                        .font(.display(.title))
                        .foregroundStyle(ink)
                }
            } else {
                Image(systemName: "drop")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CycleColors.period)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.map { "Day \($0) of your cycle" } ?? "No period logged yet")
    }
}

// MARK: Your cycle

/// The full period tracker: today's status, a month calendar with logged and predicted
/// periods and the fertile window, your averages, recent periods and settings.
struct CycleView: View {
    @Query(sort: \CycleDay.day) private var days: [CycleDay]
    @AppStorage(CycleSettings.cycleLengthKey) private var typicalCycle = CycleSettings.defaultCycle
    @AppStorage(CycleSettings.periodLengthKey) private var typicalPeriod = CycleSettings.defaultPeriod
    @AppStorage(CycleSettings.showOnTodayKey) private var showOnToday = true
    @AppStorage(CycleSettings.remindBeforeKey) private var remindBefore = false
    @AppStorage(CycleSettings.remindLogKey) private var remindLog = false
    @AppStorage(CycleSettings.remindMinutesKey) private var remindMinutes = CycleSettings.defaultRemindMinutes
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var editing: CycleDayPick?

    private var summary: CycleSummary {
        CycleSummary(days: days, typicalCycle: typicalCycle, typicalPeriod: typicalPeriod)
    }

    var body: some View {
        let summary = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your \(Text("cycle").font(.display(.largeTitle, italic: true)).foregroundStyle(Theme.terracotta))")
                        .font(.display(.largeTitle))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text("Average cycle \(summary.averageCycle) days · period \(summary.averagePeriod) days")
                        .font(.sans(.subheadline))
                        .foregroundStyle(Theme.muted)
                }

                statusCard(summary)
                CycleMonthCard(month: $month, summary: summary, days: days) { day in
                    editing = CycleDayPick(day: day)
                }
                stats(summary)
                if !summary.periods.isEmpty { history(summary) }
                settings
                VStack(alignment: .leading, spacing: 10) {
                    Text("Re\(Text("minders").font(.display(.title3, italic: true)))")
                        .font(.display(.title3))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 4)
                    reminders
                }

                Text("Predictions are estimates based on what you've logged. They aren't medical advice and shouldn't be used as birth control.")
                    .font(.sans(.caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = CycleDayPick(day: .now) } label: { AddButtonLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log today")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(item: $editing) { CycleDaySheet(day: $0.day) }
    }

    /// The dark fern card: day of cycle, when the next period is due, and the fertile window.
    private func statusCard(_ summary: CycleSummary) -> some View {
        HStack(spacing: 18) {
            CycleRing(day: summary.dayOfCycle, length: summary.averageCycle, onPeriod: summary.isOnPeriod,
                      lineWidth: 8, track: Theme.onHero.opacity(0.16), ink: Theme.onHero)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.headline)
                    .font(.display(.title2))
                    .foregroundStyle(Theme.onHero)
                if let next = summary.nextStart {
                    Text("Next period \(next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                        .font(.sans(.footnote))
                        .foregroundStyle(Theme.onHero.opacity(0.8))
                }
                if let fertile = summary.fertileLine {
                    Label(fertile, systemImage: "sparkle")
                        .font(.sans(.footnote, .semibold))
                        .foregroundStyle(Theme.honey)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Average cycle, average period and how many cycles that's from.
    private func stats(_ summary: CycleSummary) -> some View {
        HStack(spacing: 10) {
            statTile("\(summary.averageCycle)", "day cycle")
            statTile("\(summary.averagePeriod)", "day period")
            statTile("\(summary.cyclesLogged)", summary.cyclesLogged == 1 ? "cycle logged" : "cycles logged")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.display(.title))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.sans(.caption))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline))
        .accessibilityElement(children: .combine)
    }

    /// The last six periods, newest first: dates, length, and the cycle that followed.
    private func history(_ summary: CycleSummary) -> some View {
        let periods = Array(summary.periods.suffix(7))
        let rows = periods.indices.reversed().prefix(6).map { index in
            let period = periods[index]
            let next = index + 1 < periods.count ? periods[index + 1].start : nil
            let cycle = next.flatMap { Calendar.current.dateComponents([.day], from: period.start, to: $0).day }
            return (period, cycle)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Recent \(Text("periods").font(.display(.title3, italic: true)))")
                .font(.display(.title3))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                    HStack {
                        Circle().fill(CycleColors.period).frame(width: 8, height: 8)
                        Text("\(row.0.start.monthDay) – \(row.0.end.monthDay)")
                            .font(.sans(.subheadline, .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        let days = row.0.length == 1 ? "1 day" : "\(row.0.length) days"
                        Text(row.1.map { "\(days) · \($0)-day cycle" } ?? days)
                            .font(.sans(.footnote))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 12)
                    if offset < rows.count - 1 { Divider().overlay(Theme.hairline) }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
        }
    }

    /// Typical lengths (used until you've logged a couple of cycles) and the Today card.
    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Stepper(value: $typicalCycle, in: 20...45) {
                LabeledContent("Typical cycle", value: "\(typicalCycle) days")
            }
            .padding(.vertical, 10)
            Divider().overlay(Theme.hairline)
            Stepper(value: $typicalPeriod, in: 2...10) {
                LabeledContent("Typical period", value: "\(typicalPeriod) days")
            }
            .padding(.vertical, 10)
            Divider().overlay(Theme.hairline)
            Toggle("Show on Today", isOn: $showOnToday)
                .padding(.vertical, 10)
            Text("The typical lengths are used until you've logged two periods. After that, predictions follow your own history.")
                .font(.sans(.caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 12)
        }
        .font(.sans(.subheadline))
        .foregroundStyle(Theme.ink)
        .tint(Theme.forest)
        .padding(.horizontal, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
    }

    /// Notifications: a heads-up before your period, and reminders to log it.
    private var reminders: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Before my period", isOn: $remindBefore.animation())
                .padding(.vertical, 10)
            Divider().overlay(Theme.hairline)
            Toggle("Remind me to log it", isOn: $remindLog.animation())
                .padding(.vertical, 10)
            if remindBefore || remindLog {
                Divider().overlay(Theme.hairline)
                DatePicker("Time", selection: $remindMinutes.timeOfDay, displayedComponents: .hourAndMinute)
                    .padding(.vertical, 6)
            }
            Text(reminderNote)
                .font(.sans(.caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 12)
                .padding(.top, 4)
        }
        .font(.sans(.subheadline))
        .foregroundStyle(Theme.ink)
        .tint(Theme.forest)
        .padding(.horizontal, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
    }

    private var reminderNote: String {
        let time = remindMinutes.timeOfDayText
        switch (remindBefore, remindLog) {
        case (true, true):
            return "At \(time): a heads-up 2 days before your period, then a reminder each day to log it, with a Log today button."
        case (true, false):
            return "At \(time), 2 days before your period is expected."
        case (false, true):
            return "At \(time): \u{201C}Has your period started?\u{201D} once it's due, and \u{201C}Still on your period?\u{201D} each day while it's on. Tap Log today on the notification to log it."
        default:
            return "Get a heads-up before your period, and reminders to log it."
        }
    }
}

// MARK: Month calendar

/// One month with logged periods (filled), predicted ones (dashed), the fertile window
/// (honey) and a dot under days with symptoms or notes. Tap a past day to log it.
struct CycleMonthCard: View {
    @Binding var month: Date
    let summary: CycleSummary
    let days: [CycleDay]
    let onPick: (Date) -> Void

    private let calendar = Calendar.current

    /// Blank cells before the 1st, then each day of the month.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let blanks = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: blanks) + dates.map { Optional($0) }
    }

    private var weekdayLetters: [String] {
        let letters = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(letters[first...] + letters[..<first])
    }

    private var logs: [Date: CycleDay] {
        Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let logs = logs
        VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.display(.title3))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
                    .padding(.leading, 14)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.forest)
            .buttonStyle(.plain)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.sans(.caption2, .semibold))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date, log: logs[date])
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }

            legend
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { shift(1) } else if value.translation.width > 40 { shift(-1) }
        })
    }

    private func dayCell(_ date: Date, log: CycleDay?) -> some View {
        let mark = summary.mark(for: date)
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > .now
        return Button { onPick(date) } label: {
            VStack(spacing: 2) {
                ZStack {
                    switch mark {
                    case .period:
                        Circle().fill(CycleColors.period)
                    case .predicted:
                        Circle().strokeBorder(CycleColors.period, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    case .ovulation:
                        Circle().fill(CycleColors.ovulation)
                    case .fertile:
                        Circle().fill(CycleColors.fertile)
                    case .none:
                        EmptyView()
                    }
                    if isToday {
                        Circle().strokeBorder(Theme.forest, lineWidth: 1.5)
                            .padding(mark == .none ? 0 : -3)
                    }
                    Text(date.formatted(.dateTime.day()))
                        .font(.sans(.subheadline, isToday || mark == .period ? .semibold : nil))
                        .foregroundStyle(mark == .period ? Theme.onPrimary
                                         : mark == .fertile || mark == .ovulation ? CycleColors.fertileInk
                                         : Theme.ink)
                }
                .frame(width: 34, height: 34)
                // A dot for days with symptoms, spotting or a note.
                Circle()
                    .fill(log.map { !$0.symptoms.isEmpty || $0.flowValue == .spotting || !$0.note.isEmpty } == true
                          ? Theme.peachInk : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .opacity(isFuture && mark == .none ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isFuture)   // you can't log days that haven't happened
        .accessibilityLabel(accessibilityText(date, mark: mark, log: log))
    }

    private func accessibilityText(_ date: Date, mark: CycleSummary.Mark, log: CycleDay?) -> String {
        var text = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        switch mark {
        case .period: text += ", period" + (log?.flowValue.map { ", \($0.label) flow" } ?? "")
        case .predicted: text += ", predicted period"
        case .ovulation: text += ", likely ovulation"
        case .fertile: text += ", fertile window"
        case .none: break
        }
        if let symptoms = log?.symptoms, !symptoms.isEmpty { text += ", " + symptoms.joined(separator: ", ") }
        return text
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Period") { Circle().fill(CycleColors.period) }
            legendItem("Predicted") {
                Circle().strokeBorder(CycleColors.period, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            }
            legendItem("Fertile") { Circle().fill(CycleColors.fertile) }
            legendItem("Ovulation") { Circle().fill(CycleColors.ovulation) }
        }
        .font(.sans(.caption))
        .foregroundStyle(Theme.muted)
        .accessibilityHidden(true)
    }

    private func legendItem(_ label: String, @ViewBuilder dot: () -> some View) -> some View {
        HStack(spacing: 5) {
            dot().frame(width: 10, height: 10)
            Text(label)
        }
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) {
            withAnimation(.snappy) { month = next }
        }
    }
}

// MARK: Log a day

/// Logs one day: flow, symptoms and a note. Saving an empty day removes it.
struct CycleDaySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [CycleDay]
    let day: Date

    @State private var flow: Flow?
    @State private var symptoms: Set<String> = []
    @State private var note = ""
    @State private var loaded = false

    init(day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        self.day = start
        _existing = Query(filter: #Predicate<CycleDay> { $0.day == start })
    }

    private var log: CycleDay? { existing.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Flow") {
                    FlowLayout(spacing: 8) {
                        flowChip(nil, label: "None")
                        ForEach(Flow.allCases) { flowChip($0, label: $0.label) }
                    }
                    .padding(.vertical, 4)
                }
                Section("Symptoms") {
                    FlowLayout(spacing: 8) {
                        ForEach(CycleSymptom.all, id: \.name) { symptom in
                            let on = symptoms.contains(symptom.name)
                            Button {
                                if on { symptoms.remove(symptom.name) } else { symptoms.insert(symptom.name) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: symptom.icon)
                                    Text(symptom.name)
                                }
                                .font(.sans(.footnote, .medium))
                                .foregroundStyle(on ? Theme.onPrimary : Theme.ink)
                                .lineLimit(1)
                                .fixedSize()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(on ? Theme.forest : Theme.sage, in: Capsule())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Note") {
                    TextField("Anything else about today", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if log != nil {
                    Section {
                        Button("Clear this day", role: .destructive) {
                            if let log { context.delete(log) }
                            dismiss()
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .tint(Theme.forest)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                flow = log?.flowValue
                symptoms = Set(log?.symptoms ?? [])
                note = log?.note ?? ""
            }
        }
        .presentationDetents([.large])
    }

    private func flowChip(_ value: Flow?, label: String) -> some View {
        let on = flow == value
        return Button { flow = value } label: {
            HStack(spacing: 4) {
                if let value {
                    if value.drops == 0 {
                        Circle().frame(width: 5, height: 5)
                    } else {
                        ForEach(0..<value.drops, id: \.self) { _ in
                            Image(systemName: "drop.fill").font(.system(size: 9))
                        }
                    }
                }
                Text(label)
            }
            .font(.sans(.footnote, .semibold))
            .foregroundStyle(on ? Theme.onPrimary : value == nil ? Theme.ink : Theme.peachInk)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(on ? (value == nil ? Theme.forest : CycleColors.period) : Theme.peach, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func save() {
        let ordered = CycleSymptom.all.map(\.name).filter(symptoms.contains)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = flow == nil && ordered.isEmpty && trimmed.isEmpty
        if let log {
            if isEmpty {
                context.delete(log)
            } else {
                log.flow = flow?.rawValue ?? ""
                log.symptoms = ordered
                log.note = trimmed
            }
        } else if !isEmpty {
            let new = CycleDay(day: day, flow: flow)
            new.symptoms = ordered
            new.note = trimmed
            context.insert(new)
        }
        dismiss()
    }
}
