import DeskCore
import SwiftUI

struct ChangesTab: View {
    let changes: Surface<ChangeSet>
    @State private var selectedFileID: String?

    var body: some View {
        SurfaceView(changes) { changeSet in
            if let firstFile = changeSet.files.first {
                let selected = changeSet.files.first { $0.id == selectedFileID } ?? firstFile
                HStack(alignment: .top, spacing: 14) {
                    fileColumn(changeSet, selectedID: selected.id)
                    DiffView(file: selected, diff: changeSet.diffs[selected.id])
                }
            } else {
                EmptyStateView(title: "No changes", message: changeSet.baseNote)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileColumn(_ changeSet: ChangeSet, selectedID: String) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Changed files · \(changeSet.files.count)")
                VStack(spacing: 0) {
                    ForEach(Array(changeSet.files.enumerated()), id: \.element.id) { index, file in
                        if index > 0 {
                            Rectangle()
                                .fill(DeskColor.rowDivider)
                                .frame(height: 1)
                        }
                        TaskChangedFileRow(file: file, isSelected: file.id == selectedID) { selectedFileID = file.id }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius - 1))
                .padding(1)
                .background(DeskColor.surface, in: cardShape)
                .overlay(cardShape.strokeBorder(DeskColor.border))
                .padding(.top, 8)
                MarkdownText(changeSet.baseNote, font: .system(size: 11), color: DeskColor.mutedInk)
                    .lineSpacing(3.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .frame(width: 290)
    }
}

private struct TaskChangedFileRow: View {
    let file: ChangedFile
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Text(file.displayPath)
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let additions = file.additions, let deletions = file.deletions {
                    Text(verbatim: "+\(additions)")
                        .foregroundStyle(DeskColor.tone(.running).foreground)
                        .fixedSize()
                    Text(verbatim: "−\(deletions)")
                        .foregroundStyle(DeskColor.tone(.failed).dot)
                        .fixedSize()
                } else {
                    Text("binary")
                        .foregroundStyle(DeskColor.mutedInk)
                        .fixedSize()
                }
            }
            .font(DeskFont.mono(11.5))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? DeskColor.tone(.info).fill : DeskColor.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.id)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        guard let additions = file.additions, let deletions = file.deletions else { return "\(file.id), binary" }
        return "\(file.id), \(additions) additions, \(deletions) deletions"
    }
}
