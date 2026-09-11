import Foundation
import XCTest
@testable import DeskCore

final class TaskFolderTests: XCTestCase {
    private let head1 = String(repeating: "1", count: 40)
    private let head2 = String(repeating: "2", count: 40)
    private let head3 = String(repeating: "3", count: 40)

    // MARK: - WorktreeList.parse

    func testParseReadsTheMainAndALinkedWorktree() {
        let output = "worktree /Users/me/app\0HEAD \(head1)\0branch refs/heads/main\0\0"
            + "worktree /Users/me/wt/app-42\0HEAD \(head2)\0branch refs/heads/gh-42-x\0\0"
        XCTAssertEqual(WorktreeList.parse(output), [
            Worktree(path: "/Users/me/app", head: head1, branch: "main", isBare: false, isDetached: false),
            Worktree(path: "/Users/me/wt/app-42", head: head2, branch: "gh-42-x", isBare: false, isDetached: false),
        ])
    }

    func testParseMarksBareAndDetachedEntriesAndSkipsLockedAndPrunableLines() {
        let output = "worktree /srv/app.git\0bare\0\0"
            + "worktree /Users/me/wt/detached\0HEAD \(head1)\0detached\0locked on usb\0\0"
            + "worktree /Users/me/wt/gone\0HEAD \(head2)\0branch refs/heads/gh-8-gone\0prunable gitdir file points to non-existent location\0\0"
            + "worktree /Users/me/wt/held\0HEAD \(head3)\0branch refs/heads/gh-9-held\0locked\0\0"
        XCTAssertEqual(WorktreeList.parse(output), [
            Worktree(path: "/srv/app.git", head: nil, branch: nil, isBare: true, isDetached: false),
            Worktree(path: "/Users/me/wt/detached", head: head1, branch: nil, isBare: false, isDetached: true),
            Worktree(path: "/Users/me/wt/gone", head: head2, branch: "gh-8-gone", isBare: false, isDetached: false),
            Worktree(path: "/Users/me/wt/held", head: head3, branch: "gh-9-held", isBare: false, isDetached: false),
        ])
    }

    func testParseKeepsSpacesAndNewlinesInPathsWhateverTheTrailingNuls() {
        let entry = "worktree /Users/me/wt/app 42\0HEAD \(head1)\0branch refs/heads/gh-42-x\0"
        let expected = [Worktree(path: "/Users/me/wt/app 42", head: head1, branch: "gh-42-x", isBare: false, isDetached: false)]
        XCTAssertEqual(WorktreeList.parse(entry + "\0"), expected, "git's own ending: the entry's NUL, then the empty field")
        XCTAssertEqual(WorktreeList.parse(entry), expected, "no closing empty field")
        XCTAssertEqual(WorktreeList.parse(entry + "\0\0"), expected, "an extra trailing NUL adds no entry")
        XCTAssertEqual(WorktreeList.parse("worktree /Users/me/wt/line\nbreak\0HEAD \(head2)\0detached\0\0"),
                       [Worktree(path: "/Users/me/wt/line\nbreak", head: head2, branch: nil, isBare: false, isDetached: true)])
        XCTAssertEqual(WorktreeList.parse(""), [])
    }

    // MARK: - TaskFolderResolver.plan

    private static let root = URL(fileURLWithPath: "/work/My App", isDirectory: true)
    private static let listKey = FakeRunner.gitRead("worktree list --porcelain -z")
    private var mainOnly: String { "worktree /work/My App\0HEAD \(head1)\0branch refs/heads/main\0\0" }

    private func resolver(_ runner: CommandRunner, location: String,
                          home: URL = URL(fileURLWithPath: "/Users/nobody", isDirectory: true)) -> TaskFolderResolver {
        TaskFolderResolver(projectRoot: Self.root, worktreeLocation: location, runner: runner, homeDirectory: home)
    }

