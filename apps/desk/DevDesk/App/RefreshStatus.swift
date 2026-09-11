import DeskCore
import SwiftUI

/// A spinner while the project reloads, otherwise how long ago it did, beside a Reload button that does what ⌘R does.
struct RefreshStatus: View {
    let model: ProjectWindowModel

    var body: some View {
        HStack(spacing: 6) {
            if model.isRefreshing {
                ProgressView().controlSize(.small)
                Text("Updating…")
            } else if let loaded = model.lastLoadedAt {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text(ProjectWindowModel.updatedLabel(since: loaded, now: context.date))
                }
            }
            Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .help("Reload (⌘R)")
                .accessibilityLabel("Reload")
        }
        .font(DeskFont.secondary)
        .foregroundStyle(DeskColor.mutedInk)
    }
}
