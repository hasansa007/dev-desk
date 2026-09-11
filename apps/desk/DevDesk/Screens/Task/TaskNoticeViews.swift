import AppKit
import DeskCore
import SwiftUI

struct TaskNoticeView: View {
    let model: ProjectWindowModel
    let notice: TaskNotice
    let offersHandoff: Bool

    var body: some View {
        switch notice {
        case .waitingForDecision(let title, let message, let decisionID):
            NoticeBanner(tone: .waiting, title: title, message: message) {
                Button("Answer decision") { model.openDecision(decisionID) }
                    .buttonStyle(DeskButtonStyle(kind: .primary))
                    .fixedSize()
            }
        case .externalConnection(let connection):
            TaskExternalConnectionPanel(model: model, connection: connection, offersHandoff: offersHandoff)
        }
    }
}

private struct TaskExternalConnectionPanel: View {
    let model: ProjectWindowModel
    let connection: ExternalConnection
    let offersHandoff: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panel
            if !connection.facts.isEmpty {
                SectionLabel("Repository facts")
                    .padding(.top, 16)
                KeyValueTable(rows: connection.facts)
                    .padding(.top, 8)
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(connection.title)
                .font(DeskFont.body.weight(.semibold))
                .foregroundStyle(DeskColor.ink)
            MarkdownText(connection.message, color: DeskColor.secondaryInk)
                .lineSpacing(4.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.top, 6)
            if !connection.levels.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(connection.levels, id: \.self) { level in
                        TaskConnectionLevelCard(level: level)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }
            HStack(spacing: 8) {
                if offersHandoff {
                    Button("Start with handoff…") { model.present(.handoff) }
                        .buttonStyle(DeskButtonStyle(kind: .primary))
                        .fixedSize()
                }
                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expandedCheckoutPath)])
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary))
                .fixedSize()
                .disabled(!checkoutExists)
                .help(checkoutExists ? "Reveal the checkout in Finder" : "This checkout does not exist on this Mac")
                if !connection.handoffNote.isEmpty {
                    Text(connection.handoffNote)
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.neutralChipFill, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DeskColor.border))
    }

    private var expandedCheckoutPath: String { (connection.checkoutPath as NSString).expandingTildeInPath }
    private var checkoutExists: Bool {
        !connection.checkoutPath.isEmpty && FileManager.default.fileExists(atPath: expandedCheckoutPath)
    }
}

private struct TaskConnectionLevelCard: View {
    let level: ConnectionLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(level.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
            Text(level.statusLabel)
                .font(DeskFont.secondary)
                .foregroundStyle(level.isAvailable ? DeskColor.tone(.running).foreground : DeskColor.faintInk)
            Text(level.detail)
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .deskCard(padding: 11)
        .opacity(level.isAvailable ? 1 : 0.75)
        .accessibilityElement(children: .combine)
    }
}
