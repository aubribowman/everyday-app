// The habit screens: the plant shelf card on Today (pots are in PlantShelf.swift), the full Habits screen, and the
// add/edit sheet. Also FlowLayout, which wraps views onto new lines.

import SwiftUI
import SwiftData

/// Opens the Habits screen from anywhere in a NavigationStack.
enum HabitRoute: Hashable { case all }

extension View {
    /// The Habits screen any tab can push to.
    func habitDestinations() -> some View {
        navigationDestination(for: HabitRoute.self) { _ in HabitsView() }
    }
}

// MARK: Today card

/// Today's habits as a shelf of potted plants. Tap a plant to check in;
/// long-press for more. Scrolls sideways when there are more than three.
struct HabitsCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var adding = false
    @State private var editing: Habit?

    let onManage: () -> Void

    private var doneCount: Int { habits.filter(\.isDoneToday).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Plant \(Text("shelf").font(.display(.title3, italic: true)))")
                    .font(.display(.title3))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !habits.isEmpty {
                    // "1 of 3 watered". Tap it to see every habit.
                    Button(action: onManage) {
                        Text(doneCount == habits.count ? "All watered" : "\(doneCount) of \(habits.count) watered")
                            .font(.sans(.caption, .semibold))
                            .foregroundStyle(Theme.forest)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens all habits")
                }
            }

            if habits.isEmpty {
                ideas
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(habits) { habit in
                                PlantPot(habit: habit)
                                    .containerRelativeFrame(.horizontal, count: 3, spacing: 8)
                                    .contextMenu {
                                        if habit.target > 1 && !habit.isDoneToday {
                                            Button("Mark all done", systemImage: "checkmark.circle") {
                                                while !habit.isDoneToday { habit.addOne(in: context) }
                                            }
                                        }
                                        if habit.countToday > 0 {
                                            Button("Take one back", systemImage: "arrow.uturn.backward") {
                                                habit.removeOne(in: context)
                                            }
                                        }
                                        Button("Edit", systemImage: "pencil") { editing = habit }
                                    }
                            }
                            EmptyPot { adding = true }
                                .containerRelativeFrame(.horizontal, count: 3, spacing: 8)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollDisabled(habits.count < 3)

                    // The wooden shelf the pots sit on.
                    Capsule()
                        .fill(PlantColors.shelf)
                        .frame(height: 8)
                        .padding(.horizontal, 2)
                        .padding(.top, 8)
                }

                Button("All habits", action: onManage)
                    .font(.sans(.footnote, .medium))
                    .foregroundStyle(Theme.forest)
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.sage, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .sheet(isPresented: $adding) { HabitSheet(order: habits.count) }
        .sheet(item: $editing) { HabitSheet(editing: $0) }
    }

    /// No habits yet: a few ideas you can add with one tap.
    private var ideas: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Small things you want to do every day. Tap an idea to add it.")
                .font(.sans(.subheadline))
                .foregroundStyle(Theme.muted)
            FlowLayout(spacing: 8) {
                ForEach(HabitIdeas.all) { idea in
                    Button {
                        context.insert(Habit(name: idea.name, icon: idea.icon, tint: idea.tint,
                                             target: idea.target, order: habits.count))
                    } label: {
                        IdeaChip(idea: idea)
                    }
                    .buttonStyle(.plain)
                }
                Button { adding = true } label: {
                    Label("Your own", systemImage: "plus")
                        .font(.sans(.footnote, .medium))
                        .foregroundStyle(Theme.forest)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(Theme.hairline))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: All habits

/// Your garden: every habit as a plant with its streaks and last 7 days,
/// a key to the growth stages, and ideas ("seeds") you can add with one tap.
struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var adding = false
    @State private var editing: Habit?
    @AppStorage(HabitNudge.remindKey) private var nudge = false
    @AppStorage(HabitNudge.minutesKey) private var nudgeMinutes = HabitNudge.defaultMinutes

    /// Ideas you haven't added yet.
    private var seeds: [HabitIdeas.Idea] {
        let names = Set(habits.map { $0.name.lowercased() })
        return HabitIdeas.all.filter { !names.contains($0.name.lowercased()) }
    }

    /// "3 habits · 1 watered today · 1 thirsty"
    private var summary: String {
        let watered = habits.filter(\.isDoneToday).count
        let thirsty = habits.filter(\.isThirsty).count
        var line = "\(habits.count) \(habits.count == 1 ? "habit" : "habits") · \(watered) watered today"
        if thirsty > 0 { line += " · \(thirsty) thirsty" }
        return line
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your \(Text("garden").font(.display(.largeTitle, italic: true)).foregroundStyle(Theme.terracotta))")
                        .font(.display(.largeTitle))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text(habits.isEmpty ? "Small things, every day." : summary)
                        .font(.sans(.subheadline))
                        .foregroundStyle(Theme.muted)
                }

                stageKey

                if habits.isEmpty {
                    Text("Nothing planted yet. Tap + or pick a seed below.")
                        .font(.sans(.subheadline))
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(habits) { habit in
                            HabitWeekCard(habit: habit) { editing = habit }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = habit }
                                    Button("Move up", systemImage: "arrow.up") { move(habit, by: -1) }
                                        .disabled(habit == habits.first)
                                    Button("Move down", systemImage: "arrow.down") { move(habit, by: 1) }
                                        .disabled(habit == habits.last)
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(habit)
                                    }
                                }
                        }
                    }
                    Text("Forgot one? Tap any of the last 7 days to log it, or open a habit to fix older days.")
                        .font(.sans(.caption))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)

                    checkInCard
                }

                if !seeds.isEmpty { seedChips }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { AddButtonLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New habit")
            }
            .sharedBackgroundVisibility(.hidden)   // just the green circle, no glass ring
        }
        .sheet(isPresented: $adding) { HabitSheet(order: habits.count) }
        .sheet(item: $editing) { HabitSheet(editing: $0) }
    }

    /// The evening check-in reminder: one notification listing the habits not logged yet.
    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $nudge.animation()) {
                Label("Evening check-in", systemImage: "bell")
            }
            .padding(.vertical, 10)
            if nudge {
                Divider().overlay(Theme.hairline)
                DatePicker("Time", selection: $nudgeMinutes.timeOfDay, displayedComponents: .hourAndMinute)
                    .padding(.vertical, 6)
            }
            Text(nudge
                 ? "At \(nudgeMinutes.timeOfDayText), a reminder listing any habits you haven't logged yet. None once they're all done. Open a habit to give it its own reminder too."
                 : "A reminder each evening to log any habits you haven't yet.")
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
        .padding(.top, 4)
    }

    /// The six growth stages, from Seed to Flourish, and how the game works.
    private var stageKey: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(PlantStage.allCases, id: \.self) { stage in
                    VStack(spacing: 2) {
                        PlantDrawing(stage: stage)
                            .frame(width: 36, height: 38)
                        Text(stage.name)
                            .font(.sans(.footnote, .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(stage.meaning)
                            .font(.sans(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stage.name): \(stage.meaning)")
                }
            }
            Text("Each day you do a habit waters its plant, and it grows. Miss a day and it gets thirsty. Keep missing and it shrinks.")
                .font(.sans(.caption))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Theme.sage, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// "Seeds to plant": ideas you haven't added. Tap one to add it.
    private var seedChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Seeds to \(Text("plant").font(.display(.title3, italic: true)))")
                .font(.display(.title3))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)
            FlowLayout(spacing: 8) {
                ForEach(seeds) { idea in
                    Button {
                        withAnimation(.snappy) {
                            context.insert(Habit(name: idea.name, icon: idea.icon, tint: idea.tint,
                                                 target: idea.target, order: habits.count))
                        }
                    } label: {
                        Label(idea.name, systemImage: "plus")
                            .font(.sans(.subheadline, .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(Capsule().strokeBorder(Theme.muted.opacity(0.5),
                                                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(idea.name)")
                }
            }
        }
    }

    /// Swaps a habit with its neighbor, then renumbers them all.
    private func move(_ habit: Habit, by offset: Int) {
        var ordered = habits
        guard let index = ordered.firstIndex(of: habit),
              ordered.indices.contains(index + offset) else { return }
        ordered.swapAt(index, index + offset)
        withAnimation(.snappy) {
            for (position, item) in ordered.enumerated() { item.order = position }
        }
    }
}

/// A habit on the Habits screen: its plant, growth, streaks, and the last 7 days.
/// Tap a day to mark it done or not (for days you forgot); tap the rest to edit the habit.
struct HabitWeekCard: View {
    @Environment(\.modelContext) private var context
    let habit: Habit
    var onEdit: () -> Void

    static let plantSize: CGFloat = 64

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PlantDrawing(stage: habit.stage, thirsty: habit.isThirsty)
                .padding(4)
                .frame(width: Self.plantSize, height: Self.plantSize)
                .background(habit.tintValue.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture(perform: onEdit)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(habit.name)
                            .font(.sans(.headline))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(status.text)
                            .font(.sans(.footnote, .semibold))
                            .foregroundStyle(status.color)
                    }
                    Text(growthLine)
                        .font(.sans(.footnote, .medium))
                        .foregroundStyle(Theme.forest)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.sans(.footnote))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the habit. Long-press to move or delete it.")
                .accessibilityAction(.default) { onEdit() }

                HStack(spacing: 2) {
                    ForEach(habit.lastWeek, id: \.day) { entry in
                        DayButton(habit: habit, day: entry.day)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
    }

    /// "Watered", "3 of 8", "Thirsty" or "Not yet".
    private var status: (text: String, color: Color) {
        if habit.isDoneToday { return ("Watered", Theme.terracotta) }
        if habit.countToday > 0 { return ("\(habit.countToday) of \(habit.target)", Theme.ink) }
        if habit.isThirsty { return ("Thirsty", Theme.terracotta) }
        return ("Not yet", Theme.muted)
    }

    /// "Leafy · 4 days to Bud"
    private var growthLine: String {
        let stage = habit.stage
        guard let next = stage.next, let days = habit.daysToNextStage else {
            return "\(stage.name) · fully grown"
        }
        return "\(stage.name) · \(days) \(days == 1 ? "day" : "days") to \(next.name)"
    }

    /// "5-day streak · best 12 · 9:00 AM" or "Streak ended · best 6"
    private var subtitle: String {
        var parts: [String] = []
        if habit.streak > 0 { parts.append("\(habit.streak)-day streak") }
        else if habit.bestStreak > 0 { parts.append("Streak ended") }
        else { parts.append("Just planted") }
        if habit.bestStreak > habit.streak { parts.append("best \(habit.bestStreak)") }
        if let time = habit.reminderLine { parts.append(time) }
        return parts.joined(separator: " · ")
    }
}

/// One day as a tappable dot with its weekday letter. Tap to mark it done or not done.
struct DayButton: View {
    @Environment(\.modelContext) private var context
    let habit: Habit
    let day: Date
    var size: CGFloat = 26
    var label: String?            // defaults to the weekday's letter, under the dot

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var done: Bool { habit.isDone(on: day) }
    private var started: Bool { habit.count(on: day) > 0 }

    var body: some View {
        Button {
            withAnimation(.snappy) { habit.toggle(on: day, in: context) }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(fill)
                    if isToday && !done {
                        Circle().strokeBorder(Theme.forest, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    }
                    if let label {
                        Text(label)
                            .font(.sans(.footnote, done ? .semibold : nil))
                            .foregroundStyle(done ? Theme.onPrimary : Theme.ink)
                    } else if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
                if label == nil {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.sans(.caption2, isToday ? .semibold : nil))
                        .foregroundStyle(isToday ? Theme.ink : Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: done)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month().day())), \(done ? "done" : started ? "started" : "not done")")
        .accessibilityHint(done ? "Double-tap to mark not done" : "Double-tap to mark done")
    }

    /// Fern for done (terracotta for today), a pale fern for started, sage for not done.
    private var fill: Color {
        if done { return isToday ? Theme.terracotta : PlantColors.stem }
        if started { return PlantColors.stem.opacity(0.3) }
        return Theme.sage
    }
}

/// The last 5 weeks as a little calendar, for logging older days you forgot.
struct HabitHistoryGrid: View {
    let habit: Habit

    /// Every day from the start of the week 4 weeks ago through the end of this week.
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = calendar.date(byAdding: .weekOfYear, value: -4, to: thisWeek)!
        return (0..<35).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// "S M T W T F S", starting on the first day of the week where you live.
    private var weekdayLetters: [String] {
        let calendar = Calendar.current
        let letters = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(letters[first...] + letters[..<first])
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.sans(.caption2, .semibold))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(days, id: \.self) { day in
                if day > .now {
                    Text(day.formatted(.dateTime.day()))
                        .font(.sans(.footnote))
                        .foregroundStyle(Theme.muted.opacity(0.4))
                        .frame(width: 34, height: 34)
                        .accessibilityHidden(true)
                } else {
                    DayButton(habit: habit, day: day, size: 34, label: day.formatted(.dateTime.day()))
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: Add / edit

/// Adds a habit, or edits `editing` when one is passed in.
struct HabitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let editing: Habit?
    private let order: Int

    @State private var name: String
    @State private var icon: String
    @State private var tint: CardTint
    @State private var target: Int
    @State private var remind: Bool
    @State private var remindAt: Date
    @State private var confirmingDelete = false
    @Query private var existing: [Habit]

    init(editing habit: Habit? = nil, order: Int = 0) {
        editing = habit
        self.order = order
        _name = State(initialValue: habit?.name ?? "")
        _icon = State(initialValue: habit?.icon ?? "leaf")
        _tint = State(initialValue: habit?.tintValue ?? .sage)
        _target = State(initialValue: habit?.target ?? 1)
        _remind = State(initialValue: habit?.remindAt != nil)
        // New reminders start at 9 AM.
        _remindAt = State(initialValue: habit?.remindAt
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Ideas you haven't added yet. Tapping one fills in the form.
    private var unusedIdeas: [HabitIdeas.Idea] {
        let names = Set(existing.map { $0.name.lowercased() })
        return HabitIdeas.all.filter { !names.contains($0.name.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Stretch", text: $name)
                }
                if editing == nil && !unusedIdeas.isEmpty {
                    Section("Ideas") {
                        FlowLayout(spacing: 8) {
                            ForEach(unusedIdeas) { idea in
                                Button {
                                    name = idea.name
                                    icon = idea.icon
                                    tint = idea.tint
                                    target = idea.target
                                } label: {
                                    IdeaChip(idea: idea)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    Stepper(value: $target, in: 1...20) {
                        Text(target == 1 ? "Once a day" : "\(target) times a day")
                    }
                } footer: {
                    Text("More than once is handy for things like glasses of water. Each tap counts one.")
                }
                Section {
                    Toggle("Remind me", isOn: $remind.animation())
                    if remind {
                        DatePicker("Every day at", selection: $remindAt, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    if remind {
                        Text("No reminder on days you've already checked in.")
                    }
                }
                Section("Color") {
                    Picker("Color", selection: $tint) {
                        ForEach(CardTint.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(tint.fill)
                }
                Section("Icon") {
                    IconGrid(icons: HabitIdeas.icons, selection: $icon)
                }
                if let editing {
                    Section {
                        HabitHistoryGrid(habit: editing)
                    } header: {
                        Text("Past 5 weeks")
                    } footer: {
                        Text("Tap a day to mark it done or not done. This saves right away.")
                    }
                    Section {
                        Button("Delete habit", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .themedForm()
            .navigationTitle(editing == nil ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete this habit and its history?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let editing { context.delete(editing) }
                    dismiss()
                }
            }
            .tint(Theme.forest)
        }
    }

    private func save() {
        if let editing {
            editing.name = trimmedName
            editing.icon = icon
            editing.tint = tint.rawValue
            editing.target = target
            editing.remindAt = remind ? remindAt : nil
        } else {
            let habit = Habit(name: trimmedName, icon: icon, tint: tint, target: target, order: order)
            habit.remindAt = remind ? remindAt : nil
            context.insert(habit)
        }
        dismiss()
    }
}

// MARK: Layout

/// A habit idea as a small colored pill: icon and name.
struct IdeaChip: View {
    let idea: HabitIdeas.Idea

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: idea.icon)
            Text(idea.name)
        }
        .font(.sans(.footnote, .medium))
        .foregroundStyle(idea.tint.ink)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(idea.tint.fill, in: Capsule())
    }
}

/// Lays out views left to right and wraps onto new lines, like words in a sentence.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    /// Splits the views into rows that fit within `width`.
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
