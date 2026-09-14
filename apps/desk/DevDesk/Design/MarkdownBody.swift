import SwiftUI

/// Block markdown: headings, paragraphs, lists, and quotes. `MarkdownText` reads inline syntax only,
/// so a `## Goal` or a `- item` pasted from an issue body arrived on screen as its own source text.
/// Every block's inline content still runs through `MarkdownText.attributed`, which keeps bold, code
/// spans, and links identical to everywhere else in the app.
struct MarkdownBody: View {
    let markdown: String
    let font: Font
    let color: Color

    init(_ markdown: String, font: Font = DeskFont.body, color: Color = DeskColor.ink) {
        self.markdown = markdown
        self.font = font
        self.color = color
    }

    var body: some View {
        let blocks = MarkdownBlock.parse(markdown)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, index == 0 ? 0 : block.spacing(after: blocks[index - 1]))
            }
        }
        .tint(DeskColor.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            let headingFont = Self.headingFont(level)
            inline(text, font: headingFont, color: color)
        case let .paragraph(text):
            inline(text, font: font, color: color)
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DeskColor.border)
                    .frame(width: 2)
                inline(text, font: font, color: DeskColor.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        case let .listItem(item):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(item.marker)
                    .font(font)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .monospacedDigit()
                inline(item.text, font: font, color: color)
            }
            .padding(.leading, CGFloat(item.depth) * 15)
        }
    }

    /// A hanging indent needs the text to claim the rest of the row, so every block ends the same way.
    private func inline(_ text: String, font: Font, color: Color) -> some View {
        Text(MarkdownText.attributed(text, font: font))
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(4.6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 16, weight: .semibold)
        case 2: .system(size: 15, weight: .semibold)
        case 3: .system(size: 14, weight: .semibold)
        default: .system(size: 13, weight: .semibold)
        }
    }
}

/// What one pass over the source lines can tell apart. Anything it cannot name stays a paragraph.
private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case listItem(ListItem)

    struct ListItem {
        let marker: String
        let text: String
        let depth: Int
    }

    /// Blank lines close a block; consecutive plain lines join into one paragraph, keeping their
    /// newlines the way GitHub does rather than collapsing them into spaces.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
            } else if let item = listItem(line, trimmed: trimmed) {
                flush()
                blocks.append(.listItem(item))
            } else if trimmed.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
        }
        flush()
        return blocks
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes.count, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String, trimmed: String) -> ListItem? {
        let depth = indentDepth(line)
        if let bullet = trimmed.first, "-*+".contains(bullet), trimmed.dropFirst().first == " " {
            let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            return ListItem(marker: "•", text: text, depth: depth)
        }
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")", rest.dropFirst().first == " " else {
            return nil
        }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return ListItem(marker: "\(digits).", text: text, depth: depth)
    }

    /// Two spaces per level is the common hand-written nesting; a tab counts as one level.
    private static func indentDepth(_ line: String) -> Int {
        var columns = 0
        for character in line {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += 2
            } else {
                break
            }
        }
        return min(columns / 2, 4)
    }

    /// List rows sit closer to each other than to the prose around them, and a heading needs air.
    func spacing(after previous: MarkdownBlock) -> CGFloat {
        if case .listItem = self, case .listItem = previous { return 4 }
        if case .heading = self { return 14 }
        return 8
    }
}
