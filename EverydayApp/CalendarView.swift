import SwiftUI
import SwiftData

/// One row on the day timeline: a calendar event or a task with a due time.
enum AgendaEntry: Identifiable {
    case event(CalendarEvent)
    case task(TaskItem)

    var id: AnyHashable {
        switch self {
        case .event(let event): AnyHashable(event.id)
        case .task(let task): AnyHashable(task.persistentModelID)
        }
    }

    var date: Date {
        switch self {
        case .event(let event): event.start
        case .task(let task): task.dueDate ?? .distantFuture
        }
    }
}

struct CalendarView: View {
    @Environment(CalendarStore.self) private var calendarStore
    @Query(sort: \TaskItem.createdAt) private var allItems: [TaskItem]
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var newKind: NewTaskKind?
    @State private var showingNewEvent = false
    @State private var editingEvent: CalendarEvent?
    private let cal = Calendar.mondayFirst

    private var weekDays: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// One EventKit fetch for the whole visible week.
    private var weekEvents: [CalendarEvent] {
        guard let first = weekDays.first, let last = weekDays.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return [] }
        // Skip events the app made for tasks: those tasks already show on the timeline.
        let taskEventIDs = Set(allItems.map(\.calendarEventID).filter { !$0.isEmpty })
        return calendarStore.events(from: first, to: end)
            .filter { !taskEventIDs.contains($0.eventID) }
    }

    private func events(on day: Date, from pool: [CalendarEvent]) -> [CalendarEvent] {
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return pool.filter { $0.start < end && $0.end > start }
    }

    private func tasks(on day: Date) -> [TaskItem] {
        allItems.filter { item in
            guard let due = item.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }
    }

    var body: some View {
        let pool = weekEvents
        let dayEvents = events(on: selectedDay, from: pool)
        let allDay = dayEvents.filter(\.isAllDay)
        let entries = (dayEvents.filter { !$0.isAllDay }.map(AgendaEntry.event)
                       + tasks(on: selectedDay).map(AgendaEntry.task))
            .sorted { $0.date < $1.date }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Calendar")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        SearchButton()
                        AddMenu(
                            onTask: { newKind = .task },
                            onReminder: { newKind = .reminder },
                            onEvent: { showingNewEvent = true }
                        )
                    }

                    CalendarStatusCard()

                    HStack {
                        Text(selectedDay.formatted(.dateTime.month(.wide).year()))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        // Back to today from any week. Hidden when you're already on today.
                        if !cal.isDateInToday(selectedDay) {
                            Button {
                                withAnimation(.snappy) { selectedDay = cal.startOfDay(for: .now) }
                            } label: {
                                Text("Today")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.forest)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.sage, in: Capsule())
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .accessibilityHint("Shows today's plans")
                        }
                        Button { shiftWeek(-1) } label: {
                            Image(systemName: "chevron.left").foregroundStyle(Theme.ink).padding(8)
                        }
                        Button { shiftWeek(1) } label: {
                            Image(systemName: "chevron.right").foregroundStyle(Theme.ink).padding(8)
                        }
                    }
                    .buttonStyle(.plain)

                    weekStrip(pool: pool)

                    if calendarStore.access == .granted {
                        HStack(spacing: 16) {
                            legend("Work", Theme.forest)
                            legend("Personal", Theme.peachInk)
                            legend("Reminders", Theme.lavenderInk)
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(entries.count + allDay.count) planned")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.forest)
                    }

                    if !allDay.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(allDay) { event in
                                EditableEvent(event: event, onEdit: { editingEvent = $0 }) {
                                    AllDayChip(event: event)
                                }
                            }
                        }
                    }

                    if entries.isEmpty && allDay.isEmpty {
                        Text("Nothing planned. Tap + to add something.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(entries) { entry in
                                HStack(alignment: .top, spacing: 14) {
                                    TimeLabel(date: entry.date)
                                    switch entry {
                                    case .event(let event):
                                        EditableEvent(event: event, onEdit: { editingEvent = $0 }) {
                                            EventCard(event: event)
                                        }
                                    case .task(let task):
                                        NavigationLink(value: task) { TaskTimelineCard(task: task) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    Label("A little breathing room between your plans.", systemImage: "sun.max")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.background)
            // Pull down to fetch the latest events from Google, Outlook and iCloud.
            .refreshable { await calendarStore.refreshAndWait() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TaskItem.self) { TaskDetailView(task: $0) }
            .navigationDestination(for: TaskList.self) { ListDetailView(list: $0) }
            .sheet(item: $newKind) { NewTaskSheet(kind: $0, defaultDate: selectedDay) }
            .sheet(isPresented: $showingNewEvent) {
                EventEditSheet(defaultDate: selectedDay).environment(calendarStore)
            }
            .sheet(item: $editingEvent) { EventEditSheet(editing: $0).environment(calendarStore) }
        }
    }

    private func weekStrip(pool: [CalendarEvent]) -> some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
                let hasItems = !events(on: day, from: pool).isEmpty || !tasks(on: day).isEmpty
                let isToday = cal.isDateInToday(day)

                Button {
                    withAnimation(.snappy) { selectedDay = day }
                } label: {
                    VStack(spacing: 8) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.medium))
                        Text(day.formatted(.dateTime.day()))
                            .font(.title3.weight(.medium))
                        Circle()
                            .fill(hasItems ? (isSelected ? Theme.onPrimary : Theme.forest) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(isSelected ? Theme.onPrimary : (isToday ? Theme.forest : Theme.ink))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if isSelected { Capsule().fill(Theme.forest) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func shiftWeek(_ direction: Int) {
        withAnimation(.snappy) {
            selectedDay = cal.date(byAdding: .day, value: 7 * direction, to: selectedDay) ?? selectedDay
        }
    }
}
