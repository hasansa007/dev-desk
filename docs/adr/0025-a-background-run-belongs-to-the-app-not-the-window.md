# 0025 — A background run belongs to the app, not the window

Status:  Accepted
Date:    2026-09-12
Commit:  (this branch)  ·  `feat/desk-install-script-and-one-card`
Closes:  [#67](https://github.com/hasansa007/dev-skill/issues/67), the last child of [#59](https://github.com/hasansa007/dev-skill/issues/59)

## Context

`dev:survey`'s fan-out takes minutes and needs nobody while it works. Until now every run held a
terminal in a task's dialog, and that terminal dies with its window: `ShellTerminalRegistry.endAll()`
ends every session when a project window closes. So the run that least needs watching was the one
that could least survive being left.

#68 built the half that could be built without deciding anything: `JobCommand.launch` produces the
headless argv for either CLI (`claude -p --output-format stream-json --verbose --session-id …`, and
`codex exec --json`, which has no id flag and reports its own), `JobCommand.resume` rebuilds it with
an answer, and `RunPermission` records what a run may do without asking — because a headless run
cannot prompt, so the grant has to be made before it starts. **Nothing called any of it**: for a day,
`JobCommandTests` were its only callers.

What was left was not code but a choice about lifetime, and #67's first criterion — *"survives closing
the project window"* — is in direct conflict with the rule that a window ends its sessions.

## Decision

**1. The registry is owned by the app.** `JobRegistry` is created in `DevDeskApp` and passed into every
window, not created by one. Closing a project window leaves its background runs going; quitting the
app ends them, which is the same bargain `LiveShells.endAllBeforeQuit` already makes for shells. A run
that outlives the app was rejected — see below.

**2. The output is parsed, not tailed.** `JobStream` reads the agents' JSONL into three events —
`session`, `line`, `ended(text:question:)`. It lives in DeskCore and touches no process, so the shapes
are tested against recorded output rather than by starting an agent; a parser that can only be
exercised by spawning one is a parser nobody re-tests once it works.

**3. Ending on a question is a state, not a failure.** A headless run has no terminal to prompt in, so
needing an answer shows up as the run ending. `.asking(question)` keeps the row waiting instead of
finished, the row grows an answer box, and answering calls `JobCommand.resume` with the **same session
id** — which is why the id is captured from the stream for Codex and chosen up front for Claude.

**4. The spawner is a protocol.** `JobSpawner` has one real implementation (`ProcessJobSpawner`: a
plain child process, pipe, line-buffered) and a fake one in the tests. The callbacks are `@MainActor`,
so the hop from the pipe's background queue belongs to the spawner that owns the pipe — hopping inside
the registry instead made every state change land a turn later, invisible in the app and untestable
everywhere.

## Consequences

- **Quitting the app ends background runs.** They are children of the app; nothing reattaches to an
  orphan. The alternative is in the rejected list, with the reason.
- **A pipe delivers chunks, not lines**, so the spawner buffers until a newline and flushes whatever
  has no trailing one. A JSONL reader handed half an object parses nothing, silently.
- **The log is capped at 200 lines.** A run can talk for a long time and this is a row in a panel.
- **A crash with no result line still ends the row.** Without that, a killed run pulses forever and the
  live count never comes down.
- **Nothing is guessed for an agent the family has not verified.** `JobCommand.launch` returns nil for
  Gemini, so `start` returns nil and no row appears — rather than a plausible invocation nobody ran.
- **The end-to-end spawn is the one part not covered by tests.** The parser and the registry are; the
  `Process` plumbing is exercised only by running one. Both CLIs were confirmed to resolve on the
  widened PATH a GUI app needs (claude 2.1.269, codex-cli 0.154.0 — the versions `RunPermission`'s
  flags were verified against).

## Alternatives rejected

```
rejected: detached, surviving app quit — a log file under .dev/runs/ and state in JSON, reattached on
          launch. Survives a crash, and costs orphan reconciliation on every launch, runs nothing is
          watching, and processes alive after you quit: the opposite of the teardown rule the rest of
          the app follows
rejected: reuse the pty and simply not show it — cheapest, and inherits stop and state for free, but
          the log becomes terminal scrollback, so "ends on a question" has nothing reliable to detect,
          and it still dies with the window unless the registry moves app-wide anyway
rejected: a per-window registry — cannot satisfy the first criterion at all; its owner is gone
rejected: prompting mid-run — there is no terminal to prompt in. The grant is made before the start,
          which is what RunPermission is for
```
