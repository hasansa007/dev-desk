# Dev Desk: runs without a terminal — design record

**Date:** 2026-09-15

**Status:** **reviewed and accepted, 2026-09-16, with five amendments** — see §10, which is the part
to read if you have read this record before. Implementation started at step 1. The mockup is
[`docs/design/2026-09-15-runs-without-terminal.html`](../../design/2026-09-15-runs-without-terminal.html)
(four tabs, a Dark toggle); the review's A-vs-B comparison is
[`docs/design/2026-09-16-substrate-comparison.html`](../../design/2026-09-16-substrate-comparison.html)
(five tabs: the two start sheets, the two Runs screens, both core-logic diagrams, the dependency
lanes, the deltas). The decision is
[ADR 0036](../../adr/0036-agents-run-over-a-protocol-and-the-terminal-leaves-the-app.md), accepted.

**§3 is a day old and six of its claims have drifted.** Read §10.2 before relying on any of them.

**Related:** [container](2026-09-11-container-design.md) ·
[the next level](2026-09-13-next-level-direction-design.md) ·
[ADR 0016](../../adr/0016-dev-desk-embeds-a-terminal-with-swiftterm.md) ·
[ADR 0017](../../adr/0017-a-tasks-shell-opens-in-its-own-worktree-when-asked.md) ·
[ADR 0018](../../adr/0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md) ·
[ADR 0025](../../adr/0025-a-background-run-belongs-to-the-app-not-the-window.md) ·
[ADR 0026](../../adr/0026-a-task-has-one-session-and-terminals-is-where-it-lives.md) ·
[ADR 0030](../../adr/0030-insights-runs-its-agent-headlessly.md) ·
[ADR 0031](../../adr/0031-a-killed-run-leaves-a-record-and-the-next-launch-offers-to-continue-it.md) ·
[ADR 0035](../../adr/0035-the-board-stores-what-git-cannot-see.md)

---

## 1. What was asked

Three statements from the developer, in order, on 2026-09-15:

1. *"I wonder if I can replace the terminal and the chat with app integrations like Claude Code or
   Antigravity or Codex or open source apps or super.engineer or ZadLoop, like resume."*
2. *"I want to prevent [myself] from mimicking other apps — they will do it better than me."*
3. *"The main idea of this app is to mirror my dev skill. Regarding tasks and agents, the idea is
   to generate all data needed to start a new branch — fix or job needed — so that the task can be
   completed, and multiple tasks can run in parallel."*

And the conclusion: *"I want them all [removed], but I want to see the new UI first."*

Statement 3 is the design constraint. Dev Desk's product is the **preparation** of a task — the
door, the branch, the worktree, the prompt, the gates — and the **scheduling** of many at once. It is
not a terminal emulator and not a chat client. Everything in this record follows from that.

---

## 2. What Dev Desk has today

### 2.1 Two execution substrates

