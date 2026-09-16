# 0036 — Agents run over a protocol, and the terminal leaves the app

Status:  Accepted — reviewed 2026-09-16; amended four times 2026-09-16; implementation started at step 1
Date:    2026-09-15  ·  accepted 2026-09-16
Commit:  (this branch)  ·  `main`  ·  design record
[`docs/superpowers/specs/2026-09-15-runs-without-terminal-design.md`](../superpowers/specs/2026-09-15-runs-without-terminal-design.md)
· mockup [`docs/design/2026-09-15-runs-without-terminal.html`](../design/2026-09-15-runs-without-terminal.html)

Reverses [ADR 0016](0016-dev-desk-embeds-a-terminal-with-swiftterm.md) (SwiftTerm).
Amends [ADR 0017](0017-a-tasks-shell-opens-in-its-own-worktree-when-asked.md),
[ADR 0018](0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md),
[ADR 0026](0026-a-task-has-one-session-and-terminals-is-where-it-lives.md).
Extends [ADR 0025](0025-a-background-run-belongs-to-the-app-not-the-window.md),
[ADR 0031](0031-a-killed-run-leaves-a-record-and-the-next-launch-offers-to-continue-it.md).

## Context

The developer, 2026-09-15: *"I want to prevent [myself] from mimicking other apps — they will do it
better than me,"* and: *"the main idea of this app is to mirror my dev skill … generate all data
needed to start a new branch … so that the task can be completed, and multiple tasks can run in
parallel."*

Dev Desk today hosts every task agent inside a SwiftTerm pty (ADR 0016, 0018, 0026). The app sees
a drawn screen and no data — `SessionUsageReader.swift` says so in its first comment. On top of that
pty sit two chat surfaces: one scrapes the terminal text every 600 ms and guesses where a turn ends
(`TerminalChatView`), the other runs a fresh `claude -p` per message and carries nothing between
turns (`ChatTab`/`ChatSession`). Both are a worse version of what Claude Code, Codex, Zed, Cursor and
super.engineering ship as their whole product.

Meanwhile the app's *other* substrate — the headless job path of ADR 0025/0030/0031 — already
has session ids, `--resume`, an *asking* state answered in the app, a context meter, and a recovery
record. Only background doors get it. Task agents, the thing the app exists for, get bytes.

The check (design record §3) found that every agent in scope speaks one protocol, the Agent Client
Protocol: JSON-RPC over the agent's stdio, a registry naming each binary, streamed
`session/update`s carrying text, tool calls, diffs and plans, `session/load`/`session/list` for
history, and one blocking client request — `session/request_permission` — which is precisely what
a pipeline gate is. Claude, Codex, Gemini CLI, Goose, opencode, Copilot and Cursor ship adapters.
Two products that cannot be embedded (Antigravity, by its terms; super.engineering, alpha and the
competitor for the part being removed) can still be launched with a folder and a session id.

## Decision

**1. Dev Desk prepares and schedules; it does not host a screen and it does not converse.**
The product is `TaskLaunch` — door, branch, worktree, base, prompt, gates, permission policy, mode,
labels — built once as a value, shown before anything runs, stored, queued, and handed to a runner.
It is `Codable` and it **serialises to a file**, `.devdesk/launch/<id>.json`, because every runner
has to read it: `ACPSession` takes the prompt, `sc worktree create --from-file` takes the file
literally, a Terminal hand-off writes it and pre-types the command. Run-it-here and hand-it-to stop
being two designs and become one payload with different executors.

**2. A task's session is a protocol session, and the substrate is decided by the KIND of run, never
by the machine.** `AgentSession` is the one abstraction the app hosts. `ACPSession` (ACP v1,
decoding behind a negotiated version switch, `fs/*` and `terminal/*` never adopted) is the only
substrate for a task agent. Today's `claude -p`/`codex exec` path stays as `HeadlessSession`
permanently, for **background doors only** — Survey, Ideation, Insights, file-an-issue — which are
one-shot and never gated. Where no ACP adapter is detected the app does **not** quietly run the task
headlessly: *Run it here* is empty with the reason, and the hand-off list is the answer. A gate that
means "the agent waits for you" on one machine and "you are told afterwards" on another is the one
defect this whole decision exists to remove; a capability fallback reintroduces it behind identical
chrome.

**3. The pane is an event log, not a transcript — and it is not the record.** What the app draws
about a run is what the stream says: phase, text, tool, diff, plan, ask, usage, ended. Three stores
now touch a run, so the rank is stated once and does not move: **git and `.dev/<branch>.json` decide
what happened** (ADR 0011); **`RunJournal` holds the durable facts the app owns** — the launch, the
provider session id, every gate answer, the outcome; **`RunEvent[]` is a rendering**, rebuildable
with `session/load` and never consulted for a decision. A gate answer is a durable fact, so it is
journaled and written to `.dev/events/<branch>.jsonl` beside the phase it gated. The terminal kept
no such record; that was a defect, not a baseline.

