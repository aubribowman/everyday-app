import SwiftUI
import SwiftData
import MapKit

/// The Library tab: books, TV shows and restaurants you want to get to,
/// are in the middle of, or have finished (with a star rating).
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    // Newest change first, so something you just started or finished is at the top of its section.
    @Query(sort: \LibraryItem.statusChangedAt, order: .reverse) private var items: [LibraryItem]

    // Remembers which section (Books, TV shows, Restaurants) you were last looking at.
    @AppStorage("libraryKind") private var kind = LibraryKind.book
    @State private var genreFilter: String?        // nil = all genres
    @State private var adding = false
    @State private var editing: LibraryItem?
    /// Folded-away sections, remembered between launches, e.g. "book.want,show.done".
    /// Finished starts folded so the list stays focused on what's next.
    @AppStorage("libraryCollapsed") private var collapsedRaw = "book.done,show.done,restaurant.done"

    private var ofKind: [LibraryItem] { items.filter { $0.kindValue == kind } }
    private var shown: [LibraryItem] {
        guard let genreFilter else { return ofKind }
        return ofKind.filter { $0.genre == genreFilter }
    }
    private func items(_ status: LibraryStatus) -> [LibraryItem] {
        shown.filter { $0.statusValue == status }
    }
    /// Genres actually used in this section, for the filter chips.
    private var usedGenres: [String] {
        var seen: [String] = []
        for item in ofKind where !item.genre.isEmpty && !seen.contains(item.genre) {
            seen.append(item.genre)
        }
        return seen.sorted()
    }

    private func key(_ status: LibraryStatus) -> String { "\(kind.rawValue).\(status.rawValue)" }
    private func isCollapsed(_ status: LibraryStatus) -> Bool {
        collapsedRaw.split(separator: ",").contains { $0 == key(status) }
    }
    private func toggle(_ status: LibraryStatus) {
        var keys = Set(collapsedRaw.split(separator: ",").map(String.init))
        if !keys.insert(key(status)).inserted { keys.remove(key(status)) }
        withAnimation(.snappy) { collapsedRaw = keys.sorted().joined(separator: ",") }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    Picker("Section", selection: $kind) {
                        ForEach(LibraryKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !usedGenres.isEmpty { genreChips }

                    if ofKind.isEmpty {
                        ContentUnavailableView(
                            "No \(kind.label.lowercased()) yet",
                            systemImage: kind.emptyIcon,
                            description: Text(kind.emptyMessage)
                        )
                        .padding(.top, 30)
                    }

                    ForEach(kind.statuses) { section($0) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // Switching sections clears the genre filter, since genres differ.
            .onChange(of: kind) { genreFilter = nil }
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
                Text("Books, shows and places to get to.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 10) {
                SearchButton()
                AddButton { adding = true }
            }
        }
    }

    /// A row of pills to show only one genre or cuisine. Tap the chosen one again for all.
    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isOn: genreFilter == nil) { genreFilter = nil }
                ForEach(usedGenres, id: \.self) { genre in
                    chip(genre, isOn: genreFilter == genre) {
                        genreFilter = genreFilter == genre ? nil : genre
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy, action) }) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(isOn ? Theme.onPrimary : Theme.forest)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Theme.forest : Theme.sage, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// "WANT TO READ · 3" with its items in a card. Tap the heading to fold it away. Hidden when empty.
    @ViewBuilder
    private func section(_ status: LibraryStatus) -> some View {
        let list = items(status)
        if !list.isEmpty {
            let collapsed = isCollapsed(status)
            VStack(alignment: .leading, spacing: 8) {
                Button { toggle(status) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                        Text("\(status.label(for: kind).uppercased()) · \(list.count)")
                    }
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(collapsed ? "Shows this section" : "Hides this section")

                if !collapsed { card(list) }
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

/// One item: title, "author · genre", and a quick Start / Finish button,
/// or tappable stars once it's finished. Tap to edit; long-press to move it or delete it.
struct LibraryRow: View {
    @Bindable var item: LibraryItem
    let onEdit: (LibraryItem) -> Void
    let onDelete: (LibraryItem) -> Void

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: item.cover, kind: item.kindValue)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(Theme.ink)
                if !item.detailLine.isEmpty {
                    Text(item.detailLine)
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
            ForEach(item.kindValue.statuses.filter { $0 != item.statusValue }) { status in
                Button("Move to \(status.label(for: item.kindValue))") { move(to: status) }
            }
            Divider()
            Button("Edit", systemImage: "pencil") { onEdit(item) }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item) }
        }
    }

    /// Want to → "Start" (or "Been" for restaurants); in progress → "Finish"; done → stars.
    @ViewBuilder
    private var quickAction: some View {
        switch item.statusValue {
        case .want where item.kindValue == .restaurant:
            pill("Been", icon: "checkmark") { move(to: .done) }
        case .want:
            pill("Start", icon: "play.fill") { move(to: .active) }
        case .active:
            pill("Finish", icon: "checkmark") { move(to: .done) }
        case .done:
            StarRating(rating: $item.rating, size: 14)
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

/// Five stars. Tap one to set the rating; tap the same star again to clear it.
struct StarRating: View {
    @Binding var rating: Int
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = (rating == star) ? 0 : star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(star <= rating ? Theme.lemonInk : Theme.muted.opacity(0.5))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
    }
}

/// Add a book, show or restaurant, or edit one when you pass `editing:`.
struct LibraryItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let editing: LibraryItem?

    @State private var title: String
    @State private var creator: String
    @State private var kind: LibraryKind
    @State private var status: LibraryStatus
    @State private var genre: String
    @State private var rating: Int
    @State private var notes: String
    @State private var coverURL: String
    @State private var typingGenre = false
    @State private var customGenre = ""

    // Matches found while you type the title.
    @State private var suggestions: [LookupResult] = []
    @State private var searching = false
    @State private var lookupFailed = false
    /// The title we last looked up or picked, so picking a match (or opening an
    /// existing item) doesn't start a new search.
    @State private var settledTitle: String

    init(kind: LibraryKind = .book, editing item: LibraryItem? = nil) {
        editing = item
        _title = State(initialValue: item?.title ?? "")
        _creator = State(initialValue: item?.creator ?? "")
        _kind = State(initialValue: item?.kindValue ?? kind)
        _status = State(initialValue: item?.statusValue ?? .want)
        _genre = State(initialValue: item?.genre ?? "")
        _rating = State(initialValue: item?.rating ?? 0)
        _notes = State(initialValue: item?.notes ?? "")
        _coverURL = State(initialValue: item?.coverURL ?? "")
        // Saved items without a cover get matches right away, so you can add one.
        // Restaurants never have covers, so they only search when you change the name.
        let needsCover = item.map { $0.coverURL.isEmpty && $0.kindValue != .restaurant } ?? false
        _settledTitle = State(initialValue: needsCover ? "" : item?.title ?? "")
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    // Include a genre you typed yourself so it shows as chosen.
    private var genreChoices: [String] {
        genre.isEmpty || kind.genres.contains(genre) ? kind.genres : kind.genres + [genre]
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
                    HStack(spacing: 12) {
                        if !coverURL.isEmpty {
                            CoverImage(url: URL(string: coverURL), kind: kind, width: 34)
                        }
                        TextField(kind == .restaurant ? "Name" : "Title", text: $title)
                        if searching { ProgressView() }
                    }
                    TextField(kind.creatorPrompt, text: $creator)
                    Picker(kind.genreLabel, selection: $genre) {
                        Text("None").tag("")
                        ForEach(genreChoices, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Type your own \(kind.genreLabel.lowercased())…") {
                        customGenre = ""
                        typingGenre = true
                    }
                    .font(.subheadline)
                }

                suggestionSection

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(kind.statuses) { Text($0.label(for: kind)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                // Rating appears once you've finished it (or been there).
                if status == .done {
                    Section("Your rating") {
                        StarRating(rating: $rating, size: 28)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }

                Section("Notes") {
                    TextField(kind.notesPrompt, text: $notes, axis: .vertical)
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
            .navigationTitle("\(editing == nil ? "New" : "Edit") \(kind.singular)")
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
            // Look things up shortly after you stop typing.
            .task(id: "\(kind.rawValue)|\(trimmedTitle)") { await lookUp() }
            // Switching type: drop a genre that doesn't belong, and a status restaurants don't have.
            .onChange(of: kind) { _, newKind in
                if !newKind.genres.contains(genre) { genre = "" }
                if !newKind.statuses.contains(status) { status = .want }
                coverURL = ""
                settledTitle = ""   // look the title up again as the new type
            }
            .alert(kind.genreLabel, isPresented: $typingGenre) {
                TextField(kind == .restaurant ? "e.g. Ethiopian" : "e.g. Cozy mystery", text: $customGenre)
                Button("Cancel", role: .cancel) {}
                Button("Use") {
                    let typed = customGenre.trimmingCharacters(in: .whitespaces)
                    if !typed.isEmpty { genre = typed }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Matches for the title as you type. Tap one to fill in the details.
    @ViewBuilder
    private var suggestionSection: some View {
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { result in
                    Button { pick(result) } label: {
                        HStack(spacing: 12) {
                            CoverImage(url: result.coverURL, kind: kind, width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                Text([result.creator, result.year, result.genre]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Tap a match to fill in the details")
            }
        } else if lookupFailed {
            Section {
                Text("Couldn't look that up. Check your connection, or fill it in yourself.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func lookUp() async {
        let query = trimmedTitle
        guard query.count >= 2, query != settledTitle else {
            suggestions = []
            lookupFailed = false
            return
        }
        // Wait until typing pauses; a new keystroke cancels this and starts over.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }

        searching = true
        defer { searching = false }
        do {
            let results = try await LibraryLookup.search(query, kind: kind)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { suggestions = results }
            lookupFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            // Apple Maps reports "nothing found" as an error; that isn't worth a message.
            lookupFailed = !(error is MKError)
        }
    }

    /// Fills in the details. For something already saved, only blanks are filled,
    /// so an author or genre you chose yourself stays.
    private func pick(_ result: LookupResult) {
        title = result.title
        settledTitle = result.title
        let isNew = editing == nil
        if !result.creator.isEmpty && (isNew || creator.isEmpty) { creator = result.creator }
        if !result.genre.isEmpty && (isNew || genre.isEmpty) { genre = result.genre }
        coverURL = result.coverURL?.absoluteString ?? ""
        withAnimation(.snappy) { suggestions = [] }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let item = editing ?? LibraryItem(title: trimmed, kind: kind)
        item.title = trimmed
        item.creator = creator.trimmingCharacters(in: .whitespaces)
        item.genre = genre
        item.rating = status == .done ? rating : 0
        item.notes = notes
        item.coverURL = coverURL
        if item.statusValue != status { item.statusValue = status }
        if editing == nil { context.insert(item) }
        dismiss()
    }
}
