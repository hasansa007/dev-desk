import DeskCore
import SwiftUI

/// One control, no prose: a ring that drains toward the next automatic reload, and a click that reloads now.
/// The words that used to sit in the toolbar ("Updated 30 s ago") live in the tooltip instead.
struct RefreshStatus: View {
    let model: ProjectWindowModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = remaining(at: context.date)
            Button { Task { await model.load() } } label: {
                ZStack {
                    Circle().strokeBorder(DeskColor.border, lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: remaining / ProjectWindowModel.refreshSeconds)
                        .stroke(DeskColor.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(model.isRefreshing ? DeskColor.accent : DeskColor.mutedInk)
                }
                .frame(width: 17, height: 17)
                .padding(3)
                .contentShape(Circle())
                .opacity(model.isRefreshing ? 0.55 : 1)
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help(help(remaining, now: context.date))
            .accessibilityLabel("Reload")
            .accessibilityValue(help(remaining, now: context.date))
        }
    }

    /// Seconds until the next automatic reload; a project that has never loaded shows a full ring.
    private func remaining(at now: Date) -> Double {
        guard let loaded = model.lastLoadedAt else { return ProjectWindowModel.refreshSeconds }
        let left = ProjectWindowModel.refreshSeconds - now.timeIntervalSince(loaded)
        return min(max(left, 0), ProjectWindowModel.refreshSeconds)
    }

    /// Both halves of what the toolbar used to say out loud, now that the ring says it without words.
    private func help(_ remaining: Double, now: Date) -> String {
        if model.isRefreshing { return "Reloading…" }
        let seconds = Int(remaining.rounded())
        let next = seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
        let ago = model.lastLoadedAt.map { ProjectWindowModel.updatedLabel(since: $0, now: now) }
        return ([ago, "reloads in \(next)"].compactMap { $0 }.joined(separator: " · ")) + ". Click to reload now (⌘R)."
    }
}
