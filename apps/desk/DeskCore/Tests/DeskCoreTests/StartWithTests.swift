import XCTest
@testable import DeskCore

final class StartWithTests: XCTestCase {
    func testEveryPlaceholderIsFilledAndQuoted() {
        let result = StartWithTemplate.render("zadloop run {folder} --prompt {prompt} --file {taskFile} --title {title}",
                                              values: ["folder": "/p/My App", "prompt": "Read it", "taskFile": "/p/t.json",
                                                       "title": "arch-2"])
        XCTAssertEqual(result.line, "zadloop run '/p/My App' --prompt 'Read it' --file '/p/t.json' --title 'arch-2'")
        XCTAssertEqual(result.unknown, [])
    }

    /// A card title is the developer's text, not the template author's: it must not be able to run a command.
    func testAValueCannotEndTheStringOrStartASecondCommand() {
        let result = StartWithTemplate.render("tool {title}", values: ["title": "fix it'; rm -rf ~; echo '"])
        XCTAssertEqual(result.line, "tool 'fix it'\\''; rm -rf ~; echo '\\'''")
    }

    func testAnUnknownPlaceholderIsLeftAsWrittenAndReported() {
        let result = StartWithTemplate.render("tool {folder} {branch} {branch}", values: ["folder": "/p"])
        XCTAssertEqual(result.line, "tool '/p' {branch} {branch}")
        XCTAssertEqual(result.unknown, ["branch"])
        XCTAssertEqual(StartWithTemplate.unknownPlaceholders(in: "sc x {taskFile} {nope}"), ["nope"])
    }

    func testBracesThatAreNotAPlaceholderSurviveAndAreNotReported() {
        let result = StartWithTemplate.render("awk '{print $1}' {} {", values: [:])
        XCTAssertEqual(result.line, "awk '{print $1}' {} {")
        XCTAssertEqual(result.unknown, [])
    }

    func testTheListRoundTripsAndAnUnreadableValueIsEmpty() {
        let entries = [StartWithEntry(id: "1", name: "Cursor", kind: .app(path: "/Applications/Cursor.app")),
                       StartWithEntry(id: "2", name: "ZadLoop", kind: .command(template: "zadloop {folder}"))]
        XCTAssertEqual(StartWithList.decode(StartWithList.encode(entries)), entries)
        XCTAssertEqual(StartWithList.decode(Data()), [])
        XCTAssertEqual(StartWithList.decode(Data("not json".utf8)), [])
    }

    /// A task handed to another app must not look like a remembered launch, or its next Start runs Claude here.
    func testALaunchForAnotherAppIsNotWhereARememberedLaunchIsRead() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let launch = TaskLaunch(id: "task:7", task: "7", title: "t", door: "dev", arguments: ["#7"], agent: .claude,
                                worktreeLocation: "~/.devdesk/wt")
        TaskLaunchStore(projectRoot: root, folder: TaskLaunchStore.startWithFolder).write(launch)
        XCTAssertNotNil(TaskLaunchStore(projectRoot: root, folder: TaskLaunchStore.startWithFolder).read(id: "task:7"))
        XCTAssertNil(TaskLaunchStore(projectRoot: root).read(id: "task:7"))
    }
}
