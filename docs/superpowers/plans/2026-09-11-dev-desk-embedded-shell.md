# Dev Desk Embedded Shell (Step 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each task's Agents & Terminals dock in a real project has a working terminal. It opens in that task's own folder, reusing a checkout of the task's branch or creating a git worktree for it, and it starts only when the user clicks.

**Architecture:** The app target hosts SwiftTerm's `LocalProcessTerminalView`, and a per-window registry keeps each task's terminal view, and its process, alive across task switches. DeskCore gets the pure, tested parts:
- parsing `git worktree list --porcelain -z`;
- the task-folder rule, and running `git worktree add`;
- a per-window `ShellSessions` state store.

The dock model gains two tab kinds besides the transcript: a live shell, and an unavailable tab with its reason.

**Tech Stack:** Swift 5 language mode, SwiftUI with AppKit, macOS 14, xcodegen, and SwiftTerm 1.20.0 in the app target only.

**Spec:** the developer's decisions of 2026-09-11 in the Dev Desk session: an embedded shell, opened in the task's branch folder, starting on the user's click. This is step 1 of 2; step 2 adds agents in the shell, a Manual/Auto setting, a parallel limit and a token warning. The Global Constraints below are that spec.

## Global Constraints

- **Ruled during implementation (2026-09-11): SwiftTerm is pinned at `1.11.2`, not `1.20.0`.** 1.12 and later need Xcode 26's separate Metal Toolchain, and 1.19 and later carry a build plugin. See ADR 0016.
- **SwiftTerm** comes from `https://github.com/migueldeicaza/SwiftTerm`, pinned `exactVersion: 1.20.0` (MIT). Only the `DevDesk` app target depends on it. **DeskCore stays dependency-free** and is tested with `swift test --package-path apps/desk/DeskCore`.
- `SWIFT_VERSION` stays `5.0`, and macOS stays `14.0`. There are no other new dependencies.
- **Nothing runs in a repository until the user clicks "Start shell".** A shell never starts on its own when a task opens. (Auto-start is step 2.)
- **Reads stay hardened.** Every git invocation goes through `GitCommand.read(...)`, whose flags turn off fsmonitor, hooks, external diff and signature programs. `git worktree add` runs with those same `-c` flags, through the existing `CommandRunner`, with argument arrays and a timeout.
- **The task-folder rule, in this order:**
  1. The task has a branch, and `git worktree list --porcelain -z` shows a worktree whose `branch` is `refs/heads/<branch>`: use that worktree's path. It can be the project root itself.
  2. The task has a branch that no worktree has checked out: plan a new worktree at `<worktreeLocation>/<project folder name>-<suffix>`, where `<suffix>` is the task number when there is one, else a slug of the branch (`[a-z0-9-]`, at most 40 characters). If the path already exists, use `-2`, `-3` and so on; never reuse or overwrite an existing path. A leading `~` expands to the home directory. Create it with `git worktree add <path> <branch>`. When only `origin/<branch>` exists, git's own lookup creates a tracking branch.
  3. The task has no branch: use the project root, with the note `No branch for #N yet. The shell opens at the project root; running /dev #N there cuts gh-N-… at its first write.` When there is no number, use `No branch for this task yet. The shell opens at the project root.`
  4. `git worktree add` fails or times out: use the project root, with the note `Couldn't create a worktree for <branch>, so the shell opens at the project root: <first line of git's error>`.
- **The worktree location** is Settings → Execution, `desk.worktreeLocation`, default `~/.devdesk/wt`. The app passes the current value when the user clicks.
- **The shell** is the user's `$SHELL` (falling back to `/bin/zsh`) run as a login shell (`-l`), with the user's environment plus `TERM=xterm-256color`, and the resolved folder as its working directory.
- **Lifetime.** Sessions are kept per window and keyed by task id. Switching tasks, or hiding the dock, keeps each shell running. **End shell** in the tab, or closing the window, sends SIGHUP to the process, then SIGKILL if it is still alive after 2 s.
- **The trust note** appears inline in the Shell tab before the first start, not as a modal: `Starting a shell runs your login shell and git in this repository, as Terminal would. Only start one in a repository you trust.` Under it, the planned folder:
  - `Opens in <path>, where <branch> is checked out.`
  - `Creates a worktree for <branch> at <path>.`
  - `Opens at the project root: <note>.`
