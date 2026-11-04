import WidgetKit
import SwiftUI

// MARK: Timeline

/// One moment the widget can show. iOS redraws it at each entry's `date`,
/// so finished events drop off without the app having to run.
struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        // The widget gallery shows example content if the app hasn't saved anything yet.
        completion(DayEntry(date: .now, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date.now
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))

        // Redraw now, whenever an event ends, and at midnight (when "Tomorrow" becomes today).
        var times = [now, midnight]
        times += (snapshot?.events ?? []).map(\.end).filter { $0 > now && $0 < midnight }
        let entries = Set(times).sorted().map { DayEntry(date: $0, snapshot: snapshot) }

        // After midnight, ask again; the app also refreshes the widget whenever things change.
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

// MARK: Views

struct EverydayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    /// Events that haven't ended yet at this entry's time.
    private var events: [WidgetSnapshot.Event] {
        (entry.snapshot?.events ?? []).filter { $0.end > entry.date }
    }
    private var tasks: [WidgetSnapshot.Task] { entry.snapshot?.tasks ?? [] }
    private var taskCount: Int { entry.snapshot?.openTaskCount ?? 0 }

    var body: some View {
        if entry.snapshot == nil {
            emptyState
        } else {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
    }

    // Small: date, the next event, tasks left.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            dateHeader
            Spacer(minLength: 0)
            if let next = events.first {
                Text(next.title)
                    .font(.headline)
                    .foregroundStyle(WTheme.ink)
                    .lineLimit(2)
                Text(when(next))
                    .font(.caption)
                    .foregroundStyle(WTheme.peachInk)
            } else {
                Text("No more events")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WTheme.muted)
            }
            Spacer(minLength: 0)
            taskCountLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Medium: events on the left, tasks on the right.
    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                dateHeader
                eventList(limit: 2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                taskCountLabel
                taskList(limit: 3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Large: everything, stacked.
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            dateHeader
            sectionTitle("Coming up")
            eventList(limit: 4)
            Divider().overlay(WTheme.sage)
            HStack {
                sectionTitle("On your list")
                Spacer()
                taskCountLabel
            }
            taskList(limit: 5)
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Everyday", systemImage: "leaf")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WTheme.forest)
            Spacer(minLength: 0)
            Text("Open Everyday to see your day here.")
                .font(.subheadline)
                .foregroundStyle(WTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(WTheme.forest)
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.title3.weight(.semibold))
                .foregroundStyle(WTheme.ink)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WTheme.ink)
    }

    private var taskCountLabel: some View {
        Label("\(taskCount) \(taskCount == 1 ? "task" : "tasks") left", systemImage: "checkmark.circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(WTheme.forest)
    }

    @ViewBuilder
    private func eventList(limit: Int) -> some View {
        if events.isEmpty {
            Text("No more events")
                .font(.caption)
                .foregroundStyle(WTheme.muted)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(events.prefix(limit).enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .top, spacing: 6) {
                        Capsule().fill(WTheme.peachInk).frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WTheme.ink)
                                .lineLimit(1)
                            Text(when(event))
                                .font(.caption2)
                                .foregroundStyle(WTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func taskList(limit: Int) -> some View {
        if tasks.isEmpty {
            Text("Nothing left today")
                .font(.caption)
                .foregroundStyle(WTheme.muted)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(tasks.prefix(limit).enumerated()), id: \.offset) { _, task in
                    HStack(spacing: 6) {
                        Image(systemName: task.icon.isEmpty ? "circle" : task.icon)
                            .font(.caption2)
                            .foregroundStyle(WTheme.forest)
                            .frame(width: 14)
                        Text(task.title)
                            .font(.caption)
                            .foregroundStyle(WTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let due = task.due {
                            Text(due.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(WTheme.muted)
                        }
                    }
                }
            }
        }
    }

    /// "7:00 PM · Little Olive", "Tomorrow 9:00 AM" or "All day".
    private func when(_ event: WidgetSnapshot.Event) -> String {
        let time = event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
        // Started today or earlier (and still going) = today; anything else is tomorrow.
        let isToday = Calendar.current.isDate(event.start, inSameDayAs: entry.date) || event.start < entry.date
        let day = isToday ? time : "Tomorrow \(time)"
        return event.location.isEmpty ? day : "\(day) · \(event.location)"
    }
}

// MARK: Widget

struct EverydayWidget: Widget {
    let kind = "EverydayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            EverydayWidgetView(entry: entry)
                .containerBackground(WTheme.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your next events and today's tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    EverydayWidget()
} timeline: {
    DayEntry(date: .now, snapshot: .sample)
}

#Preview(as: .systemMedium) {
    EverydayWidget()
} timeline: {
    DayEntry(date: .now, snapshot: .sample)
}

#Preview(as: .systemLarge) {
    EverydayWidget()
} timeline: {
    DayEntry(date: .now, snapshot: .sample)
}
