import Foundation
import XCTest
@testable import DeskCore

final class MarkdownTests: XCTestCase {
    /// The parse `MarkdownText` runs in the app, so these tests see what a user would.
    private func render(_ markdown: String) throws -> AttributedString {
        try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }

    private func links(_ text: AttributedString) -> [URL] { text.runs.compactMap { $0.link } }

    func testBareURLsWwwHostsAndEmailsInEscapedTextRenderAsPlainText() throws {
        let untrusted = "see https://evil.example/x, www.evil.example, a@b.co and <https://x>"
        for escaped in [Markdown.escape(untrusted), Markdown.reason(untrusted)] {
            let rendered = try render(escaped)
            XCTAssertEqual(links(rendered), [], "untrusted text must not produce a link")
            XCTAssertEqual(String(rendered.characters), untrusted, "the visible text must not change")
        }
    }

    func testEveryAutolinkShapeStaysPlain() throws {
        let untrusted = [
            "https://evil.example/x", "www.evil.example", "a@b.co", "<https://x>",
            "HTTP://EVIL.EXAMPLE", "ftp://evil.example/x", "http://x", "WWW.evil.example", "(www.evil.example)",
            "_www.evil.example_", "mailto:a@b.co", "xmpp:a@b.co/res", "a+b@c.d.e", "a^@b.co", "(a@b.co)",
            "fatal: unable to access 'https://github.com/acme/app.git/': git@github.com: Permission denied (publickey).",
            "\\`*_[]<>~&^() stays literal",
        ]
        for text in untrusted {
            let rendered = try render(Markdown.escape(text))
            XCTAssertEqual(links(rendered), [], "\(text) rendered a link")
            XCTAssertEqual(String(rendered.characters), text)
        }
    }

    /// Mirrors the Findings run line, whose label is a report's file name.
    func testASurveyReportFileNameInTheRunLineStaysPlain() throws {
        for stem in ["www.evil.example", "[x](https:evil.example)", "https://evil.example", "a@b.co", "2026-09-30 · Report too large to read (over 1 MB)"] {
            let rendered = try render("Run · \(Markdown.escape(stem)) · rev `9c2e410`")
            XCTAssertEqual(links(rendered), [], "\(stem) rendered a link")
            XCTAssertEqual(String(rendered.characters), "Run · \(stem) · rev 9c2e410")
        }
    }

    func testLinksTheAppWritesStillWorkAroundAndAroundEscapedText() throws {
        let untrusted = "see https://evil.example, www.evil.example or a@b.co"
        let task59 = try XCTUnwrap(URL(string: "desk://task/59"))
        let sentence = try render("Blocked by [#59](desk://task/59) — \(Markdown.escape(untrusted))")
        XCTAssertEqual(Set(links(sentence)), [task59])
        XCTAssertEqual(String(sentence.characters), "Blocked by #59 — \(untrusted)")

        let task5 = try XCTUnwrap(URL(string: "desk://task/5"))
        let titled = try render("[\(Markdown.escape("Fix a@b.co"))](desk://task/5)")
        XCTAssertTrue(titled.runs.allSatisfy { $0.link == task5 }, "escaped text in a link's title must not break the link")
        XCTAssertEqual(String(titled.characters), "Fix a@b.co")
    }
}
