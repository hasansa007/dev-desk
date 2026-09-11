import XCTest
@testable import DeskCore

@MainActor
final class InsightsConversationTests: XCTestCase {
    private func makeConfigured() -> InsightsConversation {
        let conversation = InsightsConversation(delay: .zero)
        conversation.configure(SampleData.studyHub().insights)
        return conversation
    }

    func testConfigureAppliesDemoScript() {
        let conversation = makeConfigured()
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.chips.count, 3)
        XCTAssertEqual(conversation.provider, "Codex")
    }

    func testEmptyDraftSendsNothing() {
        let conversation = makeConfigured()
        let before = conversation.messages.count
        conversation.draft = "   "
        conversation.send()
        XCTAssertEqual(conversation.messages.count, before)
    }

    func testSendAppendsUserMessageImmediatelyThenAppendsReply() async {
        let conversation = makeConfigured()
        let before = conversation.messages.count
        conversation.draft = "hi"
        conversation.send()
        XCTAssertEqual(conversation.messages.count, before + 1)
        XCTAssertEqual(conversation.messages.last?.isUser, true)
        XCTAssertTrue(conversation.isReading)

        await waitUntil { !conversation.isReading }
        XCTAssertFalse(conversation.isReading)
        XCTAssertEqual(conversation.messages.count, before + 2)
        XCTAssertNotNil(conversation.messages.last?.citation)
    }

    func testStartNewConversationEmptiesMessagesAndSwitchesReplyAuthor() async {
        let conversation = makeConfigured()
        conversation.startNewConversation(with: "Claude")
        XCTAssertTrue(conversation.messages.isEmpty)

        conversation.draft = "hello"
        conversation.send()
        await waitUntil { !conversation.isReading }
        XCTAssertEqual(conversation.messages.last?.author, "Insights · Claude")
    }

    func testUnavailableAvailabilitySendsNothing() {
        let conversation = InsightsConversation(delay: .zero)
        conversation.configure(.unavailable("no script"))
        conversation.draft = "hi"
        conversation.send()
        XCTAssertTrue(conversation.messages.isEmpty)
    }
}
