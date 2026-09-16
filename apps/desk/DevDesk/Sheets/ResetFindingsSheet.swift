import DeskCore
import SwiftUI

/// Starting a project's survey over from nothing (ADR 0041). What accumulates is owned by different parties:
/// set-aside findings live in the app, the screen's selection in the window, the reports in the repository and
/// the cards they filed on the board or the tracker. Each is a line with its own count, and nothing is cleared
/// silently. Work in progress is the one thing a reset never takes: it is listed, warned about, and offered to resume.
struct ResetSurveySheet: View {
    @Bindable var model: ProjectWindowModel
    @State private var options = SurveyResetOptions()
    @State private var runAfterwards = false
    /// Cards ticked to go, by card id: issues closed as not planned, local entries to the Trash. Every card
    /// that can go starts ticked — a reset is asked for to clean up.
    @State private var removing: Set<String> = []
    @State private var closeReason = ""
    /// Read once when the sheet opens, so a reload underneath cannot change the list being confirmed.
    @State private var cards: [FiledCard] = []
    @State private var reports: [String] = []
    @State private var listed = false
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var ignoredCount: Int { model.ignoredFindingsCount }

    /// Any survey at all, of any scope, in a terminal or in the background. Scope buys nothing here: a reset
    /// moves the reports both halves are being written into, so one going at all is enough to refuse.
    private var isAnySurveyRunning: Bool {
        if model.isSurveyRunning() { return true }
        guard case .local(let path) = model.ref else { return false }
        return jobs?.hasLiveJob(door: "survey", in: path) ?? false
    }

    var body: some View {
        SheetChrome(title: "Reset survey", confirmTitle: confirmTitle, confirmDisabled: !canConfirm,
                    size: .confirm, onCancel: model.dismissSheet, onConfirm: reset) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Clears the findings and the tasks they filed, so the next run starts from nothing. Work in progress is kept.")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if isAnySurveyRunning {
                    NoticeBanner(tone: .waiting, title: "A survey is running",
                                 message: "Its report is being written into docs/survey/. Reset once it has finished.",
                                 style: .compact)
                }

                line(isOn: $options.reports,
                     title: "Clear the findings",
                     detail: reportsDetail,
                     enabled: !reports.isEmpty && model.canRunDoors && !isAnySurveyRunning)

                line(isOn: $options.ignoredFindings,
                     title: "Bring back ignored findings",
                     detail: ignoredCount == 0
                        ? "Nothing is set aside in this project."
                        : "\(ignoredCount) finding\(ignoredCount == 1 ? "" : "s") set aside here. They live in the app, never in docs/survey/.",
                     enabled: ignoredCount > 0)

                line(isOn: $options.viewState,
                     title: "Reset this screen",
                     detail: "Selected run, category filter and the ignored-findings view go back to how the project opens.",
                     enabled: true)

                if !cards.isEmpty {
                    Divider()
                    filedCards
                }

                Divider()

