import DeskCore
import SwiftUI

struct ActivityEventRow: View {
    let event: ActivityEvent
    var onFollowUp: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.time)
                .font(DeskFont.mono(11))
                .foregroundStyle(DeskColor.faintInk)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    MarkdownText(event.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if event.offersFollowUp, let onFollowUp {
                        Button("Request follow-up", action: onFollowUp)
                            .buttonStyle(LinkButtonStyle())
                            .font(DeskFont.body)
                    }
                }
                if let detail = event.detail {
                    ToolDetailDisclosure(detail: detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ToolDetailDisclosure: View {
    let detail: ToolDetail
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(detail.lines.joined(separator: "\n"))
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.secondaryInk)
                .lineSpacing(4.5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Button(detail.title) { isExpanded.toggle() }
                .buttonStyle(LinkButtonStyle())
                .font(DeskFont.secondary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DeskColor.border))
    }
}
