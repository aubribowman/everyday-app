import SwiftUI
import SwiftData
import Charts

/// Opens the Gym screen from Today or Lists.
enum GymRoute: Hashable { case gym }

extension View {
    /// The Gym screens any tab can push to.
    func gymDestinations() -> some View {
        navigationDestination(for: GymRoute.self) { _ in GymView() }
            .navigationDestination(for: WorkoutDay.self) { WorkoutDayView(day: $0) }
    }
}

// MARK: All workouts

/// Your routine: each workout day, with the next one in the rotation marked.
struct GymView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutDay.order) private var days: [WorkoutDay]
    @State private var importing = false
    @State private var addingDay = false
    @State private var editingDay: WorkoutDay?

    private var next: WorkoutDay? { Gym.nextDay(in: days) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gym")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.ink)
                        Text("Your routine, one day at a time.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Menu {
                        Button("New workout day", systemImage: "plus") { addingDay = true }
                        Button("Paste from Notes", systemImage: "doc.on.clipboard") { importing = true }
                    } label: {
                        AddButtonLabel()
                    }
                    .accessibilityLabel("Add")
                }

                if days.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(days) { day in
                            NavigationLink(value: day) {
                                WorkoutDayCard(day: day, isNext: day == next)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { editingDay = day }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(day)
                                }
                            }
                        }
                    }
                    Text("Workouts take turns in this order. Long-press one to rename or delete it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $importing) { ImportRoutineSheet(existingCount: days.count) }
        .sheet(isPresented: $addingDay) { WorkoutDaySheet(order: days.count) }
        .sheet(item: $editingDay) { WorkoutDaySheet(editing: $0) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                "No workouts yet",
                systemImage: "dumbbell",
                description: Text("Copy your routine from the Notes app and paste it here. Each day becomes a workout you can tick off.")
            )
            Button("Paste from Notes", systemImage: "doc.on.clipboard") { importing = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.forest)
                .foregroundStyle(Theme.onPrimary)
            Button("Start from scratch") { addingDay = true }
                .foregroundStyle(Theme.forest)
        }
        .padding(.top, 30)
    }
}

/// A day on the Gym screen: icon, name, how many exercises, and "Up next".
struct WorkoutDayCard: View {
    let day: WorkoutDay
    var isNext = false

    private var tint: CardTint {
        let all: [CardTint] = [.sage, .peach, .lavender, .lemon]
        return all[abs(day.order) % all.count]
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: day.icon)
                .font(.title2)
                .foregroundStyle(tint.ink)
                .frame(width: 52, height: 52)
                .background(tint.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                if day.isFinishedToday {
                    tag("DONE TODAY", systemImage: "checkmark")
                } else if isNext {
                    tag("UP NEXT", systemImage: "arrow.right")
                }
                Text(day.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(day.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(isNext && !day.isFinishedToday ? Theme.forest.opacity(0.5) : Theme.hairline))
    }

    private func tag(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.forest)
    }
}

// MARK: One workout

/// A workout at the gym: tick off each exercise, then Finish to bump the weights for next time.
struct WorkoutDayView: View {
    @Environment(\.modelContext) private var context
    @Bindable var day: WorkoutDay
    @State private var editMode = EditMode.inactive   // .active while reordering
    @AppStorage("restSeconds") private var restSeconds = 90   // 0 = no rest timer
    private let timer = RestTimer.shared

    @State private var addingExercise = false
    @State private var editingExercise: Exercise?
    @State private var bumping = false
    @State private var renaming = false

    private var exercises: [Exercise] { day.sortedExercises }
    private var doneCount: Int { exercises.filter(\.isDoneToday).count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(day.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    if !exercises.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView(value: Double(doneCount), total: Double(exercises.count))
                                .tint(Theme.forest)
                                .frame(width: 110)
                            Text("\(doneCount) of \(exercises.count) done")
                                .font(.caption)
                                .foregroundStyle(Theme.forest)
                        }
                        .padding(.top, 2)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            Section {
                ForEach(exercises) { exercise in
                    ExerciseRow(exercise: exercise,
                                onEdit: { editingExercise = exercise },
                                onSetFinished: { startRest(after: exercise) })
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(exercises[index]) }
                }
                .onMove(perform: move)

                Button("Add exercise", systemImage: "plus") { addingExercise = true }
                    .foregroundStyle(Theme.forest)
            } footer: {
                Text("Tap the circle after each set to start your rest. Tap the name to change it or see your history.")
            }

