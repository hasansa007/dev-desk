import DeskCore
import SwiftUI

/// The strip's own measurements. In an extension rather than in `Tokens.swift` because the strip is the one
/// piece of chrome outside every project — it belongs with the strip, the way the board's column width does not.
extension DeskMetric {
    /// Narrow enough that it costs the work almost nothing, wide enough for a 36 pt badge and its gutter.
    static let stripWidth: CGFloat = 56
    static let stripBadge: CGFloat = 36
    static let stripBadgeRadius: CGFloat = 10
    static let stripGap: CGFloat = 8
}

/// The far-left column: Home on top, one badge per open project, `+` at the bottom (ADR 0050). It is what
/// replaced a window per project, so it carries what a window's absence would otherwise hide — an amber number
/// means runs are waiting on you in that project, a green dot means something is running there.
struct ProjectStrip: View {
    let workspace: Workspace

    var body: some View {
        VStack(spacing: DeskMetric.stripGap) {
            homeButton
            // Home is not one of the projects, so a line separates the place from the list.
            Rectangle().fill(DeskColor.divider).frame(width: 28, height: 1)
            ForEach(workspace.contextsInStripOrder) { context in
                projectButton(context)
            }
            Spacer(minLength: 8)
            openProjectButton
        }
        .padding(.vertical, 10)
        .frame(width: DeskMetric.stripWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DeskColor.strip)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private var homeButton: some View {
        Button { workspace.select(nil) } label: {
            Image(systemName: "house")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(workspace.isHome ? DeskColor.onColorInk : DeskColor.navInk)
                .frame(width: DeskMetric.stripBadge, height: DeskMetric.stripBadge)
                .background(workspace.isHome ? DeskColor.accent : DeskColor.surface,
                            in: RoundedRectangle(cornerRadius: DeskMetric.stripBadgeRadius))
                .overlay(alignment: .leading) { selectionMark(workspace.isHome) }
                .contentShape(RoundedRectangle(cornerRadius: DeskMetric.stripBadgeRadius))
        }
        .buttonStyle(.plain)
        .help("Home — what needs you")
        .accessibilityLabel("Home")
        .accessibilityAddTraits(workspace.isHome ? .isSelected : [])
    }

    private func projectButton(_ context: ProjectContext) -> some View {
        let isSelected = workspace.selection == context.ref
        return Button { workspace.select(context.ref) } label: {
            ProjectBadge(ref: context.ref, name: context.name, size: DeskMetric.stripBadge)
                .overlay(alignment: .leading) { selectionMark(isSelected) }
                // The count wins when both are true: a run that has stopped to ask you something is not
                // news that the project is busy, it is news that it is stuck on you.
                .overlay(alignment: .bottomTrailing) {
                    if context.waitingCount > 0 {
                        waitingCount(context.waitingCount)
                    } else if context.isRunning {
                        runningDot
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: DeskMetric.stripBadgeRadius))
        }
        .buttonStyle(.plain)
        .help(helpText(context))
        .accessibilityLabel(accessibilityLabel(context))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Close Project") { workspace.close(context.ref) }
        }
    }

    private var openProjectButton: some View {
        Button { workspace.isOpeningProject = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: DeskMetric.stripBadge, height: DeskMetric.stripBadge)
                .overlay {
                    RoundedRectangle(cornerRadius: DeskMetric.stripBadgeRadius)
                        .strokeBorder(DeskColor.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .contentShape(RoundedRectangle(cornerRadius: DeskMetric.stripBadgeRadius))
        }
        .buttonStyle(.plain)
        .help("Open project (⌘O)")
        .accessibilityLabel("Open project")
    }

    /// In the strip's own gutter, not flush with its edge: the prototype sits it at x=0, which on a macOS
    /// window is the rounded frame itself and cut the bar in half (2026-09-20, on screen). The badge keeps
    /// its full size whether or not it is selected, so the list does not shift as you switch projects.
    @ViewBuilder private func selectionMark(_ isSelected: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 3, topTrailingRadius: 3)
            .fill(isSelected ? DeskColor.ink : .clear)
            .frame(width: 4, height: 20)
            .offset(x: -6)
    }

    private func waitingCount(_ count: Int) -> some View {
        Text("\(count)")
            // Not mono: a mono digit in a 16 pt circle is a wide digit in a small circle.
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DeskColor.onColorInk)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(DeskColor.tone(.waiting).dot, in: Capsule())
            .overlay(Capsule().strokeBorder(DeskColor.strip, lineWidth: 2))
            .offset(x: 5, y: 4)
    }

    private var runningDot: some View {
        Circle()
            .fill(DeskColor.tone(.running).dot)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(DeskColor.strip, lineWidth: 2))
            .offset(x: 3, y: 3)
    }

    private func helpText(_ context: ProjectContext) -> String {
        if context.waitingCount > 0 { return "\(context.name) — \(context.waitingCount) waiting on you" }
        return context.isRunning ? "\(context.name) — running" : context.name
    }

    private func accessibilityLabel(_ context: ProjectContext) -> String {
        if context.waitingCount > 0 { return "\(context.name), \(context.waitingCount) waiting on you" }
        return context.isRunning ? "\(context.name), running" : context.name
    }
}
