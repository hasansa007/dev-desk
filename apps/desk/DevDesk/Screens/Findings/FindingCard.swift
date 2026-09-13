import DeskCore
import SwiftUI

/// A finding, as a card — the same anatomy a board card has (ADR 0024): a two-line title, a chip row, the
/// facts, and one band along the bottom carrying the note and the action. It opens the same dialog too.
struct FindingCard: View {
    let finding: Finding
    let model: ProjectWindowModel
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"
    @State private var fileWidth: CGFloat = 0

    private var isIgnored: Bool { model.ignoredFindings.contains(finding.id) }
    private var blockedReason: String? { model.runBlockedReason(agent: defaultConnection) }

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
        .frame(height: DeskMetric.cardContentHeight, alignment: .topLeading)
        .deskCard()
    }

    private var chips: some View {
        HStack(spacing: 6) {
            StatusPill(badge: StatusBadge(FindingTone.of(finding), finding.listDetail))
            if isIgnored { StatusPill(badge: StatusBadge(.neutral, "Ignored")) }
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
        Text(sourceLine)
            .font(DeskFont.mono(11))
            .foregroundStyle(DeskColor.faintInk)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.trailing, fileWidth + 8)
            .frame(maxWidth: .infinity, minHeight: DeskButtonStyle.Size.mini.height,
                   maxHeight: DeskButtonStyle.Size.mini.height, alignment: .leading)
    }

    private var menu: some View {
        Menu {
            Button("Add to backlog…") { file() }
                .disabled(blockedReason != nil)
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
    @ViewBuilder private var fileButton: some View {
        if !isIgnored {
            Button { file() } label: {
                Label("Backlog", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            .disabled(blockedReason != nil)
            .help(blockedReason ?? "Queues dev:create-issue for this finding, in the background")
            .accessibilityLabel("Add \(finding.id) to the backlog")
            .background(GeometryReader { proxy in
                Color.clear.preference(key: FileWidthKey.self, value: proxy.size.width)
            })
        }
    }

    private func file() {
        model.fileFromReport(jobs: jobs, itemID: finding.id, description: finding.backlogDescription,
                             agent: defaultConnection)
    }
}

/// The file control is an overlay, so the note sharing its band has to be told how much room it takes.
private struct FileWidthKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
