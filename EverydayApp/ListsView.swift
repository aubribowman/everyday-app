import SwiftUI
import SwiftData

struct ListsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.createdAt) private var lists: [TaskList]
    @State private var showingNewList = false
    // The list being edited from a tile's long-press menu (nil = none).
    @State private var editingList: TaskList?

    private var tileLists: [TaskList] { lists.filter { !$0.isFeatured } }
    private var featuredLists: [TaskList] { lists.filter { $0.isFeatured } }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your lists")
                                .font(.largeTitle.weight(.semibold))
                                .tracking(-0.5)
                                .foregroundStyle(Theme.ink)
                            Text("A place for everything on your mind.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        AddButton { showingNewList = true }
                    }

                    if lists.isEmpty {
                        VStack(spacing: 14) {
                            ContentUnavailableView(
                                "No lists yet",
                                systemImage: "checklist",
                                description: Text("Tap + to start a list, or load sample data to see the design filled in.")
                            )
                            Button("Load sample data") { SampleData.load(into: context) }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.forest)
                                .foregroundStyle(Theme.onPrimary)
                        }
                        .padding(.top, 40)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tileLists) { list in
                            NavigationLink(value: list) { ListTile(list: list) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Edit list", systemImage: "pencil") {
                                        editingList = list
                                    }
                                    Button("Delete list", systemImage: "trash", role: .destructive) {
                                        context.delete(list)
                                    }
                                }
                        }
                    }

                    ForEach(featuredLists) { ListContent(list: $0) }
                }
                .padding(20)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TaskList.self) { ListDetailView(list: $0) }
            .navigationDestination(for: TaskItem.self) { TaskDetailView(task: $0) }
            .sheet(isPresented: $showingNewList) { NewListSheet() }
            .sheet(item: $editingList) { NewListSheet(editing: $0) }
        }
    }
}

struct ListTile: View {
    let list: TaskList

    var body: some View {
        let tint = list.tintStyle
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: list.icon)
                .font(.title3)
                .foregroundStyle(tint.ink)
            Spacer(minLength: 14)
            Text(list.name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text("\(list.remainingCount) \(list.countPhrase)")
                .font(.caption)
                .foregroundStyle(tint.ink)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(16)
        .background(tint.fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