            if day.isFinishedToday {
                Section {
                    Label("Finished today. Nice work!", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.forest)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            } else if doneCount > 0 {
                Section {
                    Button {
                        day.lastCompletedAt = .now
                        if exercises.contains(where: { $0.weight != nil && $0.isDoneToday }) { bumping = true }
                    } label: {
                        Label("Finish workout", systemImage: "flag.checkered")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.forest)
                    .foregroundStyle(Theme.onPrimary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .bottom) { RestBar(timer: timer) }
        .animation(.snappy, value: timer.end)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.forest)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button("Done") { withAnimation { editMode = .inactive } }
                } else {
                    Menu {
                        Picker(selection: $restSeconds) {
                            Text("Off").tag(0)
                            ForEach([30, 45, 60, 90, 120, 180], id: \.self) { seconds in
                                Text(seconds < 120 ? "\(seconds) seconds" : "\(seconds / 60) minutes").tag(seconds)
                            }
                        } label: {
                            Label("Rest timer", systemImage: "timer")
                            Text(restSeconds == 0 ? "Off" : restSeconds < 120 ? "\(restSeconds) sec" : "\(restSeconds / 60) min")
                        }
                        .pickerStyle(.menu)
                        Button("Rename workout", systemImage: "pencil") { renaming = true }
                        Button("Reorder exercises", systemImage: "arrow.up.arrow.down") {
                            withAnimation { editMode = .active }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $addingExercise) { ExerciseSheet(day: day) }
        .sheet(item: $editingExercise) { ExerciseSheet(day: day, editing: $0) }
        .sheet(isPresented: $bumping) { NextTimeSheet(day: day) }
        .sheet(isPresented: $renaming) { WorkoutDaySheet(editing: day) }
    }

    /// After a set: rest before the next set, or before the next exercise.
    /// No rest once every exercise is done.
    private func startRest(after exercise: Exercise) {
        guard restSeconds > 0 else { return }
        let next: String
        if !exercise.isDoneToday {
            next = "Set \(exercise.setsDoneToday + 1) of \(exercise.sets) · \(exercise.name)"
        } else if let upcoming = nextExercise(after: exercise) {
            next = "Next: \(upcoming.name)"
        } else {
            timer.skip()
            return
        }
        withAnimation(.snappy) {
            timer.begin(seconds: restSeconds, next: next, workout: day.name)
        }
    }

    /// The next exercise not done yet, going down the list and wrapping to the top.
    private func nextExercise(after exercise: Exercise) -> Exercise? {
        let all = exercises
        guard let index = all.firstIndex(of: exercise) else { return nil }
        let order = all[(index + 1)...] + all[..<index]
        return order.first { !$0.isDoneToday }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = exercises
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in reordered.enumerated() { exercise.order = index }
    }
}

/// Set ring, name, "3 × 12 · 80 lbs". Tap the ring after each set; it fills up as you go.
private struct ExerciseRow: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    let onEdit: () -> Void
    let onSetFinished: () -> Void

    private var done: Int { exercise.setsDoneToday }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    if exercise.isDoneToday {
                        exercise.resetSets(in: context)
                    } else {
                        exercise.finishSet(in: context)
                        onSetFinished()
                    }
                }
            } label: {
                SetRing(done: done, total: exercise.sets)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.increase, trigger: done)
            .accessibilityLabel(exercise.isDoneToday
                ? "All sets done. Tap to start over."
                : "Finish set \(done + 1) of \(exercise.sets)")

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .foregroundStyle(exercise.isDoneToday ? Theme.muted : Theme.ink)
                    .strikethrough(exercise.isDoneToday, color: Theme.muted)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if let change = recentChange {
                Text(change)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.forest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.sage, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            if !exercise.isDoneToday {
                Button("Finish all sets", systemImage: "checkmark.circle") {
                    withAnimation { exercise.finishAllSets(in: context) }
                }
            }
            if done > 0 {
                Button("Undo last set", systemImage: "arrow.uturn.backward") {
                    withAnimation { exercise.undoSet(in: context) }
                }
            }
            Button("Edit", systemImage: "pencil", action: onEdit)
        }
    }

    /// "3 × 12 · 80 lbs · 1 of 3 sets" while you're partway through.
    private var detail: String {
        guard done > 0, !exercise.isDoneToday else { return exercise.planLine }
        return "\(exercise.planLine) · \(done) of \(exercise.sets) sets"
    }

    /// "+5" when the weight is up since the last time you did it.
    private var recentChange: String? {
        guard let weight = exercise.weight,
              let last = exercise.sortedLogs.first(where: { !Calendar.current.isDateInToday($0.date) }),
              let before = last.weight, weight > before else { return nil }
        return "+\((weight - before).formatted(.number.precision(.fractionLength(0...1))))"
    }
}

