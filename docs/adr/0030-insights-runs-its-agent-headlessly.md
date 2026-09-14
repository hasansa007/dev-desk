# 0030 — Insights runs its agent headlessly

Status:  Accepted
Date:    2026-09-14
Commit:  (this branch) · `main`
Amends:  0018 (Dev Desk starts the task's agent, by hand or in Auto for queued tasks)

## Context

Insights is the one screen in Dev Desk that asks a question and expects an answer back. Until now it
could not answer anything: `LocalGitDataSource` handed every real project
`.unavailable("Insights needs a validated agent connection…")`, and `InsightsConversation.ask`
replayed a canned `InsightsReply` after a delay. The sample project's scripted conversation was the
only thing that had ever "worked".

The door it needs already exists. `skills/insights/SKILL.md` — the front desk — answers a question
about a codebase from evidence with `file:line` citations, and it is read-only apart from
`PROJECT_MAP.md`.

What blocked the wiring is a boundary this family has held since ADR 0018. `AgentLaunch.arguments`
passes the agent's name and the prompt and **nothing else** — its comment says *"Always interactive:
the agent's name and the prompt, never -p, exec, a model, or a flag that skips approvals."* ADR 0018
rejected `dev run --execute` for exactly one reason: *"It is non-interactive, so the run can't stop
at the gates."* A pipeline run passes through Phases 5, 6 and 14, where the agent must stop and ask.
A headless run has no terminal to ask in, so it would answer its own approval questions.

That reason is about **gates**, and Insights has none. It runs one door, that door writes nothing
into the working tree, and there is nothing for a human to approve mid-run. Meanwhile the
interactive form is actively wrong here: it would open a terminal beside the chat, make the
developer read the answer in a scrollback, and leave the bubble they typed into empty forever.

## Decision

**1. Insights runs its agent headlessly: `claude -p "<prompt>"` or `codex exec "<prompt>"`.**
`InsightsAgent` in DeskCore builds the prompt, runs it through the ordinary `CommandRunner`, and
hands the text back to the conversation, which appends it as the next bubble. **This reverses ADR
0018's "never -p, exec" for this surface, and only this one.**

**2. The prompt is the family's prompt, pointed at one door.** `Read <skillRoot>/skills/insights/SKILL.md
and execute it exactly as written, following every phase and gate it defines. Arguments: <question>` —
the same sentence `scripts/dev.py` builds and `DoorCommand.prompt` repeats, with the question where
a door's arguments go. Nothing is reworded for being headless.

**3. The interactive path is untouched.** `AgentLaunch.arguments` still adds no flag, task agents and
door runs still open a terminal you can watch, and no other screen changed. The headless form lives
in `InsightsAgent` and is built nowhere else.

**4. Availability is read, not assumed.** `InsightsAgent.availability` takes what `ToolDetection`
found and returns the agent to use, or the reason there isn't one: a signed-out CLI is not a
connection, because a headless run has no terminal to answer a sign-in prompt in. The demo path
(`.demo(InsightsScript)`) is unchanged, so the sample project still replays its script.

**5. A run gets minutes, not seconds.** `InsightsAgent.timeout` is 300s. `CommandTimeout`'s entries
are all sized for a git read, and an agent reading a repository is not one.

## Rejected

```
rejected: an interactive terminal for Insights, per 0018 — the answer would land in a scrollback
          beside the chat that asked for it; a Q&A surface whose answers appear elsewhere is not one
rejected: keeping the canned reply and calling the screen "not built yet" — the screen exists, ships,
          and says "No agent connection" on every real project
rejected: --dangerously-skip-permissions or an equivalent — nothing here needs approvals skipped;
          the door reads, and 0018's refusal of approval-skipping flags stands unamended
rejected: a new sidebar destination for the diagrams — architecture is the same question drawn
          rather than asked, so it is a tab inside Insights
rejected: reusing CommandTimeout.git — a 15-second budget for an agent is a timeout, not a timeout value
```

## Consequences

- **Insights spends tokens without a terminal to watch it.** One question is one headless run, started
  only by pressing Send. Nothing runs on load, and a newer question cancels the run in flight.
- **The gate argument is now surface-by-surface, not app-wide.** 0018's rule holds wherever a run has
  gates to stop at; this ADR is the standing exception, and any future headless path must argue its
  own case here rather than cite this one.
- **The answer is only as good as the door.** Citations, routing and `PROJECT_MAP.md` upkeep are
  `skills/insights/SKILL.md`'s job; the app shows what came back and lifts a trailing `file:line` into
  the bubble's citation line.
- **A failure is said in the conversation** — missing CLI, non-zero exit, timeout — rather than leaving
  the reading indicator spinning.
- **`dev:arch`'s diagrams are surfaced beside the chat**, read straight from `docs/arch/*.html` in a
  `WKWebView` (the app's first). The app lists and displays them; it never draws one.
