import SwiftUI

/// Inline markdown; links open through the environment's `openURL`, so `desk://` links route in-app.
struct MarkdownText: View {
    let markdown: String
    let font: Font
    let color: Color

    init(_ markdown: String, font: Font = DeskFont.body, color: Color = DeskColor.ink) {
        self.markdown = markdown
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(color)
            .tint(DeskColor.accent)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var text = try? AttributedString(markdown: markdown, options: options) else {
            return AttributedString(markdown)
        }
        let codeRanges = text.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for range in codeRanges {
            text[range].font = font.monospaced()
        }
        let linkRanges = text.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            text[range].foregroundColor = DeskColor.accent
        }
        return text
    }
}
