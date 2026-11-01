import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: TaskItem

    @State private var showingDatePicker = false
    @State private var editingLocation = false

    static let remindOptions: [Option<Int>] = [
        Option(value: 0, label: "At the time"),
        Option(value: 5, label: "5 minutes before"),
        Option(value: 15, label: "15 minutes before"),
        Option(value: 30, label: "30 minutes before"),
        Option(value: 60, label: "1 hour before"),
        Option(value: 1440, label: "1 day before"),
    ]

    static let repeatOptions: [Option<String>] = [
        Option(value: "never", label: "Does not repeat"),
        Option(value: "daily", label: "Every day"),
        Option(value: "weekdays", label: "Every weekday"),
        Option(value: "weekly", label: "Every week"),
        Option(value: "monthly", label: "Every month"),
    ]

    private var remindLabel: String {
        Self.remindOptions.first { $0.value == task.remindMinutesBefore }?.label
            ?? "\(task.remindMinutesBefore) minutes before"
    }
    private var repeatLabel: String {
        Self.repeatOptions.first { $0.value == task.repeatRule }?.label ?? "Does not repeat"
    }
    private var dateBinding: Binding<Date> {
        Binding(get: { task.dueDate ?? .now }, set: { task.dueDate = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label(task.dueDate == nil ? "TASK" : "PERSONAL REMINDER", systemImage: "bell")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.forest)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.sage, in: Capsule())

                TextField("Title", text: $task.title, axis: .vertical)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                settingsCard

                if let list = task.linkedList {
                    NavigationLink(value: list) { LinkedListCard(list: list) }
                        .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("NOTE TO SELF", systemImage: "note.text")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.muted)
                    TextField("Add a note", text: $task.notes, axis: .vertical)
                        .foregroundStyle(Theme.ink)
                }

                Button {
                    withAnimation { task.isDone.toggle() }
                    if task.isDone { dismiss() }
                } label: {
                    Label(task.isDone ? "Mark as not done" : "Mark as complete",
                          systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                        .font(.headline)
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.forest, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        dismiss()
                        context.delete(task)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("Location", isPresented: $editingLocation) {
            TextField("Place", text: $task.location)
            TextField("Address", text: $task.locationDetail)
            Button("Done") {}
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if task.dueDate == nil { task.dueDate = .now.addingTimeInterval(3600) }
                    showingDatePicker.toggle()
                }
            } label: {
                DetailRow(icon: "calendar", label: "Date & time",
                          value: task.dueDate?.longDayTime ?? "Add a date")
            }
            .buttonStyle(.plain)

            if showingDatePicker {
                DatePicker("Date", selection: dateBinding)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.forest)
                Button("Remove date", role: .destructive) {
                    withAnimation(.snappy) {
                        task.dueDate = nil
                        showingDatePicker = false
                    }
                }
                .font(.footnote)
                .padding(.bottom, 10)
            }

            Divider().overlay(Theme.hairline)

            Menu {
                Picker("Remind me", selection: $task.remindMinutesBefore) {
                    ForEach(Self.remindOptions) { Text($0.label).tag($0.value) }
                }
            } label: {
                DetailRow(icon: "bell", label: "Remind me", value: remindLabel,
                          detail: task.nudgeDate.map { "You'll get a nudge at \($0.timeText)" })
            }

            Divider().overlay(Theme.hairline)

            Menu {
                Picker("Repeat", selection: $task.repeatRule) {
                    ForEach(Self.repeatOptions) { Text($0.label).tag($0.value) }
                }
            } label: {
                DetailRow(icon: "repeat", label: "Repeat", value: repeatLabel)
            }

            Divider().overlay(Theme.hairline)

            Button { editingLocation = true } label: {
                DetailRow(icon: "mappin.circle", label: "Location",
                          value: task.location.isEmpty ? "Add a place" : task.location,
                          detail: task.locationDetail.isEmpty ? nil : task.locationDetail)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline))
    }
}

struct LinkedListCard: View {
    let list: TaskList

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: list.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.forest)
                VStack(alignment: .leading, spacing: 3) {
                    Text(list.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("\(list.remainingCount) items left · \(list.doneCount) \(list.doneLabel.lowercased())")
                        .font(.footnote)
                        .foregroundStyle(Theme.forest)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.forest)
            }
            if !list.openItems.isEmpty {
                Text(list.openItems.map(\.title).formatted(.list(type: .and)))
                    .font(.footnote)
                    .foregroundStyle(Theme.forest)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sage, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
