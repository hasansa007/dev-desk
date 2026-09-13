import DeskCore
import SwiftUI

/// A finding, as a card — the same anatomy a board card has (ADR 0024): a two-line title, a chip row, the
/// facts, and one band along the bottom carrying the note and the action. It opens the same dialog too.
struct FindingCard: View {
    let finding: Finding
    let model: ProjectWindowModel
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @State private var fileWidth: CGFloat = 0

    private var isIgnored: Bool { model.ignoredFindings.contains(finding.id) }

    /// Why filing cannot be asked for right now. A run of its own already going is one of the reasons: a
    /// second one would draft a second issue for the same finding, and the app can see that before it happens.
    private var blockedReason: String? {
        model.fileBlockedReason(key: finding.id, job: filing, agent: defaultConnection)
    }

    private var isInLocalBacklog: Bool { model.isInLocalBacklog(finding.id) }

    /// The run this card started, if it started one. Filing takes a door and a minute, and a card that shows
    /// nothing while that happens is a card whose button "does nothing".
    private var filing: BackgroundJob? {
        guard let jobs, case .local(let path) = model.ref else { return nil }
        return jobs.job(subject: finding.id, in: path)
    }

    /// The issue this finding is tracked by, when the report matched one. It is the only place a rating can
    /// come from: a survey rates nothing — `dev:survey` sets impact and complexity when it *files*.
    private var trackedTask: DeskTask? {
        guard let number = finding.reconcile?.candidateIssue else { return nil }
        return model.tasks.first { $0.issueNumber == number }
    }

    var body: some View {
        // Not a Button: the menu and the file control are its children, and a button inside a button never
        // gets its own clicks — which is how Start, then Stop, came to do nothing.
        content
            .overlay(alignment: .topTrailing) { menu.padding(7) }
            .overlay(alignment: .bottomTrailing) { fileButton.padding(11) }
            .onPreferenceChange(FileWidthKey.self) { fileWidth = $0 }
            .onTapGesture { model.openFinding(finding.id) }
            .opacity(isIgnored ? 0.62 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(finding.id), \(finding.title), \(finding.listDetail)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open") { model.openFinding(finding.id) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(finding.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
                .lineSpacing(2)
                .lineLimit(2)
                .truncationMode(.tail)
                // The menu is a top-trailing overlay and takes no layout space, so without this a long title
                // runs straight under it.
                .padding(.trailing, DeskMetric.cardMenuInset)
                .frame(maxWidth: .infinity, minHeight: DeskMetric.cardTitleHeight,
                       maxHeight: DeskMetric.cardTitleHeight, alignment: .topLeading)
            chips
                .padding(.top, 9)
            ratings
                .padding(.top, 7)
            // How far it was verified, on its own line. It shared the bottom band with the file control and
            // came out as "Code-inspected · confi…", which is the half that says nothing.
            Text(finding.verificationLabel)
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
                .padding(.top, 7)
            bottomBand
                .padding(.top, 9)
        }
        .frame(height: DeskMetric.findingCardHeight, alignment: .topLeading)
        .deskCard()
    }

    private var chips: some View {
        HStack(spacing: 6) {
            StatusPill(badge: StatusBadge(FindingTone.of(finding), finding.listDetail))
            if let area = finding.area {
                PropertyChip(area.rawValue, fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            }
            if isIgnored { StatusPill(badge: StatusBadge(.neutral, "Ignored")) }
            Spacer(minLength: 0)
        }
    }

    /// On every card, dashed where nothing rated it (ADR 0020). A finding is rated when it becomes an issue,
    /// so these stay dashes until it is filed and read back from the tracker.
    private var ratings: some View {
        HStack(spacing: 6) {
            PropertyChip("impact \(trackedTask?.impact ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            PropertyChip("complexity \(trackedTask?.complexity ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            Spacer(minLength: 0)
        }
    }

    /// Where it was found, or a dash — the same row on every card, so one card is not a different shape from
    /// the next (ADR 0020).
    private var sourceLine: String {
        guard let first = finding.locations.first else { return "—" }
        return finding.locations.count > 1 ? "\(first) +\(finding.locations.count - 1)" : first
    }

    /// Always present, so a card with something to say is not a different size from one without. A path
    /// truncates from the head, so what is left is the file rather than the first folder.
    private var bottomBand: some View {
        Text(filingNote?.text ?? sourceLine)
            .font(filingNote == nil ? DeskFont.mono(11) : .system(size: 11))
            .foregroundStyle(filingNote.map { $0.isWarning ? DeskColor.tone(.failed).dot : DeskColor.mutedInk }
                             ?? DeskColor.faintInk)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.trailing, fileWidth + 8)
            .frame(maxWidth: .infinity, minHeight: DeskButtonStyle.Size.mini.height,
                   maxHeight: DeskButtonStyle.Size.mini.height, alignment: .leading)
    }

    private var menu: some View {
        Menu {
            // What this finding's own run can do, when it has one. Offering "Add to backlog…" beside a card
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

    /// Filing is what you do with a finding, so it is on the card — the place Start sits on a task card.
    /// While its run is going the card says so, because the run itself has no other sign on this screen.
    @ViewBuilder private var fileButton: some View {
        if let filing, filing.state.isLive {
            StatusPill(badge: StatusBadge(.running, "Filing…", pulses: true))
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: FileWidthKey.self, value: proxy.size.width)
                })
        } else if let filing, case .asking = filing.state {
            Button("Answer…") { showRun(filing) }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .mini))
                .help("The run stopped to ask something; it is waiting in Terminals")
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: FileWidthKey.self, value: proxy.size.width)
                })
        } else if isInLocalBacklog {
            StatusPill(badge: StatusBadge(.info, "In backlog"))
                .help("Filed to docs/backlog/ — it is on the board")
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: FileWidthKey.self, value: proxy.size.width)
                })
        } else if !isIgnored {
            Button { file() } label: {
                Label("Backlog", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            .disabled(blockedReason != nil)
            .help(blockedReason ?? model.backlogDestination)
            .accessibilityLabel("Add \(finding.id) to the backlog")
            .background(GeometryReader { proxy in
                Color.clear.preference(key: FileWidthKey.self, value: proxy.size.width)
            })
        }
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

    /// What the run left behind, under the title: the only place a failed filing could ever be seen from here.
    private var filingNote: (text: String, isWarning: Bool)? {
        guard let filing else { return nil }
        switch filing.state {
        case .starting, .running: return ("Filing this as an issue…", false)
        case .asking: return ("The run is waiting for an answer in Terminals", false)
        case .ended(let text, let failed): return (failed ? "Filing failed: \(text)" : "Filed — see the board", failed)
        }
    }
}

/// The file control is an overlay, so the note sharing its band has to be told how much room it takes.
private struct FileWidthKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
