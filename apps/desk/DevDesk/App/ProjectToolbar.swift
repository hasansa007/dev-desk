import DeskCore
import SwiftUI

struct ProjectToolbar: ToolbarContent {
    let model: ProjectWindowModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.present(.openProject) } label: {
                Label("Open project", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
        }
        if let summary = model.snapshot?.activitySummary {
            ToolbarItem(placement: .primaryAction) {
                ActivitySummary(badge: summary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("View mode", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text("Focus").tag(ViewMode.focus)
                Text("Parallel").tag(ViewMode.parallel)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Ask about this project") { model.toggleInsights() }
                .buttonStyle(.borderedProminent)
                .tint(DeskColor.accent)
        }
    }
}

private struct ActivitySummary: View {
    let badge: StatusBadge

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(tone: badge.tone, pulses: badge.pulses)
            Text(badge.label)
        }
        .font(DeskFont.secondary)
        .foregroundStyle(DeskColor.navInk)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DeskColor.controlBorder))
        .accessibilityElement(children: .combine)
    }
}