**4. The human types into a run only when it asks.** A permission request renders as Allow once ·
Allow for this run · Reject with the command shown; a question renders with its options and a free
line. Answers go back over the same channel. There is no composer.

**5. Terminals becomes Runs, and only one thing is called Runs.** Rows grouped Running · Queued ·
Elsewhere · Doors · Ended — *Doors*, not *Background*, because the group carries the substrate:
headless, one-shot, never gated. The existing Runs bottom panel folds into the screen; `ProjectRuns`
and `DoorRuns` keep their names in DeskCore, but the app shows one place where everything executing
appears, which is the "many at once" promise made visible. An **Elsewhere** run does not consume a
slot — the app can neither see nor stop the tokens a handed-off run burns — but it is counted in the
meter: `3 of 5 running · 2 elsewhere`. It returns only when the human clicks *Bring back*; ACP has
no locking, and two hosts replaying one session concurrently render garbage.
"A task has one session" (ADR 0026) stands; "Terminals is the only host of a live terminal" is void
because there is none.

**6. What needs a TTY leaves the app.** Provider sign-in and *New terminal* open the user's own
terminal. Run project becomes a process with a log row. *Continue in ▾* hands the same session
(`claude --resume <id>`) or the same worktree to Terminal, Codex, Antigravity, super.engineering or
an editor; a handed-off task is watched by its branch, as any external work already is (ADR 0013).

**7. SwiftTerm leaves `project.yml`.** With it go `ShellTerminalView`, `ShellPane`,
`ShellSessions`, both chats, the chat-style preference, the terminal tokens and tile metrics.

## Rejected

- **Keeping the terminal "one click deeper"** (next-level decision 17). It is the whole cost — the
  dependency, the registry, the pty per session, the precedence rules — kept for a view the
  developer can have in Terminal.app with one `--resume`.
- **A protocol chat: a proper composer over ACP.** It is a better chat, and a chat all the same. The
  developer's rule was not "mimic well"; it was "do not mimic".
- **Embedding Antigravity or super.engineering.** Antigravity's FAQ names third-party access as a
  terms violation; super.engineering is alpha on a nightly track and is the competitor for exactly
  this layer. Launch and watch.
- **Reverse-engineering Claude Code's SDK control channel** to get `canUseTool` from the raw CLI.
  Not specified publicly; ACP gives the same thing specified.
- **ACP `fs/*` and `terminal/*`.** Removed in the v2 draft; an agent that needs a file reads it
  itself in its worktree.
- **A capability fallback: run the task headlessly where no ACP adapter is found.** This was in the
  proposed version and the review removed it. It buys a run on a machine without Node at the price
  of a permission control that means two different things, under one chrome, decided by the
  machine. It is also worth less than it looked: of the seven adapters in the registry, only Claude
  Code and Codex are npm packages — opencode, Goose and Cursor spawn their own binaries with an
  `acp` subcommand, so a developer without Node still has ACP. The state the fallback rescued is
  rarer than the defect it introduced.
- **Letting the event stream be the record.** Persisting `RunEvent[]` as truth is the cheap way to
  get history and the fast way to lose ADR 0011: the stream is what an agent *said*, and the board
  already knows better. It is a rendering, rebuilt on demand.
- **The community Swift ACP SDK** (`wiedymi/swift-acp`, MIT, 32 stars, last pushed 2026-07-24;
  `rebornix/acp-swift-sdk` stale since February). SwiftTerm is being deleted to stop owing a
  dependency our surface; taking a pre-1.0 package while the protocol itself has a published
  breaking draft hands that ownership straight back. The version switch has to be ours. The mapper
  to `RunEvent` is the same work either way. Read it, do not link it.

## Consequences

- Parallel runs are honest: N sessions are N processes and N rows; the slot limit (ADR 0035) is
  about tokens, which is what the Auto warning says.
- Gates become native. ADR 0018's *"stops at the pipeline's approval gates and asks you in its
  terminal"* becomes *"asks you in Runs"*, with the command and the diff in the dialog.
- Recovery gains history: `session/load` replays the log, so a recovered run (ADR 0031) comes back
  with what it did, which a pty never could.
- Decision 14 is stronger: the app no longer hosts even the pty a credential flows through.
- New runtime assumption, smaller than it first looked: only the Claude Code
  (`@agentclientprotocol/claude-agent-acp`) and Codex (`@agentclientprotocol/codex-acp`) adapters
  are npm packages. Gemini CLI, opencode, Goose, Copilot and Cursor spawn their own binary with an
  `acp` flag or subcommand. Detection names the one it found and pins its version; a machine with no
  Node loses two providers, not the feature.