                Toggle(isOn: $runAfterwards) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run a new survey afterwards").font(DeskFont.body)
                        Text(model.canRunDoors
                             ? "Opens dev:survey in Terminals. Nothing executes until you start it there."
                             : "A sample project has no folder to survey.")
                            .font(DeskFont.secondary)
                            .foregroundStyle(DeskColor.mutedInk)
                    }
                }
                .disabled(!model.canRunDoors || isAnySurveyRunning)
            }
        }
        .onAppear {
            guard !listed else { return }
            listed = true
            reports = model.surveyReports
            options.reports = !reports.isEmpty && model.canRunDoors && !isAnySurveyRunning
            options.ignoredFindings = ignoredCount > 0
            cards = model.surveyFiledCards.map(FiledCard.init)
            if model.canRunDoors { removing = Set(removable.map(\.id)) }
            closeReason = "Superseded: the survey was reset on \(Self.today) to start over from a new run."
        }
    }

    // MARK: - Filed cards

    struct FiledCard: Identifiable {
        let id: String
        let label: String
        let title: String
        let column: BoardColumn
        let reset: FiledCardReset

        init(_ task: DeskTask) {
            id = task.id
            label = task.issueLabel
            title = task.title
            column = task.column
            reset = FiledCardReset.of(column: task.column, branch: task.branch, issue: task.issueNumber,
                                      localBacklogID: task.localBacklogID)
        }

        var canGo: Bool {
            switch reset {
            case .closable, .trashable: return true
            case .inProgress, .done: return false
            }
        }
    }

    private var removable: [FiledCard] { cards.filter(\.canGo) }
    private var inProgress: [FiledCard] { cards.filter { $0.reset == .inProgress } }
    private var closingIssues: [Int] {
        cards.compactMap { card in
            guard removing.contains(card.id), case .closable(let issue) = card.reset else { return nil }
            return issue
        }
    }
    private var trashing: [String] {
        cards.compactMap { card in
            guard removing.contains(card.id), case .trashable(let entry) = card.reset else { return nil }
            return entry
        }
    }
    private var trimmedReason: String { closeReason.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What the survey put on the board. Everything not in progress is ticked to go; in progress is kept.
    private var filedCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel("Tasks this survey filed")
                Text("\(cards.count)")
                    .font(DeskFont.label)
                    .foregroundStyle(DeskColor.faintInk)
                Spacer(minLength: 0)
                if removable.count > 1 {
                    Button(removing.count == removable.count ? "Keep all" : "Select all") {
                        removing = removing.count == removable.count ? [] : Set(removable.map(\.id))
                    }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .disabled(!model.canRunDoors)
                }
            }
            Text(removable.isEmpty
                 ? "Nothing here can go — every task is in progress or already done."
                 : "A ticked docs/backlog/ entry goes to the Trash; a ticked issue is closed on GitHub as not planned, with the reason below. Untick what you want to keep.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(cards) { card in cardRow(card) }
                }
            }
            .frame(maxHeight: min(CGFloat(cards.count) * 30, 210))
            .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.border))

            if !inProgress.isEmpty {
                NoticeBanner(tone: .waiting,
                             title: inProgress.count == 1 ? "1 task is in progress" : "\(inProgress.count) tasks are in progress",
                             message: "A reset never removes work in progress. Resume it, or close it from its own card if it is no longer wanted.",
                             style: .compact)
            }

            if !closingIssues.isEmpty {
                Text("Why").font(DeskFont.secondary).foregroundStyle(DeskColor.secondaryInk)
                TextField("Superseded by a new survey", text: $closeReason, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .font(DeskFont.body)
                    .padding(8)
                    .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
                Text("dev:roadmap reads this comment back, so a closed direction is not proposed again. Reopening is `gh issue reopen`.")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cardRow(_ card: FiledCard) -> some View {
        HStack(spacing: 8) {
            if card.canGo {
                Toggle("", isOn: Binding(get: { removing.contains(card.id) },
                                         set: { if $0 { removing.insert(card.id) } else { removing.remove(card.id) } }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!model.canRunDoors)
                    .frame(width: 18)
                    .accessibilityLabel(card.label.isEmpty ? "Move \(card.title) to the Trash" : "Close \(card.label) as not planned")
            } else if card.reset == .inProgress {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DeskColor.tone(.waiting).dot)
                    .frame(width: 18)
            } else {
                Color.clear.frame(width: 18, height: 1)
            }
            if !card.label.isEmpty {
                Text(card.label)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .fixedSize()
            }
            Text(card.title)
                .font(DeskFont.secondary)
                .foregroundStyle(card.canGo ? DeskColor.ink : DeskColor.mutedInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(card.title)
            if card.reset == .inProgress {
                Button("Resume") { resume(card) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .disabled(!model.canRunDoors)
                    .fixedSize()
            } else {
                Text(rowNote(card))
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineLimit(1)
                    .fixedSize()
            }
            StatusPill(badge: StatusBadge(FindingRow.tone(of: card.column), card.column.title))
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
    }

    private func rowNote(_ card: FiledCard) -> String {
        let ticked = removing.contains(card.id)
        switch card.reset {
        case .closable: return ticked ? "closes" : "kept"
        case .trashable: return ticked ? "to the Trash" : "kept"
        case .inProgress, .done: return "kept"
        }
    }

    /// A live session is picked up where it is; otherwise the start sheet, which reopens the task's own worktree.
    private func resume(_ card: FiledCard) {
        model.dismissSheet()
        if model.sessions.activeTaskIDs.contains(card.id) {
            model.selectedSessionID = card.id
            model.go(.terminals)
        } else {
            model.present(.startTask(card.id))
        }
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var canConfirm: Bool {
        if !closingIssues.isEmpty && trimmedReason.isEmpty { return false }
        return !options.isEmpty || !removing.isEmpty
    }

    private var reportsDetail: String {
        guard model.canRunDoors else { return "A sample project has no reports on disk." }
        switch reports.count {
        case 0: return "There are no reports in docs/survey/."
        case 1: return "The report in docs/survey/ goes to the Trash, and the Survey screen is empty until the next run."
        default: return "All \(reports.count) reports in docs/survey/ go to the Trash, and the Survey screen is empty until the next run."
        }
    }

    private var confirmTitle: String {
        var parts: [String] = []
        if !closingIssues.isEmpty { parts.append("close \(closingIssues.count)") }
        if !trashing.isEmpty || (options.reports && !reports.isEmpty) { parts.append("move to Trash") }
        return parts.isEmpty ? "Reset" : "Reset and " + parts.joined(separator: " and ")
    }

    private func line(isOn: Binding<Bool>, title: String, detail: String, enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DeskFont.body)
                Text(detail)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!enabled)
        .onChange(of: enabled) { _, isEnabled in if !isEnabled { isOn.wrappedValue = false } }
    }

    private func reset() {
        var options = options
        options.closeIssues = closingIssues
        options.closeReason = trimmedReason
        options.trashBacklogIDs = trashing
        let runAfterwards = runAfterwards
        model.dismissSheet()
        Task {
            await model.resetSurvey(options)
            // The same door start the screen's own button uses: it asks what to focus on first, and nothing
            // executes until you start it in Terminals.
            if runAfterwards { model.present(.runFocus("survey")) }
        }
    }
}