/// A circle that fills a slice per set and turns into a check when all are done.
private struct SetRing: View {
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            if done >= total {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.forest)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .stroke(Theme.muted.opacity(0.4), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(done) / CGFloat(max(total, 1)))
                    .stroke(Theme.forest, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done > 0 {
                    Text("\(done)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.forest)
                }
            }
        }
        .frame(width: 26, height: 26)
        .padding(2)
    }
}

// MARK: After a workout

/// "Up the weights for next time?" — one row per weighted exercise, +5 by default.
struct NextTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: WorkoutDay
    @State private var bumps: [PersistentIdentifier: Double] = [:]

    /// Only exercises you did today; skipped ones keep their weight.
    private var weighted: [Exercise] { day.sortedExercises.filter { $0.weight != nil && $0.isDoneToday } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(weighted) { exercise in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(exercise.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(nextWeight(exercise))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.forest)
                                    .contentTransition(.numericText())
                            }
                            Picker("Change", selection: binding(for: exercise)) {
                                Text("Same").tag(0.0)
                                Text("+5").tag(5.0)
                                Text("+10").tag(10.0)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Up the weights for next time?")
                } footer: {
                    Text("You can always change a weight by tapping the exercise.")
                }
            }
            .tint(Theme.forest)
            .navigationTitle("Nice work!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        for exercise in weighted {
                            exercise.weight = (exercise.weight ?? 0) + (bumps[exercise.persistentModelID] ?? 5)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func binding(for exercise: Exercise) -> Binding<Double> {
        Binding(
            get: { bumps[exercise.persistentModelID] ?? 5 },
            set: { value in withAnimation { bumps[exercise.persistentModelID] = value } }
        )
    }

    /// "80 → 85 lbs"
    private func nextWeight(_ exercise: Exercise) -> String {
        let now = exercise.weight ?? 0
        let bump = bumps[exercise.persistentModelID] ?? 5
        let nowText = now.formatted(.number.precision(.fractionLength(0...1)))
        return bump == 0 ? Exercise.pounds(now) : "\(nowText) → \(Exercise.pounds(now + bump))"
    }
}

// MARK: Adding and editing

