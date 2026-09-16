import DeskCore
import SwiftUI

/// A finding, as a row of the survey list. It was a card in a grid, and a grid of 26 same-sized cards spent
/// most of each card repeating what its neighbours said — the verification label, and ratings no unfiled
/// finding can have — while cutting off the title, which is the finding. A row gives the title the width.
struct FindingRow: View {
    let finding: Finding
    let model: ProjectWindowModel
    @Binding var isChecked: Bool
    /// Set when the list is grouped by file: the header names the file, so the row says only where in it.
    var lines: String?
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @State private var isHovered = false

    enum Width {
        static let check: CGFloat = 18
        static let kind: CGFloat = 86
        static let area: CGFloat = 52
        static let source: CGFloat = 190
        static let action: CGFloat = 118
    }

    private var isIgnored: Bool { model.ignoredFindings.contains(finding.id) }

    /// Why filing cannot be asked for right now. A run of its own already going is one of the reasons: a
    /// second one would draft a second issue for the same finding, and the app can see that before it happens.
    private var blockedReason: String? {
        model.fileBlockedReason(key: finding.id, job: filing, agent: defaultConnection)
    }

    private var isInLocalBacklog: Bool { model.isInLocalBacklog(finding.id) }

    /// The run this row started, if it started one. Filing takes a door and a minute, and a row that shows
    /// nothing while that happens is a row whose button "does nothing".
    private var filing: BackgroundJob? {
        guard let jobs, case .local(let path) = model.ref else { return nil }
        return jobs.job(subject: finding.id, in: path)
    }

    var body: some View {
        // Not a Button: the checkbox, the menu and the file control are its children, and a button inside a
        // button never gets its own clicks.
        HStack(spacing: 10) {
            Toggle("", isOn: $isChecked)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Width.check)
                .accessibilityLabel("Select \(finding.id)")
            if lines != nil {
                StatusPill(badge: StatusBadge(FindingTone.of(finding), finding.listDetail))
                    .fixedSize()
            }
            Text(finding.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DeskColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(finding.title)
            if lines == nil {
                Text(finding.kind.rawValue)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .frame(width: Width.kind, alignment: .leading)
                Text(finding.area?.rawValue ?? "—")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .frame(width: Width.area, alignment: .leading)
            }
            sourceText
                .frame(width: lines == nil ? Width.source : 90, alignment: .leading)
            actions
                .frame(width: Width.action, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(isChecked ? DeskColor.accent.opacity(0.09) : (isHovered ? DeskColor.neutralChipFill2 : DeskColor.surface))
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { model.openFinding(finding.id) }
        .opacity(isIgnored ? 0.62 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(finding.id), \(finding.title), \(finding.listDetail)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { model.openFinding(finding.id) }
    }

    /// Where it was found. A filing that failed says so here instead, because this is the only place on the
    /// screen a failed run could be seen from.
    @ViewBuilder private var sourceText: some View {
        if let note = filingNote, note.isWarning {
            Text(note.text)
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.tone(.failed).dot)
                .lineLimit(1)
                .help(note.text)
        } else {
            Text(lines ?? sourceLine)
                .font(DeskFont.mono(11))
                .foregroundStyle(DeskColor.faintInk)
                .lineLimit(1)
                .truncationMode(.head)
                .help(finding.locations.joined(separator: "\n"))
        }
    }

    /// A path truncates from the head, so what is left is the file rather than the first folder.
    private var sourceLine: String {
        guard let first = finding.locations.first else { return "—" }
        return finding.locations.count > 1 ? "\(first) +\(finding.locations.count - 1)" : first
    }

    /// A state that has something to say is always shown; the Backlog button and the menu only on hover, so
    /// 26 rows are not 26 identical buttons.
    private var actions: some View {
        HStack(spacing: 4) {
            if let filing, filing.state.isLive {
                StatusPill(badge: StatusBadge(.running, "Filing…", pulses: true))
            } else if let filing, case .asking = filing.state {
                Button("Answer…") { showRun(filing) }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .mini))
                    .help("The run stopped to ask something; it is waiting in Terminals")
            } else if let task = model.boardTask(forFinding: finding.id) {
                // Where its card is now, not where it was filed: "In backlog" stayed on a finding whose task
                // had long since moved to In progress or Done.
                Button { model.openTask(task.id) } label: {
                    StatusPill(badge: StatusBadge(Self.tone(of: task.column), task.column.title))
                }
                .buttonStyle(.plain)
                .help("Its card is in \(task.column.title) — click to open it")
            } else if isInLocalBacklog || isFiledByRun {
                // Filed, but with no card on this board to point at — promoted to the tracker, say.
                StatusPill(badge: StatusBadge(.neutral, "Filed"))
                    .help("Filed as an issue")
            } else if isIgnored {
                StatusPill(badge: StatusBadge(.neutral, "Ignored"))
            } else if isHovered {
                Button { file() } label: {
                    Label("Backlog", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .disabled(blockedReason != nil)
                .help(blockedReason ?? model.backlogDestination)
                .accessibilityLabel("Add \(finding.id) to the backlog")
            }
            menu
                .opacity(isHovered ? 1 : 0)
        }
    }

    private var isFiledByRun: Bool {
        if let filing, case .ended(_, false) = filing.state { return true }
        return false
    }

    static func tone(of column: BoardColumn) -> StatusTone {
        switch column {
        case .queued, .inProgress: return .running
        case .review: return .waiting
        case .done: return .ended
        case .backlog, .readyForDev: return .neutral
        }
    }

    private var menu: some View {
        Menu {
            // What this finding's own run can do, when it has one. Offering "Add to backlog…" beside a row
            // that says "Filing…" is offering to file it twice.
            if let filing {
                switch filing.state {
                case .starting, .running:
                    Button("Show the run") { showRun(filing) }
                    Button("Stop filing") { jobs?.stop(filing.id) }
                case .asking:
                    Button("Answer the run…") { showRun(filing) }
                    Button("Stop filing") { jobs?.stop(filing.id) }
                case .ended(_, let failed):
                    if failed { Button("Try filing again") { file() } }
                    Button("Show what the run said") { showRun(filing) }
                }
            } else {
                Button("Add to backlog…") { file() }
                    .disabled(blockedReason != nil)
            }
            if isIgnored {
                Button("Stop ignoring") { model.restoreFinding(finding.id) }
            } else {
                Button("Ignore") { model.ignoreFinding(finding.id) }
            }
            Divider()
            Button("Open") { model.openFinding(finding.id) }
            if !finding.locations.isEmpty {
                Button("Copy source locations") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finding.locations.joined(separator: "\n"), forType: .string)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.medium)
                .foregroundStyle(DeskColor.mutedInk)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Actions for \(finding.id)")
    }

    private func file() {
        model.fileToBacklog(finding.backlogDraft, jobs: jobs, agent: defaultConnection)
    }

    /// Opens the run's own row in Terminals. A background run's id is its row's id there, so selecting it
    /// expands the one that belongs to this finding rather than landing on whatever was open.
    private func showRun(_ job: BackgroundJob) {
        model.selectedSessionID = job.id
        model.go(.terminals)
    }

    private var filingNote: (text: String, isWarning: Bool)? {
        guard let filing, case .ended(let text, true) = filing.state else { return nil }
        return ("Filing failed: \(text)", true)
    }
}
