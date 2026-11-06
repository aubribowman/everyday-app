import SwiftUI
import EventKit

/// The card at the top of the Calendar tab (and on Today until you connect).
/// Not connected → asks for access. Denied → opens Settings. Connected → manage calendars.
struct CalendarStatusCard: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showingSettings = false

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.forest)
                    .frame(width: 40, height: 40)
                    .background(Theme.sage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sans(.subheadline, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.sans(.caption))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: trailingIcon)
                    .foregroundStyle(store.access == .granted ? Theme.forest : Theme.muted)
            }
            .card()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSettings) {
            CalendarSettingsSheet().environment(store)
        }
    }

    private var title: String {
        store.access == .granted ? "Calendars connected" : "Connect your calendars"
    }

    private var subtitle: String {
        switch store.access {
        case .granted: "\(store.visibleCount) of \(store.calendars.count) calendars shown · Tap to manage"
        case .notDetermined: "Show your Google and Outlook events here"
        case .denied: "Calendar access is off. Tap to open Settings."
        }
    }

    private var trailingIcon: String {
        switch store.access {
        case .granted: "checkmark.circle"
        case .notDetermined: "plus.circle"
        case .denied: "gearshape"
        }
    }

    /// What the status card does depends on calendar access: ask, open Settings, or manage calendars.
    private func tap() {
        switch store.access {
        case .granted:
            showingSettings = true
        case .notDetermined:
            Task { await store.requestAccess() }
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}

/// Choose which calendars show up and whether each counts as Work or Personal.
struct CalendarSettingsSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.calendarGroups) { group in
                    Section(group.name) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            CalendarSettingsRow(calendar: calendar)
                        }
                    }
                }

                Section {
                    Text("To add Google or Outlook, go to iPhone Settings → Calendar → Accounts → Add Account. New accounts show up here automatically.")
                        .font(.sans(.footnote))
                        .foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.forest)
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One calendar in the settings list: show or hide it, and choose Work or Personal.
struct CalendarSettingsRow: View {
    @Environment(CalendarStore.self) private var store
    let calendar: EKCalendar

    var body: some View {
        let isVisible = Binding(
            get: { !store.isHidden(calendar) },
            set: { store.setHidden(!$0, for: calendar) }
        )
        let category = Binding(
            get: { store.category(for: calendar) },
            set: { store.setCategory($0, for: calendar) }
        )

        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: isVisible) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(cgColor: calendar.cgColor))
                        .frame(width: 10, height: 10)
                    Text(calendar.title)
                }
            }
            if isVisible.wrappedValue {
                Picker("Counts as", selection: category) {
                    ForEach(EventCategory.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 4)
    }
}
