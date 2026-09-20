# Dev Desk Agents and Auto Mode (Step 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A task's Agents tab runs the developer's agent CLI, Claude Code or Codex, interactively in the task's own folder. The developer starts it by hand. In a project with Auto on, Dev Desk starts agents itself for the board's Queued tasks, with at most N running at once across the app.

**Architecture:** DeskCore adds four things:
- the agent's folder plan: a detached worktree for a task that has no branch yet, and reuse of a worktree already at the task's own path;
- the launch command, built from `dev run`'s own prompt;
- a pure Auto scheduler;
- `DockTab.Kind.liveAgent`, `DeskTask.baseRef`, and a second `ShellSessions` whose purpose is agents.

The app reuses step 1's terminal machinery to run a command rather than a bare shell. It adds an app-wide count of running agents, a per-window Auto loop, and the settings: Auto per project (behind the warning confirmation) and the limit app-wide.

**Tech Stack:** Swift 5 language mode, SwiftUI with AppKit, macOS 14, xcodegen, and SwiftTerm 1.11.2 (app target only). DeskCore stays dependency-free.

**Spec:** the developer's decisions of 2026-09-11. Step 2's design table was approved as shown, with the default limit set to 3. Step 1 is ADRs 0016 and 0017, merged in #54. The Global Constraints below are that spec.

## Global Constraints

- **Never launch the real `claude` or `codex` in tests, harnesses or manual runs.** It spends the developer's tokens. Use a stand-in script. The launch builder takes the executable as a parameter. A **DEBUG-only** launch argument, `-DevDeskAgentExecutable <path>`, makes the app run that path instead of the resolved CLI; release builds ignore it.
- **Never create a worktree, start a shell or start an agent in the dev-desk repository or any real checkout.** Tests and manual runs use throwaway repositories under `$TMPDIR`.
- **The prompt matches `dev run`'s `build_prompt` (`scripts/dev.py:599-602`) byte for byte.** It is `Read <skill root>/SKILL.md and execute it exactly as written, following every phase and gate it defines.`, followed by ` Arguments: #N` only when the task has no branch and has a number. The skill root is `~/.claude/skills/dev` with `~` expanded (`skill_root()`, `scripts/dev.py:572-574`), for every agent.
- **The commands.** Claude → `claude <prompt>`. Codex → `codex <prompt>`. Always interactive: never `-p` or `exec`, never a flag that skips permissions or approvals, and no `--model`.
- **The agent runs through the user's login shell,** so the user's `PATH` applies. It starts through step 1's fail-closed `cd -- "$1"` wrapper. The folder, shell, executable and prompt are separate argv elements, never interpolated into a script string.
- **Which agent.** Use `desk.connectionOverride.<project id>` when it's set to Claude or Codex, and otherwise `desk.defaultConnection` (default `Codex`). When the agent is Gemini, or isn't detected by `ToolDetection`, the Agents tab is unavailable with one of these reasons:
  - `<Name> isn't installed here, so Dev Desk can't start it.`
  - `Gemini has no confirmed way to run the dev pipeline, so Dev Desk doesn't start it.`
- **The agent folder rule, in order.** The exclusive claim, hardened flags and failure fallbacks from ADR 0017 all apply.
  1. A worktree whose branch is the task's branch: use that worktree.
  1b. The task has **no branch yet**, and a worktree of this repository already sits at the task's own path (`<location>/<project>-<N>`, or that path plus `-k`): reuse it. *Ruled during review: a task that has a branch never uses 1b, because another branch's task can share its folder name.*
  2. The task's branch exists but no worktree has it checked out: create a worktree on it, as the shell does.
  3. The task has no branch, it has a number, and a base ref is known: run `git worktree add --detach <path> <base ref>` at the task's own path. The plan note is `The pipeline creates the task's branch here at its first write.`
  4. Anything else, such as no base ref or a fork PR's task: use the project root, with its note. **Auto never starts such a task.**

  **The Shell tab gains rule 1b too,** so a task's shell and its agent share a folder.
- **Manual is the default.** The Agents tab has three states:
  - **Idle** shows `Starting an agent runs <Claude Code|Codex> in this task's folder under your account. It uses tokens and can change files; it stops at the pipeline's approval gates and asks you here.`, then the plan line, then **Start agent**.
  - **Running** shows the terminal and **Stop agent**, which sends SIGHUP and then SIGKILL after 2 s.
  - **Ended** shows `Agent ended (status N).` and **Start again**.
- **Auto** is set per project with `desk.autoMode.<project id>`. It is off by default and applies to local projects only.
  - Turning it on first shows a confirmation with exactly this text: `Auto runs up to <N> agents in parallel. Each one spends tokens on your Claude or Codex plan, and Dev Desk can't see your usage or prices. To keep spend down it runs at most <N> at a time, queues the rest, and skips tasks that already have an agent running, including ones waiting on your answer.` The buttons are `Turn on Auto` and `Cancel`. The same text, without the buttons, sits under the setting.
