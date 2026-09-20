import AppKit
import DeskCore
import SwiftUI

/// A task typed onto the board (ADR 0045): a title, the bullets that become its `## Done when`, and a description.
/// It is filed where the tracker is — a GitHub issue when one is reachable, a `docs/backlog/` file when not
/// (ADR 0027) — and the sheet says which before anything is typed. As the title settles, open items that may
/// already be this task are listed; they are a proposal, the developer decides. "Add & start" files it and opens
/// the same start sheet a card's first Start opens, so `/dev` cuts the branch at the pipeline's moment, never here.
/// A refused write keeps the sheet open: what was just typed must not vanish with the failure, which the window's
/// banner explains.
struct AddTaskSheet: View {
    let model: ProjectWindowModel
    let column: BoardColumn

    @State private var title = ""
    @State private var bullets = ""
    @State private var notes = ""
    @State private var milestone = ""
    /// The same two ratings the dialog's edit sets, chosen here rather than left for the board (ADR 0020).
    @State private var impact = TaskRatings.none
    @State private var complexity = TaskRatings.none
    /// `.failed` when the search itself did not answer — never shown as "no matches".
    @State private var matches: MatchState = .idle
    @FocusState private var titleFocused: Bool

    private enum MatchState: Equatable { case idle, searching, found([DuplicateCandidate]), failed }

    private var destination: TaskDestination { model.addTaskDestination }
    private var draft: TaskDraft { TaskDraft(title: title, bulletsText: bullets, description: notes) }
    private var isEmpty: Bool { draft.trimmedTitle.isEmpty }

    var body: some View {
        SheetChrome(title: "Add a task to \(column.title)", confirmTitle: "Add task",
                    confirmDisabled: isEmpty || model.isWritingTracker,
                    secondaryTitle: "Add & start", onSecondary: { confirm(start: true) },
                    onCancel: model.dismissSheet, onConfirm: { confirm(start: false) }) {
            VStack(alignment: .leading, spacing: 14) {
                destinationLine
                row("Title") {
                    TextField("What needs doing", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                }
                row("Done when") {
                    TextField("One per line — each becomes a checklist item", text: $bullets, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                }
                row("Description") {
                    TextField("What it is and why, in your own words — optional", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                }
                row("Impact") { TaskRatings.picker(selection: $impact) }
                row("Complexity") { TaskRatings.picker(selection: $complexity) }
                if destination.isGitHub, !model.openMilestones.isEmpty {
                    row("Milestone") {
                        Picker("", selection: $milestone) {
                            Text("None").tag("")
                            ForEach(model.openMilestones, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 360, alignment: .leading)
                    }
                }
                duplicates
            }
        }
        .onAppear {
            titleFocused = true
            // Start in the milestone Work has selected, so the new task appears where you were looking.
            if case .milestone(let title) = model.effectiveWorkScope, model.openMilestones.contains(title) { milestone = title }
        }
        // Searched once the title settles, not per keystroke: `gh` is a process per call.
        .task(id: draft.trimmedTitle) { await search(draft.trimmedTitle) }
    }

    private var destinationLine: some View {
        Text(destination.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(destination.isGitHub ? DeskColor.secondaryInk : DeskColor.mutedInk)
            .help(destination.isGitHub
                  ? "Filed with gh issue create — no agent run and no labels; /dev or the board labels it."
                  : "No reachable tracker, so this becomes a file in docs/backlog/. Dev Desk writes it and never commits it; the card's menu can file it on GitHub later.")
    }

    @ViewBuilder private var duplicates: some View {
        switch matches {
        case .idle, .searching:
            EmptyView()
        case .failed:
            note("The duplicate search did not answer, so nothing was checked. Adding still works.")
        case .found(let found) where found.isEmpty:
            EmptyView()
        case .found(let found):
            VStack(alignment: .leading, spacing: 6) {
                Text("May already exist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeskColor.secondaryInk)
                ForEach(found) { candidate in
                    HStack(spacing: 8) {
                        Text(candidate.number.map { "#\($0)" } ?? "local")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(DeskColor.mutedInk)
                        Text(candidate.title)
                            .font(.system(size: 12))
                            .foregroundStyle(DeskColor.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Button("Open it instead") { open(candidate) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    }
                }
                note("A keyword match, not a verdict: same work → open it; related → add this and mention it.")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(DeskColor.neutralChipFill))
            .padding(.leading, 144)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(DeskColor.faintInk)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).foregroundStyle(DeskColor.secondaryInk).frame(width: 130, alignment: .trailing)
            content()
        }
    }

    private func search(_ title: String) async {
        guard !DuplicateSearch.keywords(title).isEmpty else { matches = .idle; return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        matches = .searching
        let found = await model.possibleDuplicates(for: title)
        guard !Task.isCancelled else { return }
        matches = found.map { .found($0) } ?? .failed
    }

    private func open(_ candidate: DuplicateCandidate) {
        model.dismissSheet()
        if let entry = candidate.localEntry {
            model.openTask(DeskTask.localPrefix + entry)
        } else if let number = candidate.number, case .github(let slug) = destination,
                  let url = URL(string: "https://github.com/\(slug)/issues/\(number)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func confirm(start: Bool) {
        let draft = draft
        let milestone = destination.isGitHub ? milestone : ""
        Task {
            guard let id = await model.addTask(draft, milestone: milestone, column: column,
                                               impact: TaskRatings.value(impact),
                                               complexity: TaskRatings.value(complexity)) else { return }
            // The start sheet a card's first Start opens (ADR 0036): the agent and mode are chosen there, and
            // `/dev` cuts the branch at its first write — never at add time (ADR 0045).
            if start { model.present(.startTask(id)) } else { model.dismissSheet() }
        }
    }
}
