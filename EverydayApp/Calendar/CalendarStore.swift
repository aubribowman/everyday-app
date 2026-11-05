import EventKit
import SwiftUI
import Observation

/// How an event is colored: Work (green) or Personal (peach).
enum EventCategory: String, CaseIterable, Identifiable {
    case work, personal

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var fill: Color { self == .work ? Theme.sage : Theme.peach }
    var ink: Color { self == .work ? Theme.forest : Theme.peachInk }
}

/// A calendar event copied out of EventKit into a simple value the views can use.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String
    let calendarName: String
    let category: EventCategory
    let hasVideoCall: Bool
    let notes: String
    let eventID: String       // EventKit's identifier (all repeats of a repeating event share it)
    let calendarID: String
    let canEdit: Bool         // false for read-only calendars like Holidays or Birthdays
    let isRepeating: Bool
    let alertMinutes: Int?    // first alert, in minutes before the start (nil = no alert)

    /// "10:00–10:30 · Work calendar"
    var subtitle: String {
        let place = location.isEmpty ? calendarName : location
        return "\(start.clock)–\(end.clock) · \(place)"
    }
}

/// The calendars from one account ("Gmail", "iCloud"…), for the calendar settings list.
struct CalendarGroup: Identifiable {
    let name: String
    let calendars: [EKCalendar]
    var id: String { name }
}

/// Reads every calendar on the phone (Google, Outlook, iCloud...) through EventKit.
///
/// One instance is made in EverydayApp and shared through the environment.
/// Views get events by calling `events(from:to:)` or `events(on:)`. Reading
/// `changeToken` inside them makes SwiftUI redraw when any calendar changes.
/// The Work/Personal colors and the hidden calendars are this app's own settings,
/// saved in UserDefaults. They don't change anything in the Calendar app.
@MainActor
@Observable
final class CalendarStore {
    /// Whether the app may read calendars. `.denied` means it has to be turned on in iPhone Settings.
    enum Access { case notDetermined, granted, denied }

    private(set) var access: Access = .notDetermined
    private(set) var calendars: [EKCalendar] = []
    private(set) var changeToken = 0   // goes up every time calendars are reloaded
    private var categoryOverrides: [String: String]   // calendar id → "work" / "personal"
    private var hiddenCalendars: Set<String>

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        categoryOverrides = defaults.dictionary(forKey: "calendarCategories") as? [String: String] ?? [:]
        hiddenCalendars = Set(defaults.stringArray(forKey: "hiddenCalendars") ?? [])

