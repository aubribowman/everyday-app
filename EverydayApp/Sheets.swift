import SwiftUI
import SwiftData

struct NewTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var hasDate = true
    @State private var date: Date

    /// Pass a day from the calendar to default to 9 AM that day; otherwise the next full hour.
    init(defaultDate: Date? = nil) {
        let cal = Calendar.current
        let start: Date
        if let defaultDate, !cal.isDateInToday(defaultDate) {
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        } else {
            let nextHour = cal.date(byAdding: .hour, value: 1, to: .now) ?? .now
            start = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: nextHour)) ?? nextHour
        }
        _date = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What needs doing?", text: $title)
                Toggle("Date & time", isOn: $hasDate)
                if hasDate {
                    DatePicker("When", selection: $date)
                }
            }
            .tint(Theme.forest)
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() {
        let task = TaskItem(title: title.trimmingCharacters(in: .whitespaces))
        task.dueDate = hasDate ? date : nil
        context.insert(task)
        dismiss()
    }
}

/// Creates a new list, or edits an existing one when you pass `editing:`
/// (rename it, change its icon, color, count label or featured setting).
struct NewListSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // nil = making a new list; otherwise the list being edited.
    private let editing: TaskList?

    @State private var name: String
    @State private var icon: String
    @State private var tint: CardTint
    @State private var countPhrase: String
    @State private var isFeatured: Bool

    // Start the form with the list's current values when editing, or defaults when new.
    init(editing list: TaskList? = nil) {
        editing = list
        _name = State(initialValue: list?.name ?? "")
        _icon = State(initialValue: list?.icon ?? "checklist")
        _tint = State(initialValue: list?.tintStyle ?? .sage)
        _countPhrase = State(initialValue: list?.countPhrase ?? "things to do")
        _isFeatured = State(initialValue: list?.isFeatured ?? false)
    }

    private let icons = ["checklist", "basket", "house", "book", "briefcase",
                         "leaf", "gift", "airplane", "heart", "pawprint"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name", text: $name)
                    TextField("Count label", text: $countPhrase)
                } footer: {
                    Text("Shown on the card, like “6 books to explore”.")
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .foregroundStyle(icon == symbol ? Color.white : Theme.ink)
                                    .frame(width: 44, height: 44)
                                    .background(icon == symbol ? Theme.forest : Theme.background, in: Circle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Color") {
                    Picker("Color", selection: $tint) {
                        ForEach(CardTint.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Show the full list on the Lists tab", isOn: $isFeatured)
                } footer: {
                    Text("Handy for groceries: check things off without opening the list.")
                }
            }
            .tint(Theme.forest)
            .navigationTitle(editing == nil ? "New list" : "Edit list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Create" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let list = editing {
            // Editing: copy the form's values onto the existing list. SwiftData saves it.
            list.name = trimmedName
            list.icon = icon
            list.tint = tint.rawValue
            list.countPhrase = countPhrase
            list.isFeatured = isFeatured
        } else {
            let list = TaskList(
                name: trimmedName,
                icon: icon,
                tint: tint,
                isFeatured: isFeatured,
                countPhrase: countPhrase
            )
            context.insert(list)
        }
        dismiss()
    }
}

/// Long-press an item → Edit. Set the quantity and which section it belongs to.
struct ItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: TaskItem

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item", text: $item.title)
                TextField("Quantity (e.g. 2 pcs)", text: $item.quantity)
                LabeledContent("Section") {
                    SectionPicker(sections: item.list?.allSections ?? [], selection: $item.section)
                }
            }
            .tint(Theme.forest)
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
