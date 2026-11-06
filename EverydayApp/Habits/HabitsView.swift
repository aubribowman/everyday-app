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

    /// Ideas you haven't added yet.
    private var seeds: [HabitIdeas.Idea] {
        let names = Set(habits.map { $0.name.lowercased() })
        return HabitIdeas.all.filter { !names.contains($0.name.lowercased()) }
    }

    /// "3 habits · 1 in bloom today"
    private var summary: String {
        let bloomed = habits.filter(\.isDoneToday).count
        return "\(habits.count) \(habits.count == 1 ? "habit" : "habits") · \(bloomed) in bloom today"
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
                            Button { editing = habit } label: { HabitWeekCard(habit: habit) }
                                .buttonStyle(.plain)
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
                                .accessibilityHint("Opens the habit. Long-press to move or delete it.")
                        }
                    }
                    // Labels the bars: oldest day on the left, today on the right.
                    HStack {
                        Text(Date.now.addingTimeInterval(-6 * 86_400).formatted(.dateTime.weekday(.abbreviated)))
                        Spacer()
                        Text("Today")
                    }
                    .font(.sans(.caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, HabitWeekCard.barInset)
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
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

    /// The four growth stages: Seed, Sprout, Leafy, Bloom.
    private var stageKey: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(PlantStage.allCases, id: \.self) { stage in
                VStack(spacing: 2) {
                    PlantDrawing(stage: stage)
                        .frame(width: 40, height: 42)
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

/// A habit on the Habits screen: its plant, streaks, today's status and a bar for each of the last 7 days.
struct HabitWeekCard: View {
    let habit: Habit

    static let plantSize: CGFloat = 64
    /// Where the bars start, so the "Fri … Today" labels can line up with them.
    static let barInset: CGFloat = 16 + plantSize + 14

    var body: some View {
        HStack(spacing: 14) {
            PlantDrawing(stage: PlantStage(habit))
                .padding(4)
                .frame(width: Self.plantSize, height: Self.plantSize)
                .background(habit.tintValue.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
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
                Text(subtitle)
                    .font(.sans(.footnote))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    ForEach(habit.lastWeek, id: \.day) { entry in
                        Capsule()
                            .fill(barColor(entry))
                            .frame(height: 7)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), \(status.text). \(subtitle). Done \(habit.lastWeek.filter(\.done).count) of the last 7 days.")
    }

    /// "In bloom", "3 of 8" or "Seed".
    private var status: (text: String, color: Color) {
        if habit.isDoneToday { return ("In bloom", Theme.terracotta) }
        if habit.countToday > 0 { return ("\(habit.countToday) of \(habit.target)", Theme.ink) }
        return ("Seed", Theme.lavenderInk)
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

    /// Green for done days, terracotta once today is done, a lighter green for today in progress.
    private func barColor(_ entry: (day: Date, done: Bool)) -> Color {
        let isToday = Calendar.current.isDateInToday(entry.day)
        if entry.done { return isToday ? Theme.terracotta : PlantColors.stem }
        if isToday && habit.countToday > 0 { return PlantColors.stem.opacity(0.45) }
        return Theme.sage
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
                if editing != nil {
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
