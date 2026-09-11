import XCTest
@testable import DeskCore

final class GitParsersTests: XCTestCase {
    func testNumstatReadsCountsLeavesBinaryNilAndResolvesRenames() {
        let output = "3\t1\tSources/App/Main.swift\n-\t-\tAssets/logo.png\n0\t5\tdocs/{old => new}/guide.md\n2\t2\tREADME.md => README.markdown\n1\t0\t{lib => }/util.swift\n"
        XCTAssertEqual(GitOutput.numstat(output), [
            NumstatEntry(path: "Sources/App/Main.swift", additions: 3, deletions: 1),
            NumstatEntry(path: "Assets/logo.png", additions: nil, deletions: nil),
            NumstatEntry(path: "docs/new/guide.md", additions: 0, deletions: 5),
            NumstatEntry(path: "README.markdown", additions: 2, deletions: 2),
            NumstatEntry(path: "util.swift", additions: 1, deletions: 0),
        ])
    }

    func testUnifiedDiffSplitsTwoFilesWithTheirHunks() {
        let diff = """
        diff --git a/Sources/App/Main.swift b/Sources/App/Main.swift
        index 1111111..2222222 100644
        --- a/Sources/App/Main.swift
        +++ b/Sources/App/Main.swift
        @@ -1,3 +1,3 @@ struct Main {
         let a = 1
        -let b = 2
        +let b = 3\r
        @@ -10,2 +10,3 @@
         func run() {
        +    print(a)
        --- old comment
         }
        \\ No newline at end of file
        diff --git a/docs/new file.md b/docs/new file.md
        new file mode 100644
        index 0000000..3333333
        --- /dev/null
        +++ b/docs/new file.md\t
        @@ -0,0 +1,2 @@
        +# Title
        +--- not a header

        """
        let files = GitOutput.fileDiffs(diff)
        XCTAssertEqual(files.map(\.path), ["Sources/App/Main.swift", "docs/new file.md"])
        XCTAssertEqual(files[0].hunks, [
            DiffHunk(header: "@@ -1,3 +1,3 @@ struct Main {", lines: [
                DiffLine(.context, "let a = 1"), DiffLine(.deletion, "let b = 2"), DiffLine(.addition, "let b = 3"),
            ]),
            DiffHunk(header: "@@ -10,2 +10,3 @@", lines: [
                DiffLine(.context, "func run() {"), DiffLine(.addition, "    print(a)"),
                DiffLine(.deletion, "-- old comment"), DiffLine(.context, "}"),
            ]),
        ])
        XCTAssertEqual(files[1].hunks, [
            DiffHunk(header: "@@ -0,0 +1,2 @@", lines: [DiffLine(.addition, "# Title"), DiffLine(.addition, "--- not a header")]),
        ])
        XCTAssertFalse(files[0].truncated || files[1].truncated)
    }

    func testDiffTruncatesAFileAtFifteenHundredLines() {
        let body = (1...1600).map { "+line \($0)" }.joined(separator: "\n")
        let diff = "diff --git a/big.txt b/big.txt\n--- /dev/null\n+++ b/big.txt\n@@ -0,0 +1,1600 @@\n\(body)\n"
        let file = GitOutput.fileDiffs(diff)[0]
        XCTAssertEqual(file.hunks.flatMap(\.lines).count, 1500)
        XCTAssertEqual(file.hunks[0].lines.last, DiffLine(.addition, "line 1500"))
        XCTAssertTrue(file.truncated)
    }

    func testDiffKeepsAtMostTwoHundredFiles() {
        let diff = (1...205).map { "diff --git a/f\($0).txt b/f\($0).txt\n--- /dev/null\n+++ b/f\($0).txt\n@@ -0,0 +1 @@\n+x" }.joined(separator: "\n")
        let files = GitOutput.fileDiffs(diff)
        XCTAssertEqual(files.count, 200)
        XCTAssertEqual(files.last?.path, "f200.txt")
    }