| | PTY (SwiftTerm) | Headless job |
|---|---|---|
| Where | `ShellTerminalRegistry` in `ShellTerminalView.swift` (546 lines), state in `DeskCore/State/ShellSessions.swift` (236) | `DeskCore/State/JobRegistry.swift` (284), `DeskCore/Local/JobCommand.swift` (166), `Runs/ProcessJobSpawner.swift` (147), UI `JobPane.swift` (95) |
| Introduced by | ADR 0016, 0017, 0018, 0026 | ADR 0025, 0030, 0031 |
| Used for | every **task agent** started from a card or by Auto; a task's **shell**; **Run project**; diagram generation; provider sign-in | background doors (Survey, Ideation, file-an-issue), Insights, the "recovered run" resume path |
| What the app sees | a drawn screen — bytes; `SessionUsageReader.swift` line 5 says it outright: *"the app sees a drawn screen and no JSON at all"* | `stream-json` events: `system/init` with `session_id`, `result`, `permission_denials`, usage |
| Gates | the door prints a question in the terminal; the human types in the terminal | `.asking(question)` state; answered in `JobPane`, resumes the same session |
| Resume | none — a pty that ended is gone (ADR 0026's "start again") | `JobCommand.resume(agent:sessionID:answer:)` → `claude -p --output-format stream-json --verbose --resume <id>` / `codex exec resume --last --json` |
| Parallel cost | one pty + one `LocalProcessTerminalView` per session | one `Process` per session |

The headless side is already the better substrate for what statement 3 describes. The PTY side is
where every task agent actually runs. That inversion is the problem.

### 2.2 Three chat surfaces

| File | What it is | Verdict |
|---|---|---|
| `Screens/Terminals/TerminalChatView.swift` (199) | Polls the pty's text every 600 ms, splits it into "turns" where a prompt or blank line falls (`TerminalTurns`). Its own header: *"best effort, and said to be … a full-screen CLI keeps no scrollback at all."* | mimicry — remove |
| `Screens/Task/ChatTab.swift` (179) + `ChatComposer.swift` (306) + `DeskCore/Local/ChatSession.swift` (168) | Each message is a fresh one-shot `claude -p` / `codex exec`. Its own header: *"Nothing is carried between turns."* A chat app minus memory. | mimicry — remove |
| `DeskCore/State/InsightsConversation.swift` (108) | Insights' ask surface (ADR 0030, next-level decision 2). Starter prompts that kick a door. Not a task chat. | keep — out of scope |

Leftovers that go with the first two: `PreferenceKey.chatStyle` (`Preferences.swift:18`), the
Chat/Terminal mode on a Sessions row (`TerminalsScreen.swift` ~line 719), `scratchChat(for:)` on
`ProjectWindowModel` and its three assertions in `ProjectWindowModelTests.swift:66-73`.

### 2.3 Everything that rides on the terminal registry

Found by `grep ShellTerminalRegistry|terminals\.` outside the Terminals screen:

| Caller | Call | Needs a TTY? | Goes to |
|---|---|---|---|
| `Screens/Task/AutoAgents.swift:76` | `terminals.startAgent(for:agent:worktreeLocation:mode:)` | no | protocol session (§4) |
| `Screens/Diagrams/DiagramGenerating.swift:39` | `terminals.start(taskID:folder:command:)` | no | protocol session, or headless job |
| `Runs/RunProjectControl.swift:29-50` | `start` + `send(shellLine)`; stop = `send("\u{03}")` then stop lines then `end` | no — it is a dev server with a log | plain `Process` in a job row (§4.6) |
| Settings → Accounts sign-in (`gh auth login`, `claude auth login`, `codex login`; next-level decision 14) | scratch terminal | **yes** (device-code flows, browser hand-offs, password prompts) | the user's own terminal (§4.7) |
| `Screens/Task/ShellPane.swift`, "New terminal ⌘T" | a shell for the human | **yes** | the user's own terminal (§4.7) |
| `App/ProjectWindow.swift:8`, `App/ProjectToolbar.swift:8` | own and pass the registry | — | own the session registry instead |
| `DeskCore`: `ProjectWindowModel`, `ProjectRuns`, `DoorRuns`, `RunJournal` | reference `ShellSessions` state | — | reference `AgentSession` state |

Two of seven genuinely need a TTY. Neither of those two is a task agent.

---

## 3. The check: what the other apps actually expose

Researched 2026-09-15 from official docs. Verified facts; inferences are marked.

### 3.1 Agent Client Protocol (ACP) — the general answer

- Spec: <https://agentclientprotocol.com>. Repo moved to the multi-vendor org
  `agentclientprotocol/agent-client-protocol` (Zed + JetBrains, RFD process). Stable wire version
  `protocolVersion: 1`.
- Transport: JSON-RPC 2.0, newline-delimited over the agent subprocess's stdin/stdout. Agent may log
  to stderr, must not write non-ACP bytes to stdout.
- **Client → agent:** `initialize`, `session/new {cwd, mcpServers}` → `{sessionId}`,
  `session/prompt {sessionId, prompt}` (pending for the whole turn; resolves with `stopReason`),
  `session/cancel` (notification). Capability-gated: `session/load` (replays the whole
  conversation as updates), `session/resume` (reattach without replay), `session/list {cwd?}`,
  `session/delete`, `session/set_mode`.
- **Agent → client:** `session/update` notifications — `agent_message_chunk`,
  `agent_thought_chunk`, `tool_call`, `tool_call_update` (content: text / `diff {oldText,newText}` /
  terminal), `plan`, `usage_update`, `session_info_update`, `current_mode_update`. And one
  baseline **request**: `session/request_permission {sessionId, toolCall, options[]}` with option
  kinds `allow_once | allow_always | reject_once | reject_always`. It is a blocking JSON-RPC
  request — the agent waits for the client's answer. Optional: `fs/*`, `terminal/*`,
  `elicitation/create`.
- **Registry** (machine-readable, per-platform `cmd`/`args`/`sha256`):
  `https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json`.
- **Agents, exact spawn** (from the registry, 2026-09):
  Claude `npx -y @agentclientprotocol/claude-agent-acp` (co-authored Anthropic/Zed/JetBrains) ·
  Codex `npx -y @agentclientprotocol/codex-acp` (wraps Codex App Server) ·
  Gemini CLI `npx @google/gemini-cli --acp` · Goose `goose acp` · opencode `opencode acp` ·
  Copilot `npx @github/copilot --acp` · Cursor `cursor-agent acp` · Junie `junie --acp=true` ·
  Qwen, Kimi, Kilo, Devin, Poolside and others `<bin> acp`. **Crush has no ACP** (private HTTP
  protocol behind `CRUSH_CLIENT_SERVER=1`). **aider has nothing** embeddable.
- **Clients:** JetBrains (first-party), Neovim (CodeCompanion, avante), Emacs (agent-shell),
  VS Code extensions, marimo, and several native macOS apps (Capsule, Superlite, Braide, Aizen).
  The client role is well-trodden.
- **Swift:** no official SDK (official: Rust, TS, Python, Kotlin, Java). Community:
  [`wiedymi/swift-acp`](https://github.com/wiedymi/swift-acp) (client + agent, stdio, actors,
  `AsyncStream` updates, `session/list`, an `ACPRegistry` module that installs agents from the
  registry; built for a native macOS worktree/agent app; macOS 12+, MIT),
  [`rebornix/acp-swift-sdk`](https://github.com/rebornix/acp-swift-sdk) (Swift 6 strict, client),
  `aptove/swift-sdk` (not inspected).
- **Size of a hand-rolled client:** 4 outbound messages for a working client, 6 with history, 2
  inbound handlers. The work is the `session/update` union (~11 variants) and rendering it.
- **Risk — ACP v2 is a published breaking draft:** `session/prompt` becomes an ack and completion
  moves to a `state_update` notification; `session/load` removed (use `session/resume` +
  `replayFrom`); `tool_call` removed (first `tool_call_update` creates); `fs/*` and `terminal/*`
  removed; modes become config options. Migration guide:
  <https://agentclientprotocol.com/protocol/v2/migration.md>. **Build v1, keep decoding behind a
  version switch negotiated per connection, never adopt `fs/*`/`terminal/*`.**

### 3.2 Claude Code

- Docs moved to <https://code.claude.com/docs>. Current to ~Sept 2026 (v2.1.27x).
- **Agent SDK is TypeScript and Python only.** The documented path for other languages is the CLI
  as a subprocess.
- Native drive: `claude -p --input-format stream-json --output-format stream-json --verbose` as a
  long-lived process (bidirectional; user messages as JSON lines on stdin). Flags that matter:
  `--session-id <uuid>`, `--resume <id|name|path>`, `--fork-session`, `--continue`,
  `--permission-mode default|acceptEdits|plan|auto|dontAsk|bypassPermissions|manual`,
  `--permission-prompt-tool <mcp tool>`, `--permission-prompts host|none` (v2.1.259+),
  `--include-partial-messages`, `--max-turns`, `--max-budget-usd`, `--json-schema`, `--agents`,
  `--bare` (will become default for `-p`), `--no-session-persistence`.
- **Permission without a terminal:** (a) an MCP server the app hosts, passed as
  `--permission-prompt-tool`; (b) an HTTP `PermissionRequest` hook (app listens on localhost;
  deny via the `decision` object, not exit 2); (c) SDK `canUseTool` — TS/Python only. The raw
  control channel the SDK uses over stream-json is **not publicly specified** (inferred from
  "sends them to the Agent SDK host").
- Sessions on disk: `~/.claude/projects/<cwd-mangled>/<session-id>.jsonl`. Explicitly *"internal …
  changes between versions"*. Sanctioned: `--resume` by id (v2.1.223+ resolves across projects),
  `claude agents --json`. Host env: `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_PROJECT_DIR_NAME`
  (v2.1.234+, documented for hosts that embed Claude Code).
- No app-server equivalent. `claude mcp serve` exposes *tools*, not a conversation. The VS Code
  IDE websocket (`~/.claude/ide/<port>.lock`) is disclosed, not offered as an API.
- Licensing: third parties may not offer claude.ai login/rate limits for products built on the SDK.
  Driving the **user's own installed CLI under their own login** is the ordinary path and what Dev
  Desk already does (decision 14: the app never handles a credential).

### 3.3 Codex

- Docs moved to <https://learn.chatgpt.com/docs>.
- **`codex app-server`** is the documented embedding surface: JSON-RPC over `stdio://` (default),
  `ws://`, `unix://`. `initialize` → `thread/start | thread/resume | thread/fork` → `turn/start`,
  `turn/steer`, `turn/interrupt`; notifications `item/started`, `item/agentMessage/delta`,
  `item/completed`, `turn/completed`; **approvals as server-initiated requests**
  `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`,
  `tool/requestUserInput`; `thread/list {cwd}`, `thread/read`; auth `account/*`. Bindings:
  `codex app-server generate-json-schema`. Wrapped by `@openai/codex-sdk` (TS) and `openai-codex`
  (Python). **Marked experimental / "may change without notice."** Pin a version, regenerate.
- `codex exec`: `--json` (JSONL: `thread.started {thread_id}`, `turn.completed {usage}`, `item.*`),
  `resume [SESSION_ID] [--last] [--all]`, `fork <id>`, `--sandbox`, `--worktree`, `--add-dir`,
  `--ephemeral`, `--output-schema`. **No `--session-id`.** `--full-auto` deprecated.
- `codex mcp-server` **removed**. `codex proto` gone.
- Sessions: `$CODEX_HOME/sessions/**/rollout-<ts>-<threadId>.jsonl` (directory nesting inferred,
  version-dependent). Prefer `thread/list`.

### 3.4 Antigravity (Google)

- Now a five-surface family; changelog current to 2026-09-15. CLI `agy` at `~/.local/bin/agy`.
- **Drivable:** `agy -p "<prompt>"` headless; `agy --conversation <id>` resume; `agy -c` last
  conversation for this cwd; `--output-format json|stream-json` (`init`/`step_update`/`result`,
  envelope carries `conversation_id`); `--input-format stream-json` for one long-lived
  bidirectional process; `--sandbox`, `--json-schema`, `--model`, `--effort`. Hooks (JSON, shell).
- On disk: `~/.gemini/antigravity-cli/cache/last_conversations.json` maps **absolute workspace
  path → last conversation id**.
- Desktop app control exists only as the sidecar-scoped `agentapi new-conversation` /
  `agentapi send-message <id>` — not offered as a public path binary.
- **No URL scheme. No documented `code .` launcher** (an `antigravity` shell alias is implied by
  the installer's `--skip-aliases`; unverified).
- **ToS caveat (verified):** the FAQ says using third-party tools to access Antigravity — naming
  Claude Code, OpenClaw and OpenCode — violates the Terms and may suspend the account. Shelling out
  to the user's own `agy` is a different act from proxying credentials, but it is close enough that
  the terms must be read before this adapter ships. Treat Antigravity as **hand-off only**.

### 3.5 super.engineering (the developer wrote "super.engineer")

- `super.engineer` is a stock nginx page. The product is <https://super.engineering> — *"the native
  agent control plane"*, formerly **Superconductor** (the `sc` command, `~/.superconductor`, and
  `SUPERCONDUCTOR_*` env vars survive). **Alpha, nightly-only.**
- It is a native macOS app (Rust, Metal) that runs **parallel coding agents in isolated git
  worktrees**, orchestrating Claude Code, Codex, Cursor, opencode, Antigravity, Copilot and more.
  Local-first; brings the user's own CLIs and credentials. That is the session-hosting half of Dev
  Desk, as a whole company's product — the concrete proof of statement 2.
- Local API is the `sc` CLI against a running app: `sc status --json`,
  `sc workspace open <path> --activate --json`, `sc chat new --provider codex`,
  `sc chat send <id> "<prompt>" --watch`, `sc worktree create --from-file <task.md> --provider …`,
  `sc history list|get`. Resume by prior session id is *"best effort, per provider."* Some
  operations are deliberately human-gated. No URL scheme, no HTTP API, no SDK.

### 3.6 What the check settles

- There is one protocol every agent Dev Desk cares about already speaks, with a registry that names
  the binary, with permission requests as a first-class blocking call, and with session ids the
  client persists. The app does not need to know Claude from Codex from Gemini.
- Two products cannot be embedded and should not be: Antigravity (ToS) and super.engineering
  (alpha, and it is the competitor for exactly the part being removed). Both can be **launched** with
  a folder and, best effort, a session.
- Nothing above needs a pty.

---

## 4. The design

### 4.1 Principle

> Dev Desk prepares a task and schedules it. It watches an agent work; it does not host the agent's
> screen, and it does not converse.

Corollaries: the only place the human types into a run is when the run asks; the only thing the app
draws about a run is what the agent's protocol stream says; and any moment that wants a real
conversation or a real shell is a hand-off to the tool built for it.

### 4.2 `TaskLaunch` — the payload (DeskCore, pure data)

The "all data needed to start" of statement 3, made one value:

```swift
public struct TaskLaunch: Codable, Hashable {
    public let task: DeskTask.ID           // or a DoorRun for Survey/Ideation/Roadmap starts
    public let door: String                // "dev:task-start", "dev:survey", …
    public let folder: TaskFolderPlan      // existing / create / createDetached / root — ADR 0017, unchanged
    public let branch: String?             // to check out or create
    public let base: String                // "origin/main@8c1f2a0"
    public let prompt: String              // exactly what scripts/dev.py builds today (ADR 0018)
    public let gates: [Int]                // 11, 12, 13, 14 — from shared/pipeline.md
    public let permission: PermissionPolicy // askAtGates(editsInWorktree) | askEveryTool | (never bypass)
    public let mode: RunMode               // standard | delegate — unchanged
    public let labels: [String]            // proposed by the door (ADR 0020)
}
```

Built by the same code that builds `startAgent`'s argv today; the only change is that it is a value
first and a process second, so it can be shown (start sheet), stored (`RunJournal`), queued
(`StartQueue`) and handed off (§4.5) without re-deriving anything.

### 4.3 `AgentSession` — the one abstraction the app hosts

```swift
public protocol AgentSession: AnyObject, Observable {
    var id: SessionID { get }                    // the agent's own id, persisted by Dev Desk
    var provider: Provider { get }               // claude, codex, gemini, opencode, …
    var state: AgentSessionState { get }         // preparing · running · waiting(Ask) · ended(Outcome) · failed
    var events: [RunEvent] { get }               // §4.4
    var usage: ContextUsage? { get }
    func start(_ launch: TaskLaunch) async throws
    func answer(_ ask: Ask, with: AskAnswer) async  // permission option or free text
    func cancel() async
    func resume(id: SessionID, in folder: URL) async throws
}
```

One implementation ships first: **`ACPSession`** (a `Process` per session, JSON-RPC line codec,
v1 with a version switch). `JobRegistry`'s existing `claude -p`/`codex exec` path is kept as a
**second implementation, `HeadlessSession`**, so background doors and the recovered-run resume keep
working unchanged during the migration — and so a machine with no `npx` still works.

`ShellSessions`/`ShellTerminalRegistry` are not a third implementation. They are removed.

### 4.4 `RunEvent` — what the pane draws

```
.started(folder, provider, sessionID)
.phase(Int, title)                         // from the .dev/events sidecar (next-level decision 1) — outranks agent text
.text(String)                              // agent_message_chunk, coalesced per messageId
.thought(String)                           // agent_thought_chunk — collapsed by default
.tool(name, input summary, status, content: .text | .diff(path, old, new) | .none)
.plan([PlanEntry])                         // plan updates; gate phases marked from TaskLaunch.gates
.ask(Ask)                                  // .permission(toolCall, options) | .question(text, options?)
.usage(ContextUsage)
.ended(stopReason, outcome)                // outcome from git + .dev state, not from the agent's word (ADR 0011 truth rank)
```

The mapping from ACP `session/update` to `RunEvent` is one file, pure, unit-tested against recorded
fixtures — the same discipline `JobStream.event(from:)` already has in `JobRegistryTests`.

### 4.5 Providers and hand-offs

Two lists, both from detection, never hard-coded:

- **Run it here** — providers from the ACP registry JSON that are installed and signed in
  (`ToolDetection` already answers "installed and who is signed in"). The registry gives
  `cmd`/`args`/`sha256`; Dev Desk never installs an agent, it only names the one it finds.
- **Hand it to** — launchers. Each is a `Handoff` with `canOpen(worktree)`, `open(launch)`, and
  optionally `resume(sessionID)`:
  - *Terminal* (`Terminal.app` / iTerm via `open`/AppleScript): `claude --resume <id>` in the
    worktree — the same session, continued where a human wants to sit.
  - *Codex*: `codex --cd <worktree>` (fresh) or `codex resume <thread>` (same).
  - *Antigravity*: `agy -c` in the worktree, or `--conversation <id>` when
    `last_conversations.json` has one for that path. Shipped **only after the ToS is read**.
  - *super.engineering*: `sc workspace open <worktree> --activate --json`, then `sc chat new`
    when the user asks for a fresh session there. Probe `sc status --json` first; it is alpha.
  - *Editors*: `open -a Cursor|Zed|"Visual Studio Code" <worktree>`.

A handed-off task appears under **Elsewhere** in Runs: Dev Desk keeps the card In progress, watches
the branch and `.dev/<branch>.json` exactly as it does for a run it never started (ADR 0013), and
stores the session id it was given so *Continue in* can offer the same session again.

### 4.6 Run project

`RunProjectControl` becomes a `ProcessRun`: `/bin/zsh -lc "<shellLine>"` with stdout/stderr merged
into a log row in Runs; Stop sends the configured stop lines to a fresh shell, then `SIGINT`, then
`SIGTERM` after the existing grace. Configuration stays in `.devdesk/run.json`. Setup rows stay.
Nothing the README promises about Run project changes except that there is no cursor to click into.

### 4.7 The two things that need a TTY leave the app

- **Provider sign-in** (`gh auth login`, `claude auth login`, `codex login`) opens in the user's
  terminal with the command pre-typed. Settings → Accounts still shows the result, because
  `ToolDetection` re-reads it. Decision 14 (never touch a credential) is *strengthened*: the app no
  longer even hosts the pty the credential flows through.
- **New terminal ⌘T** becomes **Open project in Terminal** (project root or a task's worktree from
  its row). It was always the user's shell; now it is in the user's terminal.

### 4.8 The UI

Four moments, all in the mockup. Everything else in the app is untouched.

1. **Start** — a card's Start (button, menu, ⌘↩, the dialog) opens one sheet at the existing
   900 × 660 dialog size (ADR 0021/0028). Left: the `TaskLaunch` as a key–value block and the prompt
   in a scrollable mono box. Right: *Run it here* radio list · *Or hand it to* radio list ·
   *Permissions* (two policies). Footer: free slots, Cancel, one primary button that names the
   choice. **Nothing runs until this button.** Auto skips the sheet and uses the defaults, as today.
2. **Runs** (was Terminals) — left column 300 pt, grouped: Running · Queued · Elsewhere ·
   Background · Ended. A row: `#number title`, state chip (right, tone by `StatusTone`),
   provider chip, branch in mono. Header: slot meter (`3 of 5 running · 2 queued`), *Open project in
   Terminal*, *Start a door*. Right: the pane — header (title, provider, branch, Files, Diff,
   *Continue in ▾*, Stop), the **event log** (phase-gutter timeline; tool rows with a mono command
   chip and a result; diffs inline using the existing `diffAdd/Delete` tokens; the plan card with
   ✓ ● ○), footer (context meter — already in `JobPane`; turn/tool/files counts).
   **No composer.**
3. **A gate / a question** — the ask block docks above the footer, tone *waiting* for permission,
   *info* for a question. Permission: the command in a mono box, *Allow once* (primary) · *Allow for
   this run* · *Reject*, and the note *"answered here, never in a terminal."* Question: the agent's
   options as radios plus a free-text line and *Answer*. Waiting outranks running everywhere
   (next-level decision 7): the row chip, the sidebar badge, the toolbar chip, the notification.
4. **Continue in ▾** — grouped menu: *Same session* (Claude Code in Terminal `--resume`, Claude
   Code app) · *Fresh session, same worktree* (Codex, Antigravity, super.engineering, Cursor · Zed ·
   VS Code) · *Copy the resume command* · *Reveal worktree in Finder*. Entries are present only when
   detected.

Removed from the UI: the Terminal view, the Chat view, the Sessions "starter" ("open a terminal or a
chat here"), the chat-style preference, the 1/2/4-up terminal tiling and its tile heights
(`DeskMetric.terminalTileHeight`, `terminalTileTallHeight`), the `terminal*` color tokens.

### 4.9 Parallelism, queue, recovery — what changes and what does not

- The slot limit (1–6, default 3; ADR 0035, Settings → Execution) and `StartQueue` are unchanged.
  What changes is honesty: N sessions are N processes and N log rows; nothing about N depends on how
  many terminals a person can watch. The limit is about tokens, which is what the Auto warning says.
- `RunJournal`/ADR 0031: a record now stores the `TaskLaunch` and the provider session id.
  Recovery becomes `AgentSession.resume(id:in:)` — `session/load` on ACP v1 replays the log, so a
  recovered run comes back **with its history**, which the pty never could.
- `.dev/events/<branch>.jsonl` (next-level decision 1) remains the phase truth and outranks the
  agent's text; the protocol stream fills in what the sidecar does not say (tools, diffs, asks).

### 4.10 What is not built

- No conversation view. No transcript "bubbles". No composer outside an ask.
- No agent installation. No credential handling. No proxying of any provider's login.
- No `fs/*` or `terminal/*` ACP capabilities (removed in v2; an agent that needs a file reads it
  itself in the worktree).
- No embedding of Antigravity or super.engineering. Launch and watch only.
- No change to the doors, the pipeline, `scripts/dev.py`, or the prompt.

---

## 5. Decisions this reverses or amends (one ADR)

| ADR | Effect |
|---|---|
| 0016 *Dev Desk embeds a terminal with SwiftTerm* | **reversed** — SwiftTerm leaves `project.yml` |
| 0026 *A task has one session, and Terminals is where it lives* | **amended** — one session stays true; the session is a protocol session; the screen is Runs; the "only host of a live terminal" clause is void |
| 0017 *A task's shell opens in its own worktree when asked* | **amended** — the worktree rules (`TaskFolderPlan`) stay; "shell" becomes "session or hand-off" |
| 0018 *Dev Desk starts the task's agent by hand or in Auto* | **amended** — same triggers, same prompt; the agent runs over ACP, gates are answered in the app |
| 0025 *A background run belongs to the app* | **extended** — every run now has what only background runs had |
| 0031 *A killed run leaves a record* | **extended** — the record carries the session id; resume replays |
| next-level decision 1 (events sidecar) | unchanged, and now paired with a real stream |
| next-level decision 14 (sign-in in a scratch terminal) | **amended** — sign-in in the user's terminal |
| next-level decision 17 (*"the terminal stays one click deeper"*) | **reversed** — there is no terminal; the event log is the click deeper |
| next-level decision 21 (save an ended session's transcript) | **kept, better** — the transcript is the event log, structured |

The draft is [ADR 0036](../../adr/0036-agents-run-over-a-protocol-and-the-terminal-leaves-the-app.md).

---

## 6. Order of work

Each step builds with `apps/desk/install.sh`, is looked at on screen, and commits to the working
branch (this repo's rule). Tests: `swift test --package-path apps/desk/DeskCore` after every step.

| # | Step | Deletes | Adds | Risk |
|---|---|---|---|---|
| 1 | **Remove both chats** | `TerminalChatView.swift`, `ChatTab.swift`, `ChatComposer.swift`, `ChatSession.swift`, `PreferenceKey.chatStyle`, the row's Chat mode, `scratchChat(for:)` + its tests | nothing | none — no caller outside these files |
| 2 | **`TaskLaunch` + start sheet** | nothing | `TaskLaunch` in DeskCore (built from today's `startAgent` inputs), `StartSheet`, provider/hand-off detection lists | low — the pty path still runs it |
| 3 | **`AgentSession` + `ACPSession`** | nothing yet | JSON-RPC line codec, `ACPSession`, `session/update → RunEvent` mapper with fixtures, `RunPane` (event log + ask block), Runs screen list | medium — the new thing; behind the start sheet's provider choice so the pty remains the fallback until 5 |
| 4 | **Move the callers** | `startAgent` use in `AutoAgents`, `DiagramGenerating`; `RunProjectControl`'s pty use | `ProcessRun` for Run project; sign-in and ⌘T become `open` into Terminal | low — each caller is one call site |
| 5 | **Remove the terminal** | `ShellTerminalView.swift`, `ShellPane.swift`, the terminal half of `TerminalsScreen.swift`, `ShellSessions.swift` + tests, `terminal*` tokens and metrics, SwiftTerm from `project.yml`; rename Terminals → Runs in `Sidebar`, `ContentRouter`, README | ADR 0036 accepted; README "Using it" rewritten for Runs | none once 4 is in |
| 6 | **Hand-offs** | — | Terminal `--resume`, Codex, editors; Antigravity and super.engineering behind detection, Antigravity after the ToS read | low; each is a launcher |

Step 1 can land today. Steps 2–3 are the work. Step 5 is the payoff.

Estimated deletion: ~2,300 lines of Swift across the files named in §2 (the pty and chat surfaces),
against roughly 1,200 added for `ACPSession`, the mapper, the sheet and the pane.

---

## 7. Risks, plainly

1. **ACP v2 break.** Mitigated by v1 + version switch + no `fs`/`terminal`. Watch the RFD.
2. **`npx` on the user's machine.** The Claude and Codex adapters are npm packages. A machine with
   Claude Code installed but no Node cannot run `claude-agent-acp`. Fallback: `HeadlessSession`
   (today's `claude -p` path). Detection must say which one it found.
3. **Codex app-server is experimental.** The ACP adapter wraps it; a Codex release could break the
   adapter before the adapter updates. Pin what detection reports; `HeadlessSession` remains.
4. **Antigravity ToS.** Hand-off only, and only after reading the terms. Not in step 3's scope.
5. **super.engineering is alpha on nightly.** Probe `sc status --json` at runtime; never hard-code
   flags; hide the entry when the probe fails.
6. **Claude's permission channel.** Over ACP it is `session/request_permission` — clean. Over
   `HeadlessSession` it stays what it is today (`permission_denials` after the fact, or the door's
   own gate question). Do not try to reverse-engineer the SDK's control channel.
7. **Losing the "watch it type" affordance.** Some developers like seeing the raw agent screen. The
   answer is *Continue in → Terminal* with `--resume`: the same session, in a real terminal, on
   demand. It costs one click and nothing else.

---

## 8. Questions for the architecture review

1. Is **Runs** the right name, or should the screen keep *Sessions*? (The mockup says Runs; the
   codebase already says "session" in DeskCore and "Runs" for the bottom panel.)
2. Should `HeadlessSession` (today's `claude -p` / `codex exec`) survive as a permanent second
   implementation, or only through the migration? Keeping it is the `npx`-free fallback; dropping
   it is one less path to test.
3. Should the start sheet appear for **every** start, or only the first start of a task, with the
   card's Start reusing the last choice? (Auto never shows it either way.)
4. Should a handed-off task be able to come **back** — i.e. should Dev Desk `session/load` a
   session that Terminal continued? ACP allows it; the question is whether the UX wants two hosts of
   one session's history.
5. Community Swift SDK (`wiedymi/swift-acp`, MIT) vs. hand-rolled ~8 messages. The SDK saves the
   codec and gives `session/list` and registry install; hand-rolling keeps the dependency count at
   one (DeskCore) after SwiftTerm leaves. The mapper to `RunEvent` is the same work either way.
6. Does the gate answer flow need an **audit line** in `.dev/events/<branch>.jsonl` (who allowed
   what, when), given the pipeline's gates are the product? Today the terminal kept no such record.

---

## 9. Not doing

- Not building a chat, in any form, for any provider.
- Not building a terminal emulator, embedding a web terminal, or reading a pty.
- Not integrating a cloud agent API (Antigravity's Gemini-hosted agent runs in Google's sandbox, not
  on the worktree).
- Not touching Insights' ask surface (ADR 0030) — it is a door launcher, not a chat, and it already
  runs headless.
- Not changing how the board decides anything (ADR 0011). Runs shows; the board and git decide.

---

## 10. The review, 2026-09-16

The record above is unchanged from the day it was written, apart from its Status line. This section
is what the architecture review added. Where the two disagree, this section wins.

### 10.1 Five amendments

**1. `HeadlessSession` is for doors, never a fallback for a task.** §4.3 kept it "so a machine with
no `npx` still works", and risks 2 and 6 are both that sentence. But the two substrates do not agree
on the one thing the app exists to do: over ACP a gate is a blocking `session/request_permission`;
headless reports `permission_denials` after the fact. Same ask block, same Permissions control, two
meanings, chosen by the machine. The split is by **kind of run** — `ACPSession` for task agents,
`HeadlessSession` permanently for doors — and where no adapter is found, *Run it here* is empty with
the reason and hand-off is the answer. This removes an axis from the test matrix and both risks with
it. It costs: a machine with neither Node nor opencode/Goose/Cursor cannot run a task in-app. It
could before — in a terminal, which is where the hand-off puts it.

**2. `TaskLaunch` serialises to a file, and every executor reads it.** §4.2 made it a value; the
review makes it `.devdesk/launch/<id>.json`. The payload — branch, worktree plan, base SHA, the
prompt the doors compose, the gates, the labels — is the part no other product builds; executors are
commodities that will churn. One file means *Run it here* and *Hand it to* are one design with
different executors, that `sc worktree create --from-file` consumes it literally, and that if ACP v2
lands badly Dev Desk degrades to a launcher rather than to nothing. That is the structural form of
the developer's *"they will do it better than me"*: the executor is theirs, the task is ours.

**3. The truth rank is stated once.** §4.9 said the sidecar outranks the stream and then put
`TaskLaunch` and the session id into `RunJournal`, so three stores touch a run. The rank:
**git + `.dev/<branch>.json`** decide (ADR 0011) · **`RunJournal`** holds durable facts the app owns
— launch, session id, gate answers, outcome · **`RunEvent[]`** is a rendering, rebuildable with
`session/load`, never consulted for a decision. This answers §8 question 6 with a yes: a gate answer
is a durable fact and is journaled to `.dev/events/<branch>.jsonl`.

**4. Step 3 splits into 3a, 3b, 3c.** As written it is the entire risk of the project in one step
with nothing to look at until the end — in a repo whose rule is *edit → build → look at the result
on screen*. **3a**: the JSON-RPC line codec and the `session/update → RunEvent` mapper, with
fixtures recorded from a real adapter, no UI, verified by `swift test`. **3b**: `RunPane` and the
Runs list rendering `RunEvent` **from those fixtures** — the full UI on screen, no live agent, which
is where the event log gets found to be too noisy or too quiet, cheaply. **3c**: wire them. Same
work, three commits, each one lookable-at.

**5. One thing is called Runs.** `ProjectRuns`, `DoorRuns` and a Runs bottom panel already exist;
renaming the screen to Runs while that panel exists is the problem, not the noun. The panel folds
into the screen. *Background* becomes **Doors**, because the group should carry its substrate.
**Elsewhere** does not consume a slot — the app cannot see or stop those tokens — but is counted:
`3 of 5 running · 2 elsewhere`, and comes back only on an explicit *Bring back*.

### 10.2 What §3 got wrong, verified live 2026-09-16

| § | Claimed | Actually |
|---|---|---|
| 3.1 | `session/update` carries the nine variants listed | **11.** Add `config_option_update`, `available_commands_update`, `user_message_chunk`. The 3a mapper is wider than §4.4 |
| 3.1 | `session/set_mode` is capability-gated | Deprecated on arrival in v1 — *"will be removed in a future version"*. Do not build on it |
| 3.1 | the registry's adapters are `@agentclientprotocol/*` npm packages | **Only two are.** Claude Code `@0.78.0` and Codex `@1.12.0`. Gemini CLI is `npx @google/gemini-cli --acp`; opencode, Goose and Cursor spawn their own binaries (`opencode acp`, `goose acp`, `cursor-agent acp`). A machine without Node still has ACP — which is why amendment 1 costs less than §7 risk 2 implies |
| 3.1 | ACP v2 is a published breaking draft | Still **Draft**, published 2026-07-20, no stabilisation date, spec says do not ship it by default. v1 + version switch holds |
| 3.2 | permission without a TTY: "an HTTP `PermissionRequest` hook (app listens on localhost)" | **Wrong.** It is the ordinary hook mechanism — callback or shell command — resolved through a `decision` object. No localhost listener |
| 3.2 | `--permission-mode` values | Seven: `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`, `manual` |
| 3.2 / 3.3 | doc URLs | `docs.claude.com` now splits to code.claude.com and platform.claude.com; Codex's docs moved to learn.chatgpt.com |
| 3.1 | community Swift SDKs | `wiedymi/swift-acp` — MIT, 32 stars, last push 2026-07-24, targets v1. `rebornix/acp-swift-sdk` — 7 stars, stale since 2026-02-07 |

Unchanged and load-bearing: ACP v1 is the stable version; `session/request_permission` is exactly as
described, with option kinds `allow_once` / `allow_always` / `reject_once` / `reject_always` and a
`selected` / `cancelled` response. The gate mechanism this design rests on is real. Codex's
app-server is still experimental. Antigravity's terms still name third-party access as a violation.

### 10.3 §8 answered

1. **Runs** — and the duplicate panel folds in (amendment 5).
2. **Permanent, for doors only** (amendment 1).
3. **First start of a task in full**, then a compact confirm; ⌥Start reopens the sheet; Auto never.
4. **Yes, one way** — an Elsewhere run returns on an explicit *Bring back*. ACP has no locking, and
   two hosts replaying one session concurrently render garbage, so return is a deliberate act.
5. **Hand-rolled**, in DeskCore. SwiftTerm is being deleted to stop owing our surface to a
   dependency; a pre-1.0 package, while the protocol has a published breaking draft, gives that
   ownership back. The version switch must be ours; the mapper is the same work either way.
6. **Yes** — gate answers are journaled (amendment 3).

### 10.4 Still open

- **The quit policy.** ACP sessions are children of Dev Desk, so quit kills them exactly as it
  killed a pty. But a session id now exists, so quit could be survivable: journal it, resume with
  history next launch. `QuitGuard.swift` was written for a world where a killed run was lost; that
  assumption is false now and deserves its own decision.
- **Elsewhere and the meter.** Counted, not governed, is the choice made here. The alternative —
  letting a handed-off run hold a slot — is a lie in the other direction.