- **What Auto starts.** It picks tasks in the board's Queued column, in board order. A task qualifies when it has a number, has no `noBranchNote`, has no agent running, and Auto hasn't already started it in this app session.
  - It starts as many as `limit − running agents across all windows`.
  - It re-evaluates after every board load and every agent exit.
  - Turning Auto off stops new starts; running agents keep going.
- **The limit** is `desk.agentLimit`. It is app-wide, defaults to 3, and ranges from 1 to 6. It appears in Settings → Execution as `Run at most N agents at once`.
- **The dock caption for local tasks** becomes `Agents & Terminals · your shell and the task's agent, in the task's folder`.
- Sample projects are unchanged. Every note and reason is plain `Text`. Comment density matches the surrounding code. Implementers never commit or stage.

---

### Task 3: DeskCore — agent folders, the launch command, and the Auto scheduler

**Files:**
- Modify: `apps/desk/DeskCore/Sources/DeskCore/Local/TaskFolder.swift` (rule 1b, `planAgent`, `.existingOwn`, `.createDetached`)
- Create: `apps/desk/DeskCore/Sources/DeskCore/Local/AgentLaunch.swift`
- Create: `apps/desk/DeskCore/Sources/DeskCore/State/AutoScheduler.swift`
- Modify: `apps/desk/DeskCore/Sources/DeskCore/State/ShellSessions.swift` (`SessionPurpose`, `baseRef`)
- Modify: `apps/desk/DeskCore/Sources/DeskCore/Model/DeskTask.swift` (`DockTab.Kind.liveAgent`, `DeskTask.baseRef`)
- Modify: `apps/desk/DeskCore/Sources/DeskCore/Local/BoardBuilder.swift` (the `.liveAgent` tab, the caption, and `baseRef` from `GitFacts.baseRef`)
- Modify: `apps/desk/DeskCore/Sources/DeskCore/State/ProjectWindowModel.swift` (`agentSessions`)
- Test: `TaskFolderTests.swift`, `ShellSessionsTests.swift` and `BoardBuilderTests.swift` get additions; `AgentLaunchTests.swift` and `AutoSchedulerTests.swift` are new

**Interfaces:**
- Consumes: step 1's DeskCore (`TaskFolderResolver`, `TaskFolderPlan`, `ShellSessions`, `GitCommand.read`, and `CommandRunner`), `GitFacts.baseRef` (`GitReader.swift:33`), and `ToolDetection`.
- Produces. Task 4 codes against these exact names:

