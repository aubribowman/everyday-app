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
            .themedForm()
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
            .themedForm()
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
            .themedForm()
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

    // Sync and backups (see SyncFolder.swift and Backup.swift).
    @Environment(SyncFolder.self) private var sync
    @State private var picking = false          // the one file picker on this screen
    @State private var pickingFolder = false    // ...choosing a sync folder rather than a backup
    @State private var foundInFolder: EverydayBackup?   // the other device's copy, waiting for a choice
    @State private var backupToImport: EverydayBackup?  // a picked backup, waiting for "Replace"
    @State private var backupFile: URL?
    @State private var dataMessage: String?

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

                syncSection
                backupSection
            }
            .tint(Theme.forest)
            .themedForm()
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
            // SwiftUI won't reliably show two file pickers from one form, so backups and the
            // sync folder share this one.
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: pickingFolder ? [.folder] : [.json]) { result in
                let forFolder = pickingFolder
                pickingFolder = false
                guard case .success(let url) = result else { return }
                if forFolder { connect(url) } else { readBackup(url) }
            }
            .confirmationDialog("There's already data in this folder", isPresented: Binding(
                get: { foundInFolder != nil }, set: { if !$0 { foundInFolder = nil } }
            ), titleVisibility: .visible, presenting: foundInFolder) { found in
                Button("Use the folder's copy") { sync.useFolderCopy(found) }
                Button("Replace it with this device's", role: .destructive) {
                    Task { await sync.useThisDevice() }
                }
                Button("Cancel", role: .cancel) { sync.disconnect() }
            } message: { found in
                Text("It has \(found.summary), last changed \(found.savedAt.formatted(date: .abbreviated, time: .shortened)). Use it on this device, or replace it with what's on this device?")
            }
            .confirmationDialog("Replace everything on this device?", isPresented: Binding(
                get: { backupToImport != nil }, set: { if !$0 { backupToImport = nil } }
            ), titleVisibility: .visible, presenting: backupToImport) { backup in
                Button("Replace with backup", role: .destructive) { importBackup(backup) }
                Button("Cancel", role: .cancel) {}
            } message: { backup in
                Text("The backup has \(backup.summary), from \(backup.savedAt.formatted(date: .abbreviated, time: .shortened)). What's on this device now will be replaced.")
            }
            .alert(dataMessage ?? "", isPresented: Binding(
                get: { dataMessage != nil }, set: { if !$0 { dataMessage = nil } }
            )) {
                Button("OK") {}
            }
            .alert("Couldn't use that photo", isPresented: $photoError) {
                Button("OK") {}
            } message: {
                Text("Try picking a different photo.")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Sync and backups

    /// Pick the same iCloud Drive folder on each device to keep them in step.
    private var syncSection: some View {
        Section {
            if sync.isOn {
                LabeledContent("Syncing with", value: sync.folderName ?? "Folder")
                if let problem = sync.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.sans(.footnote))
                        .foregroundStyle(Theme.terracotta)
                } else if let date = sync.lastSynced {
                    Text("Last checked \(Text(date, style: .relative)) ago")
                        .font(.sans(.footnote))
                        .foregroundStyle(Theme.muted)
                }
                Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await sync.syncNow() }
                }
                Button("Change folder", systemImage: "folder") { chooseFolder() }
                Button("Stop syncing", systemImage: "xmark.circle", role: .destructive) { sync.disconnect() }
            } else {
                Button("Choose a sync folder", systemImage: "arrow.triangle.2.circlepath") { chooseFolder() }
            }
        } header: {
            Text("Sync between devices")
        } footer: {
            Text(sync.isOn
                 ? "Changes are shared through this folder. Pick the same folder on your other devices. If both change before they sync, the most recent change wins."
                 : "Keep your iPhone and iPad in step. In the Files app, make a folder in iCloud Drive (like \u{201C}EverydayApp\u{201D}), then choose it here on each device.")
        }
    }

    /// One file with everything, to keep somewhere safe or move to another device.
    private var backupSection: some View {
        Section {
            Button("Import a backup", systemImage: "square.and.arrow.down") {
                pickingFolder = false
                picking = true
            }
            if let backupFile {
                ShareLink(item: backupFile) { Label("Share backup file", systemImage: "square.and.arrow.up") }
            } else {
                Button("Create a backup", systemImage: "doc.badge.plus") {
                    do { backupFile = try sync.makeBackupFile() }
                    catch { dataMessage = "Couldn't make a backup: \(error.localizedDescription)" }
                }
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("A backup is one file with your lists, tasks, library, workouts, habits and cycle. Save it somewhere safe, or import it on another device. Calendar events stay in your calendar app.")
        }
    }

    private func chooseFolder() {
        pickingFolder = true
        picking = true
    }

    /// Starts syncing. If your other device already put data in the folder, asks which copy
    /// to keep; otherwise starts the folder with this device's data.
    private func connect(_ url: URL) {
        if let found = sync.connect(url) {
            foundInFolder = found
        } else if sync.problem == nil {
            Task { await sync.useThisDevice() }
        }
    }

    private func readBackup(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let backup = EverydayBackup.decode(data) else {
            dataMessage = "That file isn't an EverydayApp backup."
            return
        }
        backupToImport = backup
    }

    private func importBackup(_ backup: EverydayBackup) {
        do {
            try sync.importBackup(backup)
            backupFile = nil
            dataMessage = "Backup imported"
        } catch {
            dataMessage = "Couldn't import the backup: \(error.localizedDescription)"
        }
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
            .themedForm()
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