    func testRenameBinaryAndQuotedPathsFindTheirPath() {
        let diff = """
        diff --git a/old.txt b/new.txt
        similarity index 100%
        rename from old.txt
        rename to new.txt
        diff --git a/logo.png b/logo.png
        index 1111111..2222222 100644
        Binary files a/logo.png and b/logo.png differ
        diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"
        new file mode 100644
        --- /dev/null
        +++ "b/caf\\303\\251.txt"
        @@ -0,0 +1 @@
        +hi
        """
        let files = GitOutput.fileDiffs(diff)
        XCTAssertEqual(files.map(\.path), ["new.txt", "logo.png", "café.txt"])
        XCTAssertEqual(files[0].hunks, [])
        XCTAssertEqual(files[1].hunks, [])
        XCTAssertEqual(GitOutput.numstat("1\t0\t\"caf\\303\\251.txt\"\n"), [NumstatEntry(path: "café.txt", additions: 1, deletions: 0)])
    }

    func testLogSplitsUnitSeparatedFields() {
        let output = "a1b2c3d\u{1F}Ada Lovelace\u{1F}2026-09-11T09:30:00+03:00\u{1F}Fix *bold* subject\nb2c3d4e\u{1F}Bob\u{1F}2026-09-10T18:00:00Z\u{1F}\n"
        XCTAssertEqual(GitOutput.commits(output), [
            GitCommit(sha: "a1b2c3d", author: "Ada Lovelace", date: "2026-09-11T09:30:00+03:00", subject: "Fix *bold* subject"),
            GitCommit(sha: "b2c3d4e", author: "Bob", date: "2026-09-10T18:00:00Z", subject: ""),
        ])
    }

    func testWorktreePorcelainMapsBranchesToPaths() {
        let output = """
        worktree /Users/me/app
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /Users/me/wt/app 12
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/gh-12-x

        worktree /Users/me/wt/detached
        HEAD 3333333333333333333333333333333333333333
        detached

        """
        XCTAssertEqual(GitOutput.worktrees(output), ["main": "/Users/me/app", "gh-12-x": "/Users/me/wt/app 12"])
    }

    func testTruePromisorIsDetectedFromGetRegexpOutput() {
        XCTAssertTrue(GitOutput.hasTruePromisor("remote.origin.promisor true\n"))
        XCTAssertTrue(GitOutput.hasTruePromisor("remote.origin.promisor 1\nremote.up.promisor false\n"))
        XCTAssertTrue(GitOutput.hasTruePromisor("remote.origin.promisor\n"), "a bool key with no value is git-true")
        XCTAssertTrue(GitOutput.hasTruePromisor("remote.origin.promisor YES\n"))
        XCTAssertFalse(GitOutput.hasTruePromisor("remote.origin.promisor false\n"))
        XCTAssertFalse(GitOutput.hasTruePromisor("remote.origin.promisor 0\n"))
        XCTAssertFalse(GitOutput.hasTruePromisor(""))
    }

    func testBasePrefersStagingThenDevelopThenMainThenMaster() {
        XCTAssertEqual(GitOutput.preferredBase(remoteBranches: "origin\norigin/master\norigin/main\norigin/develop\norigin/staging\n"), "staging")
        XCTAssertEqual(GitOutput.preferredBase(remoteBranches: "origin/master\norigin/main\norigin/develop\n"), "develop")
        XCTAssertEqual(GitOutput.preferredBase(remoteBranches: "origin/master\norigin/main\n"), "main")
        XCTAssertEqual(GitOutput.preferredBase(remoteBranches: "origin/master\n"), "master")
        XCTAssertNil(GitOutput.preferredBase(remoteBranches: "origin\norigin/feature\nupstream/main\n"))
        XCTAssertEqual(GitOutput.preferredBase(among: ["feature/x", "main"]), "main")
    }
}
