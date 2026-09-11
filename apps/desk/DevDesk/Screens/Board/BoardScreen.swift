import DeskCore
import SwiftUI

struct BoardScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            boardArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeskColor.canvas)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Board")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            searchField
            BacklogToggle(isOn: $model.showBacklog)
            Spacer(minLength: 0)
            if let note = model.snapshot?.boardNote, !note.isEmpty {
                Text(note)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DeskColor.divider).frame(height: 1)
        }
    }

    private var searchField: some View {
        TextField("Search tasks", text: $model.searchText)
            .textFieldStyle(.plain)
            .font(DeskFont.secondary)
            .foregroundStyle(DeskColor.ink)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(minWidth: 200, alignment: .leading)
            .background(DeskColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(DeskColor.border))
    }

    @ViewBuilder
    private var boardArea: some View {
        switch model.snapshot?.board {
        case .available(let tasks):
            boardContent(tasks)
        case .unavailable(let reason):
            UnavailableView(reason: reason)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func boardContent(_ tasks: [DeskTask]) -> some View {
        if tasks.isEmpty {
            EmptyStateView(title: "No tasks yet", message: "Describe the first piece of work, or run a survey to learn the codebase.") {
                Button("Open Findings") { model.go(.findings) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary))
            }
        } else {
            let columns = visibleColumns.map { column in
                ColumnEntry(column: column, tasks: tasks.filter { $0.column == column && matches($0) })
            }
            if !model.searchText.isEmpty && columns.allSatisfy({ $0.tasks.isEmpty }) {
                Text("No tasks match “\(model.searchText)”.")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(columns) { entry in
                            BoardColumnView(column: entry.column, tasks: entry.tasks, model: model)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var visibleColumns: [BoardColumn] {
        BoardColumn.allCases.filter { $0 != .backlog || model.showBacklog }
    }

    private func matches(_ task: DeskTask) -> Bool {
        guard !model.searchText.isEmpty else { return true }
        let query = model.searchText.lowercased()
        if task.title.lowercased().contains(query) { return true }
        if task.issueLabel.lowercased().contains(query) { return true }
        if let meta = task.cardMeta, meta.lowercased().contains(query) { return true }
        return false
    }
}

private struct ColumnEntry: Identifiable {
    let column: BoardColumn
    let tasks: [DeskTask]
    var id: BoardColumn { column }
}

private struct BacklogToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text("Show backlog")
                .font(DeskFont.secondary)
                .foregroundStyle(isOn ? Color.white : DeskColor.ink)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(isOn ? DeskColor.accent : DeskColor.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DeskColor.controlBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show backlog")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

private struct BoardColumnView: View {
    let column: BoardColumn
    let tasks: [DeskTask]
    let model: ProjectWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionLabel(column.title)
                Text("\(tasks.count)")
                    .font(DeskFont.label)
                    .tracking(0.66)
                    .foregroundStyle(DeskColor.disabledDot)
            }
            ForEach(tasks) { task in
                TaskCard(task: task, isLastOpened: task.id == model.lastOpenedTaskID) {
                    model.openTask(task.id)
                }
            }
        }
        .frame(width: DeskMetric.boardColumnWidth, alignment: .leading)
    }
}

struct BoardScreen_Previews: PreviewProvider {
    static var previews: some View {
        BoardPreviewHost()
            .frame(width: 1204, height: 868)
    }

    private struct BoardPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            BoardScreen(model: model)
                .task {
                    await model.load()
                    model.go(.board)
                }
        }
    }
}
