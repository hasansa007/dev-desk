import Foundation

public struct InsightsMessage: Identifiable, Hashable {
    public var id: UUID
    public var author: String
    public var text: String
    public var citation: String?
    public var isUser: Bool
    public init(id: UUID = UUID(), author: String, text: String, citation: String? = nil, isUser: Bool) {
        self.id = id
        self.author = author
        self.text = text
        self.citation = citation
        self.isUser = isUser
    }
}

public struct InsightsReply: Hashable {
    public var text: String
    public var citation: String
    public init(text: String, citation: String) { self.text = text; self.citation = citation }
}

public struct InsightsQuickAction: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var reply: InsightsReply
    public var dockedOnly: Bool
    public init(id: String, title: String, reply: InsightsReply, dockedOnly: Bool = false) {
        self.id = id
        self.title = title
        self.reply = reply
        self.dockedOnly = dockedOnly
    }
}

public struct ContextChip: Identifiable, Hashable {
    public var id: String
    public var label: String
    public var isTask: Bool         // task chips use the info (blue) tone
    public init(id: String, label: String, isTask: Bool = false) {
        self.id = id
        self.label = label
        self.isTask = isTask
    }
}

public struct InsightsScript: Hashable {
    public var provider: String
    public var providers: [String]
    public var chips: [ContextChip]
    public var initial: [InsightsMessage]
    public var freeformReply: InsightsReply
    public var quickActions: [InsightsQuickAction]
    public var footnote: String
    public init(provider: String, providers: [String], chips: [ContextChip], initial: [InsightsMessage],
                freeformReply: InsightsReply, quickActions: [InsightsQuickAction], footnote: String) {
        self.provider = provider
        self.providers = providers
        self.chips = chips
        self.initial = initial
        self.freeformReply = freeformReply
        self.quickActions = quickActions
        self.footnote = footnote
    }
}

public enum InsightsAvailability: Hashable {
    case demo(InsightsScript)
    case unavailable(String)
}
