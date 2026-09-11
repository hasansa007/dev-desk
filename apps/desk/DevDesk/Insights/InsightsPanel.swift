import DeskCore
import SwiftUI

enum InsightsPlacement { case floating, docked }

struct InsightsPanel: View {
    @Bindable var model: ProjectWindowModel
    let placement: InsightsPlacement
    @Bindable private var insights: InsightsConversation
    @FocusState private var draftFocused: Bool
    @State private var pendingProvider: String?

    init(model: ProjectWindowModel, placement: InsightsPlacement) {
        self.model = model
        self.placement = placement
        self.insights = model.insights
    }

    var body: some View {
        let core = VStack(spacing: 0) {
            header
            chipsRow
            if let reason = insights.unavailableReason {
                NoticeBanner(tone: .neutral, title: "No agent connection", message: reason)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                messagesArea
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeskColor.surface)

        switch placement {
        case .floating:
            core
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(DeskColor.controlBorder))
                .shadow(color: .black.opacity(0.28), radius: 60, x: 0, y: 24)
        case .docked:
            core
                .overlay(alignment: .leading) { Rectangle().fill(DeskColor.border).frame(width: 1) }
                .shadow(color: .black.opacity(0.06), radius: 24, x: -8, y: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Insights").font(.system(size: 13, weight: .semibold)).foregroundStyle(DeskColor.ink)
            Text(placement == .floating ? "Floating over the workspace" : "Nonmodal · docked")
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 8)
            Button(placement == .floating ? "Dock" : "Float") {
                placement == .floating ? model.dockInsights() : model.floatInsights()
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            Button("Close") { model.toggleInsights() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    private var chipsRow: some View {
        HStack(spacing: 6) {
            ForEach(displayChips) { chip in
                chipView(chip, removable: insights.script != nil)
            }
            if let script = insights.script {
                Spacer(minLength: 8)
                providerMenu(script)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
        .confirmationDialog("Start a new conversation with \(pendingProvider ?? "")?",
                             isPresented: Binding(get: { pendingProvider != nil }, set: { if !$0 { pendingProvider = nil } }),
                             titleVisibility: .visible) {
            Button("Start new conversation") {
                if let pendingProvider { insights.startNewConversation(with: pendingProvider) }
                pendingProvider = nil
            }
            Button("Cancel", role: .cancel) { pendingProvider = nil }
        } message: {
            Text("The current conversation stays as it is; switching providers never continues it.")
        }
    }

    private var displayChips: [ContextChip] {
        guard insights.script != nil else {
            return [ContextChip(id: "project", label: "Project \(model.snapshot?.project.name ?? projectDisplayName(model.ref))")]
        }
        return insights.chips
    }

    private func chipView(_ chip: ContextChip, removable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(chip.label)
            if removable {
                Button { insights.removeChip(chip) } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(chip.label)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(chip.isTask ? DeskColor.tone(.info).foreground : DeskColor.secondaryInk)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(chip.isTask ? DeskColor.tone(.info).fill : DeskColor.neutralChipFill, in: Capsule())
        .overlay(Capsule().strokeBorder(chip.isTask ? DeskColor.tone(.info).border : DeskColor.border))
    }

    private func providerMenu(_ script: InsightsScript) -> some View {
        Menu {
            ForEach(script.providers, id: \.self) { provider in
                Button(provider) { requestSwitch(to: provider) }
            }
        } label: {
            Text("\(insights.provider) ▾").font(.system(size: 11)).foregroundStyle(DeskColor.mutedInk)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func requestSwitch(to provider: String) {
        guard provider != insights.provider else { return }
        pendingProvider = provider
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(insights.messages) { message in
                        messageBubble(message).id(message.id)
                    }
                    if insights.isReading {
                        readingIndicator
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: insights.messages) { _, _ in scrollToBottom(proxy) }
            .onChange(of: insights.isReading) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if insights.isReading {
                proxy.scrollTo("reading-indicator", anchor: .bottom)
            } else if let last = insights.messages.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    private func messageBubble(_ message: InsightsMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.author).font(.system(size: 11)).foregroundStyle(DeskColor.mutedInk)
            Text(message.text).font(DeskFont.body).foregroundStyle(DeskColor.ink)
            if let citation = message.citation {
                Text(citation).font(DeskFont.mono(11.5)).foregroundStyle(DeskColor.accent)
            }
        }
        .lineSpacing(3)
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.isUser ? DeskColor.neutralChipFill2 : DeskColor.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(message.isUser ? Color.clear : DeskColor.border))
    }

    private var readingIndicator: some View {
        HStack(spacing: 7) {
            StatusDot(tone: .info, pulses: true, size: 7)
            Text("Reading evidence: 3 files, 1 finding…")
        }
        .font(DeskFont.secondary)
        .foregroundStyle(DeskColor.mutedInk)
        .id("reading-indicator")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let script = insights.script {
                let actions = script.quickActions.filter { !$0.dockedOnly || placement == .docked }
                if !actions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(actions) { action in
                            Button(action.title) { insights.run(action) }
                                .buttonStyle(QuickActionButtonStyle())
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Ask about this project", text: $insights.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(draftFocused ? DeskColor.accent : DeskColor.controlBorder, lineWidth: draftFocused ? 2 : 1))
                    .focused($draftFocused)
                    .onSubmit { insights.send() }
                    .disabled(insights.script == nil)
                Button("Send") { insights.send() }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                    .disabled(insights.script == nil || insights.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(insights.script?.footnote ?? "Exploration is read-only.")
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineSpacing(3)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}

private struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(DeskColor.ink)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DeskColor.controlBorder))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// `ProjectRef.displayName` lives in the App layer, outside this task's typecheck baseline.
private func projectDisplayName(_ ref: ProjectRef) -> String {
    switch ref {
    case .sample(let project): return project.title
    case .local(let path): return URL(fileURLWithPath: path).lastPathComponent
    }
}

/// Wraps its children onto new rows instead of clipping or scrolling horizontally.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct InsightsPanel_Previews: PreviewProvider {
    static var previews: some View {
        InsightsPreviewHost()
    }

    private struct InsightsPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            Group {
                InsightsPanel(model: model, placement: .floating)
                    .frame(width: DeskMetric.insightsFloatingSize.width, height: DeskMetric.insightsFloatingSize.height)
                InsightsPanel(model: model, placement: .docked)
                    .frame(width: DeskMetric.insightsDockedWidth, height: 600)
            }
            .task { await model.load() }
        }
    }
}
