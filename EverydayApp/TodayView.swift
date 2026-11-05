import SwiftUI
import SwiftData

struct TodayView: View {
    @Binding var tab: AppTab
    @Environment(CalendarStore.self) private var calendarStore
    @Query(sort: \TaskItem.createdAt) private var allItems: [TaskItem]
    // Newest change first, so the book you started most recently is the one shown.
    @Query(sort: \LibraryItem.statusChangedAt, order: .reverse) private var library: [LibraryItem]
    @AppStorage("userName") private var userName = "Aubri Bowman"
    @State private var newKind: NewTaskKind?       // task or reminder being added
    @State private var showingNewEvent = false
    @State private var showingSettings = false
    @State private var editingEvent: CalendarEvent?
    @State private var openLibraryItem: LibraryItem?
    @Query(sort: \WorkoutDay.order) private var workoutDays: [WorkoutDay]
    @State private var showingGym = false

    /// Today's finished workout if there is one, otherwise the next one in the rotation.
    private var workoutToShow: WorkoutDay? {
        workoutDays.first(where: \.isFinishedToday) ?? Gym.nextDay(in: workoutDays)
    }

    /// The book you're reading and the show you're watching (the latest of each).
    private var upNext: [LibraryItem] {
        [LibraryKind.book, .show].compactMap { kind in
            library.first { $0.kindValue == kind && $0.statusValue == .active }
        }
    }

    private var todayTasks: [TaskItem] {
        allItems.filter { item in
            item.list == nil && (item.dueDate.map { Calendar.current.isDateInToday($0) } ?? false)
        }.byDue
    }
    private var openCount: Int { todayTasks.filter { !$0.isDone }.count }
    private var doneCount: Int { todayTasks.count - openCount }

    // Skips events the app made for tasks, since those tasks are already listed.
    private var todayEvents: [CalendarEvent] {
        let taskEventIDs = Set(allItems.map(\.calendarEventID).filter { !$0.isEmpty })
        return calendarStore.events(on: .now).filter { !taskEventIDs.contains($0.eventID) }
    }
    private var upcomingEvents: [CalendarEvent] {
        Array(todayEvents.filter { !$0.isAllDay && $0.end > .now }.prefix(3))
    }

    private var firstName: String {
        userName.split(separator: " ").first.map(String.init) ?? userName
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var summaryLine: String {
        let things = "\(openCount) \(openCount == 1 ? "thing" : "things") to do"
        guard calendarStore.access == .granted else { return things }
        let count = todayEvents.count
        return "\(count) \(count == 1 ? "event" : "events") · \(things)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    hero
                    comingUp
                    onYourList
                    if let workoutToShow { workoutCard(workoutToShow) }
                    if !upNext.isEmpty { upNextCard }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            // Pull down to fetch the latest events from Google, Outlook and iCloud.
            .refreshable { await calendarStore.refreshAndWait() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TaskItem.self) { TaskDetailView(task: $0) }
            .navigationDestination(for: TaskList.self) { ListDetailView(list: $0) }
            .gymDestinations()
            .navigationDestination(isPresented: $showingGym) { GymView() }
            .sheet(item: $newKind) { NewTaskSheet(kind: $0) }
            .sheet(isPresented: $showingNewEvent) { EventEditSheet().environment(calendarStore) }
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
            .sheet(item: $editingEvent) { EventEditSheet(editing: $0).environment(calendarStore) }
            .sheet(item: $openLibraryItem) { LibraryItemSheet(editing: $0).environment(calendarStore) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label(Theme.appName, systemImage: "leaf")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.forest)
                Text("\(greeting), \(firstName)")
                    .font(.largeTitle.weight(.semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            HStack(spacing: 10) {
                SearchButton(size: 44)
                // Tap your picture (or initials) to open Settings.
                Button { showingSettings = true } label: {
                    ProfileAvatar(size: 44)   // your photo, or your initials (see Profile.swift)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .padding(.top, 18)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.forest)
            Text("A little space for today.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(Theme.forest)
            HStack(spacing: 10) {
                ProgressView(value: todayTasks.isEmpty ? 0 : Double(doneCount) / Double(todayTasks.count))
                    .tint(Theme.forest)
                    .frame(width: 110)
                Text("\(doneCount) of \(todayTasks.count) complete")
                    .font(.caption)
                    .foregroundStyle(Theme.forest)
            }
            .padding(.top, 6)
        }
        .padding(.trailing, 70)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(alignment: .topTrailing) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.forest.opacity(0.18))
                .rotationEffect(.degrees(-25))
                .padding(18)
        }
        .background(Theme.sage, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Coming up", action: "View calendar") { tab = .calendar }

            if calendarStore.access != .granted {
                CalendarStatusCard()
            } else if upcomingEvents.isEmpty {
                Text("Nothing else on your calendar today.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 12) {
                    ForEach(upcomingEvents) { event in
                        HStack(alignment: .top, spacing: 14) {
                            TimeLabel(date: event.start)
                            EditableEvent(event: event, onEdit: { editingEvent = $0 }) {
                                EventCard(event: event)
                            }
                        }
                    }
                }
            }
        }
    }

    private var onYourList: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "On your list", action: "See all") { tab = .tasks }
            if todayTasks.isEmpty {
                Text("Nothing scheduled today. Tap + to add a task.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 12)
            } else {
                DividedStack(items: todayTasks) { TaskRow(task: $0) }
            }
        }
    }

    /// Your next workout (or today's, once finished). Tap it to start ticking off exercises.
    private func workoutCard(_ day: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Workout", action: "All workouts") { showingGym = true }
            NavigationLink(value: day) {
                WorkoutDayCard(day: day, isNext: !day.isFinishedToday)
            }
            .buttonStyle(.plain)
        }
    }

    /// "Up next": what you're in the middle of reading or watching. Tap one to open it.
    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Up next", action: "See all") { tab = .library }
            DividedStack(items: upNext) { item in
                Button { openLibraryItem = item } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: item.cover, kind: item.kindValue, width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.statusValue.label(for: item.kindValue).uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.forest)
                            Text(item.title)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            if !item.creator.isEmpty {
                                Text(item.creator)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("One thing at a time. You're doing well.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Spacer()
            // + opens a menu: a task, a reminder (task with a time + notification), or a calendar event.
            AddMenu(
                onTask: { newKind = .task },
                onReminder: { newKind = .reminder },
                onEvent: { showingNewEvent = true }
            )
        }
    }
}
