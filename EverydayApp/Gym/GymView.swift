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
    @State private var editingSchedule = false
    @AppStorage(Gym.Schedule.daysKey) private var gymDays = ""
    @AppStorage(Gym.Schedule.remindKey) private var remind = false
    @AppStorage(Gym.Schedule.minutesKey) private var remindMinutes = 7 * 60

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
                    weekCard
                    let highlights = Gym.highlights(in: days)
                    if !highlights.isEmpty { progressCard(highlights) }

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
        .sheet(isPresented: $editingSchedule) { GymScheduleSheet() }
    }

    /// Your gym days and what's coming up: "Mon, Wed, Fri · Next: Wed, Arm x Shoulder Day".
    private var weekCard: some View {
        let weekdays = Gym.Schedule.parse(gymDays)
        let upcoming = Gym.plan(days, weekdays: weekdays, count: 1).first
        return Button { editingSchedule = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Theme.forest)
                    .frame(width: 44, height: 44)
                    .background(Theme.sage, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    if weekdays.isEmpty {
                        Text("Pick your gym days")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Get a reminder with the workout that's up next.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text(Gym.Schedule.summary(weekdays))
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        if let upcoming {
                            Text("\(dayLabel(upcoming.date)): \(upcoming.day.name)")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        if remind {
                            Label("Reminder at \(minutesText(remindMinutes))", systemImage: "bell")
                                .font(.caption)
                                .foregroundStyle(Theme.forest)
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
    }

    /// New personal bests and how far you've come.
    private func progressCard(_ highlights: [Gym.Highlight]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROGRESS")
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.forest)
            ForEach(highlights) { highlight in
                HStack(spacing: 12) {
                    Image(systemName: highlight.kind == .best ? "trophy.fill" : "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(highlight.kind == .best ? Theme.lemonInk : Theme.forest)
                        .frame(width: 32, height: 32)
                        .background(highlight.kind == .best ? Theme.lemon : Theme.sage, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(highlight.exercise)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(highlight.detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
    }

    /// "Today", "Tomorrow" or "Wed".
    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
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
    @State private var healthNote: String?     // "Saved to Apple Health" after finishing

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
                                onSetFinished: {
                                    noteStart()
                                    startRest(after: exercise)
                                })
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(exercises[index]) }
                }
                .onMove(perform: move)

                Button("Add exercise", systemImage: "plus") { addingExercise = true }
                    .foregroundStyle(Theme.forest)
            } footer: {
                Text("Tap the next set when you finish it to start your rest. Got fewer reps? Tap the set again to change it. Tap a name to edit it or see your history.")
            }

            if day.isFinishedToday {
                Section {
                    VStack(spacing: 6) {
                        Label("Finished today. Nice work!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.forest)
                        if let healthNote {
                            Label(healthNote, systemImage: "heart.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else if doneCount > 0 {
                Section {
                    Button {
                        finish()
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

    /// Remembers when today's workout began: your first set.
    private func noteStart() {
        if day.startedAt.map(Calendar.current.isDateInToday) != true { day.startedAt = .now }
    }

    private func finish() {
        let end = Date.now
        day.lastCompletedAt = end
        timer.skip()
        if exercises.contains(where: { $0.weight != nil && $0.isDoneToday }) { bumping = true }

        guard GymHealth.isOn, GymHealth.isAvailable else { return }
        let started = day.startedAt.flatMap { Calendar.current.isDateInToday($0) ? $0 : nil }
        let times = GymHealth.times(startedAt: started, finishedAt: end)
        Task {
            do {
                try await GymHealth.save(start: times.start, end: times.end)
                let minutes = Int(times.end.timeIntervalSince(times.start) / 60)
                healthNote = "Saved to Apple Health (\(minutes) min)"
            } catch {
                healthNote = "Couldn't save to Apple Health. Check Settings › Health › Data Access & Devices."
            }
        }
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

/// Name, "3 × 12 · 80 lbs", and a button for each set. Tap the next set when you finish it;
/// tap a finished set to say you got fewer reps.
private struct ExerciseRow: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    let onEdit: () -> Void
    let onSetFinished: () -> Void

    private var done: Int { exercise.setsDoneToday }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .foregroundStyle(exercise.isDoneToday ? Theme.muted : Theme.ink)
                        .strikethrough(exercise.isDoneToday, color: Theme.muted)
                    Text(exercise.planLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)

                SetButtons(exercise: exercise, onSetFinished: onSetFinished)
            }
            Spacer(minLength: 8)
            if exercise.isNewBestToday {
                badge("Best!", systemImage: "trophy.fill")
            } else if let change = recentChange {
                badge(change, systemImage: nil)
            }
        }
        .padding(.vertical, 4)
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

    /// "+5" when the weight is up since the last time you did it.
    private var recentChange: String? {
        guard let weight = exercise.weight,
              let last = exercise.sortedLogs.first(where: { !Calendar.current.isDateInToday($0.date) }),
              let before = last.weight, weight > before else { return nil }
        return "+\((weight - before).formatted(.number.precision(.fractionLength(0...1))))"
    }

    private func badge(_ text: String, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.forest)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.sage, in: Capsule())
    }
}

/// One button per set: empty until you finish it, then the reps you got.
/// A set that came up short is shown in a warmer color.
private struct SetButtons: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    let onSetFinished: () -> Void

    var body: some View {
        let got = exercise.repsToday
        HStack(spacing: 6) {
            ForEach(0..<exercise.sets, id: \.self) { index in
                if index < got.count {
                    finishedSet(index, reps: got[index])
                } else {
                    Button {
                        withAnimation(.snappy) {
                            exercise.finishSet(in: context)
                            onSetFinished()
                        }
                    } label: {
                        pill(index == got.count ? amount(exercise.reps) : "", filled: false, short: false)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Finish set \(got.count + 1) of \(exercise.sets)")
                }
            }
        }
        .sensoryFeedback(.increase, trigger: got.count)
    }

    /// Tap to change the reps, or to take the set back.
    private func finishedSet(_ index: Int, reps: Int) -> some View {
        Menu {
            Picker("Set \(index + 1)", selection: Binding(
                get: { reps },
                set: { value in withAnimation(.snappy) { exercise.changeReps(ofSet: index, to: value) } }
            )) {
                ForEach(choices, id: \.self) { value in
                    Text(value == exercise.reps ? "\(amount(value)) (all of them)" : amount(value)).tag(value)
                }
            }
            .pickerStyle(.inline)
            if index == exercise.setsDoneToday - 1 {
                Button("Take back this set", systemImage: "arrow.uturn.backward") {
                    withAnimation(.snappy) { exercise.undoSet(in: context) }
                }
            }
        } label: {
            pill(amount(reps), filled: true, short: reps < exercise.reps)
        }
        .accessibilityLabel("Set \(index + 1): \(amount(reps)). Tap to change.")
    }

    /// What you might have got: a few over the goal down to 1 (or 5-second steps when timed).
    private var choices: [Int] {
        let goal = exercise.reps
        if exercise.isTimed {
            return Array(stride(from: goal + 15, through: 5, by: -5)).filter { $0 > 0 }
        }
        return Array((max(1, goal - 29)...(goal + 3)).reversed())
    }

    private func amount(_ value: Int) -> String { exercise.isTimed ? "\(value)s" : "\(value)" }

    private func pill(_ text: String, filled: Bool, short: Bool) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(filled ? (short ? Theme.peachInk : Theme.onPrimary) : Theme.muted)
            .frame(minWidth: 44, minHeight: 30)
            .padding(.horizontal, 4)
            .background {
                if filled {
                    Capsule().fill(short ? Theme.peach : Theme.forest)
                } else {
                    Capsule().strokeBorder(Theme.muted.opacity(0.45), lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
    }
}

// MARK: After a workout

/// "Up the weights for next time?" — one row per weighted exercise. +5 when you got every rep,
/// the same weight when a set came up short.
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
                            if exercise.missedRepsToday {
                                Text("Got \(exercise.repsToday.map(String.init).joined(separator: " · ")) of \(exercise.reps). Stay here until you get them all.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.peachInk)
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
                            exercise.weight = (exercise.weight ?? 0) + bump(for: exercise)
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
            get: { bump(for: exercise) },
            set: { value in withAnimation { bumps[exercise.persistentModelID] = value } }
        )
    }

    /// What you picked, or the suggestion: +5 only when you got every rep.
    private func bump(for exercise: Exercise) -> Double {
        bumps[exercise.persistentModelID] ?? (exercise.missedRepsToday ? 0 : 5)
    }

    /// "80 → 85 lbs"
    private func nextWeight(_ exercise: Exercise) -> String {
        let now = exercise.weight ?? 0
        let bump = bump(for: exercise)
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
            if let best = exercise.personalBest, let weight = best.weight {
                Label("Best: \(Exercise.pounds(weight)) on \(Gym.shortDate(best.date))", systemImage: "trophy.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.forest)
            }
            ForEach(logs.prefix(8)) { log in
                HStack {
                    Text(log.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    Spacer()
                    Text([log.weight.map(Exercise.pounds), log.repsLine]
                            .compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(log.hitAllReps ? Theme.muted : Theme.peachInk)
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

/// "7:00 AM" for 420 minutes after midnight.
func minutesText(_ minutes: Int) -> String {
    let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    return date.formatted(date: .omitted, time: .shortened)
}

// MARK: Schedule and Apple Health

/// Pick your gym days, a reminder time, and whether workouts go to Apple Health.
struct GymScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutDay.order) private var days: [WorkoutDay]
    @AppStorage(Gym.Schedule.daysKey) private var gymDays = ""
    @AppStorage(Gym.Schedule.remindKey) private var remind = false
    @AppStorage(Gym.Schedule.minutesKey) private var remindMinutes = 7 * 60
    @AppStorage(GymHealth.settingKey) private var savesToHealth = false
    @State private var healthDenied = false

    private var weekdays: Set<Int> { Gym.Schedule.parse(gymDays) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                            dayButton(weekday)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text("Gym days")
                } footer: {
                    Text("Your workouts take turns on these days, starting with the one up next.")
                }

                Section {
                    Toggle("Remind me on gym days", isOn: $remind)
                        .disabled(weekdays.isEmpty)
                    if remind {
                        DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    if let first = Gym.plan(days, weekdays: weekdays, count: 1).first, remind {
                        Text("For example: \u{201C}\(first.day.name) today\u{201D} at \(minutesText(remindMinutes)). No reminder once you've finished a workout that day.")
                    }
                }

                if GymHealth.isAvailable {
                    Section {
                        Toggle("Save workouts to Apple Health", isOn: healthToggle)
                    } footer: {
                        if healthDenied {
                            Text("Everyday isn't allowed to save workouts. Turn it on in Settings › Health › Data Access & Devices › EverydayApp.")
                        } else {
                            Text("When you tap Finish workout, it's saved as Strength Training with an estimate of the calories you burned. It shows in the Fitness app and counts toward your Move ring.")
                        }
                    }
                }

                if !upcoming.isEmpty {
                    Section("Coming up") {
                        ForEach(upcoming, id: \.date) { item in
                            HStack {
                                Text(item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 96, alignment: .leading)
                                Text(item.day.name)
                                    .foregroundStyle(Theme.ink)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .tint(Theme.forest)
            .navigationTitle("Schedule & Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: gymDays) { if weekdays.isEmpty { remind = false } }
        }
        .presentationDetents([.large])
    }

    private var upcoming: [(date: Date, day: WorkoutDay)] { Gym.plan(days, weekdays: weekdays, count: 5) }

    private func dayButton(_ weekday: Int) -> some View {
        let on = weekdays.contains(weekday)
        let name = Calendar.current.veryShortWeekdaySymbols[weekday - 1]
        return Button {
            var updated = weekdays
            if on { updated.remove(weekday) } else { updated.insert(weekday) }
            withAnimation(.snappy) { gymDays = Gym.Schedule.text(updated) }
        } label: {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Theme.onPrimary : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(on ? Theme.forest : Theme.sage.opacity(0.6), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: remindMinutes / 60, minute: remindMinutes % 60,
                                         second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                remindMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// Turning it on asks Health for permission first.
    private var healthToggle: Binding<Bool> {
        Binding(
            get: { savesToHealth },
            set: { on in
                guard on else { savesToHealth = false; return }
                Task {
                    let allowed = await GymHealth.requestAccess()
                    savesToHealth = allowed
                    healthDenied = !allowed
                }
            }
        )
    }
}