```swift
// Model/DeskTask.swift
// DockTab.Kind gains:
case liveAgent
// DeskTask gains:
public var baseRef: String?        // the ref a detached agent worktree starts from, e.g. "refs/remotes/origin/main"; nil for samples

// Local/TaskFolder.swift
// TaskFolderPlan gains:
case existingOwn(URL)                              // rule 1b: a worktree already at the task's own path
case createDetached(path: URL, baseRef: String)    // rule 3 for agents
// TaskFolderResolver gains:
public func planAgent(branch: String?, taskNumber: Int?, noBranchNote: String?, baseRef: String?) async -> TaskFolderPlan
// plan(branch:taskNumber:noBranchNote:), the shell's, applies rule 1b too.
// materialise handles .existingOwn (no git) and .createDetached (`git worktree add --detach <claimed path> <baseRef>`).

// Local/AgentLaunch.swift
public enum AgentKind: String, Equatable { case claude, codex }
public enum AgentLaunch {
    public static func agent(forConnectionName name: String) -> AgentKind?                  // "Claude" → .claude, "Codex" → .codex, else nil
    public static func prompt(skillRoot: String, taskNumber: Int?, hasBranch: Bool) -> String // dev run's build_prompt, byte for byte
    public static func arguments(agent: AgentKind, prompt: String) -> [String]               // ["claude", prompt] / ["codex", prompt]
    public static var skillRoot: String { get }                                              // ~/.claude/skills/dev, expanded
    public static func displayName(_ agent: AgentKind) -> String                             // "Claude Code" / "Codex"
}

// State/AutoScheduler.swift
public enum AutoScheduler {
    /// Task ids to start now, in board order.
    public static func tasksToStart(board: [DeskTask], runningAgentTaskIDs: Set<String>, alreadyStarted: Set<String>,
                                    runningAgentsAcrossApp: Int, limit: Int) -> [String]
}

// State/ShellSessions.swift
public enum SessionPurpose: Equatable { case shell, agent }
// ShellSessions.init gains:  purpose: SessionPurpose = .shell
// ShellSessions.start and refreshPlan gain:  baseRef: String? = nil   // an agent session plans with planAgent

// State/ProjectWindowModel.swift
public let agentSessions: ShellSessions            // purpose .agent; nil root for samples, like shellSessions
```

- [ ] **Step 1: Failing tests for rule 1b,** for both `plan` and `planAgent`:
  - a detached worktree at the task's own path gives `.existingOwn`;
  - a worktree at a *different* path is never reused by 1b;
  - rule 1 (the branch) still wins over 1b.
- [ ] **Step 2: Failing tests for `planAgent` rules 3 and 4.**
  - With no branch, a number and a base ref, the plan is `.createDetached` with the exact note.
  - With no base ref, a fork note, or no number, the plan is `.root`.
  - Then a **real temp-repo test**:
    1. Create a repo with an `origin` pointing at a local bare repo, and fetch it so `refs/remotes/origin/main` exists.
    2. `materialise(.createDetached)` gives a detached HEAD at that commit.
    3. Inside it, `git switch -c gh-7-x --no-track origin/main` succeeds, which is exactly what `shared/entry.md:76` does.
    4. A second `planAgent` with `branch: "gh-7-x"` then gives `.existing`.
- [ ] **Step 3: Implement** 1b, `planAgent` and `materialise` for the new cases, with the hardened flags and the exclusive claim.
- [ ] **Step 4: `AgentLaunch` tests.**
  - The prompt string is pinned byte for byte, with a test comment citing `scripts/dev.py:599-602`, with and without ` Arguments: #N`.
  - `hasBranch` true, or no number, drops the arguments part.
  - `arguments` returns `[name, prompt]`, with no other flag.
  - The name mapping covers Claude, Codex, Gemini (nil) and unknown (nil).
  - The skill root is expanded.

  Then implement.
- [ ] **Step 5: `AutoScheduler` tests.**
  - Only `.queued` tasks are picked, in board order.
  - Tasks are skipped when they have no number, have a `noBranchNote`, are in `runningAgentTaskIDs`, or are in `alreadyStarted`.
  - It starts `max(0, limit − runningAgentsAcrossApp)` tasks.
  - The limit is clamped to 1…6.

  Then implement.
- [ ] **Step 6: The model changes.**
  - `DockTab.Kind.liveAgent` and `DeskTask.baseRef`.
  - BoardBuilder gives every local task the dock `[Shell (.liveShell), Agents (.liveAgent)]` with the new caption, and sets `baseRef` from `GitFacts.baseRef`.
  - `ShellSessions` with purpose `.agent` plans through `planAgent`.
  - `ProjectWindowModel.agentSessions`.

  Update the tests: sample tasks are unchanged, and the old Agents `.unavailable` expectations are replaced.
