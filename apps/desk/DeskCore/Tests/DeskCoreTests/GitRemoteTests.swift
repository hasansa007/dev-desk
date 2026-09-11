import XCTest
@testable import DeskCore

final class GitRemoteTests: XCTestCase {
    func testGitHubRemoteVariantsNormalizeToTheSameDisplayAndSlug() {
        let inputs = [
            "git@github.com:acme/studyhub.git",
            "https://github.com/acme/studyhub",
            "https://x-token@github.com/acme/studyhub.git",
        ]
        for input in inputs {
            XCTAssertEqual(GitRemote.display(input), "github.com/acme/studyhub")
            XCTAssertEqual(GitRemote.githubSlug(input), "acme/studyhub")
        }
    }

    func testNonGitHubRemoteHasNoSlug() {
        XCTAssertEqual(GitRemote.display("git@gitlab.com:a/b.git"), "gitlab.com/a/b")
        XCTAssertNil(GitRemote.githubSlug("git@gitlab.com:a/b.git"))
    }
}
