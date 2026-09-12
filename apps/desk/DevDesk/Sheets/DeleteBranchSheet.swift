import DeskCore
import SwiftUI

/// The only thing Dev Desk destroys. A branch already in the base goes with one press; one holding commits the
/// base does not have asks for its own name first, because nothing else in the app can lose work.
struct DeleteBranchSheet: View {
    let model: ProjectWindowModel
    let branch: String
    @State private var typed = ""

    private var task: DeskTask? { model.tasks.first { $0.branch == branch } }
    private var unmerged: Int { task?.unmergedCount ?? 0 }
    private var needsTyping: Bool { unmerged > 0 }
    private var confirmed: Bool { !needsTyping || typed.trimmingCharacters(in: .whitespacesAndNewlines) == branch }

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
                    NoticeBanner(tone: .failed, title: "This loses commits",
                                 message: "Those \(unmerged) commits exist only on this branch. Deleting it is not undoable from here.",
                                 style: .compact)
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
    }

    private func confirm() {
        guard confirmed else { return }
        model.dismissSheet()
        Task { await model.deleteBranch(branch, force: needsTyping) }
    }
}
