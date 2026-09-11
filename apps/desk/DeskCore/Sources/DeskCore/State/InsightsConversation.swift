import Foundation
import Observation

@MainActor
@Observable
public final class InsightsConversation {
    public private(set) var availability: InsightsAvailability = .unavailable("")
    public private(set) var messages: [InsightsMessage] = []
    public private(set) var isReading = false
    public private(set) var provider = ""
    public var chips: [ContextChip] = []
    public var draft = ""

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var pendingReply: Task<Void, Never>?

    public init(delay: Duration) { self.delay = delay }

    public var script: InsightsScript? {
        if case .demo(let script) = availability { return script }
        return nil
    }

    public var unavailableReason: String? {
        if case .unavailable(let reason) = availability { return reason }
        return nil
    }

    public func configure(_ availability: InsightsAvailability) {
        self.availability = availability
        pendingReply?.cancel()
        isReading = false
        messages = script?.initial ?? []
        chips = script?.chips ?? []
        provider = script?.provider ?? ""
    }

    public func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let script, !text.isEmpty else { return }
        draft = ""
        ask(text, reply: script.freeformReply)
    }

    public func run(_ action: InsightsQuickAction) { ask(action.title, reply: action.reply) }

    public func removeChip(_ chip: ContextChip) { chips.removeAll { $0.id == chip.id } }

    /// Switching providers starts a new conversation explicitly; it never relabels the old one.
    public func startNewConversation(with provider: String) {
        pendingReply?.cancel()
        isReading = false
        messages = []
        self.provider = provider
    }

    private func ask(_ text: String, reply: InsightsReply) {
        guard script != nil else { return }
        messages.append(InsightsMessage(author: "You", text: text, isUser: true))
        isReading = true
        pendingReply?.cancel()
        let author = "Insights · \(provider)"
        pendingReply = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.messages.append(InsightsMessage(author: author, text: reply.text, citation: reply.citation, isUser: false))
            self.isReading = false
        }
    }
}
