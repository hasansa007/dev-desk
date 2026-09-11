import DeskCore
import SwiftUI

struct DiffView: View {
    let file: ChangedFile
    let diff: FileDiff?

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
        VStack(spacing: 0) {
            Text(diff?.path ?? file.id)
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(DeskColor.headerFill)
            Rectangle()
                .fill(DeskColor.border)
                .frame(height: 1)
            if let diff, !diff.hunks.isEmpty {
                lines(TaskDiffRow.rows(for: diff))
                if diff.truncated {
                    Rectangle()
                        .fill(DeskColor.border)
                        .frame(height: 1)
                    Text("Diff truncated at 1,500 lines.")
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(DeskColor.headerFill)
                }
            } else {
                Text("No preview for this file.")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.faintInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius - 1))
        .padding(1)
        .background(DeskColor.surface, in: cardShape)
        .overlay(cardShape.strokeBorder(DeskColor.border))
    }

    private func lines(_ rows: [TaskDiffRow]) -> some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        Text(row.text)
                            .foregroundStyle(row.ink)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(minWidth: proxy.size.width, maxWidth: .infinity, minHeight: 11.5 * 1.7, alignment: .leading)
                            .background(row.fill)
                    }
                }
                .font(DeskFont.mono(11.5))
                .textSelection(.enabled)
                .padding(.vertical, 8)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
    }
}

private struct TaskDiffRow: Identifiable {
    let id: Int
    let text: String
    let ink: Color
    let fill: Color

    static func rows(for diff: FileDiff) -> [TaskDiffRow] {
        var rows: [TaskDiffRow] = []
        for hunk in diff.hunks {
            rows.append(TaskDiffRow(id: rows.count, text: hunk.header, ink: DeskColor.faintInk, fill: .clear))
            for line in hunk.lines {
                rows.append(row(line, id: rows.count))
            }
        }
        return rows
    }

    private static func row(_ line: DiffLine, id: Int) -> TaskDiffRow {
        switch line.kind {
        case .context:
            return TaskDiffRow(id: id, text: "  " + line.text, ink: DeskColor.secondaryInk, fill: .clear)
        case .deletion:
            return TaskDiffRow(id: id, text: "- " + line.text, ink: DeskColor.diffDeleteInk, fill: DeskColor.diffDeleteFill)
        case .addition:
            return TaskDiffRow(id: id, text: "+ " + line.text, ink: DeskColor.diffAddInk, fill: DeskColor.diffAddFill)
        }
    }
}