- **Real (local) projects** give every task a dock with two tabs:
  - **Shell**, the live shell;
  - **Agents**, unavailable, with this reason: `Dev Desk doesn't start agents yet. You can run one in the Shell tab, for example claude "/dev #N". Starting agents from here, by hand or automatically, comes next.` Without a number, the example is `claude "/dev"`.
  - The dock caption is `Agents & Terminals · a shell in this task's folder`.
  - Every reason and note is plain `Text`, never rendered as markdown.
- **Sample projects** keep their demo transcripts unchanged and get no live shell, because a sample has no folder.
- Comment density, naming and idiom match the surrounding code. Implementers never commit or stage; the controller commits.
- **Never create a worktree in, or start a shell in, the dev-desk repository or any real checkout while testing.** Integration tests build throwaway repos under `$TMPDIR`. For a manual run, use a throwaway repo.

---

### Task 1: DeskCore — worktree parsing, the task-folder rule, and shell session state

**Files:**
- Create: `apps/desk/DeskCore/Sources/DeskCore/Local/TaskFolder.swift`
- Create: `apps/desk/DeskCore/Sources/DeskCore/State/ShellSessions.swift`
- Modify: `apps/desk/DeskCore/Sources/DeskCore/Model/DeskTask.swift` (the `DockTab` kind, and `DeskTask.branch`)
- Modify: `apps/desk/DeskCore/Sources/DeskCore/Local/BoardBuilder.swift` (set `branch`, and give every local task the two-tab dock)
- Modify: `apps/desk/DeskCore/Sources/DeskCore/State/ProjectWindowModel.swift` (own a `ShellSessions`)
- Modify: sample data and any other DeskCore call site that reads `DockTab.transcript`
- Test: `apps/desk/DeskCore/Tests/DeskCoreTests/TaskFolderTests.swift`, `ShellSessionsTests.swift`, and additions to `BoardBuilderTests.swift`

**Interfaces:**
- Consumes: `CommandRunner` / `ProcessRunner` (`run(_:_:in:timeout:) async throws -> CommandResult`), `GitCommand.read(_:)`, `Markdown` (not needed for plain text), `ProjectRef.local(path:)`.
- Produces. Task 2 codes against these exact names:

```swift
// Model/DeskTask.swift
public struct DockTab: Identifiable, Hashable {
    public enum Kind: Hashable {
        case transcript(TerminalTranscript)
        case liveShell
        case unavailable(reason: String)
    }
    public var id: String
    public var title: String
    public var kind: Kind
    public init(id: String, title: String, transcript: TerminalTranscript)   // kind = .transcript; existing call sites keep compiling
    public init(id: String, title: String, kind: Kind)
    public var transcript: TerminalTranscript? { get }                        // non-nil only for .transcript
}
// DeskTask gains:  public var branch: String?   // the task's git branch, when one is known; nil for samples unless set

// Local/TaskFolder.swift
public struct Worktree: Equatable {
    public let path: String
    public let head: String?
    public let branch: String?      // short name; "refs/heads/" stripped; nil when detached or bare
    public let isBare: Bool
    public let isDetached: Bool
}
public enum WorktreeList { public static func parse(_ porcelainZ: String) -> [Worktree] }   // `git worktree list --porcelain -z`
public struct TaskFolder: Equatable { public let url: URL; public let note: String?; public let created: Bool }
public enum TaskFolderPlan: Equatable {
    case existing(URL, branch: String)
    case create(path: URL, branch: String)
    case root(URL, note: String)
}
public struct TaskFolderResolver {
    public init(projectRoot: URL, worktreeLocation: String, runner: CommandRunner = ProcessRunner(),
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)
    public func plan(branch: String?, taskNumber: Int?) async -> TaskFolderPlan   // read-only
    public func materialise(_ plan: TaskFolderPlan) async -> TaskFolder            // runs `git worktree add` for .create only
}

// State/ShellSessions.swift
public enum ShellSessionState: Equatable {
    case idle(TaskFolderPlan?)                 // plan shown under the trust note; nil until planned
    case preparing
    case running(TaskFolder)
    case ended(TaskFolder, status: Int32?)
    case failed(String)
}
@Observable @MainActor public final class ShellSessions {
    public init(projectRoot: URL?, runner: CommandRunner = ProcessRunner())    // nil root (samples): every state stays .failed("…no folder…")
    public func state(for taskID: String) -> ShellSessionState
    public func refreshPlan(taskID: String, branch: String?, taskNumber: Int?, worktreeLocation: String) async
    public func start(taskID: String, branch: String?, taskNumber: Int?, worktreeLocation: String) async   // → .preparing → .running(folder)
    public func markEnded(taskID: String, status: Int32?)                     // called by the app when the process exits
    public var runningTaskIDs: [String] { get }
}
// ProjectWindowModel gains:  public let shellSessions: ShellSessions   // projectRoot from .local(path:); nil for samples
```

