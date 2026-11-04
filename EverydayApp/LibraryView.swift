import SwiftUI
import SwiftData

/// The Library tab: books and TV shows you want to get to, are in the middle of, or finished.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    // Newest change first, so something you just started or finished is at the top of its section.
    @Query(sort: \LibraryItem.statusChangedAt, order: .reverse) private var items: [LibraryItem]

    // Remembers whether you were last looking at Books or TV shows.
    @AppStorage("libraryKind") private var kind = LibraryKind.book
    @State private var adding = false
    @State private var editing: LibraryItem?
    @State private var showingFinished = false

    private var shown: [LibraryItem] { items.filter { $0.kindValue == kind } }
    private func items(_ status: LibraryStatus) -> [LibraryItem] {
        shown.filter { $0.statusValue == status }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    Picker("Type", selection: $kind) {
                        ForEach(LibraryKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if shown.isEmpty {
                        ContentUnavailableView(
                            kind == .book ? "No books yet" : "No shows yet",
                            systemImage: kind == .book ? "books.vertical" : "tv",
                            description: Text(kind == .book
                                ? "Tap + to save a book you want to read."
                                : "Tap + to save a show you want to watch.")
                        )
                        .padding(.top, 30)
                    }

                    section(.want)
                    section(.active)
                    finishedSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $adding) { LibraryItemSheet(kind: kind) }
            .sheet(item: $editing) { LibraryItemSheet(editing: $0) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Library")
                    .font(.largeTitle.weight(.semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                Text("Books and shows to get to later.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            AddButton { adding = true }
        }
    }

    /// "WANT TO READ" or "READING" with its items in a card. Hidden when empty.
    @ViewBuilder
    private func section(_ status: LibraryStatus) -> some View {
        let list = items(status)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(status.label(for: kind).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.muted)
                card(list)
            }
        }
    }

    /// Finished items start folded away so the list stays focused on what's next.
    @ViewBuilder
    private var finishedSection: some View {
        let list = items(.done)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy) { showingFinished.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showingFinished ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.bold))
                        Text("FINISHED · \(list.count)")
                    }
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)

                if showingFinished { card(list) }
            }
        }
    }

    private func card(_ list: [LibraryItem]) -> some View {
        DividedStack(items: list) { item in
            LibraryRow(item: item, onEdit: { editing = $0 }, onDelete: { context.delete($0) })
        }
        .padding(.horizontal, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
    }
}

/// One book or show: title, author or service, and a quick Start / Finish button.
/// Tap to edit; long-press to move it or delete it.
struct LibraryRow: View {
    let item: LibraryItem
    let onEdit: (LibraryItem) -> Void
    let onDelete: (LibraryItem) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(item.statusValue == .done ? Theme.muted : Theme.ink)
                if !item.creator.isEmpty {
                    Text(item.creator)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            quickAction
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(item) }
        .contextMenu {
            ForEach(LibraryStatus.allCases.filter { $0 != item.statusValue }) { status in
                Button("Move to \(status.label(for: item.kindValue))") { move(to: status) }
            }
            Divider()
            Button("Edit", systemImage: "pencil") { onEdit(item) }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item) }
        }
    }

    /// Want to → "Start"; in progress → "Finish"; finished → a check mark.
    @ViewBuilder
    private var quickAction: some View {
        switch item.statusValue {
        case .want:
            pill("Start", icon: "play.fill") { move(to: .active) }
        case .active:
            pill("Finish", icon: "checkmark") { move(to: .done) }
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.forest)
        }
    }

    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.forest)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.sage, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func move(to status: LibraryStatus) {
        withAnimation(.snappy) { item.statusValue = status }
    }
}

/// Add a book or show, or edit one when you pass `editing:`.
struct LibraryItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let editing: LibraryItem?

    @State private var title: String
    @State private var creator: String
    @State private var kind: LibraryKind
    @State private var status: LibraryStatus
    @State private var notes: String

    init(kind: LibraryKind = .book, editing item: LibraryItem? = nil) {
        editing = item
        _title = State(initialValue: item?.title ?? "")
        _creator = State(initialValue: item?.creator ?? "")
        _kind = State(initialValue: item?.kindValue ?? kind)
        _status = State(initialValue: item?.statusValue ?? .want)
        _notes = State(initialValue: item?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Only new items can switch type; an existing book stays a book.
                if editing == nil {
                    Picker("Type", selection: $kind) {
                        ForEach(LibraryKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Title", text: $title)
                    TextField(kind.creatorPrompt, text: $creator)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(LibraryStatus.allCases) { Text($0.label(for: kind)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes") {
                    TextField(kind == .book ? "Who recommended it, why it caught your eye…"
                                            : "Which season you're on, who recommended it…",
                              text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let editing {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(editing)
                            dismiss()
                        }
                    }
                }
            }
            .tint(Theme.forest)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var navigationTitle: String {
        if editing != nil { return kind == .book ? "Edit book" : "Edit show" }
        return kind == .book ? "New book" : "New show"
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let item = editing ?? LibraryItem(title: trimmed, kind: kind)
        item.title = trimmed
        item.creator = creator.trimmingCharacters(in: .whitespaces)
        item.notes = notes
        if item.statusValue != status { item.statusValue = status }
        if editing == nil { context.insert(item) }
        dismiss()
    }
}