    func testACheckedOutBranchOpensInItsWorktreeReadThroughTheHardenedList() async throws {
        let checkout = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(mainOnly + "worktree \(checkout.url.path)\0HEAD \(head2)\0branch refs/heads/gh-42-x\0\0")])
        let plan = await resolver(runner, location: "/unused").plan(branch: "gh-42-x", taskNumber: 42)
        XCTAssertEqual(plan, .existing(URL(fileURLWithPath: checkout.url.path, isDirectory: true), branch: "gh-42-x"))
        XCTAssertEqual(Self.listKey, (["git"] + GitCommand.readFlags + ["worktree", "list", "--porcelain", "-z"]).joined(separator: " "))
        XCTAssertEqual(runner.calls, [FakeRunner.Call(key: Self.listKey, directory: Self.root, timeout: CommandTimeout.git)])
    }

    func testAWorktreeWhoseFolderIsGoneIsNotReused() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(mainOnly + "worktree /nonexistent/wt/gone\0HEAD \(head2)\0branch refs/heads/gh-8-gone\0"
                                                    + "prunable gitdir file points to non-existent location\0\0")])
        let plan = await resolver(runner, location: location.url.path).plan(branch: "gh-8-gone", taskNumber: 8)
        XCTAssertEqual(plan, .create(path: location.url.appendingPathComponent("my-app-8", isDirectory: true), branch: "gh-8-gone"),
                       "a shell can't open in a missing folder; git's refusal to add then reaches rule 4")
    }

    func testAnUncheckedOutBranchPlansAWorktreeNamedForTheTaskNumber() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(mainOnly)])
        let plan = await resolver(runner, location: location.url.path).plan(branch: "gh-12-crash-on-launch", taskNumber: 12)
        XCTAssertEqual(plan, .create(path: location.url.appendingPathComponent("my-app-12", isDirectory: true), branch: "gh-12-crash-on-launch"))
    }

    func testABranchOnlyTaskIsNamedForTheBranchSlug() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(mainOnly)])
        let plan = await resolver(runner, location: location.url.path).plan(branch: "Spike/Try__it--NOW", taskNumber: nil)
        XCTAssertEqual(plan, .create(path: location.url.appendingPathComponent("my-app-spike-try-it-now", isDirectory: true), branch: "Spike/Try__it--NOW"))
    }

    func testAnExistingPathIsNeverReusedSoTheNextFreeSuffixIsTaken() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(mainOnly)])
        try FileManager.default.createDirectory(at: location.url.appendingPathComponent("my-app-12"), withIntermediateDirectories: true)
        let second = await resolver(runner, location: location.url.path).plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(second, .create(path: location.url.appendingPathComponent("my-app-12-2", isDirectory: true), branch: "gh-12-x"))

        try FileManager.default.createSymbolicLink(atPath: location.url.appendingPathComponent("my-app-12-2").path, withDestinationPath: "/nonexistent/target")
        let third = await resolver(runner, location: location.url.path).plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(third, .create(path: location.url.appendingPathComponent("my-app-12-3", isDirectory: true), branch: "gh-12-x"),
                       "a dangling symlink still occupies its name")
    }

    func testALeadingTildeExpandsToTheInjectedHome() async throws {
        let home = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(mainOnly)])
        let underHome = await resolver(runner, location: "~/.devdesk/wt", home: home.url).plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(underHome, .create(path: home.url.appendingPathComponent(".devdesk/wt/my-app-12", isDirectory: true), branch: "gh-12-x"))
        let atHome = await resolver(runner, location: "~", home: home.url).plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(atHome, .create(path: home.url.appendingPathComponent("my-app-12", isDirectory: true), branch: "gh-12-x"))
    }

    func testAWorktreeLocationThatIsNotAbsoluteOpensTheProjectRoot() async throws {
        let note = "The worktree location must be an absolute path or start with ~/, so the shell opens at the project root."
        let home = try TempGitRepo()
        let absolute = try TempGitRepo()
        let checkout = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(mainOnly + "worktree \(checkout.url.path)\0HEAD \(head2)\0branch refs/heads/gh-42-x\0\0")])
        for bad in ["", "wt/tasks", "~bob/wt"] {
            let plan = await resolver(runner, location: bad, home: home.url).plan(branch: "gh-12-x", taskNumber: 12)
            XCTAssertEqual(plan, .root(Self.root, note: note), "\"\(bad)\" would resolve against /")
        }
        let checkedOut = await resolver(runner, location: "", home: home.url).plan(branch: "gh-42-x", taskNumber: 42)
        XCTAssertEqual(checkedOut, .existing(URL(fileURLWithPath: checkout.url.path, isDirectory: true), branch: "gh-42-x"),
                       "a branch already checked out needs no location")
        let underHome = await resolver(runner, location: "~/x", home: home.url).plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(underHome, .create(path: home.url.appendingPathComponent("x/my-app-12", isDirectory: true), branch: "gh-12-x"))
        let atPath = await resolver(runner, location: absolute.url.path, home: home.url).plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(atPath, .create(path: absolute.url.appendingPathComponent("my-app-12", isDirectory: true), branch: "gh-12-x"))
    }

    func testAWorktreeListThatFailsStillPlansANewWorktree() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .failed(129, stderr: "error: unknown switch `z'")])
        let plan = await resolver(runner, location: location.url.path).plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(plan, .create(path: location.url.appendingPathComponent("my-app-12", isDirectory: true), branch: "gh-12-x"),
                       "git refuses to add a branch checked out elsewhere, so rule 4 still catches it")
    }

    func testNoBranchOpensAtTheProjectRootWithTheExactNoteAndRunsNothing() async {
        let runner = FakeRunner()
        let numbered = await resolver(runner, location: "/unused").plan(branch: nil, taskNumber: 42)
        XCTAssertEqual(numbered, .root(Self.root, note: "No branch for #42 yet. The shell opens at the project root; running /dev #42 there cuts gh-42-… at its first write."))
        let unnumbered = await resolver(runner, location: "/unused").plan(branch: "", taskNumber: nil)
        XCTAssertEqual(unnumbered, .root(Self.root, note: "No branch for this task yet. The shell opens at the project root."))
        let fork = "This pull request comes from a fork, so its branch isn't in this repository. The shell opens at the project root."
        let forked = await resolver(runner, location: "/unused").plan(branch: nil, taskNumber: 51, noBranchNote: fork)
        XCTAssertEqual(forked, .root(Self.root, note: fork), "the task's own reason replaces the generic note")
        XCTAssertEqual(runner.calls, [])
    }

    func testSlugLowercasesCollapsesRunsTrimsAndCutsToForty() {
        XCTAssertEqual(TaskFolderResolver.slug("My App"), "my-app")
        XCTAssertEqual(TaskFolderResolver.slug("--Feature//Search_Box--"), "feature-search-box")
        XCTAssertEqual(TaskFolderResolver.slug("café Ω 42"), "caf-42")
        XCTAssertEqual(TaskFolderResolver.slug(String(repeating: "x", count: 50)), String(repeating: "x", count: 40))
        XCTAssertEqual(TaskFolderResolver.slug(String(repeating: "a", count: 39) + "-bcd"), String(repeating: "a", count: 39),
                       "a cut that lands on a separator drops it")
        XCTAssertEqual(TaskFolderResolver.slug("日本語"), "task")
        XCTAssertEqual(TaskFolderResolver.slug(""), "task")
    }

    // MARK: - TaskFolderResolver.materialise

    private static let wt = URL(fileURLWithPath: "/work/wt/my-app-7", isDirectory: true)

    private func addKey(_ path: URL, _ branch: String) -> String {
        (["git"] + GitCommand.read(["worktree", "add", path.path, branch])).joined(separator: " ")
    }

    private func rootNote(_ reason: String) -> String {
        "Couldn't create a worktree for gh-7-demo, so the shell opens at the project root: \(reason)"
    }

    /// A worktree location on disk and the folder planned in it, since materialise makes that folder itself.
    private func planned() throws -> (location: TempGitRepo, path: URL) {
        let location = try TempGitRepo()
        return (location, location.url.appendingPathComponent("my-app-7", isDirectory: true))
    }

    func testMaterialiseMakesTheFolderThenRunsExactlyTheHardenedWorktreeAdd() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("not/yet/my-app-7", isDirectory: true)
        let runner = FakeRunner([addKey(path, "gh-7-demo"): .ok()])
        let folder = await resolver(runner, location: location.url.path).materialise(.create(path: path, branch: "gh-7-demo"))
        XCTAssertEqual(folder, TaskFolder(url: path, note: nil, created: true))
        XCTAssertEqual(runner.calls, [FakeRunner.Call(key: addKey(path, "gh-7-demo"), directory: Self.root, timeout: 60)])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: path.path), [], "the folder and its parents exist before git runs")
    }

    func testAFailedAddOpensTheProjectRootWithGitsErrorLineAndGivesTheFolderBack() async throws {
        let cases: [(stderr: String, reason: String)] = [
            ("fatal: invalid reference: gh-7-demo\n", "fatal: invalid reference: gh-7-demo"),
            // git prints its progress line before the error, as a real `worktree add` onto an existing path does.
            ("Preparing worktree (checking out 'gh-7-demo')\nfatal: '/work/wt/my-app-7' already exists\n", "fatal: '/work/wt/my-app-7' already exists"),
            ("\n  warning: odd output  \nmore\n", "warning: odd output"),
            ("", "git exited with status 128"),
        ]
        for (stderr, reason) in cases {
            let (location, path) = try planned()
            let runner = FakeRunner([addKey(path, "gh-7-demo"): .failed(128, stderr: stderr)])
            let folder = await resolver(runner, location: location.url.path).materialise(.create(path: path, branch: "gh-7-demo"))
            XCTAssertEqual(folder, TaskFolder(url: Self.root, note: rootNote(reason), created: false), stderr)
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), "the empty folder it made is removed again")
        }
    }

    func testATimedOutAddOpensTheProjectRoot() async throws {
        let (location, path) = try planned()
        let runner = FakeRunner()
        runner.script(addKey(path, "gh-7-demo"), throwing: CommandError.timedOut(tool: "git", seconds: 60))
        let folder = await resolver(runner, location: location.url.path).materialise(.create(path: path, branch: "gh-7-demo"))
        XCTAssertEqual(folder, TaskFolder(url: Self.root, note: rootNote("git did not finish within 60 seconds"), created: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testTwoStartsWhosePlansCollideGetTwoFolders() async throws {
        let location = try TempGitRepo()
        let first = location.url.appendingPathComponent("my-app-spike-x", isDirectory: true)
        let second = location.url.appendingPathComponent("my-app-spike-x-2", isDirectory: true)
        let runner = FakeRunner([Self.listKey: .ok(mainOnly), addKey(first, "Spike/X"): .ok(), addKey(second, "spike-x"): .ok()])
        let resolver = resolver(runner, location: location.url.path)
        // Both plans are read before either folder exists, as two quick starts of tasks with colliding slugs would be.
        let a = await resolver.plan(branch: "Spike/X", taskNumber: nil)
        let b = await resolver.plan(branch: "spike-x", taskNumber: nil)
        XCTAssertEqual(a, .create(path: first, branch: "Spike/X"))
        XCTAssertEqual(b, .create(path: first, branch: "spike-x"))
        let folderA = await resolver.materialise(a)
        let folderB = await resolver.materialise(b)
        XCTAssertEqual(folderA, TaskFolder(url: first, note: nil, created: true))
        XCTAssertEqual(folderB, TaskFolder(url: second, note: nil, created: true))
        XCTAssertEqual(runner.keys, [Self.listKey, Self.listKey, addKey(first, "Spike/X"), addKey(second, "spike-x")])
    }

    func testALinkPlantedAtThePlannedPathIsNeverUsed() async throws {
        let location = try TempGitRepo()
        let target = try TempGitRepo()
        let plannedPath = location.url.appendingPathComponent("my-app-12", isDirectory: true)
        let claimed = location.url.appendingPathComponent("my-app-12-2", isDirectory: true)
        let runner = FakeRunner([Self.listKey: .ok(mainOnly), addKey(claimed, "gh-12-x"): .ok()])
        let resolver = resolver(runner, location: location.url.path)
        let plan = await resolver.plan(branch: "gh-12-x", taskNumber: 12)
        XCTAssertEqual(plan, .create(path: plannedPath, branch: "gh-12-x"))

        // Planted after the plan, and pointing at an empty folder git would fill.
        try FileManager.default.createSymbolicLink(atPath: plannedPath.path, withDestinationPath: target.url.path)
        let folder = await resolver.materialise(plan)
        XCTAssertEqual(folder, TaskFolder(url: claimed, note: nil, created: true))
        XCTAssertEqual(runner.keys, [Self.listKey, addKey(claimed, "gh-12-x")])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: plannedPath.path), target.url.path, "the link is left as it was")
    }

    func testAFolderThatCannotBeMadeOpensTheProjectRootWithoutRunningGit() async throws {
        let location = try TempGitRepo()
        try location.write("taken", "a file where the worktree location's folder would go\n")
        let path = location.url.appendingPathComponent("taken/my-app-7", isDirectory: true)
        let runner = FakeRunner()
        let folder = await resolver(runner, location: location.url.path).materialise(.create(path: path, branch: "gh-7-demo"))
        XCTAssertEqual(folder.url, Self.root)
        XCTAssertFalse(folder.created)
        XCTAssertTrue(folder.note?.hasPrefix(rootNote("")) == true, folder.note ?? "no note")
        XCTAssertEqual(runner.calls, [])
    }

    func testExistingAndRootPlansRunNothing() async {
        let runner = FakeRunner()
        let resolver = resolver(runner, location: "/work/wt")
        let reused = await resolver.materialise(.existing(Self.wt, branch: "gh-7-demo"))
        XCTAssertEqual(reused, TaskFolder(url: Self.wt, note: nil, created: false))
        let note = "No branch for this task yet. The shell opens at the project root."
        let atRoot = await resolver.materialise(.root(Self.root, note: note))
        XCTAssertEqual(atRoot, TaskFolder(url: Self.root, note: note, created: false))
        XCTAssertEqual(runner.calls, [])
    }

    func testABranchGitWouldReadAsAnOptionIsNeverPassedToIt() async throws {
        let (location, path) = try planned()
        let runner = FakeRunner()
        let folder = await resolver(runner, location: location.url.path).materialise(.create(path: path, branch: "-Bmain"))
        XCTAssertEqual(folder, TaskFolder(url: Self.root, note: "Couldn't create a worktree for -Bmain, so the shell opens at the project root: "
                                          + "'-Bmain' is not a valid branch name", created: false))
        XCTAssertEqual(runner.calls, [], "worktree add would read -Bmain as -B main and reset that branch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), "nothing is made for a name it refuses")
    }

    func testARealRepositoryGetsAWorktreeThenReusesIt() async throws {
        let parent = try TempGitRepo()
        let location = try TempGitRepo()
        try parent.git("init", "-q", "-b", "main", "My App")
        try parent.write("My App/README.md", "hello\n")
        try parent.git("-C", "My App", "add", "-A")
        try parent.git("-C", "My App", "commit", "-q", "-m", "initial")
        try parent.git("-C", "My App", "branch", "gh-7-demo")
        let root = parent.url.appendingPathComponent("My App", isDirectory: true)
        let resolver = TaskFolderResolver(projectRoot: root, worktreeLocation: location.url.path)

        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let planned = await resolver.plan(branch: "gh-7-demo", taskNumber: 7)
        XCTAssertEqual(planned, .create(path: path, branch: "gh-7-demo"))

        let folder = await resolver.materialise(planned)
        XCTAssertEqual(folder, TaskFolder(url: path, note: nil, created: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.appendingPathComponent("README.md").path))
        XCTAssertEqual(try parent.gitOutput(["-C", path.path, "rev-parse", "--abbrev-ref", "HEAD"]), "gh-7-demo\n")

        // git lists worktrees by their real path, so /var/folders comes back as /private/var/folders.
        guard case .existing(let reused, branch: "gh-7-demo") = await resolver.plan(branch: "gh-7-demo", taskNumber: 7) else {
            return XCTFail("the worktree just created should be reused")
        }
        XCTAssertEqual(reused.resolvingSymlinksInPath().path, path.resolvingSymlinksInPath().path)

        guard case .existing(let checkout, branch: "main") = await resolver.plan(branch: "main", taskNumber: nil) else {
            return XCTFail("the branch checked out at the root should open there")
        }
        XCTAssertEqual(checkout.resolvingSymlinksInPath().path, root.resolvingSymlinksInPath().path)
    }
}
