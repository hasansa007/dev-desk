# 0036 — Agents run over a protocol, and the terminal leaves the app

Status:  Proposed — for architecture review; nothing built
Date:    2026-09-15
Commit:  (none)  ·  design record
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

**2. A task's session is a protocol session.** `AgentSession` is the one abstraction the app
hosts; `ACPSession` is its first implementation (ACP v1, decoding behind a negotiated version
switch, `fs/*` and `terminal/*` never adopted). Today's `claude -p`/`codex exec` path stays as
`HeadlessSession` for background doors and as the fallback where the ACP adapter is absent.

**3. The pane is an event log, not a transcript.** What the app draws about a run is what the
stream says — phase, text, tool, diff, plan, ask, usage, ended — with the `.dev/events` sidecar
outranking the agent's words on phase and git outranking everyone on outcome (ADR 0011).

**4. The human types into a run only when it asks.** A permission request renders as Allow once ·
Allow for this run · Reject with the command shown; a question renders with its options and a free
line. Answers go back over the same channel. There is no composer.

**5. Terminals becomes Runs.** Rows grouped Running · Queued · Elsewhere · Background · Ended.
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

## Consequences

- Parallel runs are honest: N sessions are N processes and N rows; the slot limit (ADR 0035) is
  about tokens, which is what the Auto warning says.
- Gates become native. ADR 0018's *"stops at the pipeline's approval gates and asks you in its
  terminal"* becomes *"asks you in Runs"*, with the command and the diff in the dialog.
- Recovery gains history: `session/load` replays the log, so a recovered run (ADR 0031) comes back
  with what it did, which a pty never could.
- Decision 14 is stronger: the app no longer hosts even the pty a credential flows through.
- New runtime assumption: the Claude and Codex ACP adapters are npm packages, so a machine with the
  CLI but no Node falls back to `HeadlessSession`. Detection must say which it found.
- New maintenance edge: ACP v2 is a published breaking draft; Codex's app-server (which the Codex
  adapter wraps) is labelled experimental. Both are pinned by what detection reports.
- Removed: ~2,300 lines (pty and chat surfaces). Added: ~1,200 (`ACPSession`, the mapper and its
  fixtures, the start sheet, the pane).
- Open for the review: the screen's name (Runs vs Sessions); whether `HeadlessSession` is permanent
  or transitional; whether the start sheet shows on every start; whether a handed-off session can
  come back into Runs; community Swift SDK vs. a hand-rolled ~8-message client; whether gate answers
  are journaled to `.dev/events`.
