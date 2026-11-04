import SwiftUI
import SwiftData

/// The round magnifying-glass button in each tab's header. Opens search.
struct SearchButton: View {
    @Environment(CalendarStore.self) private var calendarStore
    var size: CGFloat = 50
    @State private var searching = false

    var body: some View {
        Button { searching = true } label: {
            Image(systemName: "magnifyingglass")
                .font(size < 50 ? .body.weight(.medium) : .title3.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .sheet(isPresented: $searching) {
            SearchSheet().environment(calendarStore)
        }
    }
}

/// Search everything at once: tasks, list items, lists, the Library and calendar events.
struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarStore.self) private var calendarStore

    @Query(sort: \TaskItem.createdAt) private var allItems: [TaskItem]
    @Query(sort: \TaskList.createdAt) private var lists: [TaskList]
    @Query(sort: \LibraryItem.title) private var library: [LibraryItem]

    @State private var query = ""
    @State private var searchActive = true          // opens with the keyboard up
    @State private var events: [CalendarEvent] = [] // loaded once when search opens
    @State private var editingEvent: CalendarEvent?
    @State private var editingLibraryItem: LibraryItem?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// True if any of the texts contains the search words (ignores case and accents).
    private func matches(_ texts: String...) -> Bool {
        texts.contains { $0.localizedStandardContains(trimmed) }
    }

    private var taskResults: [TaskItem] {
        allItems.filter { $0.list == nil && matches($0.title, $0.notes, $0.location, $0.locationDetail) }
    }
    private var listItemResults: [TaskItem] {
        allItems.filter { $0.list != nil && matches($0.title, $0.section, $0.quantity) }
    }
    private var listResults: [TaskList] {
        lists.filter { matches($0.name) }
    }
    private var libraryResults: [LibraryItem] {
        library.filter { matches($0.title, $0.creator, $0.genre, $0.notes) }
    }
    private var eventResults: [CalendarEvent] {
        events.filter { matches($0.title, $0.location, $0.notes) }
    }
    private var hasResults: Bool {
        !(taskResults.isEmpty && listItemResults.isEmpty && listResults.isEmpty
          && libraryResults.isEmpty && eventResults.isEmpty)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    ContentUnavailableView(
                        "Search everything",
                        systemImage: "magnifyingglass",
                        description: Text("Tasks, list items, books, shows, restaurants and calendar events.")
                    )
                    .listRowBackground(Color.clear)
                } else if !hasResults {
                    ContentUnavailableView.search(text: trimmed)
                        .listRowBackground(Color.clear)
                } else {
                    resultSections
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $searchActive,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: TaskItem.self) { TaskDetailView(task: $0) }
            .navigationDestination(for: TaskList.self) { ListDetailView(list: $0) }
            .sheet(item: $editingEvent) { EventEditSheet(editing: $0).environment(calendarStore) }
            .sheet(item: $editingLibraryItem) { LibraryItemSheet(editing: $0).environment(calendarStore) }
            // Events from 3 months back to a year ahead.
            .onAppear {
                let start = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
                let end = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
                events = calendarStore.events(from: start, to: end)
            }
        }
        .tint(Theme.forest)
    }

    @ViewBuilder
    private var resultSections: some View {
        if !taskResults.isEmpty {
            Section("Tasks") {
                ForEach(taskResults) { task in
                    NavigationLink(value: task) {
                        ResultRow(icon: task.icon.isEmpty ? "checkmark.circle" : task.icon,
                                  title: task.title,
                                  subtitle: task.detailLine,
                                  isDone: task.isDone)
                    }
                }
            }
        }
        if !listItemResults.isEmpty {
            Section("List items") {
                ForEach(listItemResults) { item in
                    if let list = item.list {
                        NavigationLink(value: list) {
                            ResultRow(icon: list.icon, title: item.title,
                                      subtitle: [list.name, item.quantity].filter { !$0.isEmpty }
                                          .joined(separator: " · "),
                                      isDone: item.isDone)
                        }
                    }
                }
            }
        }
        if !listResults.isEmpty {
            Section("Lists") {
                ForEach(listResults) { list in
                    NavigationLink(value: list) {
                        ResultRow(icon: list.icon, title: list.name,
                                  subtitle: "\(list.remainingCount) \(list.countPhrase)")
                    }
                }
            }
        }
        if !libraryResults.isEmpty {
            Section("Library") {
                ForEach(libraryResults) { item in
                    Button { editingLibraryItem = item } label: {
                        ResultRow(icon: item.kindValue.emptyIcon, title: item.title,
                                  subtitle: [item.statusValue.label(for: item.kindValue), item.detailLine]
                                      .filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                }
            }
        }
        if !eventResults.isEmpty {
            Section("Calendar") {
                ForEach(eventResults) { event in
                    Button { if event.canEdit { editingEvent = event } } label: {
                        ResultRow(icon: "calendar", title: event.title,
                                  subtitle: "\(event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(event.isAllDay ? "All day" : event.start.timeText)")
                    }
                }
            }
        }
    }
}

/// One search result: an icon, a title and a gray line underneath.
private struct ResultRow: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var isDone = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.forest)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(isDone ? Theme.muted : Theme.ink)
                    .strikethrough(isDone)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