- New maintenance edge: ACP v2 is still a Draft (published 2026-07-20, no stabilisation date, and
  the spec says not to ship it by default); Codex's app-server, which the Codex adapter wraps, is
  still labelled experimental. Both are pinned by what detection reports.
- The mapper is wider than the proposal assumed: `session/update` carries **11** variants, not the
  eight listed — `config_option_update`, `available_commands_update` and `user_message_chunk` were
  missing. `session/set_mode` is deprecated on arrival in v1 and must not be built on.
- Removed: ~2,300 lines (pty and chat surfaces). Added: ~1,200 (`ACPSession`, the mapper and its
  fixtures, the start sheet, the pane).
- Settled by the review of 2026-09-16: the screen is **Runs**, and the duplicate Runs panel folds
  into it · `HeadlessSession` is **permanent, for doors only** · the start sheet shows in full on a
  task's **first** start, then a compact confirm, with ⌥Start to reopen it, and never under Auto ·
  a handed-off session **can** come back, one way, on an explicit *Bring back* · the client is
  **hand-rolled** in DeskCore · gate answers **are** journaled to `.dev/events`.
- Still open, and deliberately not decided here: the **quit policy**. ACP sessions are children of
  Dev Desk, so quitting kills them exactly as it killed a pty — but a session id now exists, so
  quit could be survivable (journal it, resume with history next launch). `QuitGuard.swift` was
  written for a world where a killed run was lost. That assumption is now false and needs its own
  decision rather than inheritance.

## Amendment — 2026-09-16 · a handed-off session can be resumed, and Gemini CLI leaves the list

Two facts arrived after the review, both from running the CLIs rather than reading about them.

**1. Hand-off resume is terms-compatible, and Antigravity already implements it.** *Rejected* above
reads "Antigravity's FAQ names third-party access as a terms violation. Launch and watch," which left
*resume* looking like a casualty of the same rule. It is not. What the FAQ bans is third-party
software using **Antigravity's OAuth** to reach the service — its own example is OpenClaw with
Antigravity OAuth — and Google is enforcing it, suspending paying subscribers on 2026-09-03 with
opencode named among the triggers. Launching Google's own binary is not that: `agy` authenticates as
itself, and no credential passes through a tool that is not Google's. `agy` 1.2.1 ships `--continue`
and `--conversation <ID>` beside `--print`, so decision 6's *Continue in ▾* can hand Antigravity a
folder **and a conversation id**, exactly as it hands Claude `claude --resume <id>`.
super.engineering reads its own history the same way (`sc history get --provider KEY --session ID`).

So *Resume an ended session* in the capability matrix is validatable for a handed-off provider and
must not be recorded as unavailable for one. What stays rejected is unchanged and better evidenced:
**embedding** — Dev Desk holding the session and speaking to the provider's backend — is both the
shape the terms forbid and the shape accounts were suspended for. The distinction the terms actually
draw is not app-versus-terminal, it is *whose binary holds the credential*.

**2. Gemini CLI is no longer a provider an individual developer has.** Context and Consequences both
count it among the adapters that spawn their own binary, and that assumption is now false. Google cut
every individual tier — free, AI Pro, AI Ultra — off that client on 2026-06-18. A browser sign-in
completed on this Mac on 2026-09-16 and the next call was still refused with `IneligibleTierError` /
`UNSUPPORTED_CLIENT`, pointing at Antigravity; only a paid API key or a Code Assist
Standard/Enterprise licence authenticates. The Consequences bullet's arithmetic stands, its roster
does not: Gemini CLI is present on PATH and unusable, which is worse than absent, because detection
that trusts `which` reports it ready. Detection must read auth, not presence.
`scripts/dev.py` records the same reason (36d0fc7).

## Amendment 2 — 2026-09-16 · the terminal stays until ACP exists, and every CLI runs in it

**Decisions 6 and 7 are deferred, not dropped.** The built-in terminal and SwiftTerm stay until `ACPSession` exists
to replace them. Until then, "What needs a TTY leaves the app" applies to sign-in — `TerminalHandoff` — and not to
task runs.

The developer, choosing between an external hand-off and the app's own terminal: *"1, all in one app."* The case
for it was already on screen. Typing `opencode` into a Sessions terminal ran it, and Claude and Codex under *Run it
here* have always run in that terminal (`StartRunners` labels them `terminal`, not `acp v1`, for exactly that
reason). Removing it is steps 3 and 7, which nothing has scheduled. Building a second path out to Terminal.app in
the meantime would have split one Start into two places to watch.

**Gemini, opencode and Antigravity run under *Run it here*, in that terminal.** `TerminalAgent` holds one command
each, run for real against a clone of this repository on 2026-09-16 — each read the family's SKILL.md and answered
from it:

- `gemini --include-directories <family> -i '<prompt>'` — 0.60.0 on an API key. The folder flag is needed: without
  it a headless Gemini asked to read SKILL.md waited five minutes and printed nothing.
- `opencode --prompt '<prompt>'` — 1.18.31, the build a login shell resolves.
- `agy --add-dir <family> -i '<prompt>'` — 1.2.1, run by the developer. Amendment 1's line holds here: `agy` holds
  its own credential and the app types a command into a shell, which is not third-party access.

They take the same run row, slot and Sessions pane as Claude. Two limits are real and stated in the code rather than
hidden. The queue can park only a Claude or Codex `TaskLaunch`, so with no free slot these rows are unavailable
rather than queued. And a start with one of them is not remembered, so the card's next Start opens the sheet
instead of quietly running Claude.

**This withdraws the external hand-off from 8e9567e.** The "Or hand it to" section returns to empty, which is where
*Continue in ▾* will fill it.

**Amendment 1 overstated one thing.** It said Gemini CLI "is no longer a provider an individual developer has".
That is true of Google sign-in, which is what it tested. The same developer added an API key the same afternoon and
Gemini ran. What an individual lost is the subscription path, not the CLI.

## Amendment 3 — 2026-09-16 · "Continue in ▾" is the developer's own list

Decision 6 named the apps a task could go to: Terminal, Codex, Antigravity, super.engineering, an editor. The
developer asked for the list to be theirs instead: *"other apps like super.engineer or ZadLoop … a list of
applications that can be configured by user"*, and then *"don't focus on the specific name — but on the 'start
with..' an app."* A fixed list goes stale as soon as a new app ships, and every name on it is a claim this app would
have to keep true.

**What an entry is.** Settings › Start with holds entries for every project, of two kinds, because apps accept
different things:

- **An app**, chosen from `/Applications`, is opened on the project folder. Nearly every app accepts a folder, and
  a folder carries no task, so the task's prompt is put on the clipboard.
- **A command** with `{folder}`, `{prompt}`, `{taskFile}` and `{title}` is typed into a Sessions terminal with the
  task filled in. That reaches any app with a command line without Dev Desk knowing the app. Every value is
  single-quoted as it goes in, so a card title cannot end the string or start a second command. A name in braces
  that is not a placeholder is left as written and flagged in Settings.

**Where it is offered.** The start sheet's empty hand-off section becomes *Or start with*, and every card that
offers Start gets a *Start with ▸* submenu ending in *Edit this list…*. A card that cannot start offers neither.

**What Dev Desk knows afterwards.** A start with the list moves the card to In progress, like any start. The launch
is written to `.devdesk/start-with/`, which `{taskFile}` names. It is deliberately not `.devdesk/launch/`: a file
there makes the card's next Start run without the sheet, and it can only name Claude or Codex. A command's run is a
Sessions row like any other. An app's run is not watched at all beyond its branch.

**Not built.** Decision 5's *Elsewhere* count needs a record of work started outside the app, and nothing stores
one yet. Starting with an app therefore takes no slot and is not counted, which is true but not yet visible.

## Amendment 4 — 2026-09-16 · the terminal-only agents are agents, and background runs have their own setting

Amendment 2 ran Gemini, opencode and Antigravity beside Claude and Codex, but with two limits: they could not be
queued, and a start with one was not remembered. Both came from one fact — `AgentKind` had two cases, and everything
that remembers or queues a start stores an `AgentKind`. The developer asked for them to be *"default-able and
remembered"*.

**`AgentKind` has five cases.** The start sheet, a remembered launch, the queue, Auto and a task's own agent session
all read the kind, so each now carries any of the five with no special path. A terminal-only kind types the command
`TerminalAgent` verified, reading the family from Claude's root, since install.sh writes no copy for the other
three. Installed is all that can be known about them: they have no Accounts row and no sign-in this app reads.

**Background runs keep to Claude and Codex, under a setting of their own.** Survey or Ideation run in the
background, filing an issue and a diagram need a headless form whose output this app reads. Only Claude and Codex
have one, and reading Antigravity's is what its terms forbid. The developer chose a separate *Background runs*
setting over a silent fallback or disabling those features. A default of Gemini must not quietly become Codex. Never
chosen, the setting shows the default when that can run in the background, and Codex otherwise.
`DoorCommand.backgroundAgent(named:)` is the only lookup `JobCommand` and `ArchRun` use. That fixes a latent defect:
`JobCommand` read every non-Claude agent as Codex and would have built `gemini exec --json`. The widening also
exposed one in Insights, which planned a headless run for any detected connection whose id was a kind. It now takes
Claude and Codex only.