- [ ] **Step 7:** run the full `swift test --package-path apps/desk/DeskCore`. Expect 0 failures, with the count above 225.

### Task 4: App — the Agents tab, the app-wide agent count, the Auto loop, and settings

**Files:**
- Modify: `apps/desk/DevDesk/Screens/Task/ShellTerminalView.swift`. A terminal can run a command: an agent launch through the login shell, via the fail-closed wrapper. `LiveShells` counts running agents app-wide.
- Modify: `apps/desk/DevDesk/Screens/Task/AgentsDock.swift`: the `.liveAgent` pane with its states and unavailable reasons, and plan lines for `.existingOwn` and `.createDetached`.
- Create: `apps/desk/DevDesk/Screens/Task/AutoAgents.swift`: the per-window Auto loop.
- Modify: `apps/desk/DevDesk/App/Preferences.swift` (`autoMode(_ ref:)`, `agentLimit`), and `apps/desk/DevDesk/Screens/Settings/SettingsPanes.swift`:
  - Execution gets the limit stepper;
  - Project overrides gets the Auto toggle, the confirmation and the warning line.
- Modify: `apps/desk/DevDesk/App/ProjectWindow.swift`: own the agent registry and the Auto loop, and end agents when the window closes, as for shells.
- Modify: `apps/desk/DevDesk/App/SnapshotMode.swift`: capture a local task's idle Agents tab. Also add the DEBUG-only `-DevDeskAgentExecutable`.

**Interfaces:**
- Consumes: Task 3's "Produces" block (exact names), and step 1's registry, `LiveShells`, generations and the `sh -c` wrapper.
- Produces: nothing that other tasks consume.

- [ ] **Step 1: A terminal that runs a command.**
  - An agent starts as `/bin/sh -c 'cd -- "$1" && shift && exec "$@"' sh <folder> <login shell> -l -c 'exec "$0" "$@"' <executable> <prompt>`, or an equivalent that keeps every value a separate argv element.
  - The agent registry is keyed separately from shells, so one task can have both.
  - Agents are counted in `LiveShells` for quit, and exposed as an app-wide running-agent count.
- [ ] **Step 2: The Agents tab states from Global Constraints.**
  - Resolve the agent through the override or the default connection, then `ToolDetection`, falling back to the unavailable reasons.
  - Start builds `AgentLaunch.arguments(...)` with `AgentLaunch.prompt(skillRoot:taskNumber:hasBranch:)`.
  - Stop and Start again work like the shell's.
- [ ] **Step 3: The Auto loop, per window.**
  - It runs only for a local project with `autoMode` on.
  - After each board load and each agent exit, it calls `AutoScheduler.tasksToStart` with this window's running agents, an **app-session** `alreadyStarted` set keyed by project id and task id, the app-wide running count, and `agentLimit`.
  - Then it starts each returned task through `agentSessions.start` and the registry.
  - It is safe to re-enter, so it never starts the same task twice.
- [ ] **Step 4: Settings.**
  - The Execution stepper (1–6, default 3).
  - The Project overrides Auto toggle. Turning it on shows the exact confirmation, and Cancel leaves it off. The warning line sits under the toggle.
- [ ] **Step 5: SnapshotMode capture and the DEBUG executable override.**
- [ ] **Step 6: Verify.**
  - `xcodegen generate && xcodebuild … build` gives `** BUILD SUCCEEDED **`, with 0 warnings from DevDesk sources.
  - `swift test --package-path apps/desk/DeskCore` passes.
  - Do a manual run in a throwaway repo, with `-DevDeskAgentExecutable` pointing at a **stand-in script**. The script prints its argv, reads one line, then exits with status 3:
    - Start agent shows the exact prompt as argv[1];
    - typing a line gives `Agent ended (status 3).`;
    - Start again works;
    - a task with no branch gets a detached worktree at its own path, and the Shell tab then opens there too (rule 1b);
    - quitting ends both.
  - Auto needs a GitHub milestone for its Queued column, so exercise the loop with a harness board, and report that honestly.
