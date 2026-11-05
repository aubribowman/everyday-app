import SwiftUI

/// "10:00 / AM" column on the left of timeline rows.
struct TimeLabel: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date.clock)
                .font(.headline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(date.meridiem)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(width: 50, alignment: .leading)
        .padding(.top, 16)
    }
}

/// A calendar event, colored green (Work) or peach (Personal).
struct EventCard: View {
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(.headline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(event.subtitle)
                .font(.footnote)
                .foregroundStyle(event.category.ink)
                .lineLimit(1)
            Label(event.category.label, systemImage: event.hasVideoCall ? "video" : "calendar")
                .font(.caption)
                .foregroundStyle(event.category.ink)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Capsule().fill(event.category.ink).frame(width: 3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(event.category.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A slim row for all-day events (holidays, birthdays, out-of-office).
struct AllDayChip: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(event.category.ink).frame(width: 6, height: 6)
            Text(event.title).lineLimit(1)
            Spacer()
            Text("All day").foregroundStyle(Theme.muted)
        }
        .font(.footnote)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(event.category.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A task with a due time, shown on the calendar timeline (lavender = reminder).
struct TaskTimelineCard: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.headline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .strikethrough(task.isDone)
            Text(task.timeLine)
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
        .opacity(task.isDone ? 0.5 : 1)
    }
}
