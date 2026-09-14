import DeskCore
import SwiftUI

/// A chat with the agent: a session in Sessions whose mode is Chat. It is not a terminal (ADR 0026) and hosts
/// none — it asks the CLI one question at a time, in `folder`, and reads the answer here; nothing is stored but
/// the turns, and no credential is ever handled (decision 14).
///
/// The session is the caller's, not this view's: the row that shows a chat collapses and the screen that lists
/// it is left and returned to, and what was said has to survive both.
struct ChatTab: View {
    let model: ProjectWindowModel
    let session: ChatSession
    /// Where each question is asked. Nil for a sample, which has no folder and so cannot chat.
    let folder: URL?
    @AppStorage(PreferenceKey.chatStyle) private var chatStyle = ChatStyle.bubbles
    /// The connection the composer's picker writes. Read here as well, so a pick re-resolves the agent at once:
    /// `AgentChoice.current` reads the preference itself, and would not redraw this view on its own.
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @State private var draft = ""
    /// The model to run, free text: the tool lists its own names, and Dev Desk stores none of them. Empty means
    /// the CLI's own default. A change applies to the next message, never to one already being answered.
    @State private var modelName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            if case .unavailable(let reason) = choice {
                NoticeBanner(tone: .failed, title: "There is no agent to chat with",
                             message: reason, style: .callout)
            }
            transcript
            composer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What answers, and as what

    /// The app's connection, resolved now — the same one "Start agent" would use, and the one the composer's
    /// picker selects, since that picker writes the same preference.
    private var choice: AgentChoice {
        _ = defaultConnection
        return AgentChoice.current(for: model.ref, connections: model.snapshot?.connections ?? [])
    }

    /// The picked connection as the CLI it runs, once the choice says it can be run at all.
    private var agent: AgentKind? {
        guard case .ready = choice else { return nil }
        return AgentLaunch.agent(forConnectionName: defaultConnection)
    }

    private var isSending: Bool { session.isSending }

    /// Why nothing can be asked: no folder, or no agent. Nil when a message would run.
    private var blockedReason: String? {
        if folder == nil { return "A sample has no folder to ask about." }
        if case .unavailable(let reason) = choice { return reason }
        return nil
    }

    private var controls: some View {
        HStack(spacing: 10) {
            SectionLabel("Chat")
            PropertyChip(agent.map(AgentLaunch.displayName) ?? "No connection",
                         tone: agent == nil ? .neutral : .info)
            if isSending {
                HStack(spacing: 6) {
                    StatusDot(tone: .info, pulses: true)
                    Text("Waiting for an answer…")
                }
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
            }
            Spacer(minLength: 8)
        }
    }

    // MARK: - The turns

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: chatStyle == .bubbles ? 10 : 6) {
                    if messages.isEmpty {
                        Text("Nothing asked yet. Each message runs the CLI once in \(folderLabel) and shows what it said.")
                            .font(DeskFont.body)
                            .foregroundStyle(DeskColor.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(messages) { message in
                        Group {
                            switch chatStyle {
                            case .bubbles: bubble(message)
                            case .transcript: line(message)
                            }
                        }
                        .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            // The row it sits in fixes the height; the transcript takes whatever is left after the controls.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: messages) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
        }
    }

    private var messages: [ChatMessage] { session.messages }

    private var folderLabel: String { folder.map { $0.lastPathComponent } ?? "this project" }

    /// A conversation: yours on the right in the accent's tint, the agent's on the left on the surface.
    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        let tone = DeskColor.tone(.info)
        let shape = RoundedRectangle(cornerRadius: 9)
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 60) }
            Group {
                if isUser {
                    Text(message.text).font(DeskFont.body).foregroundStyle(DeskColor.ink)
                } else {
                    MarkdownText(message.text)
                }
            }
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(alignment: .leading)
            .padding(10)
            .background(isUser ? tone.fill : DeskColor.surface, in: shape)
            .overlay(shape.strokeBorder(isUser ? tone.border : DeskColor.border))
            if !isUser { Spacer(minLength: 60) }
        }
    }

    /// The same turns as lines to read straight down, each named by who said it, the way a terminal reads.
    private func line(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(alignment: .top, spacing: 8) {
            Text(isUser ? "you>" : "agent>")
                .font(DeskFont.mono(12, weight: .semibold))
                .foregroundStyle(isUser ? DeskColor.accent : DeskColor.tone(.running).foreground)
            Text(message.text)
                .font(DeskFont.mono(12))
                .foregroundStyle(DeskColor.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Asking

    /// The shared composer, which owns the mode and connection chips and the model field; this view only says
    /// what a sent message does.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChatComposer(model: model, draft: $draft, modelName: $modelName,
                         blockedReason: blockedReason, isSending: isSending, onSend: send)
            // One run per message, and a run reads the repository to answer, which takes as long as it takes.
            Text(agent == nil
                 ? "Choose an installed connection from the chip above, or in Settings → Agents and defaults, to chat here."
                 : "Each message runs the CLI once through your login shell, which can take a few minutes.")
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineSpacing(3)
        }
    }

    private func send(_ text: String) {
        guard let agent, let folder, !isSending else { return }
        let name = modelName.trimmingCharacters(in: .whitespaces)
        Task { await session.send(text, agent: agent, model: name.isEmpty ? nil : name, folder: folder) }
    }
}
