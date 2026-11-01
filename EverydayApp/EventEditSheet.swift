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
    init(editing event: CalendarEvent? = nil, defaultDate: Date? = nil) {
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

    private var showingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func pickDefaultCalendar() {
        if draft.calendarID.isEmpty {
            draft.calendarID = store.defaultCalendar?.calendarIdentifier ?? ""
        }
    }

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
