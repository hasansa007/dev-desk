import DeskCore
import SwiftUI

/// What an unstarted card opens: the issue as it was filed, and the one action that starts it.
struct UnstartedTaskSheet: View {
    let model: ProjectWindowModel
    let task: DeskTask
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"

    var body: some View {
        let blocked = blockedReason
        SheetChrome(title: title, confirmTitle: "Start task", width: 720, confirmDisabled: blocked != nil,
                    onCancel: model.dismissSheet, onConfirm: start) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let blocked {
                    NoticeBanner(tone: .neutral, title: "Nothing to start yet", message: blocked)
                }
                RequirementsTab(requirements: task.requirements)
                if !task.dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Dependencies")
                        ForEach(Array(task.dependencies.enumerated()), id: \.offset) { _, dependency in
                            MarkdownText(dependency.text, color: DeskColor.secondaryInk)
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        task.issueLabel.isEmpty ? task.title : "\(task.issueLabel) · \(task.title)"
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusPill(badge: task.headerBadge, showsDot: false, verticalPadding: 2, horizontalPadding: 8)
            Text(task.branchLine)
                .font(DeskFont.mono(12))
                .foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 0)
            if let number = task.taskNumber {
                Text(verbatim: "Starts /dev #\(number) in \(defaultConnection)")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
            }
        }
    }

    /// Why Start task is disabled, or nil when it can run.
    private var blockedReason: String? {
        guard task.taskNumber != nil else { return "This card has no issue number, so `/dev` has nothing to open." }
        return model.runBlockedReason(agent: defaultConnection)
    }

    /// The run opens at the project root: the branch does not exist yet, and `/dev` cuts it at its first write.
    private func start() {
        guard let number = task.taskNumber else { return }
        model.prepareRun(door: "dev", title: "Task #\(number)", agent: defaultConnection,
                         arguments: ["#\(number)"], id: "task:\(number)",
                         folderNote: "#\(number) has no branch yet; /dev cuts one at its first write.")
        model.dismissSheet()
    }
}

struct UnstartedTaskSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost()
    }

    private struct PreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            Group {
                if let task = model.task("65") {
                    UnstartedTaskSheet(model: model, task: task)
                } else {
                    ProgressView()
                }
            }
            .task { await model.load() }
        }
    }
}