- [ ] **Step 1: Write failing tests for `WorktreeList.parse`.** Use NUL-separated porcelain fixtures that cover:
  - the main worktree and a linked worktree on `refs/heads/gh-42-x`;
  - a detached HEAD;
  - a bare entry;
  - `locked` and `prunable` lines;
  - a path containing a space;
  - a trailing NUL.
- [ ] **Step 2: Implement `WorktreeList.parse`,** then run `swift test --package-path apps/desk/DeskCore --filter TaskFolderTests`. It should pass.
- [ ] **Step 3: Write failing tests for `TaskFolderResolver.plan` with `FakeRunner`**, one for each of rules 1–3:
  - the task number used as the suffix;
  - the slug used as the suffix (branch-only task);
  - collision suffixes `-2`/`-3` against existing paths, using a temp directory;
  - `~` expansion via the injected home;
  - the exact note texts from Global Constraints.

  Also assert that the `git worktree list` call uses `GitCommand.read` flags and `-z`.
- [ ] **Step 4: Implement `plan`.**
- [ ] **Step 5: Write failing tests for `materialise`.**
  - `FakeRunner` asserts that the `worktree add` argument array is exactly `GitCommand.read(["worktree", "add", path, branch])`.
  - A failure maps to rule 4's note, taking the first stderr line.
  - Then a **real temp-repo integration test**: `git init` under `$TMPDIR`, commit, create a branch `gh-7-demo` without checking it out, and assert all three:
    - `plan` → `.create`;
    - after `materialise`, the folder exists, `git -C <folder> rev-parse --abbrev-ref HEAD` is `gh-7-demo`, and a second `plan` → `.existing`;
    - the checked-out branch → `.existing(projectRoot)`.
- [ ] **Step 6: Implement `materialise`.**
- [ ] **Step 7: `DockTab.Kind`, `DeskTask.branch` and BoardBuilder.** Update the tests so that:
  - a local issue task with a matched branch gets `branch == "gh-N-…"`;
  - a branch-only task gets its branch;
  - every local task's `dock` has tabs `[Shell (.liveShell), Agents (.unavailable(reason))]`, with the exact reason and caption;
  - sample tasks are unchanged.

  Implement it, and keep every existing call site compiling.
- [ ] **Step 8: `ShellSessions` tests.** `start` moves `.idle` → `.preparing` → `.running`, and `markEnded` moves to `.ended`. Starting again after `.ended` runs `start` anew. A sample session (nil root) never runs a command. `refreshPlan` stores the plan in `.idle`. Implement, and add the `ProjectWindowModel.shellSessions` wiring.
- [ ] **Step 9:** Run the full `swift test --package-path apps/desk/DeskCore`. Expect 0 failures, with the count higher than 186.

### Task 2: App — the SwiftTerm shell in the dock

