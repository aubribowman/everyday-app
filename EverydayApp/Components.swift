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
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
    }
}

struct AddButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Theme.forest, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
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
    @Bindable var task: TaskItem

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.snappy) { task.isDone.toggle() }
            } label: {
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
                            Text(task.detailLine)
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
