// The Library tab and its sheets: the list of books, shows, restaurants and
// recipes; one row; star ratings; the add/edit form (with look-up as you type
// and recipe import from a link); and planning a restaurant visit.

import SwiftUI
import SwiftData
import MapKit

/// The Library tab: books, TV shows, restaurants and recipes you want to get to,
/// are in the middle of, or have finished (with a star rating).
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(CalendarStore.self) private var calendarStore
    // Newest change first, so something you just started or finished is at the top of its section.
    @Query(sort: \LibraryItem.statusChangedAt, order: .reverse) private var items: [LibraryItem]

    // Remembers which section (Books, TV shows, Restaurants) you were last looking at.
    @AppStorage("libraryKind") private var kind = LibraryKind.book
    @State private var genreFilter: String?        // nil = all genres
    @State private var adding = false
    @State private var editing: LibraryItem?
    @State private var planning: LibraryItem?      // restaurant you're planning a visit to
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

    /// "book.done": how a section is saved in `collapsedRaw`.
    private func key(_ status: LibraryStatus) -> String { "\(kind.rawValue).\(status.rawValue)" }
    private func isCollapsed(_ status: LibraryStatus) -> Bool {
        collapsedRaw.split(separator: ",").contains { $0 == key(status) }
    }
    /// Folds the section away, or opens it again.
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
            .sheet(isPresented: $adding) { LibraryItemSheet(kind: kind).environment(calendarStore) }
            .sheet(item: $editing) { LibraryItemSheet(editing: $0).environment(calendarStore) }
            .sheet(item: $planning) { PlanVisitSheet(restaurant: $0).environment(calendarStore) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Library")
                    .font(.display(.largeTitle))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                Text("Books, shows, places and recipes.")
                    .font(.sans(.subheadline))
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

    /// A genre filter chip. Filled when it's the active filter.
    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy, action) }) {
            Text(title)
                .font(.sans(.footnote, .medium))
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
                            .font(.sans(.caption2, .bold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                        Text("\(status.label(for: kind).uppercased()) · \(list.count)")
                    }
                    .font(.sans(.caption, .semibold))
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

    /// One section's items as a card of rows.
    private func card(_ list: [LibraryItem]) -> some View {
        DividedStack(items: list) { item in
            LibraryRow(item: item, onEdit: { editing = $0 }, onDelete: { context.delete($0) },
                       onPlan: { planning = $0 })
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
    var onPlan: ((LibraryItem) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: item.cover, kind: item.kindValue)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(Theme.ink)
                if !item.detailLine.isEmpty {
                    Text(item.detailLine)
                        .font(.sans(.footnote))
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
            if item.kindValue == .restaurant, let onPlan {
                Button("Plan a visit", systemImage: "calendar.badge.plus") { onPlan(item) }
            }
            Divider()
            Button("Edit", systemImage: "pencil") { onEdit(item) }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item) }
        }
    }

    /// Want to → "Start" ("Been" for restaurants, "This week" for recipes);
    /// in progress → "Finish" ("Made it" for recipes); done → stars.
    @ViewBuilder
    private var quickAction: some View {
        switch item.statusValue {
        case .want where item.kindValue == .restaurant:
            pill("Been", icon: "checkmark") { move(to: .done) }
        case .want where item.kindValue == .recipe:
            pill("This week", icon: "frying.pan") { move(to: .active) }
        case .active where item.kindValue == .recipe:
            pill("Made it", icon: "checkmark") { move(to: .done) }
        case .want:
            pill("Start", icon: "play.fill") { move(to: .active) }
        case .active:
            pill("Finish", icon: "checkmark") { move(to: .done) }
        case .done:
            StarRating(rating: $item.rating, size: 14)
        }
    }

    /// The small button that moves an item along ("Start", "Finish", "Made it").
    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.sans(.footnote, .medium))
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
    @Environment(CalendarStore.self) private var calendarStore

    private let editing: LibraryItem?

    @State private var title: String
    @State private var creator: String
    @State private var kind: LibraryKind
    @State private var status: LibraryStatus
    @State private var genre: String
    @State private var rating: Int
    @State private var notes: String
    @State private var coverURL: String
    // Recipes only.
    @State private var link: String
    @State private var ingredients: String
    @State private var steps: String
    @State private var minutes: Int
    @State private var importing = false
    @State private var importError: String?
    @State private var addedToList: String?        // "Added 9 to Groceries"
    @Query(sort: \TaskList.createdAt) private var lists: [TaskList]
    @State private var typingGenre = false
    @State private var customGenre = ""
    @State private var planningVisit = false

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
        _link = State(initialValue: item?.link ?? "")
        _ingredients = State(initialValue: item?.ingredients ?? "")
        _steps = State(initialValue: item?.steps ?? "")
        _minutes = State(initialValue: item?.minutes ?? 0)
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
                    .font(.sans(.subheadline))
                }

                suggestionSection

                if kind == .recipe { recipeSections }

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

                if let editing, kind == .restaurant {
                    Section {
                        Button("Plan a visit", systemImage: "calendar.badge.plus") { planningVisit = true }
                    } footer: {
                        Text("Adds it to your calendar, with the place as the location.")
                    }
                    .sheet(isPresented: $planningVisit) {
                        PlanVisitSheet(restaurant: editing).environment(calendarStore)
                    }
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
                TextField(kind == .restaurant ? "e.g. Ethiopian" : kind == .recipe ? "e.g. Pasta" : "e.g. Cozy mystery", text: $customGenre)
                Button("Cancel", role: .cancel) {}
                Button("Use") {
                    let typed = customGenre.trimmingCharacters(in: .whitespaces)
                    if !typed.isEmpty { genre = typed }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Recipes

    /// Link (with "Get the recipe"), time, ingredients and steps.
    @ViewBuilder
    private var recipeSections: some View {
        Section {
            TextField("Paste a link to the recipe", text: $link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !link.isEmpty {
                Button {
                    Task { await importFromLink() }
                } label: {
                    HStack {
                        Label("Get the recipe from this link", systemImage: "arrow.down.circle")
                        Spacer()
                        if importing { ProgressView() }
                    }
                }
                .disabled(importing)
                if let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
                    Link(destination: url) {
                        Label("Open the page", systemImage: "safari")
                    }
                }
            } else {
                // Text rather than URL, so a link copied from Notes or Messages works too.
                PasteButton(payloadType: String.self) { strings in
                    guard let first = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                    Task { @MainActor in
                        link = first
                        await importFromLink()
                    }
                }
                .tint(Theme.forest)
            }
        } header: {
            Text("Link")
        } footer: {
            if let importError {
                Text(importError).foregroundStyle(Theme.peachInk)
            } else {
                Text("Works with most recipe sites and TikTok. It fills in the name, photo, ingredients and steps.")
            }
        }

        Section {
            Stepper(value: $minutes, in: 0...600, step: 5) {
                Text(minutes == 0 ? "Total time: not set" : "Total time: \(LibraryItem.duration(minutes))")
            }
        }

        Section {
            TextField("One per line, e.g. 2 cups flour", text: $ingredients, axis: .vertical)
                .lineLimit(4...20)
            if !LibraryItem.lines(ingredients).isEmpty && !lists.isEmpty {
                Menu {
                    ForEach(lists) { list in
                        Button(list.name, systemImage: list.icon) { addIngredients(to: list) }
                    }
                } label: {
                    Label("Add ingredients to a list", systemImage: "cart.badge.plus")
                }
            }
        } header: {
            Text("Ingredients")
        } footer: {
            if let addedToList { Text(addedToList) }
        }

        Section("Steps") {
            TextField("One step per line", text: $steps, axis: .vertical)
                .lineLimit(4...30)
        }
    }

    /// Reads the recipe at the pasted link and fills in the empty fields.
    private func importFromLink() async {
        importing = true
        importError = nil
        defer { importing = false }
        do {
            let result = try await RecipeImporter.recipe(from: link)
            withAnimation(.snappy) { fill(from: result, onlyBlanks: false) }
        } catch {
            importError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't open that page. Check your connection and try again."
        }
    }

    /// Puts each ingredient on a list (a grocery list, say), grouped under the recipe's name.
    private func addIngredients(to list: TaskList) {
        let section = trimmedTitle.isEmpty ? "Recipe" : trimmedTitle
        let lines = LibraryItem.lines(ingredients)
        for line in lines {
            let item = TaskItem(title: line, section: section)
            context.insert(item)
            item.list = list
        }
        withAnimation { addedToList = "Added \(lines.count) to \(list.name)." }
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
                                    .font(.sans(.footnote))
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
                    .font(.sans(.footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// Searches as you type the title. Runs as a `.task(id:)`, so each keystroke cancels the last search.
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
        fill(from: result, onlyBlanks: editing != nil)
        withAnimation(.snappy) { suggestions = [] }
    }

    /// Copies a match (or an imported recipe) into the form. With `onlyBlanks`,
    /// anything you've already filled in stays.
    private func fill(from result: LookupResult, onlyBlanks: Bool) {
        func use(_ value: String, for field: inout String) {
            if !value.isEmpty && (!onlyBlanks || field.isEmpty) { field = value }
        }
        if !result.title.isEmpty { title = result.title }
        settledTitle = title
        use(result.creator, for: &creator)
        use(result.genre, for: &genre)
        if let cover = result.coverURL?.absoluteString, !cover.isEmpty { coverURL = cover }
        else if !onlyBlanks { coverURL = "" }
        use(result.link, for: &link)
        use(result.ingredients.joined(separator: "\n"), for: &ingredients)
        use(result.steps.joined(separator: "\n"), for: &steps)
        if result.minutes > 0 && (!onlyBlanks || minutes == 0) { minutes = result.minutes }
        if !result.notes.isEmpty && notes.isEmpty { notes = result.notes }
    }

    /// Saves the form to a new item, or onto `editing`, then closes.
    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let item = editing ?? LibraryItem(title: trimmed, kind: kind)
        item.title = trimmed
        item.creator = creator.trimmingCharacters(in: .whitespaces)
        item.genre = genre
        item.rating = status == .done ? rating : 0
        item.notes = notes
        item.coverURL = coverURL
        if kind == .recipe {
            item.link = link.trimmingCharacters(in: .whitespaces)
            item.ingredients = ingredients
            item.steps = steps
            item.minutes = minutes
        }
        if item.statusValue != status { item.statusValue = status }
        if editing == nil { context.insert(item) }
        dismiss()
    }
}

/// A new calendar event for going to a restaurant: "Dinner at Little Olive",
/// the next evening at 7, with the place as the location. Change anything before adding.
struct PlanVisitSheet: View {
    let restaurant: LibraryItem

    var body: some View {
        EventEditSheet(prefill: Self.draft(for: restaurant))
    }

    /// The starting event for a visit: "Dinner at …" for 90 minutes from 7 PM, tonight or (if it's already late) tomorrow.
    static func draft(for place: LibraryItem) -> CalendarStore.EventDraft {
        let cal = Calendar.current
        // Tonight at 7 if it's still the afternoon, otherwise tomorrow at 7.
        let tonight = cal.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
        let start = Date.now < tonight.addingTimeInterval(-2 * 3600)
            ? tonight
            : cal.date(byAdding: .day, value: 1, to: tonight) ?? tonight

        var draft = CalendarStore.EventDraft()
        draft.title = "Dinner at \(place.title)"
        draft.start = start
        draft.end = start.addingTimeInterval(90 * 60)
        draft.location = [place.title, place.creator].filter { !$0.isEmpty }.joined(separator: ", ")
        draft.notes = place.notes
        return draft
    }
}