**Files:**
- Modify: `apps/desk/project.yml` (add package `SwiftTerm`, `url: https://github.com/migueldeicaza/SwiftTerm`, `exactVersion: 1.20.0`, and target dependency `- package: SwiftTerm`)
- Create: `apps/desk/DevDesk/Screens/Task/ShellTerminalView.swift` (an `NSViewRepresentable` over `LocalProcessTerminalView`, plus a per-window `ShellTerminalRegistry` that retains views by task id and terminates them)
- Modify: `apps/desk/DevDesk/Screens/Task/AgentsDock.swift` (render `.transcript`, `.liveShell` and `.unavailable` tabs), and any view that reads `DockTab.transcript`
- Modify: `apps/desk/DevDesk/Screens/Task/TaskHeader.swift` (only if it needs to: the dock button is already enabled whenever `task.dock != nil`)
- Modify: `apps/desk/DevDesk/App/ProjectWindow.swift` (own the registry, and end every shell when the window closes)
- Modify: `apps/desk/DevDesk/Screens/Settings/SettingsPanes.swift` (an ExecutionPane caption: `Task worktrees are created here when you start a shell for a branch that isn't checked out.`)
- Modify: `apps/desk/DevDesk/App/SnapshotMode.swift` (capture a local task with the Shell tab idle, showing the trust note and the planned folder)
- Modify: `apps/desk/README.md` (one line: the first build resolves SwiftTerm, which needs network)

**Interfaces:**
- Consumes: everything that Task 1 "Produces" (names above), and SwiftTerm 1.20.0's `LocalProcessTerminalView` / `LocalProcessTerminalViewDelegate`. Read SwiftTerm's `Sources/SwiftTerm/Mac/MacLocalTerminalView.swift` and `LocalProcess.swift` at v1.20.0 for the exact `startProcess` signature and whether it takes a working directory.
  - If it doesn't, start `/bin/sh` with `-c 'cd -- "$1" && exec "$2" -l' sh <folder> <shell>`, all as argument-array elements, never interpolated into the script.
- Produces: nothing that other tasks consume.

- [ ] **Step 1: SwiftTerm in `project.yml`.** Then `xcodegen generate` and `xcodebuild -resolvePackageDependencies`, and confirm it resolves 1.20.0.
- [ ] **Step 2: `ShellTerminalView` and `ShellTerminalRegistry`.**
  - The registry is `@MainActor`, one per window, and keyed by task id.
  - `view(for:)` returns the same `LocalProcessTerminalView` every time, so SwiftUI re-creation never restarts a shell.
  - `start(taskID:folder:)` runs the user's `$SHELL -l` in the folder with `TERM=xterm-256color`.
  - `end(taskID:)` sends SIGHUP, then SIGKILL after 2 s.
  - `endAll()`.
  - The process-exit delegate calls `ShellSessions.markEnded(taskID:status:)`.
- [ ] **Step 3: The AgentsDock tabs.**
  - `.transcript`: exactly as today.
  - `.unavailable`: the reason as plain `Text`.
  - `.liveShell`, by state:
    - `idle`: the trust note, the planned-folder line from `state(for:)`'s plan, and a **Start shell** button.
    - `preparing`: `Preparing the task's folder…`.
    - `running`: the terminal filling the pane, and an **End shell** button. If the folder has a `note`, show it in one line above the terminal.
    - `ended`: `Shell ended (status N).`, with **Start again**.
    - `failed`: the message.
  - Call `refreshPlan` when the Shell tab appears. Pass the current `desk.worktreeLocation` from `@AppStorage`.
- [ ] **Step 4: Window close ends every shell** (`registry.endAll()`), whether through the window's close or the scene going away.
- [ ] **Step 5: The ExecutionPane caption, the SnapshotMode capture of a local task's idle Shell tab, and the README line.**
- [ ] **Step 6: Verify.**
  - `cd apps/desk && xcodegen generate && xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -destination 'platform=macOS' -derivedDataPath /tmp/devdesk-shell-dd build` gives `** BUILD SUCCEEDED **`, with no warnings from DevDesk sources.
  - `swift test --package-path apps/desk/DeskCore` gives 0 failures.
  - A snapshot capture of a throwaway local repo shows the Shell tab idle. For a manual run, use a throwaway repo under `$TMPDIR` with a branch that isn't checked out: Start shell → the prompt is in the new worktree, `pwd` matches, End shell → `Shell ended`.
