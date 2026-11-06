import SwiftUI
import EventKit

/// Create a new calendar event, or edit / delete an existing one.
/// Saves straight to the phone's calendars, so it shows up in Google, Outlook, iCloud, etc.
struct EventEditSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    // nil = making a new event; otherwise the event being edited.
    private let editing: CalendarEvent?

    @State private var draft: CalendarStore.EventDraft
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    /// Pass `editing:` to edit an event, or `defaultDate:` to start a new one on that day.
    /// `prefill:` starts a new event with these details already filled in.
    init(editing event: CalendarEvent? = nil, defaultDate: Date? = nil,
         prefill: CalendarStore.EventDraft? = nil) {
        editing = event
        var draft = CalendarStore.EventDraft()
        if let event {
            draft.title = event.title
            draft.start = event.start
            draft.end = event.end
            draft.isAllDay = event.isAllDay
            draft.location = event.location
            draft.notes = event.notes
            draft.calendarID = event.calendarID
            draft.alertMinutes = event.alertMinutes
        } else if let prefill {
            draft = prefill
        } else {
            let start = Self.defaultStart(on: defaultDate)
            draft.start = start
            draft.end = start.addingTimeInterval(3600)
        }
        _draft = State(initialValue: draft)
    }

    /// 9 AM on a future day, otherwise the next full hour (same as new tasks).
    private static func defaultStart(on day: Date?) -> Date {
        let cal = Calendar.current
        if let day, !cal.isDateInToday(day) {
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        let nextHour = cal.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: nextHour)) ?? nextHour
    }

    private var canSave: Bool {
        store.access == .granted
            && !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.end >= draft.start
    }

    private var dateParts: DatePickerComponents {
        draft.isAllDay ? .date : [.date, .hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            Form {
                // Not connected yet → the same "Connect your calendars" card as elsewhere.
                if store.access != .granted {
                    Section {
                        CalendarStatusCard()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Location", text: $draft.location)
                }

                Section {
                    Toggle("All-day", isOn: $draft.isAllDay)
                    DatePicker("Starts", selection: $draft.start, displayedComponents: dateParts)
                    DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: dateParts)
                }

                Section {
                    Picker("Alert", selection: alertBinding) {
                        Text("None").tag(Int?.none)
                        ForEach(alertOptions) { Text($0.label).tag(Optional($0.value)) }
                        // Keep an alert set elsewhere (e.g. Google) that isn't one of our choices.
                        if let minutes = draft.alertMinutes, !alertOptions.contains(where: { $0.value == minutes }) {
                            Text("\(minutes) minutes before").tag(Optional(minutes))
                        }
                    }
                } footer: {
                    Text("Your iPhone's Calendar app sends the notification.")
                }

                Section {
                    Picker("Calendar", selection: $draft.calendarID) {
                        ForEach(store.writableCalendars, id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                }

                Section {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    if editing?.isRepeating == true {
                        Text("This is a repeating event. Changes apply to this one only.")
                    }
                }

                if editing != nil {
                    Section {
                        Button("Delete event", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .tint(Theme.forest)
            .themedForm()
            .navigationTitle(editing == nil ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            // Moving the start keeps the event the same length.
            .onChange(of: draft.start) { oldStart, newStart in
                let length = max(draft.end.timeIntervalSince(oldStart), 0)
                draft.end = newStart.addingTimeInterval(length)
            }
            // Switching All-day swaps the alert to a fitting choice (if there was one).
            .onChange(of: draft.isAllDay) { _, allDay in
                guard draft.alertMinutes != nil else { return }
                draft.alertMinutes = allDay ? -540 : 15
                draft.alertEdited = true
            }
            // New events go in the phone's default calendar unless you pick another.
            .onAppear(perform: pickDefaultCalendar)
            .onChange(of: store.access) { pickDefaultCalendar() }
            .confirmationDialog("Delete this event?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete event", role: .destructive) { delete() }
            } message: {
                Text("It will be removed from \(editing?.calendarName ?? "your calendar") everywhere.")
            }
            .alert("Something went wrong", isPresented: showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // Minutes before the start. For all-day events the start is midnight, so
    // -540 means 9 AM that day and 900 means 9 AM the day before.
    private var alertOptions: [Option<Int>] {
        draft.isAllDay
            ? [Option(value: -540, label: "On the day (9 AM)"),
               Option(value: 900, label: "1 day before (9 AM)"),
               Option(value: 2340, label: "2 days before (9 AM)")]
            : [Option(value: 0, label: "At time of event"),
               Option(value: 5, label: "5 minutes before"),
               Option(value: 15, label: "15 minutes before"),
               Option(value: 30, label: "30 minutes before"),
               Option(value: 60, label: "1 hour before"),
               Option(value: 1440, label: "1 day before")]
    }

    private var alertBinding: Binding<Int?> {
        Binding(get: { draft.alertMinutes },
                set: { draft.alertMinutes = $0; draft.alertEdited = true })
    }

    private var showingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// New events start in the phone's default calendar.
    private func pickDefaultCalendar() {
        if draft.calendarID.isEmpty {
            draft.calendarID = store.defaultCalendar?.calendarIdentifier ?? ""
        }
    }

    /// Saves to the calendar and closes. Errors (like a deleted event) show in an alert.
    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        do {
            try store.save(draft, updating: editing)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard let editing else { return }
        do {
            try store.delete(editing)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