/// Add an exercise, or edit one (with a chart of your weights over time).
struct ExerciseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let day: WorkoutDay
    private let editing: Exercise?

    @State private var name: String
    @State private var usesWeight: Bool
    @State private var weight: Double
    @State private var sets: Int
    @State private var reps: Int
    @State private var isTimed: Bool

    init(day: WorkoutDay, editing exercise: Exercise? = nil) {
        self.day = day
        editing = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _usesWeight = State(initialValue: exercise.map { $0.weight != nil } ?? true)
        _weight = State(initialValue: exercise?.weight ?? 20)
        _sets = State(initialValue: exercise?.sets ?? 3)
        _reps = State(initialValue: exercise?.reps ?? 10)
        _isTimed = State(initialValue: exercise?.isTimed ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise, e.g. Leg Press", text: $name)
                }

                Section {
                    Toggle("Uses weight", isOn: $usesWeight.animation())
                    if usesWeight {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("0", value: $weight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("lbs").foregroundStyle(Theme.muted)
                        }
                        HStack(spacing: 10) {
                            ForEach([-5.0, 5.0, 10.0], id: \.self) { step in
                                Button(step > 0 ? "+\(Int(step))" : "\(Int(step))") {
                                    withAnimation { weight = max(0, weight + step) }
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.forest)
                            }
                        }
                    }
                }

                Section {
                    Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                    Stepper("\(isTimed ? "Seconds" : "Reps"): \(reps)", value: $reps,
                            in: 1...600, step: isTimed ? 5 : 1)
                    Toggle("Timed (seconds instead of reps)", isOn: $isTimed)
                }

                if let editing, !editing.sortedLogs.isEmpty {
                    historySection(editing)
                }

                if let editing {
                    Section {
                        Button("Delete exercise", role: .destructive) {
                            context.delete(editing)
                            dismiss()
                        }
                    }
                }
            }
            .tint(Theme.forest)
            .navigationTitle(editing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    /// A line chart of the weight each time, plus the list of past workouts.
    private func historySection(_ exercise: Exercise) -> some View {
        let logs = exercise.sortedLogs
        let weighted = logs.filter { $0.weight != nil }.reversed()
        return Section("History") {
            if weighted.count >= 2 {
                Chart(Array(weighted)) { log in
                    LineMark(x: .value("Date", log.date, unit: .day), y: .value("Weight", log.weight ?? 0))
                        .foregroundStyle(Theme.forest)
                    PointMark(x: .value("Date", log.date, unit: .day), y: .value("Weight", log.weight ?? 0))
                        .foregroundStyle(Theme.forest)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
                .padding(.vertical, 6)
            }
            ForEach(logs.prefix(8)) { log in
                HStack {
                    Text(log.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    Spacer()
                    Text([log.weight.map(Exercise.pounds), "\(log.sets) × \(log.reps)"]
                            .compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(Theme.muted)
                }
                .font(.subheadline)
            }
        }
    }

    private func save() {
        let exercise = editing ?? Exercise(name: "", order: day.exerciseCount)
        exercise.name = name.trimmingCharacters(in: .whitespaces)
        exercise.weight = usesWeight ? weight : nil
        exercise.sets = sets
        exercise.reps = reps
        exercise.isTimed = isTimed
        if editing == nil {
            context.insert(exercise)
            exercise.day = day
        }
        dismiss()
    }
}

/// Name a new workout day, or rename one.
struct WorkoutDaySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let editing: WorkoutDay?
    private let order: Int
    @State private var name: String

    init(editing day: WorkoutDay? = nil, order: Int = 0) {
        editing = day
        self.order = order
        _name = State(initialValue: day?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("e.g. Leg x Glutes Day", text: $name)
            }
            .navigationTitle(editing == nil ? "New workout day" : "Rename workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if let editing {
                            editing.name = trimmed
                            editing.icon = WorkoutDay.icon(for: trimmed)
                        } else {
                            context.insert(WorkoutDay(name: trimmed, icon: WorkoutDay.icon(for: trimmed), order: order))
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tint(Theme.forest)
        }
        .presentationDetents([.medium])
    }
}

/// Paste your routine from the Notes app; shows what it found before adding it.
struct ImportRoutineSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let existingCount: Int
    @State private var text = ""

    private var parsed: [RoutineParser.Day] { RoutineParser.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first }
                    }
                    .tint(Theme.forest)
                    TextEditor(text: $text)
                        .frame(height: 180)   // scrolls inside, so what it found stays in view
                        .font(.callout)
                } header: {
                    Text("Your routine")
                } footer: {
                    Text("In Notes, select all of your routine and tap Copy, then tap Paste here. Or type it in.")
                }

                if !parsed.isEmpty {
                    Section("Found \(parsed.count) workout\(parsed.count == 1 ? "" : "s")") {
                        ForEach(Array(parsed.enumerated()), id: \.offset) { _, day in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(day.name, systemImage: WorkoutDay.icon(for: day.name))
                                    .font(.headline)
                                    .foregroundStyle(Theme.ink)
                                Text(day.exercises.map(\.name).joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else if !text.isEmpty {
                    Section {
                        Text("Couldn't find any exercises. Each one needs a number (like \"1.\") or sets × reps (like \"3x12\").")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .tint(Theme.forest)
            .navigationTitle("Paste from Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Gym.importDays(parsed, after: existingCount, into: context)
                        dismiss()
                    }
                    .disabled(parsed.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}
