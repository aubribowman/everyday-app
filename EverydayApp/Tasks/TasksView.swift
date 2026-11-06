// The Tasks tab: every task that isn't on a list, grouped by when it's due.

import SwiftUI
import SwiftData

/// Groups tasks into Overdue, Today, Upcoming, Someday (no date) and Done.
struct TasksView: View {
    @Query(sort: \TaskItem.createdAt) private var allItems: [TaskItem]
    @State private var showingNewTask = false

    private var tasks: [TaskItem] { allItems.filter { $0.list == nil } }
    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }
    private var startOfTomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    private var overdue: [TaskItem] {
        tasks.filter { !$0.isDone && ($0.dueDate.map { $0 < startOfToday } ?? false) }.byDue
    }
    private var today: [TaskItem] {
        tasks.filter { !$0.isDone && ($0.dueDate.map { $0 >= startOfToday && $0 < startOfTomorrow } ?? false) }.byDue
    }
    private var upcoming: [TaskItem] {
        tasks.filter { !$0.isDone && ($0.dueDate.map { $0 >= startOfTomorrow } ?? false) }.byDue
    }
    private var someday: [TaskItem] {
        tasks.filter { !$0.isDone && $0.dueDate == nil }
    }
    private var done: [TaskItem] {
        tasks.filter { $0.isDone }.byDue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Tasks")
                            .font(.display(.largeTitle))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        SearchButton()
                        AddButton { showingNewTask = true }
                    }

                    if tasks.isEmpty {
                        ContentUnavailableView(
                            "No tasks yet",
                            systemImage: "checkmark.circle",
                            description: Text("Tap + to add your first task.")
                        )
                        .padding(.top, 40)
                    }

                    group("Overdue", overdue)
                    group("Today", today)
                    group("Upcoming", upcoming)
                    group("Someday", someday)
                    group("Done", done)
                }
                .padding(20)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TaskItem.self) { TaskDetailView(task: $0) }
            .navigationDestination(for: TaskList.self) { ListDetailView(list: $0) }
            .sheet(isPresented: $showingNewTask) { NewTaskSheet() }
        }
    }

    /// A titled card of task rows. Draws nothing when there are no tasks.
    @ViewBuilder
    private func group(_ title: String, _ items: [TaskItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title)
                DividedStack(items: items) { TaskRow(task: $0) }
                    .padding(.horizontal, 16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
            }
        }
    }
}
