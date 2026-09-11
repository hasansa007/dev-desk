# Dev Desk Mac App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app, Dev Desk, that implements every screen and flow of the Claude Design prototype `docs/design/dev-desk.dc.html`. It runs on the prototype's sample projects and also opens real local folders, reading git and GitHub directly. The branch also ships the system-model page and its evidenced diagram (container spec, deliverable A).

**Architecture:** `apps/desk/` holds an xcodegen project. `DeskCore` is a local Swift package (models, data sources, per-window state; tested with `swift test`) and `DevDesk` is the SwiftUI/AppKit app target. One window per project (`WindowGroup(for: ProjectRef.self)`). Each window owns a `ProjectWindowModel` that loads a `ProjectSnapshot` from a `ProjectDataSource`: `SampleDataSource` for the prototype's content, or `LocalGitDataSource` (git + gh via `Process`) for a real folder. Every surface is a `Surface<T>`, so "unavailable" never renders like "empty".

**Tech Stack:** Swift 5 language mode (swift-tools-version 5.9), SwiftUI + AppKit, Observation, XCTest; xcodegen 2.45; no third-party dependencies. Docs task: Archify (`~/.claude/skills/archify`) via `dev:arch`.

**Spec:** `docs/design/dev-desk.dc.html` (prototype; the visual authority), `docs/design/dev-desk-app-design-prompt.md` (brief), `docs/superpowers/specs/2026-09-11-container-design.md` (system model, deliverable A), `docs/superpowers/specs/2026-09-11-app-cli-task-continuity-design.md`, `docs/superpowers/specs/2026-09-11-mac-app-navigation-and-insights-design.md`.

**Decisions already made by the developer (2026-09-11):** the app lives in `apps/desk/` in this repo; scope is the whole design on sample data *plus* real git/gh reads for opened folders; the system-model page and diagram land on this branch as their own commits.

## Global Constraints

- **Platform:** macOS 14.0 deployment target. Swift language mode 5 (`SWIFT_VERSION: "5.0"`, `swift-tools-version:5.9`). Apple frameworks only (SwiftUI, AppKit, Foundation, Observation, XCTest). No App Sandbox, no hardened runtime, ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`).
- **Location:** app code only under `apps/desk/`. Never modify `skills/`, `shared/`, `scripts/`, `hooks/`, `test-projects/`, `ci/`.
- **File ownership:** touch only the files your task lists. Need a DeskCore change from a UI task? Stop and report NEEDS_CONTEXT. Do not edit it.
- **Do not commit.** The controller commits each task's paths. Leave your changes in the working tree.
- **Colors (light values are the design's, verbatim; dark values are this plan's):**
  accent `#2F6FEB`/`#3B7BF0` · accentHover `#2A63D2` · surface `#FFFFFF`/`#1E2025` · canvas `#FBFBFC`/`#17191D` · sidebar `#F1F2F5`/`#202329` · inspector `#F7F8F9`/`#1B1D22` · headerFill `#F4F5F7`/`#23262C` · border `#DCDFE4`/`#34383F` · controlBorder `#C9CDD4`/`#454A53` · divider `#E3E6EA`/`#2C3036` · rowDivider `#EEF0F3`/`#282B31` · ink `#16181D`/`#E6E8EC` · navInk `#3C4149`/`#C9CDD4` · secondaryInk `#4B5563`/`#AEB4BD` · mutedInk `#6B7280`/`#969CA6` · faintInk `#8A9099`/`#7D838D` · disabledDot `#B9BEC6`/`#5A606A` · neutralChipFill `#EEF0F3`/`#2A2D33` · neutralChipFill2 `#F2F3F5`/`#292C32`.
  Status: running fg `#1F6B41` fill `#E4F4EA` border `#BFE3CD` dot `#1F8B4C` (dark fg `#7FD19B` fill `#16301F` border `#245C38`) · waiting fg `#8A6114` fill `#FBF2DE` border `#EBDAAE` dot `#B7791F` body `#5C4A1A` (dark fg `#E7C067` fill `#33280F` border `#5C4718` body `#D9C79A`) · failed fg `#8A1F1F` fill `#FDF6F6` border `#F0CFCF` dot `#C0392B` body `#6B2020` (dark fg `#F19A9A` fill `#331A1A` border `#5E2B2B` body `#E0B4B4`) · info fg `#1F4FB0` fill `#E7EFFD` border `#C3D7F8` (dark fg `#9CC0FF` fill `#1B2A45` border `#2F4B7C`) · ended dot `#8A9099`.
  Diff: add fill `#E7F6EC` ink `#1F5C36` (dark `#17301F`/`#9FDDB2`) · delete fill `#FDEAEA` ink `#8A1F1F` (dark `#3A1C1E`/`#F3A6A6`).
  Terminal (same in both modes): ground `#14161A` · ink `#D7DBE0` · bar `#1C1F25` · dim `#7C8796` · dim2 `#9BA3AE` · ok `#7ED492` · error `#F08A8A` · control fill `#242830` border `#343A44` · pane border `#000000`.
