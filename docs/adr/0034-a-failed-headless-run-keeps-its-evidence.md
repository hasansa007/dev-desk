# 0034 — A failed headless run keeps its evidence, and one rule places every prompt

Status:  Accepted
Date:    2026-09-15
Commit:  —  ·  working branch

## Context

Every Diagrams generate under the Claude connection died in seconds having drawn nothing, in every
project and for every kind. The argv in `ArchRun.launch` put the prompt last, after `--allowedTools`
— a variadic flag, which consumed the trailing positional as one more tool name. Claude, given no
prompt, exited 1 with *"Input must be provided either through stdin or as a prompt argument when
using --print"* (verified 2026-09-15 against the installed claude at `~/.local/bin/claude`, Claude
Code 2.1.272; the same prompt placed before the flags runs).

The one line that named the failure was printed into the run's scratch terminal — and thrown away.
`ProjectWindowModel`'s `onSessionEnded` closed the session (`closeTerminal`) the moment the run
ended, and `recordDiagramGenerateResult` then showed the only sentence it could: *"It may have
declined … Open the run in Sessions to see what it said"* — wrong in cause, and pointing at a
session that no longer existed.

Two structural weaknesses, not one bug. First, each headless launcher placed its prompt by hand:
`InsightsAgent` and `ChatSession` are safe because the prompt happens to come first, `JobCommand`'s
two builders append it last and are safe only because every flag they pass today takes exactly one
value — one variadic flag added there later reproduces the failure in the doors, silently. Second,
the failure handler destroyed the run's own words and replaced them with a guess.

## Decision

**One shared rule places the prompt.** `HeadlessArgv` (DeskCore) holds the documented list of
variadic claude/codex flags and one builder, `argv(head:flags:prompt:)`: the prompt stays the final
element — the shape every verified invocation has — unless a variadic flag is among the flags, in
which case it moves immediately after the head (`claude -p <prompt> <flags…>`), where nothing can
consume it. `ArchRun` and both `JobCommand` builders build through it; today only `ArchRun`'s claude
argv changes shape. Over-matching is safe — a prompt moved forward is never eaten — so the list is
one set for both CLIs.

**A failed generate keeps its evidence.** When a generate's session ends and the kind still has no
file, the scratch session is kept, not closed — the transcript stays readable in Sessions — and the
recorded failure carries the run's exit status, the last non-empty lines it wrote (the registry reads
the terminal's own buffer at exit, `JournalRecord.logTail`'s shape and cap; no second capture), and
the session id. The notice leads with the run's own last words; a run over in seconds is called a
launch failure, and only a run that took its time keeps "it may have declined". Success closes the
session as before.

## Rejected

- **Fix the one argv and leave a comment** — `JobCommand`'s builders stay correct only by accident,
  and the next variadic flag added there fails silently in the doors, exactly as this one did in
  Diagrams. A comment cannot reposition a prompt; the builder can.
- **Assert (crash) on a variadic flag before the prompt instead of repositioning** — the failure
  would then be the app's, at launch time, in the user's session; moving the prompt is always
  correct and costs nothing.
- **Pipe the headless run's output through a capture the app owns** — the terminal's buffer already
  holds the transcript and `RunJournal` already defines the tail's shape; a parallel byte-stream
  capture is a second source of truth and a second escape-sequence parser.
- **Close the session and copy its whole transcript into the notice** — the banner is a notice, not
  a pane. Keeping the session gives the full transcript in the surface built for reading one, and
  the notice needs only the last words and a way to open it.

## Consequences

- A failed generate leaves an ended scratch session in Sessions until the user closes it; success
  still cleans up after itself.
- Ended shell panes now show the last lines their process wrote, for every session kind — the same
  capture the Diagrams notice reads.
- `ArchRun`'s claude argv is `claude -p <prompt> --permission-mode acceptEdits --allowedTools …`;
  codex's, and every `JobCommand` argv, are byte-for-byte unchanged today.
- A future flag addition to any headless launcher is safe by construction, and
  `HeadlessArgvTests` pins the repositioning at the unit level.
