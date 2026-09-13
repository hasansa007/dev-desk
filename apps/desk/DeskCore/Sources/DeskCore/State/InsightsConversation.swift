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
    /// A live conversation runs a real agent through this; the demo path never touches it.
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private var pendingReply: Task<Void, Never>?

    public init(delay: Duration, runner: CommandRunner = ProcessRunner()) {
        self.delay = delay
        self.runner = runner
    }

    public var script: InsightsScript? {
        if case .demo(let script) = availability { return script }
        return nil
    }

    public var plan: InsightsAgentPlan? {
        if case .live(let plan) = availability { return plan }
        return nil
    }

    /// Whether there is anything to ask: a script to replay or an agent to run. Unavailable is the only case with neither.
    public var canAsk: Bool { script != nil || plan != nil }

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
        provider = script?.provider ?? plan?.provider ?? ""
    }

    public func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAsk, !text.isEmpty else { return }
        draft = ""
        if let script { ask(text, reply: script.freeformReply) } else { askAgent(text) }
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

    /// A real run of the insights door. It takes as long as it takes, a newer question cancels the one in flight, and a
    /// failure is said in the conversation rather than swallowed — the question was asked here, so the answer belongs here.
    private func askAgent(_ text: String) {
        guard let plan else { return }
        messages.append(InsightsMessage(author: "You", text: text, isUser: true))
        isReading = true
        pendingReply?.cancel()
        let author = "Insights · \(provider)"
        let agent = InsightsAgent(runner: runner, plan: plan)
        pendingReply = Task { [weak self] in
            let message: InsightsMessage
            do {
                let answer = try await agent.ask(text)
                message = InsightsMessage(author: author, text: answer.text, citation: answer.citation, isUser: false)
            } catch is CancellationError {
                return
            } catch {
                message = InsightsMessage(author: author, text: error.localizedDescription, isUser: false)
            }
            guard !Task.isCancelled, let self else { return }
            self.messages.append(message)
            self.isReading = false
        }
    }
}
