import SwiftUI
import SwiftData

struct TodayView: View {
    @Binding var tab: AppTab
    @Environment(CalendarStore.self) private var calendarStore
    @Query(sort: \TaskItem.createdAt) private var allItems: [TaskItem]
    @AppStorage("userName") private var userName = "Aubri Bowman"
    @State private var showingNewTask = false

    private var todayTasks: [TaskItem] {
        allItems.filter { item in
            item.list == nil && (item.dueDate.map { Calendar.current.isDateInToday($0) } ?? false)
        }.byDue
    }
    private var openCount: Int { todayTasks.filter { !$0.isDone }.count }
    private var doneCount: Int { todayTasks.count - openCount }

    private var todayEvents: [CalendarEvent] { calendarStore.events(on: .now) }
    private var upcomingEvents: [CalendarEvent] {
        Array(todayEvents.filter { !$0.isAllDay && $0.end > .now }.prefix(3))
    }

    private var firstName: String {
        userName.split(separator: " ").first.map(String.init) ?? userName
    }
    private var initials: String {
        userName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
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
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TaskItem.self) { TaskDetailView(task: $0) }
            .navigationDestination(for: TaskList.self) { ListDetailView(list: $0) }
            .sheet(isPresented: $showingNewTask) { NewTaskSheet() }
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
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.peachInk)
                .frame(width: 44, height: 44)
                .background(Theme.peach, in: Circle())
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
                            EventCard(event: event)
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

    private var footer: some View {
        HStack {
            Text("One thing at a time. You're doing well.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Spacer()
            AddButton { showingNewTask = true }
        }
    }
}
