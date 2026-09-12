import DeskCore
import SwiftUI

/// The only thing Dev Desk destroys. What the board knew when the sheet opened is what it asks about: a reload
/// while it is open must not be able to lower the gate under the developer's hands.
struct DeleteBranchSheet: View {
    let model: ProjectWindowModel
    let branch: String
    @State private var unmerged: Int?
    @State private var counted = false
    @State private var typed = ""

    private var needsTyping: Bool { BranchWrite.requiresTypedName(unmerged: unmerged) }
    private var confirmed: Bool { !needsTyping || typed.trimmingCharacters(in: .whitespacesAndNewlines) == branch }
    private var task: DeskTask? { model.tasks.first { $0.branch == branch } }

    var body: some View {
        SheetChrome(title: "Delete \(branch)", confirmTitle: "Delete branch",
                    confirmDisabled: !confirmed,
                    onCancel: model.dismissSheet, onConfirm: confirm) {
            VStack(alignment: .leading, spacing: 10) {
                Text(BranchWrite.confirmation(branch: branch, unmerged: unmerged))
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let committed = task?.lastCommit {
                    Text("Last commit \(BranchAge.label(committed)).")
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.mutedInk)
                }
                if needsTyping {
                    NoticeBanner(tone: .failed, title: warningTitle, message: warning, style: .compact)
                    SectionLabel("Type the branch name to confirm").padding(.top, 2)
                    TextField(branch, text: $typed)
                        .textFieldStyle(.plain)
                        .font(DeskFont.mono(12))
                        .padding(8)
                        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
                } else {
                    Text("Its commits are in the base branch already, so nothing is lost.")
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.faintInk)
                }
                Text("Dev Desk deletes the local branch only. A branch pushed to GitHub stays there.")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .padding(.top, 2)
            }
        }
        // Read once. After this the sheet asks about the branch it opened on, whatever the board reloads into.
        .onAppear {
            guard !counted else { return }
            counted = true
            unmerged = task?.unmergedCount
        }
    }

    private var warningTitle: String { unmerged == nil ? "Nothing counted this branch" : "This loses commits" }

    private var warning: String {
        guard let unmerged else {
            return "Dev Desk has not counted this branch's commits, so it cannot tell you what deleting it would lose."
        }
        return "Those \(unmerged) commits exist only on this branch. Deleting it is not undoable from here."
    }

    private func confirm() {
        guard confirmed else { return }
        model.dismissSheet()
        Task { await model.deleteBranch(branch, force: needsTyping) }
    }
}
