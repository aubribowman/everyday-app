import SwiftUI
import SwiftData

/// A full screen for one list.
struct ListDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var list: TaskList

    var body: some View {
        ScrollView {
            ListContent(list: list, onDelete: { dismiss() })
                .padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The list card: header, progress, reminder banner, sections, checked items, add field.
/// Used inline on the Lists tab (featured lists) and on the detail screen.
struct ListContent: View {
    @Environment(\.modelContext) private var context
    @Bindable var list: TaskList
    var onDelete: () -> Void = {}

    @State private var showDone = true
    @State private var newTitle = ""
    @FocusState private var adding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let reminder = list.nextReminder, let due = reminder.dueDate {
                    NavigationLink(value: reminder) {
                        Label(due.dayTimeText + (reminder.location.isEmpty ? "" : " · \(reminder.location)"),
                              systemImage: "bell")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.forest)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.sage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(list.sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        if !section.isEmpty {
                            Text(section.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 4)
                                .padding(.bottom, 2)
                        }
                        ForEach(list.openItems(in: section)) { ItemRow(item: $0) }
                    }
                }

                if list.totalCount == 0 {
                    Text("Nothing here yet. Add your first item below.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                if list.doneCount > 0 {
                    Divider().overlay(Theme.hairline)
                    Button {
                        withAnimation(.snappy) { showDone.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showDone ? "chevron.down" : "chevron.right")
                            Text("\(list.doneLabel.uppercased()) · \(list.doneCount)")
                        }
                        .font(.caption2.weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)

                    if showDone {
                        VStack(spacing: 0) {
                            ForEach(list.doneItems) { ItemRow(item: $0) }
                        }
                    }
                }
            }
            .card()

            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(Theme.forest)
                TextField("Add an item", text: $newTitle)
                    .focused($adding)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                    .foregroundStyle(Theme.ink)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 6)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: list.icon).foregroundStyle(Theme.forest)
                Text(list.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    Button("Uncheck everything", systemImage: "arrow.uturn.backward") {
                        list.doneItems.forEach { $0.isDone = false }
                    }
                    Button("Clear checked items", systemImage: "checkmark.circle") {
                        list.doneItems.forEach { context.delete($0) }
                    }
                    Divider()
                    Button("Delete list", systemImage: "trash", role: .destructive) {
                        onDelete()
                        context.delete(list)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                }
            }
            HStack {
                Text("\(list.totalCount) items · \(list.doneCount) \(list.doneLabel.lowercased())")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(list.remainingCount) to go")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.forest)
            }
            ProgressView(value: list.progress)
                .tint(Theme.forest)
        }
    }

    private func addItem() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let item = TaskItem(title: title)
        context.insert(item)
        item.list = list
        newTitle = ""
        adding = true   // keep the keyboard up for the next item
    }
}

struct ItemRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var item: TaskItem
    @State private var editing = false

    var body: some View {
        HStack(spacing: 14) {
            CheckBox(isOn: item.isDone)
            Text(item.title)
                .foregroundStyle(item.isDone ? Theme.muted : Theme.ink)
            Spacer()
            if !item.quantity.isEmpty {
                Text(item.quantity)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { item.isDone.toggle() }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = true }
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
        }
        .sheet(isPresented: $editing) { ItemEditSheet(item: item) }
    }
}
