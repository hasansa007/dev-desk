import DeskCore
import SwiftUI

/// Starting a project's survey reading over. Three things accumulate and none of them is owned by the same
/// party: the findings you set aside live in the app, the screen's selection lives in the window, and the
/// reports live in the repository. So each is a line with its own count, and nothing is cleared silently.
struct ResetSurveySheet: View {
    @Bindable var model: ProjectWindowModel
    @State private var options = SurveyResetOptions()
    @State private var runAfterwards = false
    /// Issues ticked for closing. Empty by default: keeping is what a reset does unless you say otherwise.
    @State private var closing: Set<Int> = []
    @State private var closeReason = ""
    /// Read once when the sheet opens, so a reload underneath cannot change the list being confirmed.
    @State private var cards: [FiledCard] = []
    @State private var listed = false
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var olderReports: [String] { model.olderSurveyReports }
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
                Text("Clears what has built up between runs. The newest report is always kept — it is the current picture of this project.")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

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

                line(isOn: $options.olderReports,
                     title: "Move older reports to the Trash",
                     detail: reportsDetail,
                     enabled: !olderReports.isEmpty && model.canRunDoors)

                if options.olderReports, !olderReports.isEmpty {
                    Text(olderReports.joined(separator: "   "))
                        .font(DeskFont.mono(11))
                        .foregroundStyle(DeskColor.faintInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 26)
                }

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
            cards = model.surveyFiledCards.map(FiledCard.init)
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
            reset = FiledCardReset.of(column: task.column, branch: task.branch, issue: task.issueNumber)
        }

        var issue: Int? {
            if case .closable(let issue) = reset { return issue }
            return nil
        }
    }

    private var closable: [Int] { cards.compactMap(\.issue) }
    private var startedCount: Int { cards.filter { $0.reset == .started }.count }
    private var trimmedReason: String { closeReason.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What the survey put on the board. Kept unless ticked; work already started is shown, never offered.
    private var filedCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel("Tasks this survey filed")
                Text("\(cards.count)")
                    .font(DeskFont.label)
                    .foregroundStyle(DeskColor.faintInk)
                Spacer(minLength: 0)
                if closable.count > 1 {
                    Button(closing.count == closable.count ? "Keep all" : "Select all not started") {
                        closing = closing.count == closable.count ? [] : Set(closable)
                    }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .disabled(!model.canRunDoors)
                }
            }
            Text(closable.isEmpty
                 ? "Nothing here can be closed from a reset — every task is started, done, or only in docs/backlog/."
                 : "Everything is kept unless you tick it. A ticked task is closed on GitHub as not planned, with the reason below as its comment.")
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

            if startedCount > 0 {
                NoticeBanner(tone: .waiting,
                             title: startedCount == 1 ? "1 task is already started" : "\(startedCount) tasks are already started",
                             message: "A reset never closes work in progress. If it is no longer wanted, open its card and close it there.",
                             style: .compact)
            }

            if !closing.isEmpty {
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
            if let issue = card.issue {
                Toggle("", isOn: Binding(get: { closing.contains(issue) },
                                         set: { if $0 { closing.insert(issue) } else { closing.remove(issue) } }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!model.canRunDoors)
                    .frame(width: 18)
                    .accessibilityLabel("Close \(card.label) as not planned")
            } else if card.reset == .started {
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
                .foregroundStyle(card.issue == nil ? DeskColor.mutedInk : DeskColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(card.title)
            Text(rowNote(card))
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineLimit(1)
                .fixedSize()
            StatusPill(badge: StatusBadge(FindingRow.tone(of: card.column), card.column.title))
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
    }

    private func rowNote(_ card: FiledCard) -> String {
        switch card.reset {
        case .closable: return closing.contains(card.issue ?? -1) ? "closes" : "kept"
        case .started: return "started · kept"
        case .done: return "kept"
        case .localOnly: return "docs/backlog/ · kept"
        }
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var canConfirm: Bool {
        if !closing.isEmpty && trimmedReason.isEmpty { return false }
        return !options.isEmpty || !closing.isEmpty
    }

    private var reportsDetail: String {
        guard model.canRunDoors else { return "A sample project has no reports on disk." }
        switch olderReports.count {
        case 0: return "This project has one report or none, so there is nothing older to move."
        case 1: return "1 older report goes to the Trash; the newest stays. Recoverable from the Finder."
        default: return "\(olderReports.count) older reports go to the Trash; the newest stays. Recoverable from the Finder."
        }
    }

    private var confirmTitle: String {
        var parts: [String] = []
        if options.olderReports && !olderReports.isEmpty { parts.append("move to Trash") }
        if !closing.isEmpty { parts.append("close \(closing.count) task\(closing.count == 1 ? "" : "s")") }
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
        .onAppear { if !enabled { isOn.wrappedValue = false } }
    }

    private func reset() {
        var options = options
        options.closeIssues = closable.filter(closing.contains)
        options.closeReason = trimmedReason
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
