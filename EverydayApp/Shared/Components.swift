import SwiftUI

struct CheckBox: View {
    var isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isOn ? Theme.forest : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn ? Theme.forest : Theme.muted.opacity(0.45), lineWidth: 1.5)
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.onPrimary)
                }
            }
            .frame(width: 22, height: 22)
    }
}

struct AddButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            AddButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
    }
}

/// The round green + that asks what to add: a task, a reminder or a calendar event.
struct AddMenu: View {
    var onTask: () -> Void
    var onReminder: () -> Void
    var onEvent: () -> Void

    var body: some View {
        Menu {
            Button("New task", systemImage: "checkmark.circle", action: onTask)
            Button("New reminder", systemImage: "bell", action: onReminder)
            Button("New event", systemImage: "calendar.badge.plus", action: onEvent)
        } label: {
            AddButtonLabel()
        }
        .accessibilityLabel("Add")
    }
}

/// The round green "+" look, shared by AddButton and the add menu on the Calendar tab.
struct AddButtonLabel: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.title3.weight(.medium))
            .foregroundStyle(Theme.onPrimary)
            .frame(width: 50, height: 50)
            .background(Theme.forest, in: Circle())
    }
}

/// Wraps an event card so tapping it opens the editor. Read-only calendars
/// (Holidays, Birthdays, subscribed calendars) just show the card.
struct EditableEvent<Content: View>: View {
    let event: CalendarEvent
    let onEdit: (CalendarEvent) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if event.canEdit {
            Button { onEdit(event) } label: { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onTap: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            if let action {
                Button(action, action: onTap)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.forest)
                    .buttonStyle(.plain)
            }
        }
    }
}

/// A row with icon, small label, value and chevron (reminder detail screen).
struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption).foregroundStyle(Theme.muted)
                Text(value).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// Stacks rows with hairline dividers between them.
struct DividedStack<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Theme.hairline) }
                row(item)
            }
        }
    }
}

/// A standalone task: checkbox, title, time · place, icon. Tap the text to open it.
struct TaskRow: View {
    @Environment(CalendarStore.self) private var calendarStore
    @Bindable var task: TaskItem

    var body: some View {
        HStack(spacing: 14) {
            Button(action: complete) {
                CheckBox(isOn: task.isDone)
            }
            .buttonStyle(.plain)

            NavigationLink(value: task) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .foregroundStyle(task.isDone ? Theme.muted : Theme.ink)
                            .strikethrough(task.isDone)
                        if !task.detailLine.isEmpty {
                            HStack(spacing: 4) {
                                Text(task.detailLine)
                                // A small ↻ marks tasks that repeat.
                                if task.repeats {
                                    Image(systemName: "repeat").font(.caption2)
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    if !task.icon.isEmpty {
                        Image(systemName: task.icon).foregroundStyle(Theme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func complete() {
        guard task.repeats, !task.isDone else {
            withAnimation(.snappy) { task.toggleDone() }
            return
        }
        // Repeating task: show the tick for a moment, then move it to its next date.
        withAnimation(.snappy) { task.isDone = true }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.snappy) {
                task.isDone = false
                task.toggleDone()
            }
            calendarStore.sync(task)   // moves its calendar event too, if it has one
        }
    }
}

/// A small pill that picks which section (e.g. "Produce") an item goes in,
/// with "New section…" to type a new one.
struct SectionPicker: View {
    let sections: [String]
    @Binding var selection: String

    @State private var naming = false
    @State private var newName = ""

    // Include the current choice even if no item uses it yet (a just-typed new section).
    private var choices: [String] {
        selection.isEmpty || sections.contains(selection) ? sections : sections + [selection]
    }

    var body: some View {
        Menu {
            Picker("Section", selection: $selection) {
                Text("No section").tag("")
                ForEach(choices, id: \.self) { Text($0).tag($0) }
            }
            Divider()
            Button("New section…", systemImage: "plus") {
                newName = ""
                naming = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag")
                Text(selection.isEmpty ? "No section" : selection)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.forest)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.sage, in: Capsule())
        }
        .alert("New section", isPresented: $naming) {
            TextField("e.g. Produce", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { selection = name }
            }
        }
    }
}

struct Option<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// The icons you can choose from (names from Apple's SF Symbols).
enum IconChoices {
    static let lists = ["checklist", "basket", "house", "book", "briefcase",
                        "leaf", "gift", "airplane", "heart", "pawprint"]

    static let tasks = ["briefcase", "laptopcomputer", "envelope", "phone", "person.2",
                        "basket", "cart", "fork.knife", "house", "bed.double",
                        "leaf", "drop", "sun.max", "pawprint", "figure.walk",
                        "dumbbell", "pills", "stethoscope", "car", "airplane",
                        "book", "graduationcap", "music.note", "paintbrush", "gift",
                        "heart", "tshirt", "scissors", "wrench.and.screwdriver", "dollarsign.circle"]
}

/// A grid of round icon buttons; the chosen one is filled green.
/// `allowsNone` adds a first "no icon" choice (saved as "").
struct IconGrid: View {
    let icons: [String]
    @Binding var selection: String
    var allowsNone = false

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            if allowsNone {
                cell(value: "", image: "nosign", name: "No icon")
            }
            ForEach(icons, id: \.self) { symbol in
                cell(value: symbol, image: symbol, name: symbol)
            }
        }
        .padding(.vertical, 6)
    }

    private func cell(value: String, image: String, name: String) -> some View {
        let isChosen = selection == value
        return Button { selection = value } label: {
            Image(systemName: image)
                .font(.title3)
                .foregroundStyle(isChosen ? Theme.onPrimary : Theme.ink)
                .frame(width: 44, height: 44)
                .background(isChosen ? Theme.forest : Theme.background, in: Circle())
        }
        // `.borderless` keeps each button separately tappable inside a Form row.
        .buttonStyle(.borderless)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
