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

    /// "10:00–10:30 · Work calendar"
    var subtitle: String {
        let place = location.isEmpty ? calendarName : location
        return "\(start.clock)–\(end.clock) · \(place)"
    }
}

struct CalendarGroup: Identifiable {
    let name: String
    let calendars: [EKCalendar]
    var id: String { name }
}

/// Reads every calendar on the phone (Google, Outlook, iCloud...) through EventKit.
@MainActor
@Observable
final class CalendarStore {
    enum Access { case notDetermined, granted, denied }

    private(set) var access: Access = .notDetermined
    private(set) var calendars: [EKCalendar] = []
    private var changeToken = 0
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
            Task { @MainActor in self?.reload() }
        }
        refreshAccess()
    }

    // MARK: Access

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

    func requestAccess() async {
        let _: Bool = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error { print("Calendar access error:", error) }
                continuation.resume(returning: granted)
            }
        }
        refreshAccess()
    }

    func reload() {
        calendars = store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        changeToken += 1
    }

    // MARK: Events

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

    func events(on day: Date) -> [CalendarEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return events(from: start, to: end)
    }

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
            hasVideoCall: hasCall
        )
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

    func setCategory(_ category: EventCategory, for calendar: EKCalendar) {
        categoryOverrides[calendar.calendarIdentifier] = category.rawValue
        UserDefaults.standard.set(categoryOverrides, forKey: "calendarCategories")
    }

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

    var calendarGroups: [CalendarGroup] {
        Dictionary(grouping: calendars) { $0.source.title }
            .map { CalendarGroup(name: $0.key, calendars: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var visibleCount: Int {
        calendars.filter { !hiddenCalendars.contains($0.calendarIdentifier) }.count
    }
}
