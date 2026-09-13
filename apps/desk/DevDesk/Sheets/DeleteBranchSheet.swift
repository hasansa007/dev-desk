import DeskCore
import SwiftUI

/// The only thing Dev Desk destroys. One confirmation, not a typed name: the sheet says what would be lost and
/// the button says what it does, which is the whole of the gate (amends ADR 0022's typed-name step).
///
/// What the board knew when the sheet opened is still what it asks about — a reload while it is open must not
/// change what the confirmation is about — and `git branch -d` still runs before `-D`, so a branch git thinks
/// is merged is never force-deleted.
struct DeleteBranchSheet: View {
    let model: ProjectWindowModel
    let branch: String
    @State private var unmerged: Int?
    @State private var counted = false

    /// Still true for an uncounted branch — it decides whether git is forced, not whether a name is typed.
    private var losesCommits: Bool { BranchWrite.requiresTypedName(unmerged: unmerged) }
    private var task: DeskTask? { model.tasks.first { $0.branch == branch } }

    var body: some View {
        SheetChrome(title: "Delete \(branch)", confirmTitle: "Delete branch",
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
                if losesCommits {
                    NoticeBanner(tone: .failed, title: warningTitle, message: warning, style: .compact)
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
        model.dismissSheet()
        Task { await model.deleteBranch(branch, force: losesCommits) }
    }
}
