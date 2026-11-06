import SwiftUI
import SwiftData
import PhotosUI

/// What the + menu is making. A reminder is a task with a time and a notification;
/// a plain task starts without a date (you can still add one).
enum NewTaskKind: String, Identifiable {
    case task, reminder
    var id: String { rawValue }
}

/// The form for a new task or reminder, opened from the + menu.
struct NewTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let kind: NewTaskKind
    @State private var title = ""
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var remindMinutes = 0
    @State private var icon = ""

    /// Pass a day from the calendar to default to 9 AM that day; otherwise the next full hour.
    init(kind: NewTaskKind = .task, defaultDate: Date? = nil) {
        self.kind = kind
        // Reminders always have a time; tasks from the calendar get that day's date.
        _hasDate = State(initialValue: kind == .reminder || defaultDate != nil)
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
                Section {
                    TextField(kind == .reminder ? "Remind me to…" : "What needs doing?", text: $title)
                    if kind == .task {
                        Toggle("Date & time", isOn: $hasDate)
                    }
                    if hasDate {
                        DatePicker("When", selection: $date)
                        Picker("Remind me", selection: $remindMinutes) {
                            ForEach(TaskDetailView.remindOptions) { Text($0.label).tag($0.value) }
                        }
                    }
                }

                Section("Icon") {
                    IconGrid(icons: IconChoices.tasks, selection: $icon, allowsNone: true)
                }
            }
            .tint(Theme.forest)
            .navigationTitle(kind == .reminder ? "New reminder" : "New task")
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
        // No `.presentationDetents` here, so the sheet opens at full height.
    }

    /// Saves the new task and closes the sheet.
    private func add() {
        let task = TaskItem(title: title.trimmingCharacters(in: .whitespaces))
        task.dueDate = hasDate ? date : nil
        task.remindMinutesBefore = remindMinutes
        task.icon = icon
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
                    IconGrid(icons: IconChoices.lists, selection: $icon)
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

/// App settings, opened by tapping your initials on the Today tab.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = AppearanceSetting.system
    @AppStorage("userName") private var userName = ""   // set in Settings; "" = no name yet
    @AppStorage(ProfilePhoto.versionKey) private var photoVersion = 0

    // The photo picked from your library, before it's processed and saved.
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var hasPhoto = ProfilePhoto.load() != nil
    @State private var photoError = false
    // The photo still being loaded, so it can be cancelled if you pick again or tap Remove.
    @State private var photoLoad: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ProfileAvatar(size: 96)
                        // Apple's photo picker: no permission prompt needed, you only share the one photo.
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Text(hasPhoto ? "Change photo" : "Choose photo")
                                .font(.sans(.subheadline, .medium))
                        }
                        if hasPhoto {
                            Button("Remove photo", role: .destructive) {
                                photoLoad?.cancel()
                                ProfilePhoto.remove()
                                hasPhoto = false
                                photoVersion += 1
                            }
                            .font(.sans(.subheadline))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderless)   // keeps the two buttons separate inside one row
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }   // full-width divider below
                    .padding(.vertical, 6)

                    TextField("Your name", text: $userName)
                        .textContentType(.name)
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Your first name is used in the greeting on the Today tab.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System matches your iPhone's Light or Dark setting.")
                }
            }
            .tint(Theme.forest)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // When a photo is picked: load it, crop and shrink it, then save it.
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                photoLoad?.cancel()
                photoLoad = Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    // Picked another photo or tapped Remove while this one loaded? Drop it.
                    guard !Task.isCancelled else { return }
                    if let data, let image = UIImage(data: data),
                       (try? ProfilePhoto.save(image)) != nil {
                        hasPhoto = true
                        photoVersion += 1
                    } else {
                        photoError = true
                    }
                    pickedPhoto = nil
                }
            }
            .alert("Couldn't use that photo", isPresented: $photoError) {
                Button("OK") {}
            } message: {
                Text("Try picking a different photo.")
            }
        }
        .presentationDetents([.large])
    }
}

/// Pick the icon shown next to a task. Tapping an icon saves it and closes the sheet.
struct TaskIconSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: TaskItem

    var body: some View {
        NavigationStack {
            ScrollView {
                IconGrid(icons: IconChoices.tasks, selection: $task.icon, allowsNone: true)
                    .padding(20)
            }
            .navigationTitle("Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: task.icon) { dismiss() }
        }
        .tint(Theme.forest)
        .presentationDetents([.medium])
    }
}
