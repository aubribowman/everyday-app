import SwiftUI
import SwiftData

/// Opens the Habits screen from anywhere in a NavigationStack.
enum HabitRoute: Hashable { case all }

extension View {
    func habitDestinations() -> some View {
        navigationDestination(for: HabitRoute.self) { _ in HabitsView() }
    }
}

// MARK: Today card

/// Today's habits as tiles. Tap one to check it in; long-press for more.
struct HabitsCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var adding = false
    @State private var editing: Habit?

    let onManage: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private var doneCount: Int { habits.filter(\.isDoneToday).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Habits", action: habits.isEmpty ? nil : "All habits", onTap: onManage)

            if habits.isEmpty {
                ideas
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(habits) { habit in
                        HabitTile(habit: habit)
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
                    addTile
                }
                Text(doneCount == habits.count
                     ? "All done today. Lovely."
                     : "\(doneCount) of \(habits.count) done today")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .sheet(isPresented: $adding) { HabitSheet(order: habits.count) }
        .sheet(item: $editing) { HabitSheet(editing: $0) }
    }

    /// The last tile: opens the new-habit sheet.
    private var addTile: some View {
        Button { adding = true } label: {
            Label("Add habit", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.forest)
                .frame(maxWidth: .infinity, minHeight: 68)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// No habits yet: a few ideas you can add with one tap.
    private var ideas: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Small things you want to do every day. Tap an idea to add it.")
                .font(.subheadline)
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
                        .font(.footnote.weight(.medium))
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

/// One habit: a ring that fills as you go, its name, today's progress and your streak.
struct HabitTile: View {
    @Environment(\.modelContext) private var context
    let habit: Habit

    var body: some View {
        let tint = habit.tintValue
        Button {
            withAnimation(.snappy) { habit.tap(in: context) }
        } label: {
            HStack(spacing: 10) {
                HabitRing(habit: habit, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(habit.progressLine)
                        if habit.streak > 0 {
                            Text("\(Image(systemName: "flame.fill")) \(habit.streak)")
                                .accessibilityLabel("\(habit.streak) day streak")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(tint.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(tint.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: habit.isDoneToday) { _, done in done }
        .sensoryFeedback(.increase, trigger: habit.countToday)
        .accessibilityHint(habit.isDoneToday ? "Double-tap to take one back" : "Double-tap to check in")
    }
}

/// The habit's icon inside a ring that fills up (all the way once done).
struct HabitRing: View {
    let habit: Habit
    var size: CGFloat = 40

    var body: some View {
        let tint = habit.tintValue
        let progress = min(Double(habit.countToday) / Double(max(habit.target, 1)), 1)
        ZStack {
            Circle().stroke(tint.ink.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if habit.isDoneToday {
                Circle().fill(tint.ink).padding(5)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(tint.fill)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: habit.icon)
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(tint.ink)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: All habits

/// Every habit with its last 7 days and streaks. Add, edit and delete here.
struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var adding = false
    @State private var editing: Habit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Habits")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.ink)
                        Text("Small things, every day.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { adding = true } label: { AddButtonLabel() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New habit")
                }

                if habits.isEmpty {
                    ContentUnavailableView("No habits yet", systemImage: "leaf",
                                           description: Text("Tap + to add something you want to do every day."))
                        .padding(.top, 30)
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
                        }
                    }
                    Text("Tap a habit to edit it. Long-press to move or delete it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { HabitSheet(order: habits.count) }
        .sheet(item: $editing) { HabitSheet(editing: $0) }
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

/// A habit on the Habits screen: today's ring, streaks and a dot for each of the last 7 days.
struct HabitWeekCard: View {
    let habit: Habit

    var body: some View {
        let tint = habit.tintValue
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HabitRing(habit: habit, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(tint.ink)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 0) {
                ForEach(habit.lastWeek, id: \.day) { entry in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(entry.done ? tint.ink : tint.ink.opacity(0.15))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if entry.done {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(tint.fill)
                                }
                            }
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(Calendar.current.isDateInToday(entry.day) ? .bold : .regular))
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.day.formatted(.dateTime.weekday(.wide))), \(entry.done ? "done" : "not done")")
                }
            }
        }
        .padding(16)
        .background(tint.fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// "3 of 8 today · 5-day streak · best 12 · reminder 9:00 AM"
    private var subtitle: String {
        var parts = [habit.target > 1 ? "\(min(habit.countToday, habit.target)) of \(habit.target) today"
                                      : (habit.isDoneToday ? "Done today" : "Not yet today")]
        if habit.streak > 0 { parts.append("\(habit.streak)-day streak") }
        if habit.bestStreak > habit.streak { parts.append("best \(habit.bestStreak)") }
        if let time = habit.reminderLine { parts.append("reminder \(time)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Add / edit

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
        .font(.footnote.weight(.medium))
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
