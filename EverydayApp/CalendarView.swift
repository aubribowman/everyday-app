import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(sort: \TaskItem.createdAt) private var allItems: [TaskItem]
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showingNewTask = false
    private let cal = Calendar.mondayFirst

    private var weekDays: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func items(on day: Date) -> [TaskItem] {
        allItems.filter { item in
            guard let due = item.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }.byDue
    }

    private var dayItems: [TaskItem] { items(on: selectedDay) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Calendar")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        AddButton { showingNewTask = true }
                    }

                    connectCard

                    HStack {
                        Text(selectedDay.formatted(.dateTime.month(.wide).year()))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Button { shiftWeek(-1) } label: {
                            Image(systemName: "chevron.left").foregroundStyle(Theme.ink).padding(8)
                        }
                        Button { shiftWeek(1) } label: {
                            Image(systemName: "chevron.right").foregroundStyle(Theme.ink).padding(8)
                        }
                    }
                    .buttonStyle(.plain)

                    weekStrip

                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(dayItems.count) planned")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.forest)
                    }

                    if dayItems.isEmpty {
                        Text("Nothing planned. Tap + to add something.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(dayItems) { TimelineRow(task: $0) }
                        }
                    }

                    Label("A little breathing room between your plans.", systemImage: "sun.max")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TaskItem.self) { TaskDetailView(task: $0) }
            .navigationDestination(for: TaskList.self) { ListDetailView(list: $0) }
            .sheet(isPresented: $showingNewTask) { NewTaskSheet(defaultDate: selectedDay) }
        }
    }

    private var connectCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .foregroundStyle(Theme.forest)
                .frame(width: 40, height: 40)
                .background(Theme.sage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Not connected yet")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "circle.dashed").foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
                let hasItems = !items(on: day).isEmpty
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
                            .fill(hasItems ? (isSelected ? Color.white : Theme.forest) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Theme.forest : Theme.ink))
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

    private func shiftWeek(_ direction: Int) {
        withAnimation(.snappy) {
            selectedDay = cal.date(byAdding: .day, value: 7 * direction, to: selectedDay) ?? selectedDay
        }
    }
}

struct TimelineRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.dueDate?.clock ?? "")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(task.dueDate?.meridiem ?? "")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: 50, alignment: .leading)
            .padding(.top, 16)

            NavigationLink(value: task) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .strikethrough(task.isDone)
                    Text(task.timeRangeLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.lavenderInk)
                    Label("Reminder", systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(Theme.lavenderInk)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.lavenderInk).frame(width: 3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .opacity(task.isDone ? 0.5 : 1)
    }
}