        // Refresh whenever a calendar changes (new event in Google, Outlook, etc.)
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            // `queue: .main` already runs this on the main thread, so reload right here.
            MainActor.assumeIsolated { self?.reload() }
        }
        refreshAccess()
    }

    // MARK: Access

    /// Reads the current permission from iOS (it can change in Settings while the app is closed).
    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .notDetermined:
            access = .notDetermined
        default:
            access = .denied
        }
    }

    /// Shows iOS's calendar permission prompt, then updates `access`.
    func requestAccess() async {
        let _: Bool = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error { print("Calendar access error:", error) }
                continuation.resume(returning: granted)
            }
        }
        refreshAccess()
    }

    /// Asks iOS to check Google, Outlook and iCloud for new changes right now.
    /// iOS normally only checks every so often (iPhone Settings → Calendar → Accounts → Fetch),
    /// so edits made on another device can take a while to show up. Whatever it finds
    /// arrives a moment later through the "calendar changed" notice set up in `init`.
    func refresh() {
        guard access == .granted else { return }
        store.refreshSourcesIfNecessary()
        reload()
    }

    /// For pull-to-refresh: fetch, then keep the spinner up briefly while iOS downloads.
    func refreshAndWait() async {
        refresh()
        try? await Task.sleep(for: .seconds(1.5))
        reload()
    }

    /// Re-reads the list of calendars and tells views to fetch their events again.
    func reload() {
        calendars = store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        changeToken += 1
    }

    // MARK: Events

    /// Events from every visible calendar that overlap this time range, earliest first.
    /// Repeating events come back once per occurrence.
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        _ = changeToken   // lets views refresh when calendars change
        guard access == .granted else { return [] }
        let visible = calendars.filter { !hiddenCalendars.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        return store.events(matching: predicate)
            .map(makeEvent)
            .sorted { $0.start < $1.start }
    }

    /// Every event that touches this day.
    func events(on day: Date) -> [CalendarEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return events(from: start, to: end)
    }

    /// Copies an EventKit event into a `CalendarEvent`. Spots video calls (Zoom, Meet, Webex,
    /// Teams) from the location, notes or link.
    private func makeEvent(_ event: EKEvent) -> CalendarEvent {
        let text = [event.location, event.notes, event.url?.absoluteString]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let hasCall = ["zoom.us", "teams.microsoft", "meet.google", "webex"].contains { text.contains($0) }

        return CalendarEvent(
            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location ?? "",
            calendarName: event.calendar.title,
            category: category(for: event.calendar),
            hasVideoCall: hasCall,
            notes: event.notes ?? "",
            eventID: event.eventIdentifier ?? "",
            calendarID: event.calendar.calendarIdentifier,
            canEdit: event.calendar.allowsContentModifications,
            isRepeating: event.hasRecurrenceRules,
            // relativeOffset is in seconds and negative for "before", e.g. -900 = 15 minutes before.
            alertMinutes: event.alarms?.first { $0.absoluteDate == nil }
                .map { Int(-$0.relativeOffset / 60) }
        )
    }

    // MARK: Writing events

    /// The values a new or edited event is saved with (filled in by EventEditSheet).
    struct EventDraft {
        var title = ""
        var start = Date.now
        var end = Date.now.addingTimeInterval(3600)
        var isAllDay = false
        var location = ""
        var notes = ""
        var calendarID = ""
        var alertMinutes: Int? = 15     // minutes before the start; nil = no alert
        var alertEdited = false         // only replace an event's alerts if you changed this
    }

    enum WriteError: LocalizedError {
        case eventNotFound, noCalendar

        var errorDescription: String? {
            switch self {
            case .eventNotFound: "This event couldn't be found. It may have been changed in another app."
            case .noCalendar: "There's no calendar to save to. Add one in iPhone Settings → Calendar → Accounts."
            }
        }
    }

    /// Calendars the app may add events to (skips read-only ones like Holidays and Birthdays).
    var writableCalendars: [EKCalendar] {
        calendars.filter(\.allowsContentModifications)
    }

    /// The calendar new events go in unless you pick another (set in iPhone Settings → Calendar).
    var defaultCalendar: EKCalendar? {
        store.defaultCalendarForNewEvents ?? writableCalendars.first
    }

    /// Creates a new event, or updates `existing` when given.
    func save(_ draft: EventDraft, updating existing: CalendarEvent? = nil) throws {
        let event: EKEvent
        if let existing {
            guard let found = ekEvent(for: existing) else { throw WriteError.eventNotFound }
            event = found
        } else {
            event = EKEvent(eventStore: store)
        }
        guard let calendar = store.calendar(withIdentifier: draft.calendarID) ?? defaultCalendar else {
            throw WriteError.noCalendar
        }
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.calendar = calendar
        // The alert becomes a notification from the Calendar app. When editing, alerts are left
        // alone unless you changed the picker, so extra alerts set in Google aren't lost.
        if existing == nil || draft.alertEdited {
            event.alarms = draft.alertMinutes.map { [EKAlarm(relativeOffset: TimeInterval(-$0 * 60))] }
        }
        // `.thisEvent` = for a repeating event, only this one occurrence changes.
        try store.save(event, span: .thisEvent, commit: true)
        reload()
    }

    /// Deletes this one occurrence (a repeating event keeps its other dates).
    func delete(_ event: CalendarEvent) throws {
        guard let found = ekEvent(for: event) else { throw WriteError.eventNotFound }
        try store.remove(found, span: .thisEvent, commit: true)
        reload()
    }

    /// Finds the exact EventKit occurrence. Repeating events share one identifier,
    /// so we search around its time and match the start too.
    private func ekEvent(for event: CalendarEvent) -> EKEvent? {
        guard let calendar = store.calendar(withIdentifier: event.calendarID) else { return nil }
        let predicate = store.predicateForEvents(
            withStart: event.start.addingTimeInterval(-60),
            end: event.end.addingTimeInterval(60),
            calendars: [calendar]
        )
        return store.events(matching: predicate)
            .first { $0.eventIdentifier == event.eventID && $0.startDate == event.start }
    }

    // MARK: Tasks on the calendar

    /// Keeps a task's calendar event in step with the task: creates, updates or removes it.
    /// Called when you leave a task's detail screen and when "Add to calendar" changes.
    func sync(_ task: TaskItem) {
        guard access == .granted else { return }
        let existing = task.calendarEventID.isEmpty ? nil : store.event(withIdentifier: task.calendarEventID)

        // Switched off, or no date anymore → remove the event if there is one.
        guard task.addToCalendar, let due = task.dueDate else {
            if let existing { try? store.remove(existing, span: .thisEvent, commit: true) }
            if !task.calendarEventID.isEmpty {
                task.calendarEventID = ""
                reload()
            }
            return
        }

        let event = existing ?? EKEvent(eventStore: store)
        event.title = task.title
        event.startDate = due
        event.endDate = due   // just the time you picked, no length
        event.isAllDay = false
        event.location = task.location.isEmpty ? nil : task.location
        event.notes = task.notes.isEmpty ? nil : task.notes
        // The task's "Remind me" setting becomes a real calendar alert on the phone.
        event.alarms = [EKAlarm(relativeOffset: TimeInterval(-task.remindMinutesBefore * 60))]
        if let calendar = store.calendar(withIdentifier: task.calendarID) ?? defaultCalendar,
           calendar.allowsContentModifications {
            event.calendar = calendar
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            task.calendarEventID = event.eventIdentifier ?? ""
        } catch {
            print("Couldn't save task to calendar:", error)
        }
        reload()
    }

    // MARK: Settings

    /// Exchange accounts (Outlook / Microsoft 365) default to Work; everything else to Personal.
    func category(for calendar: EKCalendar) -> EventCategory {
        if let raw = categoryOverrides[calendar.calendarIdentifier],
           let category = EventCategory(rawValue: raw) {
            return category
        }
        return calendar.source.sourceType == .exchange ? .work : .personal
    }

    /// Colors this calendar's events as Work or Personal, in this app only.
    func setCategory(_ category: EventCategory, for calendar: EKCalendar) {
        categoryOverrides[calendar.calendarIdentifier] = category.rawValue
        UserDefaults.standard.set(categoryOverrides, forKey: "calendarCategories")
    }

    /// Hidden calendars stay on the phone but aren't shown in this app.
    func isHidden(_ calendar: EKCalendar) -> Bool {
        hiddenCalendars.contains(calendar.calendarIdentifier)
    }

    func setHidden(_ hidden: Bool, for calendar: EKCalendar) {
        if hidden {
            hiddenCalendars.insert(calendar.calendarIdentifier)
        } else {
            hiddenCalendars.remove(calendar.calendarIdentifier)
        }
        UserDefaults.standard.set(Array(hiddenCalendars), forKey: "hiddenCalendars")
    }

    /// Calendars grouped by account, in alphabetical order.
    var calendarGroups: [CalendarGroup] {
        Dictionary(grouping: calendars) { $0.source.title }
            .map { CalendarGroup(name: $0.key, calendars: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var visibleCount: Int {
        calendars.filter { !hiddenCalendars.contains($0.calendarIdentifier) }.count
    }
}