- **Type:** system font (SF). Title 16/600, section 15/600, body 13/400, secondary 12, small 11.5, label 11 uppercase bold with 0.06em tracking (≈0.66pt) in faintInk. Monospaced (`.system(design: .monospaced)`) only for terminals, code, paths, revisions, issue numbers. Sentence-case labels.
- **Metrics:** spacing 4/6/8/12/16/20; radius 5 control, 8–9 card, 10 pill, 11–12 sheet; control heights 24/26/28 (sheet header buttons 27, decision button 29); sidebar 236, task inspector 262, dock 272 tall (bottom) or 460 wide (side), Insights floating 404×520 (inset 36 from the right, 34 from the bottom), docked 392 wide, board column 246 wide with 14 gap, sheet width 1000 (open project, compare outputs, finding reconcile) or 720 (others), sheet max height 790. Default window 1440×900, minimum 1100×720. When the task workspace is narrower than 980pt, hide the inspector first; below 1200pt a side dock falls back to bottom.
- **Icons:** SF Symbols, never emoji or unicode dingbats. Sidebar: Board `square.grid.3x2`, Roadmap `map`, Findings `scope`, Decisions `questionmark.diamond`, Settings `gearshape`.
- **Copy:** where the design has text, copy it verbatim from `docs/design/dev-desk.dc.html` (line ranges given per task). English only.
- **Honesty rules (the product's core):** demo content is labelled as demo and only appears for `ProjectRef.sample`. A real project never shows simulated agents, sessions, replies or tracker writes. `Surface.unavailable(reason)` always renders its reason, never an empty list. Nothing leaves the Mac except the explicit Clone action and read-only `git`/`gh` calls for a local project.
- **Processes:** every external command goes through `CommandRunner`: `Process` with an argument array, never a shell string. Put `--` before user-supplied positionals. `GIT_TERMINAL_PROMPT=0` and `GH_PROMPT_DISABLED=1`. Timeouts are 15s for git, 20s for gh, 300s for clone. Reading output must not deadlock above 64 KB.
- **Documentation budget:** at most one line above a function, only when the signature cannot carry the point. No narration inside bodies, no `TODO`, no placeholders in shipped code. Tests carry the case in their name.
- **Previews:** `PreviewProvider` structs (not the `#Preview` macro) so files typecheck outside Xcode. One preview per screen, fed from `SampleData.studyHub()`.
- **Accessibility:** status color is always paired with text; pulsing dots stop under Reduce Motion; every control has an accessibility label; visible keyboard focus.

## Commands

```bash
# DeskCore tests (any task that changes DeskCore)
swift test --package-path apps/desk/DeskCore
# Full app build (Tasks 2 and 9; Wave 2 uses the typecheck script the controller hands out)
cd apps/desk && xcodegen generate && xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -destination 'platform=macOS' -derivedDataPath /tmp/devdesk-dd build
```

## File structure

```
docs/design/dev-desk.dc.html                     the prototype (committed with this plan)
apps/desk/
  .gitignore                                     DevDesk.xcodeproj/  .build/  DerivedData/
  README.md                                      what it is + the two commands above
  project.yml                                    xcodegen spec                         Task 2
  DeskCore/Package.swift                                                                Task 1
  DeskCore/Sources/DeskCore/Model/*.swift        Surface, ProjectRef, Status, Snapshot, Task, Findings,
                                                 Roadmap, Decisions, Connections, Insights   Task 1
  DeskCore/Sources/DeskCore/Data/*.swift         ProjectDataSource + DataSources, SampleDataSource,
                                                 SampleData+*.swift                     Task 1
  DeskCore/Sources/DeskCore/State/*.swift        ProjectWindowModel, InsightsConversation, DeskLink,
                                                 RecentProjectsStore, OpenProjectRegistry   Task 1
  DeskCore/Sources/DeskCore/Local/*.swift        CommandRunner, GitRemote (Task 1); LocalGitDataSource
                                                 (interim Task 1 → full Task 3), GitReaders, GitHubReaders,
                                                 SurveyReportParser, ADRParser, ProjectOperations (Task 3)
  DeskCore/Tests/DeskCoreTests/*.swift           Task 1, Task 3
  DevDesk/App/*.swift                            DevDeskApp, ProjectWindow, Sidebar, ContentRouter,
                                                 DeskCommands, Preferences          Task 2 (+ SnapshotMode Task 9)
  DevDesk/Design/*.swift                         Tokens, Primitives, TerminalTranscriptView,
                                                 ActivityEventRow, MarkdownText     Task 2
  DevDesk/Resources/Assets.xcassets              AccentColor                        Task 2
  DevDesk/Screens/Board/*.swift                  Task 5
  DevDesk/Screens/Task/*.swift                   Task 6
  DevDesk/Screens/Findings|Roadmap|Decisions/*   Task 7
  DevDesk/Screens/Settings/*, DevDesk/Insights/*,
  DevDesk/Sheets/*, DevDesk/Launcher/*           Task 8
documentation/SYSTEM-MODEL.md, docs/arch/dev-system.{architecture.json,html}   Task 4
.github/workflows/desk.yml                                                       Task 9
docs/adr/0012-*.md, 0013-*.md, docs/adr/README.md, PROJECT_MAP.md, container spec,
README.md, documentation/CONTRIBUTING.md                                          Task 10
```

## Waves

| Wave | Tasks | Starts after |
|---|---|---|
| 0 | 1 DeskCore foundation | now |
| 1 | 2 app shell + design system · 3 real git/gh data · 4 system model page + diagram | Task 1 |
| 2 | 5 Board + Parallel · 6 task workspace + dock · 7 Findings/Roadmap/Decisions · 8 Settings/Insights/sheets/launcher | Tasks 2 and 3 |
| 3 | 9 integration, snapshot verification, CI · 10 docs gate | Wave 2 |

Wave 2 tasks own disjoint folders and must not reference each other's views; the shell (`DevDesk/App/`) is the only file that names every screen.

---

### Task 1: DeskCore foundation (models, sample data, window state, command runner)

The contract every other task consumes. Types below are written out in full; transcribe them exactly (names, fields, cases). Add `public init` with the defaults shown wherever a struct is constructed outside the module.

**Files:**
- Create: `apps/desk/.gitignore` (lines: `DevDesk.xcodeproj/`, `.build/`, `DerivedData/`, `*.xcuserstate`)
- Create: `apps/desk/DeskCore/Package.swift`
- Create: `apps/desk/DeskCore/Sources/DeskCore/Model/{Surface,ProjectRef,Status,Snapshot,DeskTask,Findings,Roadmap,Decisions,Connections,Insights}.swift`
- Create: `apps/desk/DeskCore/Sources/DeskCore/Data/{ProjectDataSource,SampleDataSource,SampleData+StudyHubTasks,SampleData+StudyHubSurfaces,SampleData+DevSkill}.swift`
- Create: `apps/desk/DeskCore/Sources/DeskCore/State/{ProjectWindowModel,InsightsConversation,DeskLink,RecentProjectsStore,OpenProjectRegistry}.swift`
- Create: `apps/desk/DeskCore/Sources/DeskCore/Local/{CommandRunner,GitRemote,LocalGitDataSource}.swift`
- Test: `apps/desk/DeskCore/Tests/DeskCoreTests/{SampleDataTests,ProjectWindowModelTests,InsightsConversationTests,DeskLinkTests,RecentProjectsStoreTests,CommandRunnerTests,GitRemoteTests}.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: every type in this task. Later tasks rely on these exact names and signatures.

#### Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DeskCore", targets: ["DeskCore"])],
    targets: [
        .target(name: "DeskCore"),
        .testTarget(name: "DeskCoreTests", dependencies: ["DeskCore"]),
    ]
)
```

#### Model/Surface.swift

```swift
/// A surface that could not be read says why; unavailable never renders like empty.
public enum Surface<Value> {
    case available(Value)
    case unavailable(String)

    public var value: Value? {
        if case .available(let value) = self { return value }
        return nil
    }

    public var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

extension Surface: Equatable where Value: Equatable {}
extension Surface: Hashable where Value: Hashable {}
```

#### Model/ProjectRef.swift

```swift
public enum SampleProject: String, Codable, CaseIterable, Hashable {
    case studyHub
    case devSkill

    public var title: String { self == .studyHub ? "StudyHub" : "dev-skill" }
    public var displayPath: String { self == .studyHub ? "~/code/studyhub" : "~/code/dev-skill" }
}

public enum ProjectRef: Hashable, Codable, Identifiable {
    case sample(SampleProject)
    case local(path: String)

    public var id: String {
        switch self {
        case .sample(let project): return "sample:\(project.rawValue)"
        case .local(let path): return "local:\(path)"
        }
    }

    public var isSample: Bool {
        if case .sample = self { return true }
        return false
    }
}
```

#### Model/Status.swift

```swift
public enum StatusTone: String, Codable, Hashable {
    case running, waiting, failed, neutral, info, ended
}

public struct StatusBadge: Hashable {
    public var tone: StatusTone
    public var label: String
    public var pulses: Bool
    /// SF Symbol drawn before the label, e.g. "questionmark.diamond" for a pending decision.
    public var symbol: String?

    public init(_ tone: StatusTone, _ label: String, pulses: Bool = false, symbol: String? = nil) {
        self.tone = tone
        self.label = label
        self.pulses = pulses
        self.symbol = symbol
    }
}

public struct KeyValue: Hashable {
    public var key: String
    public var value: String
    public var monospaced: Bool

    public init(_ key: String, _ value: String, monospaced: Bool = false) {
        self.key = key
        self.value = value
        self.monospaced = monospaced
    }
}
```

#### Model/Snapshot.swift

```swift
public struct ProjectInfo: Hashable {
    public var name: String
    public var displayPath: String
    public var branch: String
    public var remote: String?
    public var headRevision: String?

    public init(name: String, displayPath: String, branch: String, remote: String? = nil, headRevision: String? = nil) {
        self.name = name
        self.displayPath = displayPath
        self.branch = branch
        self.remote = remote
        self.headRevision = headRevision
    }
}

/// What a freshly opened window selects before any restored layout is applied.
public struct LaunchState: Hashable {
    public var selectedTaskID: String?
    public var insightsOpen: Bool

    public init(selectedTaskID: String? = nil, insightsOpen: Bool = false) {
        self.selectedTaskID = selectedTaskID
        self.insightsOpen = insightsOpen
    }
}

public struct ProjectSnapshot: Hashable {
    public var project: ProjectInfo
    public var isDemo: Bool
    public var launch: LaunchState
    public var activitySummary: StatusBadge?
    public var board: Surface<[DeskTask]>
    public var boardNote: String
    public var findings: Surface<FindingsReport>
    public var roadmap: Surface<Roadmap>
    public var decisions: Surface<[Decision]>
    public var connections: [Connection]
    public var connectionsNote: String
    public var capabilities: CapabilityMatrix
    public var insights: InsightsAvailability
    /// Settings › Project overrides: base branch, remote and similar read-only facts.
    public var projectFacts: [KeyValue]

    public init(project: ProjectInfo, isDemo: Bool, launch: LaunchState = LaunchState(),
                activitySummary: StatusBadge? = nil, board: Surface<[DeskTask]>, boardNote: String,
                findings: Surface<FindingsReport>, roadmap: Surface<Roadmap>, decisions: Surface<[Decision]>,
                connections: [Connection], connectionsNote: String, capabilities: CapabilityMatrix,
                insights: InsightsAvailability, projectFacts: [KeyValue] = []) {
        self.project = project
        self.isDemo = isDemo
        self.launch = launch
        self.activitySummary = activitySummary
        self.board = board
        self.boardNote = boardNote
        self.findings = findings
        self.roadmap = roadmap
        self.decisions = decisions
        self.connections = connections
        self.connectionsNote = connectionsNote
        self.capabilities = capabilities
        self.insights = insights
        self.projectFacts = projectFacts
    }
}
```

#### Model/DeskTask.swift

```swift
import Foundation

public enum BoardColumn: String, CaseIterable, Codable, Hashable {
    case backlog, queued, inProgress, review, done

    public var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .queued: return "Queued"
        case .inProgress: return "In progress"
        case .review: return "Review"
        case .done: return "Done"
        }
    }
}

public enum NextAction: Hashable {
    case reviewChanges
    case answerDecision(decisionID: String)
    case startHandoff
    case openURL(URL, title: String)

    public var title: String {
        switch self {
        case .reviewChanges: return "Review changes"
        case .answerDecision: return "Answer decision"
        case .startHandoff: return "Start with handoff…"
        case .openURL(_, let title): return title
        }
    }
}

public struct ConnectionLevel: Hashable {
    public var name: String
    public var isAvailable: Bool
    public var statusLabel: String
    public var detail: String
    public init(name: String, isAvailable: Bool, statusLabel: String, detail: String) { /* assign */ }
}

public struct ExternalConnection: Hashable {
    public var title: String
    /// Inline markdown; code spans render monospaced.
    public var message: String
    public var levels: [ConnectionLevel]
    public var facts: [KeyValue]
    public var handoffNote: String
    public var checkoutPath: String
    public init(title: String, message: String, levels: [ConnectionLevel], facts: [KeyValue], handoffNote: String, checkoutPath: String) { /* assign */ }
}

public enum TaskNotice: Hashable {
    case waitingForDecision(title: String, message: String, decisionID: String)
    case externalConnection(ExternalConnection)
}

public enum StageState: String, Hashable { case done, current, pending }

public struct PipelineStage: Hashable {
    public var name: String
    public var state: StageState
    public init(_ name: String, _ state: StageState) { self.name = name; self.state = state }
}

public struct PipelineProgress: Hashable {
    public var stages: [PipelineStage]
    public var note: String?
    public init(stages: [PipelineStage], note: String? = nil) { self.stages = stages; self.note = note }
}

public struct ToolDetail: Hashable {
    public var title: String
    public var lines: [String]
    public init(title: String, lines: [String]) { self.title = title; self.lines = lines }
}

public struct ActivityEvent: Identifiable, Hashable {
    public var id: String
    public var time: String
    /// Inline markdown: **bold** actor names, `code` paths, [links](desk://…).
    public var text: String
    public var detail: ToolDetail?
    public var offersFollowUp: Bool
    public init(id: String, time: String, text: String, detail: ToolDetail? = nil, offersFollowUp: Bool = false) { /* assign */ }
}

public struct AcceptanceCriterion: Hashable {
    public var text: String
    public var isMet: Bool
    public init(_ text: String, isMet: Bool) { self.text = text; self.isMet = isMet }
}

public struct Requirements: Hashable {
    public var goal: String
    public var criteria: [AcceptanceCriterion]
    public var outOfScope: String?
    public var sources: String?
    /// Full issue description for real projects; nil for the sample.
    public var body: String?
    public init(goal: String, criteria: [AcceptanceCriterion] = [], outOfScope: String? = nil, sources: String? = nil, body: String? = nil) { /* assign */ }
}

public struct ChangedFile: Identifiable, Hashable {
    public var id: String            // full repository path
    public var displayPath: String   // shortened path shown in the list
    public var additions: Int?       // nil = binary
    public var deletions: Int?
    public init(id: String, displayPath: String, additions: Int?, deletions: Int?) { /* assign */ }
}

public struct DiffLine: Hashable {
    public enum Kind: String, Hashable { case context, addition, deletion }
    public var kind: Kind
    /// Without the leading " ", "+" or "-"; the viewer adds "  ", "+ " or "- ".
    public var text: String
    public init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
}

public struct DiffHunk: Hashable {
    public var header: String
    public var lines: [DiffLine]
    public init(header: String, lines: [DiffLine]) { self.header = header; self.lines = lines }
}

public struct FileDiff: Hashable {
    public var path: String
    public var hunks: [DiffHunk]
    public var truncated: Bool
    public init(path: String, hunks: [DiffHunk], truncated: Bool = false) { /* assign */ }
}

public struct ChangeSet: Hashable {
    public var files: [ChangedFile]
    /// Inline markdown, e.g. "Diff is against `main` at `9c2e410`. Demo content."
    public var baseNote: String
    /// Keyed by ChangedFile.id; a missing key means no preview is available for that file.
    public var diffs: [String: FileDiff]
    public init(files: [ChangedFile], baseNote: String, diffs: [String: FileDiff] = [:]) { /* assign */ }
}

public enum CheckOutcome: String, Hashable { case passed, warning, failed }

public struct CheckResult: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var outcome: CheckOutcome
    public var outcomeLabel: String
    public var revisionLabel: String
    public init(id: String, name: String, outcome: CheckOutcome, outcomeLabel: String, revisionLabel: String) { /* assign */ }
}

public struct FailedRun: Hashable {
    public var title: String
    public var message: String
    public init(title: String, message: String) { self.title = title; self.message = message }
}

public struct LinkedEvidence: Hashable {
    public var title: String
    public var badge: String
    public var findingID: String?
    public init(title: String, badge: String, findingID: String?) { /* assign */ }
}

public struct Evidence: Hashable {
    public var isDemo: Bool
    public var checks: [CheckResult]
    public var failure: FailedRun?
    public var limitations: String?
    public var linked: [LinkedEvidence]
    public init(isDemo: Bool, checks: [CheckResult] = [], failure: FailedRun? = nil, limitations: String? = nil, linked: [LinkedEvidence] = []) { /* assign */ }
}

public enum AgentCapability: String, Hashable { case interactive, activityOnly, completedResult }

public enum AgentAction: String, CaseIterable, Hashable {
    case openTerminal = "Open terminal"
    case viewActivity = "View activity"
    case continueSession = "Continue"
    case stop = "Stop"
    case requestFollowUp = "Request follow-up"
    case readResult = "Read result"
}

public struct AgentSession: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var role: String          // "Primary", "Helper", "Ended"
    public var capability: AgentCapability
    public var stateLabel: String    // "Interactive session · running"
    public var tone: StatusTone      // dot color
    public var pulses: Bool
    public var actions: [AgentAction]
    public init(id: String, name: String, role: String, capability: AgentCapability, stateLabel: String, tone: StatusTone, pulses: Bool = false, actions: [AgentAction]) { /* assign */ }
}

public struct Dependency: Hashable {
    /// Inline markdown with desk:// links, e.g. "Blocked by [#59](desk://task/59) — …".
    public var text: String
    public var taskID: String?
    public init(text: String, taskID: String?) { self.text = text; self.taskID = taskID }
}

public struct TerminalLine: Hashable {
    public enum Kind: String, Hashable { case plain, success, failure, dim }
    public var kind: Kind
    public var text: String
    public init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
}

public struct TerminalTranscript: Hashable {
    public var header: String
    public var lines: [TerminalLine]
    public var showsPrompt: Bool
    public var isReadOnly: Bool
    public init(header: String, lines: [TerminalLine], showsPrompt: Bool = true, isReadOnly: Bool = false) { /* assign */ }
}

public struct DockTab: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var transcript: TerminalTranscript
    public init(id: String, title: String, transcript: TerminalTranscript) { /* assign */ }
}

public struct DockContent: Hashable {
    public var tabs: [DockTab]
    public var caption: String
    /// The tab shown in the second pane when the dock is split.
    public var splitTabID: String?
    public init(tabs: [DockTab], caption: String, splitTabID: String? = nil) { /* assign */ }
}

public enum ParallelPreview: Hashable {
    case transcript(TerminalTranscript)
    case decision(title: String, question: String, decisionID: String, note: String)
    case activity([ActivityEvent])
    case none(String)

    public var isNone: Bool {
        if case .none = self { return true }
        return false
    }
}

public struct ComparedOutput: Hashable {
    public var title: String
    public var stateLabel: String
    public var tone: StatusTone
    public var summaryLines: [String]
    public var result: String
    public init(title: String, stateLabel: String, tone: StatusTone, summaryLines: [String], result: String) { /* assign */ }
}

public struct OutputComparison: Hashable {
    public var intro: String
    public var left: ComparedOutput
    public var right: ComparedOutput
    public var footnote: String
    public var confirmTitle: String
    public init(intro: String, left: ComparedOutput, right: ComparedOutput, footnote: String, confirmTitle: String) { /* assign */ }
}

public struct FollowUpDraft: Hashable {
    public var explanation: String
    public var reviewerNote: String
    public var request: String
    public var recipient: String
    public init(explanation: String, reviewerNote: String, request: String, recipient: String) { /* assign */ }
}

public struct HandoffPlan: Hashable {
    /// Inline markdown; "**new session**" is bold.
    public var warning: String
    public var rows: [KeyValue]
    public var providers: [String]
    public var footnote: String
    public init(warning: String, rows: [KeyValue], providers: [String], footnote: String) { /* assign */ }
}

public struct DeskTask: Identifiable, Hashable {
    public var id: String
    public var issueNumber: Int?
    public var title: String
    public var column: BoardColumn
    /// Monospaced suffix after the issue label ("merged", "feat/run-summary"); shown alone when there is no issue.
    public var cardMeta: String?
    public var cardBadge: StatusBadge?
    /// Plain text beside the issue label, e.g. "No agent assigned".
    public var cardInlineText: String?
    public var cardNote: String?
    public var cardNoteIsWarning: Bool
    public var isDimmed: Bool
    public var headerBadge: StatusBadge
    public var branchLine: String
    public var parallelLine: String
    public var nextAction: NextAction?
    public var notice: TaskNotice?
    public var pipeline: PipelineProgress?
    public var activity: Surface<[ActivityEvent]>
    public var canCompareOutputs: Bool
    public var requirements: Surface<Requirements>
    public var changes: Surface<ChangeSet>
    public var evidence: Surface<Evidence>
    public var agents: [AgentSession]
    public var agentsNote: String?
    public var dependencies: [Dependency]
    public var dock: DockContent?
    public var parallel: ParallelPreview
    public var comparison: OutputComparison?
    public var followUp: FollowUpDraft?
    public var handoff: HandoffPlan?

    public var issueLabel: String { issueNumber.map { "#\($0)" } ?? "" }

    public init(id: String, issueNumber: Int? = nil, title: String, column: BoardColumn,
                cardMeta: String? = nil, cardBadge: StatusBadge? = nil, cardInlineText: String? = nil,
                cardNote: String? = nil, cardNoteIsWarning: Bool = false, isDimmed: Bool = false,
                headerBadge: StatusBadge, branchLine: String, parallelLine: String = "",
                nextAction: NextAction? = nil, notice: TaskNotice? = nil, pipeline: PipelineProgress? = nil,
                activity: Surface<[ActivityEvent]> = .available([]), canCompareOutputs: Bool = false,
                requirements: Surface<Requirements>, changes: Surface<ChangeSet>, evidence: Surface<Evidence>,
                agents: [AgentSession] = [], agentsNote: String? = nil, dependencies: [Dependency] = [],
                dock: DockContent? = nil, parallel: ParallelPreview, comparison: OutputComparison? = nil,
                followUp: FollowUpDraft? = nil, handoff: HandoffPlan? = nil) { /* assign every field */ }
}
```

`/* assign */` in the inits above means: assign each parameter to the property of the same name, nothing else.

#### Model/Findings.swift

```swift
public enum FindingCategory: String, CaseIterable, Hashable {
    case new = "New"
    case knownNewEvidence = "Known · new evidence"
    case needsDecision = "Needs a decision"
    case closedOrDeclined = "Closed or declined"
}

public struct SurveyRun: Identifiable, Hashable {
    public var id: String
    public var label: String       // "today 09:40", or a report file stem
    public var revision: String?   // "9c2e410"
    public init(id: String, label: String, revision: String?) { /* assign */ }
}

public struct CompareCard: Hashable {
    public var title: String
    public var body: String
    public var meta: String         // may contain "\n"; the sheet renders it with line breaks
    public var metaMonospaced: Bool
    public init(title: String, body: String, meta: String, metaMonospaced: Bool) { /* assign */ }
}

public struct RelationshipOption: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var detail: String
    public init(id: String, title: String, detail: String) { /* assign */ }
}

public struct Reconciliation: Hashable {
    public var candidateIssue: Int
    public var statusNote: String
    public var guidance: [String]
    public var findingCard: CompareCard
    public var issueCard: CompareCard
    public var relationships: [RelationshipOption]
    public var proposedUpdate: [String]
    public var deliveryNote: String
    /// Set after the developer queues the update in the demo.
    public var queuedNote: String?
    public init(candidateIssue: Int, statusNote: String, guidance: [String], findingCard: CompareCard, issueCard: CompareCard,
                relationships: [RelationshipOption], proposedUpdate: [String], deliveryNote: String, queuedNote: String? = nil) { /* assign */ }
}

public struct Finding: Identifiable, Hashable {
    public var id: String
    public var runID: String
    public var title: String
    public var listDetail: String
    public var categories: Set<FindingCategory>
    public var summary: String
    public var verificationLabel: String
    public var locations: [String]
    public var limits: String
    public var reconcile: Reconciliation?
    public var historyNote: String?
    public init(id: String, runID: String, title: String, listDetail: String, categories: Set<FindingCategory>, summary: String,
                verificationLabel: String, locations: [String], limits: String, reconcile: Reconciliation? = nil, historyNote: String? = nil) { /* assign */ }
}

public struct FindingsReport: Hashable {
    public var runs: [SurveyRun]
    public var findings: [Finding]
    /// Shown under the list, e.g. why issue search is unavailable.
    public var searchNote: String?
    public init(runs: [SurveyRun], findings: [Finding], searchNote: String? = nil) { /* assign */ }

    public func count(of category: FindingCategory, run runID: String?) -> Int {
        findings.filter { ($0.runID == runID || runID == nil) && $0.categories.contains(category) }.count
    }
}
```

#### Model/Roadmap.swift

```swift
public enum Commitment: String, Hashable { case committed = "Committed", considered = "Considered" }

public struct RoadmapItem: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var workType: String     // "Epic", "Feature", "Improvement", "Defect", "Task"
    public var priority: String     // "High", "Medium", "Urgent", "P1"…
    public var commitment: Commitment
    public var isCritical: Bool
    /// Inline markdown with desk://task links, e.g. "Board: [#42](desk://task/42), [#57](desk://task/57) · Milestone 1.4".
    public var linkText: String?
    public init(id: String, title: String, workType: String, priority: String, commitment: Commitment, isCritical: Bool = false, linkText: String? = nil) { /* assign */ }
}

public struct RoadmapTheme: Identifiable, Hashable {
    public var id: String
    public var title: String        // "Theme · Learning continuity", "Critical concerns"
    public var isCritical: Bool
    public var items: [RoadmapItem]
    public init(id: String, title: String, isCritical: Bool = false, items: [RoadmapItem]) { /* assign */ }
}

public struct Milestone: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var progress: Double     // 0...1
    public var note: String
    public init(id: String, title: String, progress: Double, note: String) { /* assign */ }
}

public struct Roadmap: Hashable {
    public var note: String
    public var themes: [RoadmapTheme]
    public var milestones: [Milestone]
    public init(note: String, themes: [RoadmapTheme], milestones: [Milestone]) { /* assign */ }
}
```

#### Model/Decisions.swift

```swift
public enum DecisionState: String, Hashable { case needsAttention, stale, answered }

public struct DecisionOption: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var detail: String
    public init(id: String, title: String, detail: String) { /* assign */ }
}

public struct DecisionAnswer: Hashable {
    public var optionTitle: String?
    public var rationale: String
    public var answeredLabel: String
    public init(optionTitle: String?, rationale: String, answeredLabel: String) { /* assign */ }
}

public struct Decision: Identifiable, Hashable {
    public var id: String
    public var taskID: String?
    public var listTitle: String
    public var listMeta: String
    public var state: DecisionState
    public var question: String
    /// Inline markdown line under the question.
    public var context: String
    public var notice: String?
    public var evidence: String?
    public var options: [DecisionOption]
    public var answer: DecisionAnswer?
    public var staleReason: String?
    /// Full ADR markdown for real projects.
    public var body: String?
    public init(id: String, taskID: String? = nil, listTitle: String, listMeta: String, state: DecisionState, question: String,
                context: String, notice: String? = nil, evidence: String? = nil, options: [DecisionOption] = [],
                answer: DecisionAnswer? = nil, staleReason: String? = nil, body: String? = nil) { /* assign */ }
}
```

#### Model/Connections.swift

```swift
public enum ConnectionState: String, Hashable { case connected, notConnected, unavailable, detected, missing }

public struct Connection: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var state: ConnectionState
    public var label: String        // "connected", "not connected", "unavailable", "CLI found", "not found"
    public init(id: String, name: String, state: ConnectionState, label: String) { /* assign */ }
}

public enum CapabilityValue: String, Hashable {
    case yes = "Yes", sometimes = "Sometimes", no = "No", unknown = "Unknown", notValidated = "Not validated"
}

public struct CapabilityRow: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var values: [CapabilityValue]  // one per CapabilityMatrix.providers entry
    public init(id: String, name: String, values: [CapabilityValue]) { /* assign */ }
}

public struct CapabilityMatrix: Hashable {
    public var providers: [String]
    public var rows: [CapabilityRow]
    public var note: String
    public init(providers: [String], rows: [CapabilityRow], note: String) { /* assign */ }
}
```

#### Model/Insights.swift

```swift
import Foundation

public struct InsightsMessage: Identifiable, Hashable {
    public var id: UUID
    public var author: String
    public var text: String
    public var citation: String?
    public var isUser: Bool
    public init(id: UUID = UUID(), author: String, text: String, citation: String? = nil, isUser: Bool) { /* assign */ }
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
    public init(id: String, title: String, reply: InsightsReply, dockedOnly: Bool = false) { /* assign */ }
}

public struct ContextChip: Identifiable, Hashable {
    public var id: String
    public var label: String
    public var isTask: Bool         // task chips use the info (blue) tone
    public init(id: String, label: String, isTask: Bool = false) { /* assign */ }
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
                freeformReply: InsightsReply, quickActions: [InsightsQuickAction], footnote: String) { /* assign */ }
}

public enum InsightsAvailability: Hashable {
    case demo(InsightsScript)
    case unavailable(String)
}
```

#### Data/ProjectDataSource.swift

```swift
import Foundation

public protocol ProjectDataSource {
    func load() async throws -> ProjectSnapshot
}

public enum DataSources {
    public static func make(for ref: ProjectRef) -> ProjectDataSource {
        switch ref {
        case .sample(let project): return SampleDataSource(project: project)
        case .local(let path): return LocalGitDataSource(root: URL(fileURLWithPath: path))
        }
    }
}
```

#### Data/SampleDataSource.swift

```swift
public struct SampleDataSource: ProjectDataSource {
    public let project: SampleProject
    public init(project: SampleProject) { self.project = project }

    public func load() async throws -> ProjectSnapshot {
        switch project {
        case .studyHub: return SampleData.studyHub()
        case .devSkill: return SampleData.devSkill()
        }
    }
}

public enum SampleData {}  // extended by the three SampleData+*.swift files
```

#### Sample content — StudyHub tasks (`SampleData+StudyHubTasks.swift`)

`static func studyHubTasks() -> [DeskTask]`, used by `studyHub()`. Order: the column order below, then within a column as listed. Quoted strings are verbatim. `D:<lines>` points at the design file, whose text is the source to copy.

Shared shorthands used below: `running = StatusBadge(.running, "Running", pulses: true)`. "Empty requirements" means `.available(Requirements(goal: <title>, sources: <sources>))`. "Empty changes" means `.available(ChangeSet(files: [], baseNote: <note>))`. "Empty evidence" means `.available(Evidence(isDemo: true, limitations: <text>))`.

| id | column | title | card | header badge · branchLine |
|---|---|---|---|---|
| `71` | backlog | Offline lesson cache | issue 71 | `.neutral "Backlog"` · "No branch yet" |
| `68` | backlog | Flashcard deck import | issue 68 | `.neutral "Backlog"` · "No branch yet" |
| `65` | queued | Reduce initial bundle size | issue 65, inline "No agent assigned" | `.neutral "Queued"` · "No branch yet" |
| `42` | inProgress | Preserve course-list position | badge `running`; note "Codex primary · reviewer · verifier" | `running` · "fix/42-course-scroll · worktree ~/.devdesk/wt/studyhub-42 · base main@9c2e410" |
| `57` | inProgress | Improve exam recovery | badge `.waiting "Needs a decision" symbol "questionmark.diamond"`; note "Claude session waiting for input" | `.waiting "Waiting for input"` · "feat/57-exam-recovery · worktree ~/.devdesk/wt/studyhub-57 · base main@9c2e410" |
| `63` | inProgress | Investigate slow lesson search | badge `.neutral "Connected · tracking only"`; note "External checkout, not managed here" | `.neutral "Connected · tracking only"` · "spike/search-profiling · external checkout ~/scratch/studyhub-search" |
| `59` | review | Fix streak calculation across time zones | badge `.ended "Agent ended"`; note "Blocks #42 · shared date helpers", warning | `.ended "Agent ended"` · "fix/59-streak-timezones · base main@9c2e410" |
| `38` | done | Migrate settings store | issue 38, cardMeta "merged", dimmed | `.ended "Merged"` · "Merged into main" |

**Backlog, queued and done tasks (71, 68, 65, 38):** parallel `.none("No agent assigned")`; agentsNote "No agent assigned"; activity `.available([])`; empty changes with note "No branch yet." (38: "Merged into `main`."); empty evidence with limitations "No checks recorded for this task."; empty requirements with sources "Issue #71 · roadmap item “Offline lesson cache” (considered)" for 71, "Issue #68" for 68, "Issue #65" for 65, "Issue #38" for 38. No nextAction.

**Task 42** (D:347–523, 859–887):
- parallelLine "fix/42-course-scroll · ~/.devdesk/wt/studyhub-42"; nextAction `.reviewChanges`; canCompareOutputs `true`.
- pipeline: Investigated done, Planned done, Implementing current, Verified pending (D:352–358).
- activity D:361–370, ids `42-a1`…`42-a5`: ("11:12", "**Codex** patched `useScrollRestore.ts`", detail ToolDetail(title: "Tool detail · edit_file", lines: ["path: src/features/courses/useScrollRestore.ts", "range: 12–38 · +24 −6", "result: applied"])); ("11:07", "**Reviewer** (activity only) flagged a missing cleanup on unmount.", offersFollowUp: true); ("10:49", "**Verifier** finished: 18 unit checks passed, no runtime reproduction attempted."); ("10:31", "Plan approved by you · 3 acceptance criteria accepted."); ("10:12", "Task created from issue #42 and survey finding F-108.").
- requirements D:377–388: goal, three criteria (first two met, third not met), outOfScope "Virtualised list rewrite (tracked as #71). Cross-device position sync.", sources "User report on issue #42 · survey finding F-108 (code-inspected) · PROJECT_MAP.md § Navigation."
- changes D:395–416: files `src/features/courses/useScrollRestore.ts` (display "courses/useScrollRestore.ts", +24 −6), `src/features/courses/CourseList.tsx` ("courses/CourseList.tsx", +9 −2), `src/features/courses/__tests__/scroll.test.ts` ("courses/__tests__/scroll.test.ts", +41 −0). baseNote "Diff is against `main` at `9c2e410`. Demo content." One diff, for useScrollRestore.ts: header "@@ -12,6 +12,24 @@", lines (D:407–416 without their two-character prefix): context "const key = `course-list:${filterId}`;", deletion "useEffect(() => { window.scrollTo(0, 0); }, []);", additions "useLayoutEffect(() => {", "  const saved = sessionStore.get(key);", "  if (saved != null && entry.source !== 'search') {", "    listRef.current?.scrollTo({ top: saved });", "  }", "  return () => sessionStore.set(key, listRef.current?.scrollTop ?? 0);", "}, [key, entry.source]);", context "return listRef;".
- evidence D:424–446: isDemo true; checks (`unit`, "Unit tests · courses", passed, "18 passed", "rev 7b31e0c"), (`types`, "Type check", passed, "clean", "rev 7b31e0c"), (`lint`, "Lint", warning, "2 warnings", "rev 7b31e0c"), (`e2e`, "End-to-end · navigation", failed, "failed to start", "runner unavailable"); failure FailedRun("Failed run · navigation e2e", D:436 text); limitations D:440 text; linked [LinkedEvidence(title: "Survey finding F-108 · Navigation resets list state on unmount", badge: "Code-inspected", findingID: "F-108")].
- agents D:455–477: (`codex`, "Codex", "Primary", interactive, "Interactive session · running", .running, pulses, [openTerminal, stop]); (`reviewer`, "Reviewer", "Helper", activityOnly, "Activity only · no terminal", .info, [viewActivity, requestFollowUp]); (`verifier`, "Verifier", "Ended", completedResult, "Completed helper result", .ended, [readResult]).
- dependencies [Dependency(text: "Blocked by [#59](desk://task/59) — shared date helpers are being rewritten in review.", taskID: "59")].
- dock D:491–519, caption "Agents & Terminals · views of one session, not new agents", splitTabID "reviewer". Tabs: `codex` "Codex · #42", with transcript header "codex session 3f9a · attached · demo output" and lines plain "› patch src/features/courses/useScrollRestore.ts", success "✓ applied 24 additions, 6 deletions", plain "› npm test -- courses", success "✓ 18 passed", plain "› npm run e2e -- navigation", failure "✗ runner unavailable in this environment" (showsPrompt true). `shell` "Shell · studyhub-42", with header "zsh · ~/.devdesk/wt/studyhub-42 · demo output" and lines dim "fix/42-course-scroll · 3 files changed". `reviewer` "Reviewer · activity", with header "reviewer · activity only · read-only" and lines plain "· inspected CourseList.tsx (lines 40–96)", "· note: cleanup missing on unmount when filter changes", "· no input accepted — ask the coordinating agent for follow-up" (showsPrompt false, isReadOnly true).
- parallel `.transcript` D:252–257: header "codex · session 3f9a · running", lines plain "› read src/features/courses/CourseList.tsx", plain "› patch src/features/courses/useScrollRestore.ts", plain "› run npm test -- courses", success "✓ 18 passed, 0 failed (demo output)".
- comparison D:861–874: intro D:861; left ("Codex · primary", "running", .running, ["useLayoutEffect + sessionStore", "restores before paint", "skips restore when entry.source === 'search'"], "18 unit checks pass. No runtime reproduction."); right ("Claude · alternative attempt", "ended", .ended, ["scroll anchor on list item id", "restores after data resolves", "no special case for search entry"], "16 unit checks pass, 2 skipped. Flickers on slow data."); footnote D:874; confirmTitle "Adopt Codex result".
- followUp D:880–885: explanation D:880, reviewerNote D:882, request D:884, recipient "Codex · coordinating agent for #42".

**Task 57** (D:330–345, 262–271):
- parallelLine "feat/57-exam-recovery · ~/.devdesk/wt/studyhub-57"; nextAction `.answerDecision(decisionID: "d-57")`.
- notice `.waitingForDecision(title: "Waiting for a decision before implementation continues", message: <D:335 text>, decisionID: "d-57")`.
- activity ids `57-a1…a3`: ("11:04", "Session paused and posted a question to Decisions."), ("10:58", "Read `src/features/exams/attemptStore.ts` and two migrations."), ("10:51", "Requirements accepted from issue #57.").
- requirements: goal "Exam progress is not lost when an attempt is interrupted.", sources "Issue #57 · roadmap concern “Exam progress can be lost”".
- empty changes with note "No changes yet. No code has been written against any option."; empty evidence with limitations "No checks have run for this task."
- agents [(`claude`, "Claude", "Primary", interactive, "Interactive session · waiting for input", .waiting, [openTerminal, stop])].
- dependencies [Dependency(text: "Touches the same storage layer as [#59](desk://task/59).", taskID: "59")].
- dock: one tab `claude` "Claude · #57", with header "claude session 8c21 · waiting for input · demo output" and lines plain "› read src/features/exams/attemptStore.ts", plain "› read 2 migrations", dim "? Where should partial exam state be persisted so an interrupted attempt can resume?", dim "Waiting for an answer in Decisions." (showsPrompt false). Same caption; no split tab.
- parallel `.decision(title: "Blocked on an architecture decision", question: <D:268 text>, decisionID: "d-57", note: <D:271 text>)`.

**Task 63** (D:305–328, 889–901):
- parallelLine "spike/search-profiling · ~/scratch/studyhub-search"; nextAction `.startHandoff`; parallel `.none("External checkout, not managed here")`.
- notice `.externalConnection`: title "Connected external work · repository tracking only"; message "Dev Desk discovered this checkout at `~/scratch/studyhub-search` with branch `spike/search-profiling` and 7 uncommitted changes. The original session was not started through a supported connection, so it cannot be attached or resumed."; levels D:311–313 (Repository tracking available "Available"; Attach to session unavailable "Unavailable"; Continue session unavailable "Unavailable", each with its detail line); facts D:323–325 (Branch mono, Revision inspected mono, Uncommitted plain); handoffNote D:318; checkoutPath "~/scratch/studyhub-search".
- requirements: goal "Find out why lesson search is slow.", sources "Issue #63 · roadmap item “Search responsiveness” (investigation)".
- empty changes with note "7 uncommitted files in the external checkout · not pushed. Dev Desk reads this checkout; it does not manage it."; empty evidence with limitations "No checks recorded. An earlier finding in this area (F-093) was declined on 28 Aug."
- agents []; agentsNote "No managed session. This checkout is connected for repository tracking only."; dock nil.
- handoff D:891–899: warning "This creates a **new session**. The earlier work is not resumed and its conversation is not adopted. The existing checkout, branch, and uncommitted changes stay as they are."; rows Task "#63 Investigate slow lesson search", Checkout "~/scratch/studyhub-search" mono, Artifacts included "Requirements, repository diff, 2 prior findings"; providers ["Codex", "Claude"]; footnote D:899. The sheet renders the "New session with" row itself as a provider picker.

**Task 59:** nextAction `.reviewChanges`; parallel `.none("Agent ended")`; agentsNote "Agent ended."; dependencies [Dependency(text: "Blocks [#42](desk://task/42) — shared date helpers.", taskID: "42")]; empty requirements with sources "Issue #59"; empty changes with note "No diff is included for this task in the demo."; empty evidence with limitations "No checks recorded for this task."

#### Sample content — StudyHub surfaces (`SampleData+StudyHubSurfaces.swift`)

`public static func studyHub() -> ProjectSnapshot` assembles:

- project: ProjectInfo(name "StudyHub", displayPath "~/code/studyhub", branch "main", remote "github.com/acme/studyhub", headRevision "9c2e410"); isDemo true; launch LaunchState(selectedTaskID: "42", insightsOpen: true) (matches the prototype's initial state, D:950–962); activitySummary StatusBadge(.running, "2 running · 1 waiting", pulses: true).
- board `.available(studyHubTasks())`; boardNote "Columns map to prototype labels, not the repository's status field yet." (D:155).
- connections D:130–141: (`codex`, "Codex", .connected, "connected"), (`claude`, "Claude", .connected, "connected"), (`gemini`, "Gemini", .notConnected, "not connected"), (`github`, "GitHub", .unavailable, "unavailable"). connectionsNote "Illustrative prototype states. No tools are installed or called." (D:142).
- capabilities D:724–729: providers ["Codex", "Claude", "Gemini"]; rows (`terminal`, "Interactive terminal", [.yes, .yes, .unknown]), (`resume`, "Resume an ended session", [.yes, .sometimes, .unknown]), (`attach`, "Attach to an external session", [.sometimes, .no, .unknown]); note D:729.
- projectFacts: ("Base branch", "main", mono), ("Remote", "github.com/acme/studyhub", mono), ("Parallel task checkouts", "~/.devdesk/wt", mono).

**Findings** D:530–589, 903–929. runs [SurveyRun(id: "run-0940", label: "today 09:40", revision: "9c2e410")]; searchNote D:554.
- `F-108`: title "Navigation resets list state on unmount"; listDetail "Known · new evidence · relates to #42"; categories [.knownNewEvidence, .needsDecision]; summary D:561; verificationLabel "Code-inspected · not reproduced"; locations D:568 (three lines); limits "Inspected revision `9c2e410`. No runtime reproduction, no device testing, no measurement of frequency."; historyNote D:588. reconcile: candidateIssue 42; statusNote "Candidate match found · nothing has been sent to the tracker"; guidance D:582–585 (drop the leading "· "); findingCard ("Finding F-108", "Navigation resets list state on unmount.", "useScrollRestore.ts:18 · CourseList.tsx:63\nrev 9c2e410 · code-inspected", mono true); issueCard ("Issue #42", "Returning from a lesson resets scroll position.", "Opened from a user report · 1 linked finding · in progress", mono false); relationships D:917–920 with ids `same`, `related`, `duplicate`, `unconfirmed` (title = bold text, detail = the text after " — "); proposedUpdate ["comment on #42:", "+ Survey F-108 (rev 9c2e410, code-inspected, not reproduced)", "+ Locations: useScrollRestore.ts:18, CourseList.tsx:63", "+ No status change proposed"]; deliveryNote D:929.
- `F-111`: title "Exam attempt store writes twice"; listDetail "New · unconfirmed observation"; categories [.new]; summary "Attempt writes may pass through `attemptStore.ts` twice for one answer. Seen while reading the code path; the checker could not confirm it from the code alone."; verificationLabel "Unconfirmed observation"; locations ["src/features/exams/attemptStore.ts"]; limits "Inspected revision `9c2e410`. Not confirmed from the code and not reproduced."
- `F-093`: title "Search index rebuilt per keystroke"; listDetail "Previously declined · see reason"; categories [.closedOrDeclined]; summary "The lesson search index is rebuilt on every keystroke."; verificationLabel "Code-inspected · not reproduced"; locations []; limits "Inspected revision `9c2e410`. Declined on 28 Aug; see Decisions › History, “Decline search index rewrite”."; historyNote "Previously declined. Reconsider only with a documented change in circumstances."

**Roadmap** D:595–639. note D:597. Themes:
- `continuity` "Theme · Learning continuity": (`resume`, "Resume where you left off", "Epic", "High", .committed, linkText "Board: [#42](desk://task/42), [#57](desk://task/57) · Milestone 1.4"); (`offline`, "Offline lesson cache", "Feature", "Medium", .considered).
- `performance` "Theme · Performance": (`search`, "Search responsiveness", "Improvement", "Medium", .committed, linkText "Board: [#63](desk://task/63) (investigation)").
- `critical` "Critical concerns", isCritical: (`exam`, "Exam progress can be lost", "Defect", "Urgent", .committed, isCritical true, linkText "Entered the Board directly as [#57](desk://task/57); roadmap context retained.").
- Milestones: (`m14`, "1.4 · Continuity", 0.55, "2 of 4 tasks · no date committed"), (`m15`, "1.5 · Performance", 0.15, "1 of 6 tasks · investigation stage").

**Decisions** D:645–696:
- `d-57` taskID "57": listTitle "Where should partial exam state live?"; listMeta "Task #57 · asked 11:04 · blocking"; state .needsAttention; question "Where should partial exam state be persisted?"; context "Task [#57 Improve exam recovery](desk://task/57) · raised by the Claude session during implementation · blocking"; notice D:673; evidence "Attempt writes currently go through `attemptStore.ts` with an in-memory cache. Two migrations already touch the same table. Finding F-111 suggests duplicate writes, but it is an unconfirmed observation."; options D:677–679 with ids `db`, `checkpoint`, `memory`.
- `d-scroll` taskID "42": listTitle "Scroll restoration scope"; listMeta "Answered 4 Sep · context changed"; state .stale; question "Scroll restoration scope"; context "Task [#42 Preserve course-list position](desk://task/42) · answered 4 Sep"; answer ("Restore offsets for the non-virtualised course list only", "The list is not virtualised, so a stored offset maps directly to the same rows.", "Answered 4 Sep"); staleReason D:694.
- `h-session` taskID "42", .answered: "Use session storage for list offsets" / "Task #42 · answered 2 Sep"; question "Where should list scroll offsets be stored?"; context "Task [#42 Preserve course-list position](desk://task/42) · answered 2 Sep"; answer ("Use session storage for list offsets", "Offsets only need to survive navigation within a session; cross-device position sync is out of scope for #42.", "Answered 2 Sep").
- `h-f093`, .answered: "Decline search index rewrite" / "Finding F-093 · declined 28 Aug"; question "Should the search index be rewritten?"; context "Finding [F-093](desk://finding/F-093) · declined 28 Aug"; answer ("Decline for now", "Declined until search performance is measured; #63 investigates it.", "Declined 28 Aug").
- `h-worktrees`, .answered: "Adopt worktrees for parallel tasks" / "Project · answered 21 Aug"; question "How should parallel tasks be isolated?"; context "Project StudyHub · answered 21 Aug"; answer ("Adopt worktrees for parallel tasks", "Each parallel task gets its own branch and isolated checkout under `~/.devdesk/wt`, so two writers never share a working tree.", "Answered 21 Aug").

**Insights** `.demo(InsightsScript)`: provider "Codex"; providers ["Codex", "Claude"]; chips (`project`, "Project StudyHub"), (`task`, "Task #42", isTask), (`finding`, "Finding F-108"); initial D:968–969 (the "You" question, isUser; then author "Insights · Codex" with the answer and citation "useScrollRestore.ts:18 · CourseList.tsx:63 · finding F-108"); freeformReply D:1147 (answer, src); quickActions (`survey`, "Run survey", D:1149), (`roadmap`, "Explore roadmap", D:1150), (`save`, "Save project knowledge", D:1151), (`continue`, "Continue task conversation", D:1152, dockedOnly true); footnote D:779.

#### Sample content — dev-skill window (`SampleData+DevSkill.swift`)

`public static func devSkill() -> ProjectSnapshot`, D:28–67: project ("dev-skill", "~/code/dev-skill", "main"); isDemo true; default launch; no activitySummary; boardNote D:65. Tasks (empty requirements with sources "Issue #N"; empty changes with note "No diff is included for this task in the demo."; empty evidence with limitations "No checks recorded for this task."; parallel `.none("No agent assigned")`; agentsNote "No agent assigned"):
- `12` "Survey run summaries", inProgress, cardMeta "feat/run-summary", header `.neutral "In progress"`, branchLine "feat/run-summary · base main".
- `9` "Decision gate copy pass", review, cardMeta "docs/gates", header `.info "In review"`, branchLine "docs/gates · base main".
- `4` "CLI discovery handshake", done, cardMeta "main", dimmed, header `.ended "Done"`, branchLine "main".

findings `.available(FindingsReport(runs: [], findings: []))`; roadmap `.available(Roadmap(note: <D:597>, themes: [], milestones: []))`; decisions `.available([])`; connections, connectionsNote and capabilities as StudyHub; insights `.unavailable("The dev-skill sample window has no scripted conversation.")`; projectFacts [("Base branch", "main", mono)].

#### State/DeskLink.swift

```swift
import Foundation

/// In-app links carried by markdown text, e.g. desk://task/59; ids are percent-encoded.
public enum DeskLink: Hashable {
    case task(String)
    case finding(String)
    case decision(String)

    public init?(url: URL) {
        guard url.scheme == "desk", let host = url.host else { return nil }
        let id = String(url.path.dropFirst())
        guard !id.isEmpty else { return nil }
        switch host {
        case "task": self = .task(id)
        case "finding": self = .finding(id)
        case "decision": self = .decision(id)
        default: return nil
        }
    }

    public var url: URL {
        let (kind, id): (String, String)
        switch self {
        case .task(let value): (kind, id) = ("task", value)
        case .finding(let value): (kind, id) = ("finding", value)
        case .decision(let value): (kind, id) = ("decision", value)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return URL(string: "desk://\(kind)/\(id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)")!
    }
}
```

#### State/ProjectWindowModel.swift

```swift
import Foundation
import Observation

public enum Destination: String, CaseIterable, Codable, Hashable {
    case board, roadmap, findings, decisions, settings
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum TaskTab: String, CaseIterable, Codable, Hashable {
    case activity, requirements, changes, evidence
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum ViewMode: String, Codable, Hashable { case focus, parallel }
public enum DockPlacement: String, Codable, Hashable { case bottom, side }
public enum DecisionsTab: String, Codable, Hashable { case needsAttention, history }

public enum SettingsSection: String, CaseIterable, Codable, Hashable {
    case general, appearance, agentsAndDefaults, accountsAndConnections, notifications, execution, projectOverrides

    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .agentsAndDefaults: return "Agents and defaults"
        case .accountsAndConnections: return "Accounts and connections"
        case .notifications: return "Notifications"
        case .execution: return "Execution"
        case .projectOverrides: return "Project overrides"
        }
    }
}

public enum SheetKind: Hashable, Identifiable {
    case openProject, compareOutputs, followUp, handoff, reconcileFinding(String), cloneRepository, createProject

    public var id: String {
        switch self {
        case .openProject: return "openProject"
        case .compareOutputs: return "compareOutputs"
        case .followUp: return "followUp"
        case .handoff: return "handoff"
        case .reconcileFinding(let findingID): return "reconcileFinding:\(findingID)"
        case .cloneRepository: return "cloneRepository"
        case .createProject: return "createProject"
        }
    }
}

public enum LoadState {
    case loading
    case loaded(ProjectSnapshot)
    case failed(String)
}

@MainActor
@Observable
public final class ProjectWindowModel {
    public let ref: ProjectRef
    public let insights: InsightsConversation
    public private(set) var loadState: LoadState = .loading
    public private(set) var reloadError: String?
    public var destination: Destination = .board
    public var selectedTaskID: String?
    public private(set) var lastOpenedTaskID: String?
    public var tab: TaskTab = .activity
    public var mode: ViewMode = .focus
    public var dockOpen = true
    public var dockPlacement: DockPlacement = .bottom
    public var dockSplit = false
    public var dockTabID: String?
    public var showBacklog = false
    public var searchText = ""
    public var insightsOpen = false
    public var insightsDocked = false
    public var sheet: SheetKind?
    public var decisionsTab: DecisionsTab = .needsAttention
    public var selectedDecisionID: String?
    public var selectedFindingID: String?
    public var selectedRunID: String?
    public var findingFilter: FindingCategory?
    public var settingsSection: SettingsSection = .agentsAndDefaults
    public private(set) var answeredDecisionID: String?

    @ObservationIgnored private let source: ProjectDataSource

    public init(ref: ProjectRef, source: ProjectDataSource, insightsDelay: Duration = .milliseconds(900)) {
        self.ref = ref
        self.source = source
        self.insights = InsightsConversation(delay: insightsDelay)
    }

    public var snapshot: ProjectSnapshot? {
        if case .loaded(let snapshot) = loadState { return snapshot }
        return nil
    }

    public var tasks: [DeskTask] { snapshot?.board.value ?? [] }
    public var selectedTask: DeskTask? { selectedTaskID.flatMap(task) }
    public func task(_ id: String) -> DeskTask? { tasks.first { $0.id == id } }
    public var openTaskCount: Int { tasks.filter { $0.column != .done }.count }
    public var findingsCount: Int? { snapshot?.findings.value?.findings.count }
    public var pendingDecisionCount: Int { (snapshot?.decisions.value ?? []).filter { $0.state == .needsAttention }.count }
    public var parallelTasks: [DeskTask] { Array(tasks.filter { $0.column == .inProgress && !$0.parallel.isNone }.prefix(4)) }

    /// Loads or reloads the snapshot; the launch selection applies only to the first load.
    public func load() async {
        let isFirstLoad = snapshot == nil
        do {
            let loaded = try await source.load()
            loadState = .loaded(loaded)
            reloadError = nil
            guard isFirstLoad else { return }
            insights.configure(loaded.insights)
            selectedTaskID = loaded.launch.selectedTaskID
            lastOpenedTaskID = loaded.launch.selectedTaskID
            insightsOpen = loaded.launch.insightsOpen
            selectedRunID = loaded.findings.value?.runs.first?.id
            selectedFindingID = loaded.findings.value?.findings.first?.id
            selectedDecisionID = loaded.decisions.value?.first { $0.state != .answered }?.id
        } catch {
            if isFirstLoad { loadState = .failed(error.localizedDescription) } else { reloadError = error.localizedDescription }
        }
    }

    public func go(_ destination: Destination) {
        self.destination = destination
        if destination == .board {
            selectedTaskID = nil
            mode = .focus
        }
    }

    public func openTask(_ id: String) {
        destination = .board
        mode = .focus
        selectedTaskID = id
        lastOpenedTaskID = id
        tab = .activity
        dockTabID = nil
    }

    public func setMode(_ mode: ViewMode) {
        self.mode = mode
        destination = .board
    }

    /// Runs the selected task's next action; returns a URL only when the view must open it.
    public func performNextAction() -> URL? {
        guard let action = selectedTask?.nextAction else { return nil }
        switch action {
        case .reviewChanges: tab = .changes
        case .answerDecision(let decisionID): openDecision(decisionID)
        case .startHandoff: sheet = .handoff
        case .openURL(let url, _): return url
        }
        return nil
    }

    public func openDecision(_ id: String?) {
        destination = .decisions
        decisionsTab = .needsAttention
        mode = .focus
        if let id { selectedDecisionID = id }
    }

    public func openFinding(_ id: String) {
        destination = .findings
        findingFilter = nil
        selectedFindingID = id
    }

    public func handle(_ link: DeskLink) {
        switch link {
        case .task(let id): openTask(id)
        case .finding(let id): openFinding(id)
        case .decision(let id): openDecision(id)
        }
    }

    public func toggleDock() { dockOpen.toggle() }

    public func setDockPlacement(_ placement: DockPlacement) {
        dockPlacement = placement
        dockOpen = true
    }

    public func toggleSplit() { dockSplit.toggle() }

    /// Routes an agent row's button; Stop and Continue only leave a demo note, since nothing runs.
    public func perform(_ action: AgentAction, agentID: String) {
        guard let task = selectedTask else { return }
        switch action {
        case .openTerminal:
            dockOpen = true
            dockTabID = task.dock?.tabs.first?.id
        case .viewActivity:
            dockOpen = true
            dockSplit = true
        case .requestFollowUp:
            sheet = .followUp
        case .readResult:
            tab = .evidence
        case .stop, .continueSession:
            let name = task.agents.first { $0.id == agentID }?.name ?? "the agent"
            let verb = action == .stop ? "Stop" : "Continue"
            appendDemoEvent(taskID: task.id, text: "\(verb) requested for \(name) (demo). No process was touched.")
        }
    }

    public func present(_ sheet: SheetKind) { self.sheet = sheet }
    public func dismissSheet() { sheet = nil }

    /// Confirms a demo sheet by recording it on the task; nothing leaves the app.
    public func confirmSheet(provider: String? = nil) {
        defer { self.sheet = nil }
        guard let current = sheet else { return }
        if case .reconcileFinding(let findingID) = current {
            markReconciled(findingID)
            return
        }
        guard let taskID = selectedTaskID ?? lastOpenedTaskID else { return }
        switch current {
        case .compareOutputs:
            appendDemoEvent(taskID: taskID, text: "Adopted the Codex result for the compared criterion (demo).")
        case .followUp:
            appendDemoEvent(taskID: taskID, text: "Follow-up request sent to the coordinating agent (demo).")
        case .handoff:
            appendDemoEvent(taskID: taskID, text: "New \(provider ?? "Codex") session created from a handoff (demo). The existing checkout was not changed.")
        default:
            break
        }
    }

    public func toggleInsights() { insightsOpen.toggle() }

    public func dockInsights() {
        insightsDocked = true
        insightsOpen = true
    }

    public func floatInsights() {
        insightsDocked = false
        insightsOpen = true
    }

    /// Demo only: records the answer and moves the waiting task back to running.
    public func recordAnswer(decisionID: String, optionID: String?, rationale: String) {
        mutateDemoSnapshot { snapshot in
            guard var decisions = snapshot.decisions.value,
                  let index = decisions.firstIndex(where: { $0.id == decisionID }) else { return }
            let option = decisions[index].options.first { $0.id == optionID }
            decisions[index].state = .answered
            decisions[index].answer = DecisionAnswer(optionTitle: option?.title, rationale: rationale, answeredLabel: "Answered just now")
            snapshot.decisions = .available(decisions)
            guard var tasks = snapshot.board.value else { return }
            for i in tasks.indices where tasks[i].nextAction == .answerDecision(decisionID: decisionID) {
                tasks[i].headerBadge = StatusBadge(.running, "Running", pulses: true)
                tasks[i].cardBadge = StatusBadge(.running, "Running", pulses: true)
                tasks[i].cardNote = "Session resumed with your answer"
                tasks[i].notice = nil
                tasks[i].nextAction = nil
            }
            snapshot.board = .available(tasks)
        }
        answeredDecisionID = decisionID
    }

    public func requestMoreEvidence(decisionID: String) {
        guard let taskID = snapshot?.decisions.value?.first(where: { $0.id == decisionID })?.taskID else { return }
        appendDemoEvent(taskID: taskID, text: "Asked the session for more evidence (demo).")
    }

    private func markReconciled(_ findingID: String) {
        mutateDemoSnapshot { snapshot in
            guard var report = snapshot.findings.value,
                  let index = report.findings.firstIndex(where: { $0.id == findingID }) else { return }
            report.findings[index].reconcile?.queuedNote = "Update queued locally (demo). Nothing was sent to the tracker."
            snapshot.findings = .available(report)
        }
    }

    private func appendDemoEvent(taskID: String, text: String) {
        mutateDemoSnapshot { snapshot in
            guard var tasks = snapshot.board.value,
                  let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            var events = tasks[index].activity.value ?? []
            events.insert(ActivityEvent(id: UUID().uuidString, time: Self.clock.string(from: Date()), text: text), at: 0)
            tasks[index].activity = .available(events)
            snapshot.board = .available(tasks)
        }
    }

    private func mutateDemoSnapshot(_ change: (inout ProjectSnapshot) -> Void) {
        guard var current = self.snapshot, current.isDemo else { return }
        change(&current)
        loadState = .loaded(current)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
```

#### State/InsightsConversation.swift

```swift
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
```

#### State/RecentProjectsStore.swift and State/OpenProjectRegistry.swift

```swift
import Foundation

public struct RecentProject: Codable, Hashable, Identifiable {
    public var ref: ProjectRef
    public var name: String
    public var displayPath: String
    public var openedAt: Date
    public var id: String { ref.id }
    public init(ref: ProjectRef, name: String, displayPath: String, openedAt: Date) { /* assign */ }
}

public final class RecentProjectsStore {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(defaults: UserDefaults = .standard, key: String = "desk.recentProjects", limit: Int = 10) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    public var entries: [RecentProject] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data) else { return [] }
        return decoded
    }

    /// Moves the project to the front; samples are never recorded because the picker lists them itself.
    public func record(_ ref: ProjectRef, name: String, displayPath: String, at date: Date = Date()) {
        guard !ref.isSample else { return }
        var list = entries.filter { $0.ref != ref }
        list.insert(RecentProject(ref: ref, name: name, displayPath: displayPath, openedAt: date), at: 0)
        save(Array(list.prefix(limit)))
    }

    public func remove(_ ref: ProjectRef) { save(entries.filter { $0.ref != ref }) }

    private func save(_ list: [RecentProject]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }
}
```

```swift
import Observation

@MainActor
@Observable
public final class OpenProjectRegistry {
    public private(set) var openRefs: Set<ProjectRef> = []
    public init() {}
    public func windowOpened(_ ref: ProjectRef) { openRefs.insert(ref) }
    public func windowClosed(_ ref: ProjectRef) { openRefs.remove(ref) }
    public func isOpen(_ ref: ProjectRef) -> Bool { openRefs.contains(ref) }
}
```

#### Local/CommandRunner.swift

```swift
import Foundation

public enum CommandTimeout {
    public static let git: TimeInterval = 15
    public static let gh: TimeInterval = 20
    public static let clone: TimeInterval = 300
}

public struct CommandResult: Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var succeeded: Bool { status == 0 }
    /// `/usr/bin/env` exits 127 when the tool is not on PATH.
    public var toolMissing: Bool { status == 127 }
    public init(status: Int32, stdout: String, stderr: String) { /* assign */ }
}

public enum CommandError: Error, Equatable, LocalizedError {
    case launchFailed(String)
    case timedOut(tool: String, seconds: Double)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return "Could not start the command: \(reason)"
        case .timedOut(let tool, let seconds): return "\(tool) did not finish within \(Int(seconds)) seconds."
        }
    }
}

public protocol CommandRunner {
    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult
}

/// Runs a tool from PATH, widened with the Homebrew and user bin directories a GUI app does not inherit.
public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.runBlocking(tool, arguments, directory, timeout) })
            }
        }
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", "\(home)/.local/bin", "\(home)/bin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        env["PATH"] = (existing + extra.filter { !existing.contains($0) }).joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GH_PROMPT_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        return env
    }

    private static func runBlocking(_ tool: String, _ arguments: [String], _ directory: URL?, _ timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.environment = environment()
        process.currentDirectoryURL = directory
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw CommandError.launchFailed(error.localizedDescription) }

        // Both pipes drain concurrently, so output larger than the pipe buffer never blocks the child.
        var outData = Data()
        var errData = Data()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
        readers.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); readers.leave() }

        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            if process.isRunning { timedOut.set(); process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        readers.wait()
        if timedOut.isSet { throw CommandError.timedOut(tool: tool, seconds: timeout) }
        return CommandResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}

private final class Flag {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
```

#### Local/GitRemote.swift

```swift
public enum GitRemote {
    /// "git@github.com:owner/repo.git" and "https://github.com/owner/repo" both become "github.com/owner/repo".
    public static func display(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".git") { value.removeLast(4) }
        if let scheme = value.range(of: "://") { value = String(value[scheme.upperBound...]) }
        if let at = value.firstIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        if let colon = value.firstIndex(of: ":"), !value[..<colon].contains("/") {
            value.replaceSubrange(colon...colon, with: "/")
        }
        return value
    }

    /// "owner/repo" when the remote is on github.com, otherwise nil.
    public static func githubSlug(_ url: String) -> String? {
        let shown = display(url)
        guard shown.hasPrefix("github.com/") else { return nil }
        let parts = shown.dropFirst("github.com/".count).split(separator: "/")
        return parts.count == 2 ? parts.joined(separator: "/") : nil
    }
}
```

#### Local/LocalGitDataSource.swift (interim; Task 3 replaces `load()`)

```swift
import Foundation

public enum LocalProjectError: Error, Equatable, LocalizedError {
    case folderMissing(String)
    public var errorDescription: String? {
        switch self {
        case .folderMissing(let path): return "The folder \(path) no longer exists."
        }
    }
}

public struct LocalGitDataSource: ProjectDataSource {
    public let root: URL
    let runner: CommandRunner

    public init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        self.runner = runner
    }

    public func load() async throws -> ProjectSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else { throw LocalProjectError.folderMissing(root.path) }
        let unread = "Not read yet."
        return ProjectSnapshot(project: await identity(), isDemo: false, board: .unavailable(unread), boardNote: "",
                               findings: .unavailable(unread), roadmap: .unavailable(unread), decisions: .unavailable(unread),
                               connections: [], connectionsNote: "", capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
                               insights: .unavailable(unread))
    }

    func identity() async -> ProjectInfo {
        async let branch = git(["rev-parse", "--abbrev-ref", "HEAD"])
        async let remote = git(["remote", "get-url", "origin"])
        async let head = git(["rev-parse", "--short", "HEAD"])
        return ProjectInfo(name: root.lastPathComponent, displayPath: Self.abbreviate(root.path),
                           branch: await branch ?? "", remote: await remote.map(GitRemote.display), headRevision: await head)
    }

    /// Trimmed stdout of a successful git call; nil when git fails or is missing.
    func git(_ arguments: [String]) async -> String? {
        guard let result = try? await runner.run("git", arguments, in: root, timeout: CommandTimeout.git), result.succeeded else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
```

#### Tests (XCTest; `@MainActor` on model tests; construct models with `insightsDelay: .zero`)

Test helpers live in `Tests/DeskCoreTests/TestSupport.swift`: `FixedSource(snapshot:)` and `FailingSource(message:)` implementing `ProjectDataSource`, and `waitUntil(_ condition: @MainActor () -> Bool)` that polls with `await Task.yield()` for at most 2 s.

- `SampleDataTests`
  - `testStudyHubColumnCounts`: backlog 2, queued 1, inProgress 3, review 1, done 1.
  - `testStudyHubSidebarBadges`: after `load()`, `openTaskCount == 7`, `findingsCount == 3`, `pendingDecisionCount == 1` (the design's 7 / 3 / 1, D:111, 118, 122).
  - `testTask42CarriesDesignContent`: 5 activity events, 3 criteria (two met), 3 changed files, 4 checks, 3 agents, 3 dock tabs, splitTabID "reviewer".
  - `testDevSkillBoardHasThreeTasks`: ids ["12", "9", "4"] in columns inProgress, review, done.
  - `testEveryDeskLinkInSampleResolves`: collect every `desk://…` URL in the markdown fields (activity text, dependencies, roadmap linkText, decision context). Each must parse with `DeskLink(url:)` and name an existing task, finding or decision.
  - `testDecisionTaskIDsExist`: every non-nil `Decision.taskID` is a task id.
- `ProjectWindowModelTests`
  - `testLoadAppliesStudyHubLaunchState`: selectedTaskID "42", tab .activity, insightsOpen true, destination .board, selectedDecisionID "d-57", selectedFindingID "F-108", selectedRunID "run-0940".
  - `testGoBoardClearsSelectionButKeepsLastOpened`: `openTask("57")`, `go(.board)`, then selectedTaskID nil, lastOpenedTaskID "57", mode .focus.
  - `testNextActionOf57OpensItsDecision`: returns nil, destination .decisions, decisionsTab .needsAttention, selectedDecisionID "d-57".
  - `testNextActionOf63OpensHandoff`: sheet == .handoff.
  - `testNextActionOf42ShowsChanges`: tab == .changes.
  - `testParallelModeReturnsToBoard`: `go(.findings)`, `setMode(.parallel)`, then destination .board and parallelTasks ids ["42", "57"].
  - `testSideDockPlacementOpensDock`, `testViewActivityOpensSplitDock` (agent "reviewer").
  - `testRecordAnswerResumesTask57`: `recordAnswer(decisionID: "d-57", optionID: "checkpoint", rationale: "Balanced")` → pendingDecisionCount 0; task 57 headerBadge.tone .running and nextAction nil; answer.optionTitle "Checkpoint every N answers and on blur"; answeredDecisionID "d-57".
  - `testConfirmHandoffRecordsDemoEvent`: `openTask("63")`, `present(.handoff)`, `confirmSheet(provider: "Claude")` → sheet nil; first activity event text starts with "New Claude session".
  - `testReconcileQueuesUpdateLocally`: F-108 `reconcile?.queuedNote` is set after confirming `.reconcileFinding("F-108")`.
  - `testDemoMutationsIgnoredForRealSnapshots`: a FixedSource snapshot with `isDemo = false` leaves decisions unchanged after `recordAnswer`.
  - `testLinkRoutesToFinding`: `handle(.finding("F-093"))` → destination .findings, selectedFindingID "F-093".
  - `testFailedFirstLoadReportsMessage`: FailingSource("boom") → loadState is `.failed` containing "boom".
- `InsightsConversationTests`: demo configure gives 2 messages, 3 chips, provider "Codex". An empty draft sends nothing. `draft = "hi"; send()` appends the user message at once and `isReading == true`; after waiting, the reply is appended with a citation and isReading is false. `startNewConversation(with: "Claude")` empties messages and the next reply's author is "Insights · Claude". Unavailable availability: send appends nothing.
- `DeskLinkTests`: round trips for task "59", finding "F-108", and task "branch:feature/x" (percent-encoded); rejects `https://` and `desk://task/`.
- `RecentProjectsStoreTests` (a fresh `UserDefaults(suiteName: UUID().uuidString)!`): record moves a project to the front and de-duplicates; the limit holds; samples are not recorded; remove works.
- `CommandRunnerTests`: `echo hello` → "hello\n"; `false` → status 1; `ls /definitely-missing` → non-empty stderr; `head -c 1048576 /dev/zero` → stdout of 1,048,576 bytes (no deadlock); `sleep 5` with timeout 0.5 → throws `.timedOut`; `no-such-tool-xyz` → `toolMissing`.
- `GitRemoteTests`: `git@github.com:acme/studyhub.git`, `https://github.com/acme/studyhub`, `https://x-token@github.com/acme/studyhub.git` → "github.com/acme/studyhub" and slug "acme/studyhub"; `git@gitlab.com:a/b.git` → "gitlab.com/a/b" and slug nil.
- `LocalGitIdentityTests`: in a temp dir, `git init -b main`, one commit (set `user.name`/`user.email` with `-c`), then load: name is the folder name, branch "main", headRevision non-nil. A missing folder throws `.folderMissing`.

**Steps:**

- [ ] **Step 1:** Create `Package.swift`, `apps/desk/.gitignore` and every Model file. Run `swift build --package-path apps/desk/DeskCore`; expect success.
- [ ] **Step 2:** Write `SampleDataTests` and `DeskLinkTests` and run `swift test --package-path apps/desk/DeskCore --filter SampleDataTests`. Expect a compile failure: SampleData is not written yet.
- [ ] **Step 3:** Write the Data files and `DeskLink`. Run `swift test --package-path apps/desk/DeskCore`; expect those suites to pass.
- [ ] **Step 4:** Write the model, insights, recents and registry tests. Run them and see them fail, then write the State files and see them pass.
- [ ] **Step 5:** Write the command runner, git remote and identity tests. Run them and see them fail, then write the Local files and see them pass.
- [ ] **Step 6:** Run the full suite: `swift test --package-path apps/desk/DeskCore 2>&1 | tail -5`. Expect all tests passing with no warnings about your files. Leave the changes uncommitted (the controller commits).

### Task 2: App shell, design system, and screen scaffolding

Builds the runnable app around DeskCore: the xcodegen project, the window and scene structure, the toolbar, the sidebar, the content router, keyboard commands, the design tokens and the shared primitives every screen uses. It also creates each screen file as a minimal compiling stub with its final signature. The stubs render only `EmptyStateView(title: "<screen title>", message: "")` and are replaced wholesale in Wave 2. That scaffolding is intentional and does not ship.

**Files:**
- Create: `apps/desk/project.yml`, `apps/desk/README.md`
- Create: `apps/desk/DevDesk/App/{DevDeskApp,ProjectWindow,ProjectToolbar,Sidebar,ContentRouter,DeskCommands,Preferences,AppServices}.swift`
- Create: `apps/desk/DevDesk/Design/{Tokens,Primitives,MarkdownText,TerminalTranscriptView,ActivityEventRow,SurfaceView}.swift`
- Create: `apps/desk/DevDesk/Resources/Assets.xcassets/{Contents.json,AccentColor.colorset/Contents.json}` (light `#2F6FEB`, dark `#3B7BF0`)
- Create (stubs, final signatures): `DevDesk/Screens/Board/BoardScreen.swift`, `DevDesk/Screens/Board/ParallelScreen.swift`, `DevDesk/Screens/Task/TaskWorkspaceScreen.swift`, `DevDesk/Screens/Findings/FindingsScreen.swift`, `DevDesk/Screens/Roadmap/RoadmapScreen.swift`, `DevDesk/Screens/Decisions/DecisionsScreen.swift`, `DevDesk/Screens/Settings/SettingsScreen.swift`, `DevDesk/Insights/InsightsPanel.swift`, `DevDesk/Sheets/SheetHost.swift`, `DevDesk/Launcher/LauncherView.swift`

**Interfaces:**
- Consumes: all of DeskCore from Task 1 (`ProjectWindowModel`, `ProjectRef`, `DataSources`, `OpenProjectRegistry`, `RecentProjectsStore`, `DeskLink`, model types).
- Produces (Wave 2 depends on these exact names):
  - Stub signatures: `struct BoardScreen: View { @Bindable var model: ProjectWindowModel }`, and the same shape for `ParallelScreen`, `FindingsScreen`, `RoadmapScreen`, `DecisionsScreen` and `SettingsScreen`. Also `struct TaskWorkspaceScreen: View { @Bindable var model: ProjectWindowModel; let task: DeskTask }`, `enum InsightsPlacement { case floating, docked }`, `struct InsightsPanel: View { @Bindable var model: ProjectWindowModel; let placement: InsightsPlacement }`, `struct SheetHost: View { @Bindable var model: ProjectWindowModel; let kind: SheetKind }`, `enum LauncherContext { case window, sheet }`, and `struct LauncherView: View { let context: LauncherContext; var onDismiss: () -> Void = {} }`.
  - `enum DeskColor` with one static `Color` per Global Constraints token, named as listed there (`accent`, `surface`, `canvas`, `sidebar`, `inspector`, `headerFill`, `border`, `controlBorder`, `divider`, `rowDivider`, `ink`, `navInk`, `secondaryInk`, `mutedInk`, `faintInk`, `disabledDot`, `neutralChipFill`, `neutralChipFill2`, `diffAddFill`, `diffAddInk`, `diffDeleteFill`, `diffDeleteInk`, `terminalGround`, `terminalInk`, `terminalBar`, `terminalDim`, `terminalDim2`, `terminalOK`, `terminalError`, `terminalControlFill`, `terminalControlBorder`), plus `static func tone(_ tone: StatusTone) -> ToneColors` where `struct ToneColors { let foreground, fill, border, dot, body: Color }` (neutral: secondaryInk/neutralChipFill/border/disabledDot/secondaryInk; ended: secondaryInk/neutralChipFill/border/faintInk/secondaryInk). Colors are built with `Color.desk(_ light: UInt32, _ dark: UInt32)` over `NSColor(name:dynamicProvider:)`.
  - `enum DeskFont { static let title, section, body, secondary, small, label: Font; static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font }` and `enum DeskMetric` with the Global Constraints widths and radii (`sidebarWidth`, `inspectorWidth`, `dockHeight`, `dockSideWidth`, `insightsFloatingSize`, `insightsDockedWidth`, `boardColumnWidth`, `controlRadius`, `cardRadius`, `pillRadius`, `sheetRadius`).
  - Primitives: `StatusPill(badge: StatusBadge)`, `StatusDot(tone: StatusTone, pulses: Bool = false)`, `PropertyChip(_ text: String, tone: StatusTone = .neutral)`, `SectionLabel(_ text: String)`, `View.deskCard(padding: CGFloat = 11, border: Color = DeskColor.border)`, `DeskButtonStyle(kind: .primary | .secondary, size: .regular | .small | .mini)` (heights 28/26/24, radius 5 (6 for regular), font 12 (11 mini); primary is accent fill, white semibold text, hover accentHover; secondary is surface fill, controlBorder stroke, ink text), `LinkButtonStyle()` (accent text, no chrome), `KeyValueTable(rows: [KeyValue], keyWidth: CGFloat = 190)`, `NoticeBanner(tone:title:message:actions:)` (a ViewBuilder for trailing actions; the message is markdown), `EmptyStateView(title: String, message: String, actions: () -> some View = { EmptyView() })`, `UnavailableView(reason: String)`, `SurfaceView(_ surface: Surface<Value>, content: (Value) -> some View)`, `MarkdownText(_ markdown: String, font: Font = DeskFont.body, color: Color = DeskColor.ink)` (inline markdown with `.inlineOnlyPreservingWhitespace`: code spans monospaced, links in accent color and routed through the environment's `openURL`), `TerminalTranscriptView(transcript: TerminalTranscript)`, and `ActivityEventRow(event: ActivityEvent, onFollowUp: (() -> Void)? = nil)`.
  - `enum PreferenceKey` (static string keys: `appearance`, `terminalFontSize`, `showSamples`, `defaultConnection`, `notifyDecisions`, `notifyCompletion`, `notifyFailures`, `worktreeLocation`; and `static func connectionOverride(_ ref: ProjectRef) -> String`) and `enum AppearanceChoice: String, CaseIterable { case system, light, dark }` with `title` and `colorScheme: ColorScheme?`.
  - `@MainActor enum AppServices { static let recents = RecentProjectsStore() }`; `FocusedValues.projectModel: ProjectWindowModel?`.

#### project.yml

```yaml
name: DevDesk
options:
  bundleIdPrefix: dev.devskill
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
packages:
  DeskCore:
    path: DeskCore
targets:
  DevDesk:
    type: application
    platform: macOS
    sources:
      - path: DevDesk
    dependencies:
      - package: DeskCore
    settings:
      base:
        PRODUCT_NAME: Dev Desk
        PRODUCT_BUNDLE_IDENTIFIER: dev.devskill.desk
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: Dev Desk
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.developer-tools
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.0"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "-"
        ENABLE_HARDENED_RUNTIME: NO
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
schemes:
  DevDesk:
    build:
      targets:
        DevDesk: all
    run:
      config: Debug
```

#### Behavior

- **Scenes (`DevDeskApp`):** first, `Window("Open Project", id: "launcher") { LauncherView(context: .window) }` with content-size resizability, centered. Then `WindowGroup(for: ProjectRef.self) { $ref in ProjectWindow(ref:) }`; a nil ref shows `LauncherView(context: .window)`. `.defaultSize(width: 1440, height: 900)`, `.windowToolbarStyle(.unified(showsTitle: true))`, `.commands { DeskCommands() }`. One `@State OpenProjectRegistry` is injected with `.environment(_:)` into both scenes. `openWindow(value:)` with an already-open ref focuses that window (SwiftUI's value-based WindowGroup does this).
- **`ProjectWindow`:** owns `@State var model = ProjectWindowModel(ref:, source: DataSources.make(for: ref))`. It hosts a `NavigationSplitView`: `Sidebar` at width 236, `ContentRouter` as the detail. It also carries:
  - `.navigationTitle(project name)`, and `.navigationSubtitle("<displayPath> · <branch>")` when a branch is known.
  - `.sheet(item: $model.sheet) { SheetHost(model:, kind:) }`.
  - An `openURL` environment action that routes `DeskLink` URLs to `model.handle(_:)`, with `.systemAction` for everything else.
  - `.focusedSceneValue(\.projectModel, model)`, `.preferredColorScheme` from `@AppStorage(PreferenceKey.appearance)`, and `.frame(minWidth: 1100, minHeight: 720)`.
  - `.task { await model.load(); restoreLayout(); recordRecent() }`. Registry `windowOpened`/`windowClosed` run on appear and disappear.
  - Layout restore: `@SceneStorage` keys `desk.destination`, `desk.taskID`, `desk.tab`, `desk.dockPlacement` and `desk.dockOpen` are written on change and applied after the first load when present. A stored task id that no longer exists is ignored.
  - `recordRecent()` calls `AppServices.recents.record(ref, name:, displayPath:)` for local refs only.
- **`ProjectToolbar` (ToolbarContent, D:73–98):**
  - navigation placement: "Open project" (`folder` symbol + text) → `model.present(.openProject)`.
  - primaryAction placement, in order:
    - When `snapshot.activitySummary` exists, a non-interactive capsule (surface fill, controlBorder stroke, height 28) with a `StatusDot` and the label.
    - A segmented `Picker` (Focus / Parallel) bound through `model.setMode`.
    - "Ask about this project" (`.borderedProminent`, accent tint) → `model.toggleInsights()`.
- **`Sidebar` (D:102–144):** a custom `VStack`, not a `List`, on `DeskColor.sidebar` with a 1pt right border in `border`.
  - Header: `SectionLabel("Project")`, the name at 14/600, then the remote in mono 11 faintInk (or displayPath when there is no remote).
  - Five destination buttons: SF symbols from Global Constraints, padding 7×10, radius 6. Selected is accent fill with white text; otherwise navInk. `.accessibilityLabel` includes the badge.
  - Badges: Board shows `openTaskCount` at opacity .75. Findings shows `findingsCount` when > 0. Decisions shows `pendingDecisionCount` when > 0, bold, waiting-dot color.
  - Footer (top border): `SectionLabel("Connections")`, then one row per connection (`StatusDot` + name + trailing label). Dot and text color by state: connected → running dot, navInk text. notConnected or missing → disabledDot, faintInk. unavailable → failed dot and failed-dot-colored text. detected → info dot. Last comes `connectionsNote` at 11 faintInk.
  - While loading, the header shows the ref's name and nothing else.
- **`ContentRouter`:**
  - `.loading` shows a `ProgressView`. `.failed` shows `EmptyStateView("This project could not be opened", message)` with a Retry button that calls `load()`.
  - `.loaded` switches on the destination. For `.board`: parallel mode shows `ParallelScreen`; a selected task shows `TaskWorkspaceScreen(task:)`; otherwise `BoardScreen`. Every other destination shows its own screen.
  - The content sits in an `HStack` whose trailing member is `InsightsPanel(.docked)` at width 392 when open and docked.
  - The whole router has an `.overlay(alignment: .bottomTrailing)` that shows `InsightsPanel(.floating)` at 404×520, padded 36 trailing and 34 bottom, when open and not docked.
  - A non-nil `model.reloadError` shows a `NoticeBanner(.failed, "Reload failed", message)` above the content.
- **`DeskCommands`:**
  - "Open Project…" ⌘O opens the launcher window; it replaces `.newItem`.
  - A "Project" menu:
    - one item per destination (⌘1–⌘5) → `go(_:)`;
    - "Focus" / "Parallel" (⌃⌘1 / ⌃⌘2);
    - "Reload" ⌘R → `Task { await model.load() }`;
    - "Ask About This Project" ⇧⌘I → `toggleInsights()`;
    - "Show Agents Dock" ⌥⌘D → `toggleDock()`.
  - Every item is disabled when there is no focused model.
- **`TerminalTranscriptView`** (D:490–523):
  - terminalGround background, padding 10×12, mono at the `@AppStorage(PreferenceKey.terminalFontSize)` size (default 12), line spacing ≈ 1.65.
  - The header line in terminalDim. Line kinds map to colors: plain → terminalInk, success → terminalOK, failure → terminalError, dim → terminalDim2.
  - When `showsPrompt` is set, a final row shows "❯" in terminalOK and a 7×15 block cursor that pulses at 1.1 s, static under Reduce Motion.
  - Read-only transcripts have no prompt. Text is selectable.
- **`ActivityEventRow`** (D:361–370):
  - A 52pt-wide time column in mono 11 faintInk, then the `MarkdownText` event text.
  - An optional detail uses a `DisclosureGroup` with a surface fill, border and radius 7. Its label is in accent at 12; its lines are mono 11.5 secondaryInk at line spacing 1.6.
  - An optional trailing "Request follow-up" link button.
- **`README.md`:** one paragraph on what Dev Desk is (a first build of the container in `docs/superpowers/specs/2026-09-11-container-design.md`), then the build and test commands from this plan's Commands section, and "Open a sample project from the picker, or any local folder."

**Steps:**

- [ ] **Step 1:** Write `project.yml`, the asset catalog and `README.md`. Run `cd apps/desk && xcodegen generate`; expect `Created project at .../DevDesk.xcodeproj`.
- [ ] **Step 2:** Write the Design files, then the App files, then the ten stub files.
- [ ] **Step 3:** Build: `xcodebuild -project apps/desk/DevDesk.xcodeproj -scheme DevDesk -destination 'platform=macOS' -derivedDataPath /tmp/devdesk-dd-task2 build 2>&1 | tail -3`. Expect `** BUILD SUCCEEDED **` with no warnings from DevDesk files.
- [ ] **Step 4:** Launch the app once: `open "/tmp/devdesk-dd-task2/Build/Products/Debug/Dev Desk.app"`. Confirm it starts and shows the launcher window without crashing, then quit it (`osascript -e 'quit app "Dev Desk"'`). Window-level checks happen in Task 9, once the launcher is real.
- [ ] **Step 5:** `swift test --package-path apps/desk/DeskCore` still passes. Leave the changes uncommitted.

### Task 3: Real data — git and GitHub for an opened folder

Replaces the interim `LocalGitDataSource.load()` with the full read-only mapping, and adds the Clone and Create operations the launcher calls. Board classification mirrors `scripts/dev.py` (`classify`, `build_board`, `resolve_active_milestone`, lines 269–317 and 587–598) so the app and `dev:kanban` agree. Read those functions before writing `BoardBuilder`.

**Files:**
- Modify: `apps/desk/DeskCore/Sources/DeskCore/Local/LocalGitDataSource.swift` (replace `load()`; keep `identity()`, `git(_:)`, `abbreviate`)
- Create: `apps/desk/DeskCore/Sources/DeskCore/Local/{GitReader,GitHubReader,BoardBuilder,ActiveMilestone,PipelineState,SurveyReportParser,ADRParser,ToolDetection,ProjectOperations}.swift`
- Test: `apps/desk/DeskCore/Tests/DeskCoreTests/{FakeRunner,GitParsersTests,BoardBuilderTests,ActiveMilestoneTests,GitHubDecodingTests,PipelineStateTests,SurveyReportParserTests,ADRParserTests,LocalGitDataSourceTests,ProjectOperationsTests}.swift`

**Interfaces:**
- Consumes: Task 1's models, `CommandRunner`, `CommandTimeout`, `GitRemote`, `LocalGitDataSource.identity()`.
- Produces:
  - `public enum ProjectOperations { static func cloneRepository(url: String, into parent: URL, runner: CommandRunner = ProcessRunner()) async throws -> URL; static func createProject(named name: String, in parent: URL, runner: CommandRunner = ProcessRunner()) async throws -> URL }`
  - `public enum ProjectOperationError: Error, Equatable, LocalizedError { case invalidName(String), destinationExists(String), cloneFailed(String), initFailed(String) }`, each with a plain-English `errorDescription`.

#### Reads (all through `CommandRunner`; independent reads run concurrently with `async let`)

| Fact | Command | Notes |
|---|---|---|
| is a repo | `git rev-parse --show-toplevel` | failure → board, findings, roadmap and decisions `.unavailable("This folder is not a git repository.")` |
| base | `git branch -r --format=%(refname:short)` | first of staging, develop, main, master present as `origin/<name>`; else the current branch (dev.py `resolve_base`). baseRef = `<name>` if `git rev-parse --verify --quiet refs/heads/<name>` succeeds, else `origin/<name>`. baseShort = `git rev-parse --short <baseRef>` |
| local branches | `git for-each-ref --format=%(refname:short) refs/heads` | excluding base |
| unmerged count | `git rev-list --count <baseRef>..<branch>` | per branch |
| worktrees | `git worktree list --porcelain` | map `branch refs/heads/<name>` → `worktree <path>` |
| commits | `git log --format=%h%x1f%an%x1f%aI%x1f%s -n 50 <baseRef>..<branch>` | one event per commit |
| diff | `git diff --numstat <baseRef>...<branch>` and `git diff --no-color --no-ext-diff -U3 <baseRef>...<branch>` | split the unified diff on `diff --git a/X b/Y`; cap 200 files and 1500 lines per file (`truncated = true`); numstat `-\t-\t` is binary (additions/deletions nil) |
| pipeline state | read `<root>/.dev/<slug>.json`, where slug replaces `[^A-Za-z0-9._-]` with `-` (dev.py `slugify`) | keys `phase`, `phase_group`, `tier`, `phases_completed`; missing or unparsable → nil |
| gh ready | `gh auth status --hostname github.com` | status 127 → "gh not installed"; non-zero → "not signed in to GitHub"; the remote has no `GitRemote.githubSlug` → "the remote is not on GitHub" (no remote → "no GitHub remote"). Parse the account from "Logged in to github.com account NAME" |
| open issues | `gh issue list --repo SLUG --state open --limit 200 --json number,title,labels,milestone,updatedAt,body,url` | |
| open PRs | `gh pr list --repo SLUG --state open --limit 100 --json number,title,headRefName,reviewDecision,isDraft,url,body` | |
| merged PRs | `gh pr list --repo SLUG --state merged --limit 10 --json number,title,headRefName,mergedAt,url` | Done column |
| milestones | `gh api repos/SLUG/milestones?state=open` | fields `title`, `due_on`, `created_at`, `open_issues`, `closed_issues` |
| PR checks | `gh pr checks N --repo SLUG --json name,bucket,link` | parse stdout even on a non-zero exit (gh exits 8 while checks are pending); at most 10 PRs |
| tools | `which codex`, `which claude`, `which gemini` | status 0 → `.detected "CLI found"`, else `.missing "not found"` |

#### Board (`BoardBuilder`, pure: inputs in, `[DeskTask]` out)

1. Open issues, skipping epic parents (label `epic`) that still have open checklist children (`- [ ] #N` lines, dev.py `TASK_LINE`). Matched branch: the first branch matching `^(gh-)?N(-|$)` or containing `/N-`. Linked PR: an open PR whose `headRefName` is that branch, or whose body matches `(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#N\b`.
2. Column: label `epic-leftover` → backlog with cardBadge `.neutral "Deferred"`; linked PR → review; unmerged > 0 → inProgress; milestone title == active milestone → queued; else backlog. Backlog order: P1, P2, P3 labels, then unlabelled; within that, oldest `updatedAt` first, then number (dev.py `order_next`).
3. Open PRs linked to no issue → review tasks, id `pr:N`, cardMeta "PR #N".
4. Branches with unmerged > 0 that match no issue and are no PR head → inProgress tasks, id `branch:<name>`, title = branch name.
5. Merged PRs → done tasks, id `merged:N`, cardMeta "merged", dimmed, header `.ended "Merged"`.

Per-task fields:
- **cardBadge.** In progress: `.neutral "N commit(s) ahead"`. Review: draft → `.neutral "Draft"`; CHANGES_REQUESTED → `.failed "Changes requested"`; APPROVED → `.running "Approved"`; REVIEW_REQUIRED → `.info "Review requested"`; else `.info "PR open"`.
- **headerBadge.** The cardBadge, or `.neutral "Queued"` / `.neutral "Backlog"`.
- **cardNote.** "Phase <n> · <group> · advisory" when pipeline state exists.
- **branchLine.** "<branch> · base <base>@<baseShort>", plus " · worktree <abbreviated path>" when the branch is checked out elsewhere. "No branch yet" when there is none. parallelLine is the branch, plus " · <worktree path>".
- **nextAction.** A local branch with commits → `.reviewChanges`; else a PR url → `.openURL(url, title: "Open pull request")`; else an issue url → `.openURL(url, title: "Open on GitHub")`.
- **activity.** Commits: id = sha; time is "HH:mm" today, else "d MMM" (`en_US_POSIX`); text "**<author>** <subject>", with markdown metacharacters in the subject escaped; detail `ToolDetail(title: "Commit <sha>", lines: [<ISO date>])`. No branch → `.available([])`.
- **pipeline.** Stages Investigated (phases 1–4), Planned (5–8), Implementing (9–10), Verified (11–13). A stage is done when phase > its range, current when phase is inside it, pending otherwise; phase ≥ 14 → all done. Note "Advisory — read from .dev state; git wins any disagreement."
- **requirements.** Issue (or PR for `pr:` tasks) → `Requirements(goal:, criteria:, sources:, body:)`. goal is the first body paragraph not starting with `#`, `-`, `*`, `|` or `>`, else the title. criteria are the lines `^\s*[-*]\s*\[( |x|X)\]\s*(.+)$`. sources "Issue #N" / "Pull request #N". body is the full body. Branch-only → `.unavailable("No linked issue. Name the branch gh-<number>-… to link one.")`.
- **changes.** From the diff reads. displayPath is the last two path components. baseNote "Diff is against `<base>` at `<baseShort>`.". A PR head branch missing locally → `.unavailable("The branch `<head>` is not in this checkout. Fetch it to see its diff.")`. No branch → `ChangeSet(files: [], baseNote: "No branch yet.")`.
- **evidence.**
  - PR checks: bucket pass → passed "passed"; fail → failed "failed"; pending → warning "pending"; skipping/cancel → warning with the bucket name. revisionLabel "PR #N".
  - Pipeline state adds `CheckResult(id: "pipeline", name: "Pipeline state", outcome: .passed, outcomeLabel: "phase <n> · <tier or "no tier">", revisionLabel: "advisory")`.
  - limitations when any check exists: "CI results reported by GitHub for this pull request. Dev Desk has not verified behaviour in a running app."
  - isDemo false.
- **agents** [], agentsNote "No managed sessions. Dev Desk doesn't start agents yet.", dock nil. parallel: `.activity(first 5 events)` for a branch, else `.none("No branch yet")`.
- **dependencies.** From the body: `(?i)\b(blocked by|depends on)\s+#(\d+)` → "Blocked by [#N](desk://task/N)"; `(?i)\bblocks\s+#(\d+)` → "Blocks [#N](desk://task/N)"; taskID "N".

boardNote:
- GitHub ready: "Columns follow dev:kanban's rules: git decides In progress and Review, and the active milestone decides Queued.", then either " Active milestone: <title> (<why>)." or " No active milestone, so Queued is empty.".
- GitHub not ready: "GitHub is unavailable (<reason>), so only local branches are shown."

`ActiveMilestone.resolve(_:) -> (title: String?, why: String)` is dev.py's rule verbatim: nearest `due_on`, where a same-day tie on the first 10 characters gives nil with "<a> and <b> are due the same day"; else the oldest `created_at` "oldest open milestone; none has a due date"; empty gives nil "no open milestone".

#### Other surfaces

- **Findings.** Files `docs/survey/*.md`, newest filename first; a run is `SurveyRun(id: stem, label: stem, revision: nil)`. `SurveyReportParser` reads the report format in `skills/survey/SKILL.md` lines 225–245.
  - Bullets under `## CONFIRMED` → categories [.new], verificationLabel "Code-inspected · confirmed by review".
  - Bullets under `## PLAUSIBLE` → [.needsDecision], "Unconfirmed observation".
  - Bullets under `## ALREADY TRACKED` → [.knownNewEvidence], "Already tracked".
  - Split a bullet on " · ": title = first part; locations = parts matching `^[\w./-]+:\d+`, plus the paths after `touches:` on its indented continuation line; summary = the remaining parts joined with " · ".
  - ids `<stem>-C<n>`, `-P<n>`, `-T<n>`; listDetail = the category's raw value; limits "Survey checks code only; nothing here was reproduced in a running app."
  - No folder → `FindingsReport(runs: [], findings: [])`.
- **Roadmap.** GitHub not ready → `.unavailable(reason)`.
  - One theme per open milestone ("Milestone · <title>", ordered by due date, then creation), holding that milestone's open issues as items (commitment `.committed`, `linkText` "Board: [#N](desk://task/N)").
  - workType from labels: epic → "Epic", bug → "Defect", enhancement/feature → "Feature", else "Task". priority from the P1–P3 label, else "Unprioritised".
  - Issues labelled `security` or `critical` go to a "Critical concerns" theme (isCritical) instead of their milestone theme. Epic issues with no milestone go to "Not scheduled" (`.considered`).
  - Milestones: progress = closed/(open+closed) (0 when empty); note "<closed> of <total> issues closed · due <yyyy-MM-dd>" or "· no due date".
  - Note: "Themes are this repository's open milestones. Work type, priority and commitment come from labels and milestone membership."
- **Decisions.** `docs/adr/*.md` except README.md, newest number first. `ADRParser`:
  - title = the `# ` line with its leading number and dash removed; status = the value of `Status:`; date = the value of `Date:`; rationale = the `## Decision` section with whitespace collapsed, at most 600 characters.
  - Each becomes `Decision(id: stem, listTitle: title, listMeta: "ADR <num> · <status> · <date>", state: .answered, question: title, context: "Recorded in `docs/adr/<file>`", answer: DecisionAnswer(optionTitle: nil, rationale:, answeredLabel: "<status> <date>"), body: full markdown)`.
  - No folder → `.available([])`.
- **Connections.** The three tool rows plus GitHub (`.connected "connected"` or `.unavailable <reason>`). connectionsNote "Detected on this Mac. Dev Desk doesn't connect to agents yet." capabilities: providers ["Codex", "Claude", "Gemini"], the design's three row names, every value `.notValidated`, note "No agent integration has been validated. Capabilities will be read from a connection once one exists."
- **Insights.** `.unavailable("Insights needs a validated agent connection. None is set up, so this panel can't answer yet.")`.
- **projectFacts.** Base branch, Base revision, Remote (or "none"), Active milestone (title or "none — <why>"), GitHub account (or the reason).

#### ProjectOperations

- `createProject`: trim the name; reject empty, `.`, `..`, or any name containing `/` or `:` (`.invalidName`); refuse an existing destination (`.destinationExists`). Then create the folder, run `git init` (`.initFailed(stderr)` on failure), write `PROJECT_MAP.md` containing exactly `"# PROJECT_MAP\n\n## TECH_STACK\n\n## SYSTEM_FLOW\n\n## ORPHANS & PENDING\n"`, and return the folder.
- `cloneRepository`: trim the URL; the folder name is its last path component minus a trailing `/` and `.git`, validated like a project name. Refuse an existing destination. Run `git clone -- <url> <dest>` in `parent` with `CommandTimeout.clone`. On failure throw `.cloneFailed(<last non-empty stderr line>)`. Return the destination.

#### Tests

- `FakeRunner`: responses keyed by `"<tool> <args joined by space>"`. It records calls; an unscripted call returns status 1 with stderr "unscripted".
- `BoardBuilderTests` builds one fixture covering every rule:
  - issue 12 with branch `gh-12-x` 2 ahead → inProgress, "2 commits ahead";
  - issue 13 with a PR on `gh-13-y` in CHANGES_REQUESTED → review, "Changes requested";
  - issue 14 in active milestone "v2" → queued;
  - issue 15 → backlog;
  - issue 16 `epic-leftover` → backlog "Deferred";
  - epic 17 with an open child → absent;
  - unlinked PR 20 → review `pr:20`;
  - branch `spike/z` 1 ahead → inProgress `branch:spike/z`;
  - merged PR 9 → done `merged:9`.
  - Plus backlog ordering: a P1 issue comes before an older unlabelled one.
- `ActiveMilestoneTests`: nearest due wins; a same-day tie gives nil with both names in `why`; undated → oldest; empty → nil.
- `GitParsersTests`: numstat with a binary row; a two-file unified diff with two hunks; truncation at the cap; the log format; worktree porcelain; base preference staging > develop > main > master.
- `GitHubDecodingTests`: fixtures for issues, PRs, milestones, checks, and the auth account line.
- `PipelineStateTests`: phase 9 → done, done, current, pending; phase 3 → current, pending, pending, pending; slug "feat/a b" → "feat-a-b".
- `SurveyReportParserTests`: a report with 2 CONFIRMED (one with `touches:`), 1 PLAUSIBLE, 1 ALREADY TRACKED → 4 findings with the right categories and locations.
- `ADRParserTests`: an inline fixture copied from `docs/adr/0002-diagrams-land-in-the-repo.md` → title "Evidenced diagrams land in `docs/arch/`, with their IR beside them", status "Accepted", date "2026-08-31".
- `LocalGitDataSourceTests`:
  - A real temp repo (`git init -b main`, commit, `git checkout -b feature/x`, commit a file) gives an inProgress task `branch:feature/x` with "1 commit ahead", 1 activity event, that file in its changes, a boardNote starting "GitHub is unavailable", and GitHub state `.unavailable`.
  - A plain folder gives a board `.unavailable("This folder is not a git repository.")`.
  - A FakeRunner-backed repo with gh ready gives decisions parsed from a temp `docs/adr/0001-x.md`.
- `ProjectOperationsTests`: create succeeds (a `.git` dir exists and `PROJECT_MAP.md` has the exact text); create refuses "a/b" and an existing folder; clone from a local temp repo path succeeds; clone into an existing destination refuses.

**Steps:** TDD per component in the order FakeRunner → parsers → ActiveMilestone → BoardBuilder → PipelineState → Survey/ADR parsers → LocalGitDataSource → ProjectOperations. For each: write the test, run `swift test --package-path apps/desk/DeskCore --filter <Suite>` and see it fail, implement, see it pass. Finish with the full `swift test` (all passing, no warnings from your files). Leave the changes uncommitted.

### Task 4: System model page and evidenced diagram (deliverable A)

Container spec §7 row A: "`documentation/SYSTEM-MODEL.md` (section 2 as a page) + `docs/arch/dev-system.*` rendered with `dev:arch`". Follow the `dev:arch` door exactly (`skills/arch/SKILL.md`), with the overrides in this task. Its rules win anywhere this task is silent.

**Files:**
- Create: `documentation/SYSTEM-MODEL.md`
- Create: `docs/arch/dev-system.architecture.json`, `docs/arch/dev-system.html`

**Interfaces:**
- Consumes: nothing from the app tasks. Task 10 writes the two ADRs this page links to, under these exact names: `docs/adr/0012-the-mac-app-lives-in-apps-desk.md` and `docs/adr/0013-the-app-reads-git-and-github-directly.md`.
- Produces: the page and the diagram, which Task 10 links from README.

#### The pin, and why you must not read the working tree

- Pin every source to **`321fb15a6e78d497c49dccbdfecf5c7e431b6eca`** (`origin/main` when this branch was cut). This branch does not touch any path you may cite, so the pin survives the squash merge (`skills/arch/SKILL.md` → *Pin to a commit that is already on the base branch*).
- Other agents are editing this checkout while you work. **Read every cited file with `git show 321fb15a6e78d497c49dccbdfecf5c7e431b6eca:<path>`**, never from disk.
- **Never cite** these paths, which this branch modifies or adds: `PROJECT_MAP.md`, `README.md`, anything under `documentation/`, `docs/adr/README.md`, `docs/superpowers/specs/2026-09-11-container-design.md`, `docs/superpowers/specs/2026-09-11-mac-app-navigation-and-insights-design.md`, `.github/**`, `apps/**`, `docs/design/dev-desk.dc.html`. You may *read* the container spec for content.

#### What to draw (type: architecture, evidence mandatory, `quality_profile: "standard"`)

The five layers of container spec §2, each lower layer authoritative over the one above:
- **Truth:** git branches and commits, GitHub issues and PRs.
- **Memory:** PROJECT_MAP, ADRs, survey/ideation reports, `.dev/<branch>.json`.
- **Engine:** the doors, `shared/pipeline.md` and its four human gates.
- **Helpers:** the `dev` CLI and the hooks.
- **Container:** Dev Desk.

Each component carries 1–3 sources. Starting points, each to be verified at the pin before you cite it:
- `shared/entry.md` (workspace resolution via `git remote get-url origin`)
- `scripts/dev.py` (`cmd_board`'s `gh issue list`, around 330–341; `state_path`/`save_state`, around 78–110)
- `skills/insights/SKILL.md` (maintains PROJECT_MAP)
- `shared/pipeline.md` (Phase 1 context load; "Four gates stop anyway")
- `docs/adr/0001-adrs-live-in-docs-adr.md`
- `skills/survey/SKILL.md` (the `docs/survey/<date>.md` report)
- `hooks/README.md`
- `docs/design/dev-desk-app-design-prompt.md` (the Container node — its purpose and navigation sections)

Edges state authored relationships only: doors write Truth and Memory; helpers read Truth and Memory; the container reads Truth and Memory. Put the container's first-build specifics in a card:
- it reads git and gh directly (ADR 0013);
- it does not start agents yet;
- its evidence points at the design brief at the pin, and a follow-up re-pin will cite `apps/desk/` once merged.

Draw no edge for anything unbuilt (the runner, `dev snapshot`, `dev events`). Name those in a card as not built.

#### Rendering

Resolve Archify per `skills/arch/SKILL.md` Phase 2. It is expected at `~/.claude/skills/archify/`. `export ARCHIFY_UPDATE_CHECK_DISABLED=1` before every call and run `doctor`; record the version. Validate and deliver with `--repo-root .` from this checkout: `node "$ARCHIFY/bin/archify.mjs" validate architecture docs/arch/dev-system.architecture.json --repo-root .`, then `deliver … docs/arch/dev-system.html --repo-root .`. The repair loop is capped at 8 cycles plus 2 simplification cycles (the door's rule). Copy the receipt verbatim into your report: `N/N artifact checks`, the profile, and the sha256. If Archify or `doctor` fails, stop and report BLOCKED. Never hand-draw a fallback.

#### The page (`documentation/SYSTEM-MODEL.md`, under about 90 lines)

Match the tone and structure of `documentation/GUIDE.md` and `documentation/WORKFLOW.md` (read both at HEAD; they are reader docs). Sections:
1. What the family is made of, in one paragraph.
2. **The five layers**: a table of Layer / Holds / Written by, then the authority rule in one sentence.
3. **The container today**: Dev Desk in `apps/desk/`. It opens sample projects and real folders; for a folder it reads git and GitHub directly (ADR 0013). It lives in this repo (ADR 0012). It does not start agents; Decisions shows ADRs as history, Findings reads `docs/survey/` reports, and Insights is unavailable for real projects.
4. **Not built yet**: the shared runner and jobs, `dev snapshot` / `dev events` (container spec §3), provider integrations, and tracker writes.
5. **See also**: links to `docs/arch/dev-system.html` (say that the HTML file carries the evidence and exported images do not), the container spec, the continuity spec, the navigation spec, `docs/design/dev-desk.dc.html`, and the two ADRs.

No marketing language, no emoji. State what exists, not what is hoped for.

**Steps:**

- [ ] **Step 1:** Read `skills/arch/SKILL.md` in full. Resolve Archify, run `doctor`, record the version.
- [ ] **Step 2:** Read each candidate source with `git show 321fb15…:<path>` and choose exact line ranges.
- [ ] **Step 3:** Author the IR, with `meta.repository` = `{"url": "https://github.com/hasansa007/dev-skill", "revision": "321fb15a6e78d497c49dccbdfecf5c7e431b6eca"}` and `output: "dev-system.html"`. Follow the shape of `docs/arch/dev-family.architecture.json` at HEAD.
- [ ] **Step 4:** Run validate → repair → deliver. Paste the receipt.
- [ ] **Step 5:** Write `documentation/SYSTEM-MODEL.md`.
- [ ] **Step 6:** Negative control: copy the IR to `/tmp`, set one `line` past the end of its file, validate it with `--repo-root .`, and confirm `repository-evidence/line-out-of-range`. Delete the copy. Leave the changes uncommitted.

### Task 5: Board and Parallel screens

**Files:**
- Replace stub: `apps/desk/DevDesk/Screens/Board/BoardScreen.swift`, `apps/desk/DevDesk/Screens/Board/ParallelScreen.swift`
- Create: `apps/desk/DevDesk/Screens/Board/TaskCard.swift`

**Interfaces:**
- Consumes: `ProjectWindowModel` (`tasks`, `searchText`, `showBacklog`, `lastOpenedTaskID`, `openTask(_:)`, `setMode(_:)`, `openDecision(_:)`, `go(_:)`, `parallelTasks`, `snapshot.board`, `snapshot.boardNote`); Task 2 primitives (`StatusPill`, `SectionLabel`, `EmptyStateView`, `UnavailableView`, `NoticeBanner`, `TerminalTranscriptView`, `ActivityEventRow`, `DeskButtonStyle`, `DeskColor`, `DeskFont`, `DeskMetric`).
- Produces: nothing other tasks call. Keep the signatures: `BoardScreen(model:)`, `ParallelScreen(model:)`.

**Board (D:148–236; the dev-skill window's cards D:53–64 use the same card):**
- **Header bar:** surface fill, bottom divider, padding 12×16, spacing 10.
  - "Board" at 15/600.
  - Search field: capsule, height 26, min width 200, border, 12pt, placeholder "Search tasks". Bound to `model.searchText`; filters case-insensitively on title, issue label and cardMeta.
  - "Show backlog" toggle button (height 26, radius 6; accent fill and white text when on, else surface and ink) bound to `model.showBacklog`.
  - Flexible space, then `boardNote` at 12 mutedInk, one line, truncating.
- **Columns:** a horizontal `ScrollView` (padding 16, spacing 14). Backlog appears only when `showBacklog` is on, followed by Queued, In progress, Review and Done.
  - Each column is 246 wide and holds a header (`SectionLabel(column.title)` plus the count in disabledDot color) and its cards at spacing 8.
  - A column with no cards shows only its header.
- **`TaskCard`** (a `Button` with a plain style, keyboard-focusable), D:162–232:
  - surface fill, 1pt border, radius 9, padding 11. Title at 13/600 with line spacing for a 1.35 line-height.
  - At top 9, a row: issueLabel (plus " · <cardMeta>") in mono 11 mutedInk, then `StatusPill(cardBadge)` or `cardInlineText` at 11 mutedInk.
  - At top 8, the optional `cardNote` at 11, in mutedInk or, when `cardNoteIsWarning`, the failed dot color.
  - `isDimmed` → opacity 0.72.
  - `id == lastOpenedTaskID` → accent 1pt border plus a 3pt accent ring at 14% opacity (D:187).
  - Click → `openTask(id)`. The accessibility label joins title, issue label and badge label.
- **States:**
  - `board` unavailable → `UnavailableView(reason)` below the header.
  - Board available but no tasks at all → `EmptyStateView(title: "No tasks yet", message: "Describe the first piece of work, or run a survey to learn the codebase.")` with a secondary "Open Findings" → `go(.findings)` (D:854).
  - A search that empties every column → "No tasks match “<query>”." at 13 mutedInk under the header.

**Parallel (D:238–276):**
- **Header** (surface, bottom divider, padding 12×16):
  - "‹ Back to Board" (secondary, small) → `setMode(.focus)`.
  - "Parallel view" at 15/600.
  - An explanation at 12 mutedInk: exactly D:243 when there are 2 panes; otherwise "Independent tasks, separate checkouts and branches. Running in parallel does not guarantee the changes integrate."
- **Panes:** one per `model.parallelTasks` entry, equal widths, separated by 1pt dividers.
  - Pane header (surface, bottom divider, padding 12×14): "<issueLabel> <title>" at 13/600 plus `StatusPill(headerBadge)`, then `parallelLine` in mono 11 mutedInk. Clicking the header → `openTask(id)`.
  - Pane body by `parallel`:
    - `.transcript` → `TerminalTranscriptView`, filling the pane.
    - `.decision` → padding 14, a waiting `NoticeBanner(title:, message: question)` with a primary "Answer decision" → `openDecision(decisionID)`, then `note` at 12 mutedInk with top 12.
    - `.activity` → `ActivityEventRow`s at padding 14.
    - `.none(text)` → `EmptyStateView(title: text, message: "")`.
- **No panes** → `EmptyStateView(title: "Nothing is running in parallel", message: "Parallel view shows in-progress tasks that have their own branch and checkout.")`.

**Previews:** one `PreviewProvider` per screen on a `ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))`, loaded in `.task`, framed at 1204×868. For the board list, call `go(.board)` after load.

**Steps:**
- [ ] **Step 1:** Write the three files.
- [ ] **Step 2:** Typecheck with the controller's script: `<typecheck script> apps/desk/DevDesk/Screens/Board/*.swift`. Expect no errors or warnings from your files.
- [ ] **Step 3:** Self-check against D:148–276. List each design element and where your code produces it in the report. Leave the changes uncommitted.

### Task 6: Task workspace, agents inspector, and the Agents & Terminals dock

The prototype's centrepiece (D:278–526). The design calls for the most care here: the dock and inspector must say honestly what each agent can and cannot do.

**Files:**
- Replace stub: `apps/desk/DevDesk/Screens/Task/TaskWorkspaceScreen.swift`
- Create: `apps/desk/DevDesk/Screens/Task/{TaskHeader,ActivityTab,TaskNoticeViews,RequirementsTab,ChangesTab,DiffView,EvidenceTab,AgentsInspector,AgentsDock}.swift`

**Interfaces:**
- Consumes: `ProjectWindowModel` (`tab`, `dockOpen`, `dockPlacement`, `dockSplit`, `dockTabID`, `go`, `performNextAction`, `openDecision`, `openFinding`, `present`, `perform(_:agentID:)`, `toggleDock`, `setDockPlacement`, `toggleSplit`), the `DeskTask` fields, the Task 2 primitives, and `@Environment(\.openURL)`.
- Produces: `TaskWorkspaceScreen(model:task:)`.

**Layout:**
- A header on top.
- The body depends on dock placement:
  - Bottom placement (or any width under 1200): `VStack { HStack { tabContent; inspector }; dock at height 272 }`.
  - Side placement: `HStack { HStack { tabContent; inspector }; dock at width 460 }`.
- The dock is shown only when `dockOpen && task.dock != nil`.
- Tab content scrolls with padding 16×18. The inspector is 262 wide on the inspector fill, with a leading divider and padding 14.
- Below 980 total width the inspector hides, and the header gains a secondary "Agents" button that shows the inspector in a `.popover`.

**Header (D:281–298):**
- "‹ Board" (secondary, small) → `go(.board)`; title at 16/600; issueLabel in mono 12 mutedInk; `StatusPill(headerBadge)`; flexible space.
- When a `nextAction` exists, a primary button with its title: `if let url = model.performNextAction() { openURL(url) }`.
- A secondary dock toggle, "Hide agents dock" / "Show agents dock", disabled with help "No session views for this task" when `task.dock == nil`.
- `branchLine` in mono 12 mutedInk at top 7.
- The tab bar at top 10: four buttons with padding 7×14 at 13pt. The selected tab has a 2pt accent bottom rule and ink text; the others mutedInk.

**Activity tab:**
- **`.externalConnection`** (D:307–326):
  - A neutral panel: neutralChipFill, border, radius 9, padding 14.
  - Inside: the title at 13/600, then `MarkdownText(message)` in secondaryInk with max width 760.
  - Three level cards: surface, border, radius 8, padding 10; opacity 0.75 when unavailable. Each shows the name at 12/600, the status at 12 (running fg when available, faintInk when not), and the detail at 11 mutedInk.
  - An action row:
    - A primary "Start with handoff…" → `present(.handoff)`, shown only when `task.handoff != nil`.
    - A secondary "Open in Finder", which reveals the tilde-expanded `checkoutPath` with `NSWorkspace.shared.activateFileViewerSelecting`. It is disabled with help "This checkout does not exist on this Mac" when the path is missing.
    - `handoffNote` at 11 mutedInk.
  - Then `SectionLabel("Repository facts")` at top 16 and a `KeyValueTable(facts)`.
- **`.waitingForDecision`** (D:332–338): a waiting `NoticeBanner` with a trailing primary "Answer decision" → `openDecision(decisionID)`.
- **Pipeline** (D:349–360): `SectionLabel("Pipeline")`, then one chip per stage separated by "›" in disabledDot. Done chips use the running tone; the current chip uses the info tone, semibold; pending chips are neutralChipFill2 with faintInk text. The optional note follows at 11 faintInk.
- **Events:** `SurfaceView(task.activity)`. An empty list shows "No activity yet." at 13 mutedInk. Otherwise `ActivityEventRow` at spacing 10, max width 860, with `onFollowUp` → `present(.followUp)` when `offersFollowUp`.
- **`canCompareOutputs`:** a leading secondary "Compare two agent outputs…" → `present(.compareOutputs)`.

**Requirements tab (D:376–389):**
- `SurfaceView(requirements)` with max width 820.
- Goal: `SectionLabel("Goal")` and the text.
- Criteria, when any: `SectionLabel("Acceptance criteria")`, then cards (surface, border, radius 8, padding 10). A met criterion shows `checkmark` in the running dot color; an unmet one shows `circle` in disabledDot.
- Optional "Out of scope" in secondaryInk.
- Optional "Sources" as `MarkdownText`.
- Optional "Issue description": the body as selectable plain text in a card, with whitespace preserved.

**Changes tab (D:393–419):**
- `SurfaceView(changes)`. With no files → `EmptyStateView(title: "No changes", message: <baseNote rendered as markdown>)`.
- Otherwise the left column is 290 wide:
  - `SectionLabel("Changed files · N")` and a bordered list (radius 8).
  - Each row: path in mono 11.5 with middle truncation, "+N" in the running fg, "−N" in the failed dot color ("binary" when nil).
  - The selected row (local `@State`, first file by default) uses the info fill.
  - `baseNote` as `MarkdownText` at 11 mutedInk, top 10.
- The right side is the `DiffView` card (surface, border, radius 8):
  - A header bar on headerFill with the full path in mono 11.5 secondaryInk.
  - Hunks: the header line in faintInk; lines prefixed "  " / "- " / "+ ", with the delete and add fill and ink, context in secondaryInk, mono 11.5, spaced for a 1.7 line-height. Both axes scroll.
  - `truncated` → a footer "Diff truncated at 1,500 lines."
  - No diff for the file → a centred "No preview for this file." in faintInk.

**Evidence tab (D:423–447):**
- `SectionLabel("Checks")`, plus `PropertyChip("Demo content")` when `isDemo`.
- A bordered table: rows padded 10×12 with row dividers. Each row has the name (flex), the outcome label in its color (passed → running fg, warning → `#B7791F` via the waiting dot, failed → failed dot), and the revision at 12 mutedInk in a right-aligned 190pt column. Failed rows use the failed fill.
- No checks → "No checks recorded for this task."
- `failure` → a failed `NoticeBanner` with secondary small "View log" and "Retry run", both disabled with help "No runner is connected, so there is no log or retry."
- "Limitations" text.
- "Linked evidence" rows: surface card with the title (flex), `PropertyChip(badge)`, and a secondary small "Open in Findings" → `openFinding(findingID)`.

**Inspector (D:452–486):**
- `SectionLabel("Agents")`. With no agents, show `agentsNote` at 12 mutedInk.
- Otherwise one card per agent (surface, border, radius 8, padding 10):
  - `StatusDot(tone, pulses)`, the name at 12/600, and the role at 11 mutedInk trailing;
  - `stateLabel` at 11 mutedInk;
  - one mini secondary button per action → `perform(action, agentID:)`.
- "Dependencies": each is `MarkdownText` at 12 secondaryInk; its desk:// links open through the environment. Omit the section when there are none.
- "Dock placement": mini "Bottom" and "Side" (selected = accent fill) → `setDockPlacement`, disabled when there is no dock.

**Dock (D:489–523):** terminalGround, with a black 1pt border on the edge facing the content.
- **Bar:** height 34, terminalBar, padding h10.
  - Tab buttons: padding 4×10, radius 5, 11.5pt. The selected tab (`dockTabID ?? first`) has accent fill and white text; the others terminalDim2.
  - Flexible space, then the `caption` at 11 terminalDim.
  - "Split panes" / "Single pane" → `toggleSplit()`, disabled when `splitTabID == nil`. "Hide" → `toggleDock()`. Both are 22pt high, terminalControlFill with terminalControlBorder, 11pt terminalInk.
- **Body:** the primary pane shows the selected tab's `TerminalTranscriptView`. When split, a second pane shows the `splitTabID` transcript beside it (bottom placement) or below it (side), with a black divider. If the selected tab is the split tab, the primary pane shows the first other tab instead.

**Previews:** tasks 42 (activity, with the dock), 57, and 63, each on the loaded StudyHub model.

**Steps:**
- [ ] **Step 1:** Write the files in the order header → tabs → inspector → dock → screen.
- [ ] **Step 2:** Typecheck: `<typecheck script> apps/desk/DevDesk/Screens/Task/*.swift`. Clean.
- [ ] **Step 3:** Self-check against D:278–526, element by element, in the report. Leave the changes uncommitted.

### Task 7: Findings, Roadmap, and Decisions screens

**Files:**
- Replace stub: `apps/desk/DevDesk/Screens/Findings/FindingsScreen.swift`, `apps/desk/DevDesk/Screens/Roadmap/RoadmapScreen.swift`, `apps/desk/DevDesk/Screens/Decisions/DecisionsScreen.swift`
- Create: `apps/desk/DevDesk/Screens/Findings/FindingDetail.swift`, `apps/desk/DevDesk/Screens/Decisions/DecisionDetail.swift`

**Interfaces:**
- Consumes: `ProjectWindowModel` (`snapshot.findings/roadmap/decisions`, `selectedRunID`, `selectedFindingID`, `findingFilter`, `decisionsTab`, `selectedDecisionID`, `answeredDecisionID`, `present(.reconcileFinding(_:))`, `recordAnswer(decisionID:optionID:rationale:)`, `requestMoreEvidence(decisionID:)`, `snapshot.isDemo`), `FindingsReport.count(of:run:)`, and the Task 2 primitives.
- Produces: `FindingsScreen(model:)`, `RoadmapScreen(model:)`, `DecisionsScreen(model:)`.

**Findings (D:528–591).** A 300-wide list pane (surface, trailing divider) beside a scrolling detail pane (padding 18).
- **List header** (padding 12×14, bottom divider):
  - "Findings" at 15/600, and a trailing primary small "Run survey". It opens a popover: "Run `/dev:survey` in your coding agent. Its report lands in `docs/survey/`, and Dev Desk reads it from there." Dev Desk starts no agents, so the button never pretends to run one.
  - The run line "Run · <label> · rev `<revision>`" at 12 mutedInk. With more than one run, it becomes a menu `Picker` bound to `selectedRunID`.
  - Filter chips (wrapping, gap 5): "<category raw value> <count>" per `FindingCategory`. The selected one (`findingFilter`) uses the info tone; the others neutralChipFill2. A click toggles the filter.
- **Rows** (padding 11×14, row divider; the run filter, then the category filter):
  - "<id> <title>" at 13/600, then `listDetail` at 11.5 secondaryInk.
  - The selected row has the info fill and a 3pt accent leading edge. A click sets `selectedFindingID`.
- **Below the list:** `searchNote` at 11.5 faintInk, padding 14.
- **Detail:**
  - The title at 17/600 and the summary as `MarkdownText` (secondaryInk, max width 720), with a trailing `PropertyChip(verificationLabel)`.
  - Two cards side by side: "Source locations" (mono 11.5 lines, or "No source locations recorded.") and "Verification limits" (`MarkdownText` at 12.5).
  - When `reconcile` exists, a card (radius 9):
    - A headerFill bar: "Reconcile with existing work" at 13/600, `statusNote` at 11.5 mutedInk, and a trailing primary small "Compare with #<candidateIssue>…" → `present(.reconcileFinding(id))`.
    - The body: the guidance lines prefixed "· " at 12.5 secondaryInk.
    - A running `NoticeBanner` showing `queuedNote` when set.
  - Then `historyNote` at 12 mutedInk.
- **States:**
  - No runs: `EmptyStateView("No survey runs yet", "Run `/dev:survey` to write a report to `docs/survey/`; it appears here.")`.
  - Unavailable: `UnavailableView`.

**Roadmap (D:593–641).** Scroll, padding 18×20.
- Header: "Roadmap" at 15/600 and `note` at 12 mutedInk.
- Themes in a 3-column `LazyVGrid` (spacing 14, top-aligned). Each theme is its `SectionLabel`, then item cards (radius 9, padding 12):
  - A critical item has the failed border, and its title uses the failed fg.
  - The title is at 13/600.
  - A chip row (gap 6, wrapping): workType (Epic → info tone, Defect → failed tone, else neutral), priority (neutral), and commitment (committed → running tone, considered → waiting tone).
  - `linkText` as `MarkdownText` at 12 secondaryInk, top 9.
- `SectionLabel("Milestones")` at top 20, then equal-width cards (radius 8, padding 12): the title at 13/600, a progress bar (height 6, radius 3, neutralChipFill track, accent fill at `progress`), and the note at 12 mutedInk.
- **States:**
  - No themes and no milestones: `EmptyStateView("No roadmap yet", "Run `/dev:roadmap` to turn recorded gaps into milestones and epics.")`.
  - Unavailable: `UnavailableView`.

**Decisions (D:643–699).** A 288-wide list pane plus a scrolling detail pane (padding 18, content max width 820).
- **List header:** "Needs attention" / "History" buttons (height 26, radius 6, selected = accent fill) bound to `decisionsTab`.
  - Needs attention lists the `.needsAttention` and `.stale` decisions; History lists `.answered`.
  - Rows: `listTitle` at 13/600, then `listMeta` at 11.5 (the waiting fg for stale, else secondaryInk). The selected row has the info fill and an accent leading edge.
  - An empty Needs attention reads "Nothing needs your attention.". When `!snapshot.isDemo`, add "Pending questions come from managed task sessions, which Dev Desk doesn't run yet.". An empty History reads "No recorded decisions yet."
- **Detail** (`selectedDecisionID`, defaulting to the first in the current tab):
  - The question at 17/600, then `context` as `MarkdownText` at 12 mutedInk (its links route through the environment).
  - **`.needsAttention`:**
    - `notice` as a waiting `NoticeBanner`.
    - "Evidence considered" + `MarkdownText`.
    - Option radio cards (surface, border, radius 9, padding 12; the selected card has an accent border and info fill; local `@State`): title at 13/600, detail in secondaryInk.
    - "Rationale" + a `TextEditor` (min height 60, bordered, placeholder "Explain the choice so a later review can judge it…").
    - A primary button, "Record answer and resume #<taskID>" (just "Record answer" with no task). It is disabled until an option is chosen, and calls `recordAnswer`.
    - A secondary "Ask the agent for more evidence" → `requestMoreEvidence`.
  - **`answeredDecisionID == id`:** a running `NoticeBanner` "Answer recorded (demo). #<taskID> moves from waiting to running and the answer appears in History with its rationale." (D:690).
  - **Below a needs-attention decision:** one section per stale decision (D:692–696): a waiting-fg title "Stale decision · context changed", the `staleReason`, and a secondary small "Review this decision" that selects it.
  - **`.stale` selected:** the waiting banner with the `staleReason` at the top, then "Previous answer" with the option title and rationale.
  - **`.answered`:**
    - "Answer" with the option title at 13/600 when present.
    - "Rationale" with the rationale as `MarkdownText`.
    - `answeredLabel` at 12 mutedInk.
    - When `body` is present, "Record" with the full ADR as selectable plain text in a card.
- **States:** unavailable → `UnavailableView`.

**Previews:** each screen on the loaded StudyHub model; Decisions with `decisionsTab` set to both values.

**Steps:**
- [ ] **Step 1:** Write the five files.
- [ ] **Step 2:** Typecheck: `<typecheck script> apps/desk/DevDesk/Screens/{Findings,Roadmap,Decisions}/*.swift`. Clean.
- [ ] **Step 3:** Self-check against D:528–699 in the report. Leave the changes uncommitted.

### Task 8: Settings, Insights panel, sheets, and the project launcher

**Files:**
- Replace stub: `apps/desk/DevDesk/Screens/Settings/SettingsScreen.swift`, `apps/desk/DevDesk/Insights/InsightsPanel.swift`, `apps/desk/DevDesk/Sheets/SheetHost.swift`, `apps/desk/DevDesk/Launcher/LauncherView.swift`
- Create: `apps/desk/DevDesk/Screens/Settings/SettingsPanes.swift`, `apps/desk/DevDesk/Sheets/{SheetChrome,CompareOutputsSheet,FollowUpSheet,HandoffSheet,ReconcileFindingSheet,CloneRepositorySheet,CreateProjectSheet}.swift`

**Interfaces:**
- Consumes:
  - `ProjectWindowModel` (`settingsSection`, `insights`, `insightsDocked`, `dockInsights`, `floatInsights`, `toggleInsights`, `selectedTask`, `snapshot`, `ref`, `dismissSheet`, `confirmSheet(provider:)`)
  - `InsightsConversation` (`script`, `unavailableReason`, `messages`, `isReading`, `chips`, `provider`, `draft`, `send`, `run`, `removeChip`, `startNewConversation`)
  - `ProjectOperations`, `RecentProjectsStore` via `AppServices.recents`, and `OpenProjectRegistry` from the environment
  - `PreferenceKey`, `AppearanceChoice`, and the Task 2 primitives
- Produces: `SettingsScreen(model:)`, `InsightsPanel(model:placement:)`, `SheetHost(model:kind:)`, `LauncherView(context:onDismiss:)`.

**Settings (D:701–739).** A section list, 230 wide (surface, trailing divider, padding 12×10): seven rows, padding 7×10, radius 6, the selected one on accent fill with white semibold text, bound to `settingsSection`. The detail scrolls at padding 20×24, max width 900. Each pane has its title at 15/600 and form rows with a 200-wide right-aligned label in secondaryInk.
- **Agents and defaults:**
  - "App default connection": a menu `Picker` over `capabilities.providers`, `@AppStorage(PreferenceKey.defaultConnection)`.
  - "<project name> override": "Use app default" plus the providers, stored under `PreferenceKey.connectionOverride(model.ref)`.
  - "Capabilities of the selected connection": a table with a headerFill header row and 110-wide provider columns. Values are colored: yes → running fg, sometimes → waiting dot, no → failed dot, unknown/not validated → faintInk. Then the matrix note at 12 mutedInk.
  - "Available models" with the text of D:731.
  - When the GitHub connection is `.unavailable`, a failed `NoticeBanner` "GitHub is unavailable" (D:734) with a secondary "Reconnect…". Its popover reads "Run `gh auth login` in Terminal, then reload this window (⌘R)."
- **Appearance:** a segmented System/Light/Dark control on `PreferenceKey.appearance`, and "Terminal text size" as a picker from 11 to 14 on `PreferenceKey.terminalFontSize` (default 12).
- **Accounts and connections:** each connection as `StatusDot` + name + label; the "GitHub account" fact from `projectFacts` when present; the same Reconnect help.
- **Notifications:** three toggles (Decisions that need you · Completed work · Failed runs) on their keys, plus the note "Notifications apply to managed work, which Dev Desk doesn't run yet. Your choices are kept for when it does."
- **Execution:** "Parallel task checkouts" as a text field plus "Choose…" (an `NSOpenPanel` for directories) on `PreferenceKey.worktreeLocation` (default "~/.devdesk/wt"), plus the note "Used when Dev Desk starts managed tasks. It doesn't start any yet."
- **General:** the toggle "Show sample projects in the project picker" on `PreferenceKey.showSamples` (default true), and "Dev Desk <CFBundleShortVersionString>".
- **Project overrides:** `KeyValueTable(snapshot.projectFacts)` and the note "Read from the repository. Dev Desk never overrides the repository's own configuration."

**Insights (D:741–825).**
- **Floating:** surface, controlBorder, radius 11, shadow (y 24, radius 60, black 28%).
  - A headerFill header: "Insights" at 13/600, "Floating over the workspace" at 11 mutedInk, and mini "Dock" and "Close".
- **Docked:** full height, surface, a leading border, shadow (x −8, radius 24, black 6%).
  - Header: "Insights" + "Nonmodal · docked" + "Float" + "Close".
- **Chips row** (padding 10×12, bottom divider):
  - Capsule chips at 11pt, the task chip in the info tone, each with a "×" button → `removeChip`.
  - A trailing provider `Menu` ("<provider> ▾"). Picking a different provider asks through a `confirmationDialog`: "Start a new conversation with <p>?", message "The current conversation stays as it is; switching providers never continues it." Confirming calls `startNewConversation(with:)`.
- **Messages** (scroll, padding 12, spacing 10, scrolled to the newest):
  - Bubbles have radius 9 and padding 10×11. The user's use neutralChipFill2; replies use surface with a border.
  - Each shows the author at 11 mutedInk, the text at 13, and the citation in mono 11.5 accent.
  - While `isReading`, a pulsing info dot and "Reading evidence: 3 files, 1 finding…" (D:765).
- **Composer** (padding 10×12, top divider):
  - Quick-action capsules (height 24, radius 12, bordered, 11pt) for `script.quickActions`; `dockedOnly` ones appear only when docked.
  - A `TextField` "Ask about this project" (height 30, radius 7; the focus ring in accent) bound to `draft`, submitting with Return, plus a primary "Send".
  - The footnote at 11 faintInk.
- **Unavailable:** only the project chip; the body is a neutral `NoticeBanner("No agent connection", reason)`; the field is disabled and the quick actions hidden; the footnote reads "Exploration is read-only."
- Closing and reopening keeps the conversation, since the model owns it.

**Sheets.** `SheetChrome(title:confirmTitle:width:confirmDisabled:onCancel:onConfirm:content:)` (D:828–836):
- A headerFill header with the title at 13/600, then Cancel (secondary) and the confirm button (primary), both 27 high.
- The content scrolls at padding 16×18. Width 1000 or 720, max height 790.

`SheetHost` maps each `SheetKind`:
- **`.openProject`:** `LauncherView(context: .sheet, onDismiss: model.dismissSheet)`.
- **`.compareOutputs`** (D:859–876, width 1000):
  - The intro text.
  - Two cards (radius 9): a headerFill bar with the title at 13/600 and the colored state; summary lines in mono 11.5; the result at 12.
  - The footnote at 12 mutedInk.
  - Confirm with `comparison.confirmTitle` → `confirmSheet()`.
- **`.followUp`** (D:878–887, 720):
  - The explanation box (neutralChipFill, border, radius 8, padding 12).
  - "Reviewer note" in a bordered box.
  - "Request" as a `TextEditor` prefilled from `request`.
  - "Sent to" and the recipient chip (info).
  - "Send request" → `confirmSheet()`.
- **`.handoff`** (D:889–901, 720):
  - The warning as a waiting banner (markdown).
  - "Handoff contents": the rows, plus a last row "New session with" holding a menu `Picker` over the providers and the text "· capabilities shown in Settings".
  - The footnote.
  - "Create new session" → `confirmSheet(provider: selection)`.
- **`.reconcileFinding(id)`** (D:903–931, 1000):
  - Two compare cards (meta in mono when `metaMonospaced`, with line breaks kept).
  - "Relationship" radio cards (the first selected by default).
  - "Proposed tracker update · review before sending" in a mono box on the canvas fill.
  - The delivery note at 12 in the failed dot color.
  - "Queue proposed update" → `confirmSheet()`.
  - Without `reconcile`, show `UnavailableView("Tracker updates are not available for this project.")` and disable confirm.
- **`.cloneRepository` / `.createProject`:** the two sheets below.
- **Clone:** a URL field and a destination folder (default `~/code` when it exists, else home; "Choose…" opens an `NSOpenPanel`). "Clone" shows progress, then runs `ProjectOperations.cloneRepository`. On success it records nothing itself (the window records its recent on load), calls `openWindow(value: ProjectRef.local(path:))` and dismisses. On failure it shows the error inline in the failed color.
- **Create:** a name field and a parent folder. "Create" → `ProjectOperations.createProject` → open the window.

**Launcher (D:838–857):** `LauncherView(context:onDismiss:)`.
- **Left side** (flex):
  - `SectionLabel("Recent projects")`, then a bordered list (radius 8). Rows have padding 11×12 and row dividers; each shows the name at 13/600 and the path in mono 11 mutedInk.
  - Trailing on each row, in the info fg: "Open · focuses its window" when `registry.isOpen(ref)`, else "Open".
  - Rows list the sample projects first, each with `PropertyChip("Sample")`, when `showSamples` is on. Then `AppServices.recents.entries`. A recent whose folder is missing shows "Missing" in faintInk and is disabled.
  - A single click selects a row (info fill); a double click, or the Open button, opens it: `openWindow(value: ref)` then `onDismiss()`.
  - Under the list, D:847 at 12 mutedInk.
- **Right side:** 320 wide. `SectionLabel("Start something")` and three bordered card buttons:
  - "Open local folder…" with "Opens read-only. No agent is launched." This runs an `NSOpenPanel` (directories only) and opens `.local(path:)`.
  - "Clone repository…" (D:852) → a local sub-sheet: `CloneRepositorySheet`.
  - "Create new project…" (D:853) → a local sub-sheet: `CreateProjectSheet`.
- **Chrome by context:**
  - `.sheet` wraps everything in `SheetChrome(title: "Open project", confirmTitle: "Open", width: 1000)`; confirm opens the selected row.
  - `.window` uses padding 20 and a trailing "Open" button at the bottom, at a fixed 1000×540.
- The mock's dashed empty-state note (D:854) belongs to Task 5's board and is not repeated here.

**Previews:** Settings (Agents and defaults), both Insights placements, each demo sheet, and the launcher in both contexts.

**Steps:**
- [ ] **Step 1:** Write the files, sheets first, then the launcher, Insights, and Settings.
- [ ] **Step 2:** Typecheck: `<typecheck script> apps/desk/DevDesk/{Screens/Settings,Insights,Sheets,Launcher}/*.swift`. Clean.
- [ ] **Step 3:** Self-check against D:701–936 in the report. Leave the changes uncommitted.

### Task 9: Integration, snapshot verification, and CI

Wave 2 typechecked each folder on its own. This task builds the whole app, wires it end to end, captures every screen state as evidence, compares each capture with the design, and fixes what does not match. After Wave 2 it owns every file under `apps/desk/DevDesk/`. Record each file it changes, with the reason.

**Files:**
- Create: `apps/desk/DevDesk/App/SnapshotMode.swift`
- Modify (as needed, each change listed in the report): any file under `apps/desk/DevDesk/`
- Create: `.github/workflows/desk.yml`

**Interfaces:**
- Consumes: everything.
- Produces: the launch arguments `-DevDeskSnapshot <dir>` and `-DevDeskSnapshotProject <ref id>` (default `sample:studyHub`; `local:<absolute path>` for a folder), the PNG captures, and the CI workflow.

**Snapshot mode** (debug verification; it also serves as the Phase 11 evidence tool):
- When `-DevDeskSnapshot` is present:
  - The app opens a window for the given ref, closes the launcher window, and sizes the project window to 1440×920.
  - It waits for `loadState` to be `.loaded`, then walks a fixed list of states. For each, it sets model properties, waits 0.6 s, and writes `<dir>/<nn>-<name>.png` from the hosting window's `contentView` via `bitmapImageRepForCachingDisplay`/`cacheDisplay`. That needs no Screen Recording permission.
  - Sheets are captured from `window.attachedSheet`.
  - Afterwards it quits.
- Use an `NSViewRepresentable` window accessor to find the hosting window. Do not use `NSApp.keyWindow`, which is unreliable when the app is launched from a terminal.
- **Sample states:**
  - `01-task42-activity` (the launch state: dock at the bottom, Insights floating) · `02-board` (Insights closed) · `03-board-backlog`
  - `04-task42-requirements` · `05-task42-changes` · `06-task42-evidence` · `07-task42-dock-side-split`
  - `08-task57-activity` · `09-task63-activity` · `10-parallel`
  - `11-findings` · `12-reconcile-sheet` · `13-roadmap` · `14-decisions` · `15-decisions-history` · `16-settings-agents`
  - `17-insights-docked` · `18-insights-floating`
  - `19-open-project-sheet` · `20-compare-sheet` · `21-followup-sheet` · `22-handoff-sheet`
  - `23-dark-task42` (Appearance forced dark for this capture only).
- **Local states:** `01-board` · `02-first-task-changes` · `03-findings` · `04-roadmap` · `05-decisions` · `06-settings-connections`.

**Verification to run and paste into the report (real output):**
1. `swift test --package-path apps/desk/DeskCore` → the counts.
2. `cd apps/desk && xcodegen generate && xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -destination 'platform=macOS' -derivedDataPath /tmp/devdesk-dd build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`, with a count of warnings from DevDesk sources (target zero).
3. Sample captures into `.superpowers/sdd/2026-09-11-dev-desk-mac-app/shots/sample/`, local captures of this repository into `…/shots/local-repo/`, and captures of an empty temp folder (not a git repository) into `…/shots/local-plain/`.
4. Open every sample PNG (you can read images) and compare it with the design line range for that state. Fix mismatches in layout, copy, color, or missing elements, then recapture. List every fix.
5. Quit the app and confirm no Dev Desk process remains (`pgrep -f "Dev Desk.app"` is empty).

**CI (`.github/workflows/desk.yml`):**
- Triggers: `pull_request` and `push` to main, with `paths: ['apps/desk/**', '.github/workflows/desk.yml']`.
- Job `core-tests` on `macos-15`: checkout, then `swift test --package-path apps/desk/DeskCore`.
- Job `app-build` on `macos-15`: checkout, `brew install xcodegen`, `xcodegen generate --spec apps/desk/project.yml`, then `xcodebuild -project apps/desk/DevDesk.xcodeproj -scheme DevDesk -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- A one-line header comment in the style of the repo's other workflows.

**Steps:**
- [ ] **Step 1:** Full build. Fix compile errors across folders.
- [ ] **Step 2:** Write SnapshotMode, then capture the sample, local-repo and local-plain sets.
- [ ] **Step 3:** Compare against the design and fix. Recapture until the sample set matches, and name any deliberate native deviation (for example the native toolbar chrome) in the report.
- [ ] **Step 4:** Write `desk.yml`. Run the two CI commands locally as written and paste the tails.
- [ ] **Step 5:** Report, and leave the changes uncommitted.

### Task 10: Docs and decisions gate (Phase 12)

**Files:**
- Create: `docs/adr/0012-the-mac-app-lives-in-apps-desk.md`, `docs/adr/0013-the-app-reads-git-and-github-directly.md`
- Modify: `docs/adr/README.md` (index rows), `PROJECT_MAP.md`, `docs/superpowers/specs/2026-09-11-container-design.md`, `README.md`, `documentation/CONTRIBUTING.md`

**Interfaces:** consumes the branch's final state (read the diff with `git diff main --stat`). The ADR file names are fixed; Task 4's page links to them.

**Content:**
- **Format:** read `skills/docs/SKILL.md` and apply it. ADRs follow the format of `docs/adr/0002-diagrams-land-in-the-repo.md` and the newest ADR (0011): Status / Date / Commit·PR / Context / Decision / Rejected / Consequences / Evidence. Write the Commit·PR line the way 0011 does for work that has not merged.
- **ADR 0012 — the Mac app lives in `apps/desk/`:**
  - Decision: one repo, with xcodegen `project.yml` and the local `DeskCore` package.
  - Rejected: a separate `dev-desk` repo, which was container spec §5's recommendation. Give its arithmetic: the install cost, measured with `du -sh apps/desk` excluding build output, since `install.sh` symlinks the whole clone and builds nothing. It lost because the contract (`dev snapshot`) is unbuilt and app and CLI will change together for now.
  - Consequences: the path-filtered `desk.yml`; `tests.yml` and `line-budget.yml` untouched (say why); and the revisit trigger taken from §5 ("if the app turns out to change in lock-step with the CLI on most PRs" — here, the reverse).
- **ADR 0013 — the app reads git and GitHub directly until `dev snapshot` exists:**
  - Decision: `LocalGitDataSource` mirrors `scripts/dev.py` `classify`, `build_board` and `resolve_active_milestone`.
  - Rejected, with reasons:
    - a sample-only first build (the developer chose real reads);
    - waiting for contract B (it blocks the app on an unbuilt contract);
    - shelling out to `dev board --json` (no PR numbers, branch names or Done column in its JSON; needs python3 and an installed `dev`, so a second path is needed anyway).
  - Consequences: the rules now exist twice, so change both; tests pin both; the migration is one `dev snapshot --json` read behind the `ProjectDataSource` seam.
- **`PROJECT_MAP.md`:**
  - TECH_STACK gains a "Mac app" row (apps/desk, SwiftUI/AppKit, macOS 14+, Swift 5 mode, xcodegen, DeskCore via `swift test`) and adds `desk.yml` to the CI row.
  - SYSTEM_FLOW gains a short "The container" paragraph: reads only, starts no agents, sample projects demo the full design.
  - ORPHANS & PENDING gains:
    - runner-dependent surfaces are demo-only (agents, dock, needs-attention decisions, Insights, tracker updates);
    - `dev snapshot` / `jobs` / `events` are not built;
    - the board rules are duplicated in `BoardBuilder.swift`;
    - the diagram's Container node needs a re-pin to cite `apps/desk` after merge;
    - `desk.yml` is unproven until its first CI run;
    - the Notifications and Execution settings are stored but have no effect yet.
- **Container spec:**
  - Add a status line noting that deliverables A and C landed together on this branch (see ADR 0012/0013).
  - Add "Decided 2026-09-11: one repo — ADR 0012" under §5.
  - Record under §7 that A and C shipped in one PR at the developer's request.
  - Reread every touched section for accuracy (Phase 12's rule).
- **`README.md`:** one "Learn more" line linking `documentation/SYSTEM-MODEL.md`.
- **`documentation/CONTRIBUTING.md`:** one "Where to extend" row for `apps/desk/`, including "board rules mirror scripts/dev.py (ADR 0013) — change both".

**Steps:**
- [ ] **Step 1:** Read `skills/docs/SKILL.md`, ADRs 0002 and 0011, and the ADR index.
- [ ] **Step 2:** Write the two ADRs, the index rows, and the PROJECT_MAP, spec, README and CONTRIBUTING edits.
- [ ] **Step 3:** Accuracy pass: reread each touched section whole, and fix or delete any claim this branch made false.
- [ ] **Step 4:** Put the PR body's `## DOCS` section (dev:docs format) in your report. Leave the changes uncommitted.

---

## Self-review (plan author, 2026-09-11)

- **Spec coverage.** Brief flows 1–10 map as follows:
  - flow 1 (open/restore) → Tasks 2 and 8;
  - flow 2 (#42 tabs and compare) → Tasks 6 and 8;
  - flow 3 (Focus/Parallel) → Tasks 2 and 5;
  - flow 4 (helper follow-up) → Tasks 6 and 8;
  - flow 5 (#57 decision) → Tasks 6 and 7;
  - flow 6 (#63 handoff) → Tasks 6 and 8;
  - flow 7 (finding vs #42) → Tasks 7 and 8;
  - flow 8 (Insights dock/close/reopen) → Tasks 2 and 8;
  - flow 9 (cited answer, handoff from chat) → Task 8;
  - flow 10 (Roadmap, history, settings) → Tasks 7 and 8.
  - The required states: empty project (Task 5), disconnected agent (Settings and sidebar), unavailable GitHub (sidebar, Findings, Settings, reconcile), failed run (Task 6 Evidence), stale decision (Task 7).
  - Real reads → Task 3. Deliverable A → Task 4.
- **Placeholders.** Not in shipped code. The Task 2 stubs are scaffolding that Wave 2 replaces. `/* assign */` is defined once in Task 1.
- **Type consistency.** Wave 2 names are checked against Task 1: `perform(_:agentID:)`, `confirmSheet(provider:)`, `recordAnswer(decisionID:optionID:rationale:)`, `count(of:run:)`, `ProjectOperations.cloneRepository(url:into:runner:)` and `createProject(named:in:runner:)`, `LauncherView(context:onDismiss:)`, `InsightsPanel(model:placement:)`.
