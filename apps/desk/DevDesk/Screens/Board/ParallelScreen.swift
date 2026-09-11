import DeskCore
import SwiftUI

struct ParallelScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            panes
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeskColor.canvas)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button("‹ Back to Board") { model.setMode(.focus) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            Text("Parallel view")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            Text(explanation)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DeskColor.divider).frame(height: 1)
        }
    }

    /// D:243's exact copy applies only for the two-pane case the prototype shows.
    private var explanation: String {
        model.parallelTasks.count == 2
            ? "Two independent tasks, separate checkouts and branches. Running in parallel does not guarantee the changes integrate."
            : "Independent tasks, separate checkouts and branches. Running in parallel does not guarantee the changes integrate."
    }

    @ViewBuilder
    private var panes: some View {
        let tasks = model.parallelTasks
        if let reason = model.snapshot?.board.unavailableReason {
            UnavailableView(reason: reason)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if tasks.isEmpty {
            EmptyStateView(title: "Nothing is running in parallel", message: "Parallel view shows in-progress tasks that have their own branch and checkout.")
        } else {
            HStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Rectangle().fill(DeskColor.divider).frame(width: 1)
                    }
                    ParallelPane(task: task, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

private struct ParallelPane: View {
    let task: DeskTask
    let model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            paneBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        Button { model.openTask(task.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("\(task.issueLabel) \(task.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DeskColor.ink)
                    StatusPill(badge: task.headerBadge, showsDot: false)
                }
                Text(task.parallelLine)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DeskColor.divider).frame(height: 1)
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        switch task.parallel {
        case .transcript(let transcript):
            TerminalTranscriptView(transcript: transcript)
        case .decision(let title, let question, let decisionID, let note):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NoticeBanner(tone: .waiting, title: title, message: question, style: .stacked) {
                        Button("Answer decision") { model.openDecision(decisionID) }
                            .buttonStyle(DeskButtonStyle(kind: .primary))
                    }
                    Text(note)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.mutedInk)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                .padding(14)
            }
        case .activity(let events):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(events) { event in
                        ActivityEventRow(event: event)
                    }
                }
                .padding(14)
            }
        case .none(let text):
            EmptyStateView(title: text, message: "")
        }
    }
}

struct ParallelScreen_Previews: PreviewProvider {
    static var previews: some View {
        ParallelPreviewHost()
            .frame(width: 1204, height: 868)
    }

    private struct ParallelPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            ParallelScreen(model: model)
                .task { await model.load() }
        }
    }
}
