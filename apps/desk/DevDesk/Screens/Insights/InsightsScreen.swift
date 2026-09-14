import DeskCore
import SwiftUI

/// Asking about the project is a place you go, not a panel over something else: history on the left, the
/// conversation down the middle, the composer along the bottom. Architecture is the same question drawn rather
/// than asked, so it is a tab here and not a destination of its own.
struct InsightsScreen: View {
    @Bindable var model: ProjectWindowModel
    @Bindable private var insights: InsightsConversation
    @FocusState private var composerFocused: Bool
    @State private var tab = Tab.chat
    @State private var diagrams: [ArchDiagram] = []
    @State private var selectedDiagramID: String?

    private enum Tab: String, CaseIterable {
        case chat = "Chat", architecture = "Architecture"
    }

    init(model: ProjectWindowModel) {
        self.model = model
        self.insights = model.insights
    }

    private var repositoryRoot: String? { model.snapshot?.repositoryRoot }
    private var selectedDiagram: ArchDiagram? {
        diagrams.first { $0.id == selectedDiagramID } ?? diagrams.first
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            VStack(spacing: 0) {
                header
                DialogTabBar(titles: Tab.allCases.map(\.rawValue), selected: tab.rawValue) { title in
                    if let next = Tab(rawValue: title) { tab = next }
                }
                if tab == .chat {
                    conversation
                    composer
                } else {
                    architecture
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DeskColor.canvas)
        // The folder is read when the project is, not on every redraw: a pane that lists files must not list them in body.
        .task(id: repositoryRoot) {
            diagrams = repositoryRoot.map(ArchDiagrams.list) ?? []
            if selectedDiagramID == nil { selectedDiagramID = diagrams.first?.id }
        }
    }

    @ViewBuilder private var rail: some View {
        if tab == .chat { historyRail } else { diagramRail }
    }

    /// The diagrams `dev:arch` wrote, by name. The app lists and shows them; it never draws one.
    private var diagramRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Diagrams")
                .font(DeskFont.body.weight(.semibold))
                .foregroundStyle(DeskColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
                .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }

            if diagrams.isEmpty {
                Text("No diagrams yet")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(diagrams) { diagram in
                            Button { selectedDiagramID = diagram.id } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(diagram.title)
                                        .font(DeskFont.secondary)
                                        .foregroundStyle(DeskColor.ink)
                                        .lineLimit(2)
                                    Text(diagram.url.lastPathComponent)
                                        .font(DeskFont.mono(11))
                                        .foregroundStyle(DeskColor.faintInk)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
                                .background(selectedDiagram?.id == diagram.id ? DeskColor.tone(.info).fill : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedDiagram?.id == diagram.id ? .isSelected : [])
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 248, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    @ViewBuilder private var architecture: some View {
        if let diagram = selectedDiagram {
            WebView(file: diagram.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack {
                Spacer(minLength: 0)
                NoticeBanner(tone: .neutral, title: "No diagrams yet",
                             message: "dev:arch draws this project and writes each diagram to docs/arch/ as a standalone HTML file. Run it, and they appear here.")
                    .frame(maxWidth: 560)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var historyRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Chat history").font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                Spacer(minLength: 4)
                Button { insights.startNewConversation(with: insights.provider) } label: {
                    Image(systemName: "plus").imageScale(.small).foregroundStyle(DeskColor.mutedInk)
                }
                .buttonStyle(.plain)
                .help("Start a new conversation")
                .accessibilityLabel("New conversation")
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }

            if insights.messages.isEmpty {
                Text("No conversations yet")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(14)
            } else {
                Button {} label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(insights.messages.first?.text ?? "Conversation")
                            .font(DeskFont.secondary)
                            .foregroundStyle(DeskColor.ink)
                            .lineLimit(2)
                        Text("\(insights.messages.count) messages · \(insights.provider)")
                            .font(.system(size: 11))
                            .foregroundStyle(DeskColor.faintInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
                    .background(DeskColor.tone(.info).fill)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // One conversation is kept per project window; the rail lists it rather than pretending to a history.
                .help("Dev Desk keeps the current conversation only")
            }
            Spacer(minLength: 0)
        }
        .frame(width: 248, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(DeskColor.accent)
                .frame(width: 28, height: 28)
                .background(DeskColor.tone(.info).fill, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            VStack(alignment: .leading, spacing: 1) {
                Text("Insights").font(DeskFont.section).foregroundStyle(DeskColor.ink)
                Text("Ask questions about this project")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            Spacer(minLength: 8)
            if let script = insights.script {
                Menu {
                    ForEach(script.providers, id: \.self) { provider in
                        Button(provider) { insights.startNewConversation(with: provider) }
                    }
                } label: {
                    Text("\(insights.provider) ▾").font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Switching provider starts a new conversation; it never relabels this one")
            }
            Button("New chat") { insights.startNewConversation(with: insights.provider) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    @ViewBuilder private var conversation: some View {
        if let reason = insights.unavailableReason {
            VStack {
                Spacer(minLength: 0)
                NoticeBanner(tone: .neutral, title: "No agent connection", message: reason)
                    .frame(maxWidth: 560)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else if insights.messages.isEmpty {
            emptyState
        } else {
            messages
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "bubble.left")
                .font(.system(size: 22))
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: 56, height: 56)
                .background(DeskColor.neutralChipFill, in: Circle())
            Text("Start a conversation")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
                .padding(.top, 4)
            Text("Ask about the architecture, what the evidence says, or what to do next. Answers cite what they read.")
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if let script = insights.script {
                FlowLayout(spacing: 6) {
                    ForEach(script.quickActions) { action in
                        Button(action.title) { insights.run(action) }
                            .buttonStyle(SuggestionButtonStyle())
                    }
                }
                .frame(maxWidth: 620)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(insights.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if insights.isReading {
                        HStack(spacing: 7) {
                            StatusDot(tone: .info, pulses: true, size: 7)
                            Text("Reading evidence…")
                        }
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.mutedInk)
                        .id("reading")
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
            }
            .onChange(of: insights.messages) { _, _ in
                withAnimation { proxy.scrollTo(insights.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: insights.isReading) { _, reading in
                if reading { withAnimation { proxy.scrollTo("reading", anchor: .bottom) } }
            }
        }
    }

    private func bubble(_ message: InsightsMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.author).font(.system(size: 11)).foregroundStyle(DeskColor.mutedInk)
            Text(message.text).font(DeskFont.body).foregroundStyle(DeskColor.ink).padding(.top, 4)
            if let citation = message.citation {
                Text(citation).font(DeskFont.mono(11.5)).foregroundStyle(DeskColor.accent).padding(.top, 6)
            }
        }
        .lineSpacing(3)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.isUser ? DeskColor.neutralChipFill2 : DeskColor.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DeskColor.border))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about this project…", text: $insights.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DeskFont.body)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(composerFocused ? DeskColor.accent : DeskColor.controlBorder,
                                      lineWidth: composerFocused ? 2 : 1))
                    .focused($composerFocused)
                    .onSubmit { insights.send() }
                    .disabled(!insights.canAsk)
                Button("Send") { insights.send() }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .composer))
                    .disabled(!insights.canAsk || insights.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(insights.script?.footnote ?? liveFootnote)
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineSpacing(3)
        }
        .frame(maxWidth: 940)
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 12, leading: 24, bottom: 14, trailing: 24))
        .background(DeskColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    /// A real run reads the repository through the insights door, which takes as long as reading takes; saying so
    /// under the composer is the only warning a question needs.
    private var liveFootnote: String {
        guard let plan = insights.plan else { return "Press Enter to send. Exploration is read-only." }
        return "Press Enter to send. \(plan.provider) reads this repository to answer, which can take a few minutes. Exploration is read-only."
    }
}

private struct SuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DeskFont.secondary)
            .foregroundStyle(DeskColor.ink)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct InsightsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost().frame(width: 1180, height: 800)
    }

    private struct PreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            InsightsScreen(model: model)
                .task {
                    await model.load()
                    model.go(.insights)
                }
        }
    }
}
