# Dev Desk: the gaps epic — design record

**Date:** 2026-09-12

**Status:** built. Decisions 1, 2, 3, 5 and 6 shipped as recorded; **4 and 7 were overridden by use
on the same day** — see [ADR 0021](../../adr/0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md),
which also records the reorganization that use asked for (one dialog for every card, one dialog
size, Insights as a destination, Decisions removed, panels as window edges, Survey and Ideation as
two workflows). Decision 3 is [ADR 0020](../../adr/0020-impact-and-complexity-are-labels-the-doors-propose.md).

**Epic:** [#59](https://github.com/hasansa007/dev-skill/issues/59) · children #60–#67

**Related:** [container](2026-09-11-container-design.md) ·
[navigation and Insights](2026-09-11-mac-app-navigation-and-insights-design.md) ·
[ADR 0011](../../adr/0011-the-project-board-mirrors-it-never-decides.md) ·
[ADR 0013](../../adr/0013-the-app-reads-git-and-github-directly.md) ·
[ADR 0014](../../adr/0014-dev-desk-replaces-dev-ui.md) ·
[ADR 0017](../../adr/0017-a-tasks-shell-opens-in-its-own-worktree-when-asked.md)

## What was asked

Nine gaps, reported from screenshots of the app open on a real project: a file browser, a menu on
each card, impact and complexity labels, a button that runs `dev:survey` instead of instructions to
run it elsewhere, the same for ideation, an Ideation destination, an unstarted task that does not
open as if it were running, Settings at the bottom of the sidebar, and one control style in place of
three.

Three of them contradicted decisions already recorded, and those contradictions are what the
discussion settled.

## Decisions

### 1. A button runs a door in a terminal inside the app, and every run appears in one list

The doors are conversations. `dev:survey` and `dev:ideation` both stop before their fan-out to ask
*"N surveyors — go, or narrow it?"*, walk findings one at a time, and ask again before filing;
`/dev #N` stops at Phase 5 and Phase 6. A run with nobody to answer stops at its first question.
Dev Desk already runs a login shell in a PTY, after a click, behind a trust note (ADR 0016, 0017).

So: a project-level terminal, the command typed into it, and a Runs list carrying every run's kind
(terminal or background job), its state and a Stop. Background jobs follow as the second half
(#67), behind the same list, because everything unverified lives there: the question-answer-resume
loop, what a run may do without asking, and surviving a quit.

**The list is built for both kinds from the first line of code.** A list designed around terminals
alone cannot express *waiting for your answer* — the app sees a terminal as bytes, not as a state —
and that is the state that matters most once jobs exist.

```
rejected: a terminal alone — nothing shows or stops a run from another screen
rejected: hand off to Terminal.app — ADR 0016 already rejected this for the dock; the list stays a mock
rejected: background jobs alone — Start task's gates are decisions, and one answer box per gate is
          worse than a terminal
rejected: jobs and terminals shipped together — the unverified half would block the verified one
```

Cost to change later: low for the first half, because only the button knows how a door starts.

### 2. The card menu writes Move and Cancel; the app never writes the other three columns

Git decides In progress (a branch with unmerged commits), Review (an open pull request) and Done (a
merged one); the active milestone decides Queued. A menu that set those would make the board
disagree with git, which is what ADR 0011 forbids. They appear disabled, each saying so.

Queue and Return to backlog are a milestone edit; Cancel is a close as *not planned* with the reason
written as a comment, exactly as `dev:board` Phase 7 defines them. Delete stays out of the app —
that tier keeps its own hard gate in the door. This gives Dev Desk its first `gh` write; until now
it wrote only `git clone`, `git init` and `git worktree add`.

```
rejected: no writes, actions only — the menu becomes navigation and the move stays a conversation
rejected: the menu proposes and /dev:board writes — an agent run for a one-line label edit
rejected: split by reversibility, app moves and door cancels — two mechanisms for one menu
```

### 3. Impact and complexity are labels the doors propose and the developer corrects

`impact:high|medium|low` and `complexity:high|medium|low`, created in this repository on 2026-09-12.
Every filing door proposes both with its reasoning, marked as an assumption, and files what the
developer confirms. A repository lacking the labels is offered them and never given them silently,
which is the rule `dev:roadmap` already applies to `epic` and `dev:board` to `P1`–`P3`.

The board shows both as chips, with a dash where an issue has neither, so a rated card and an
unrated one are never confused.

The two scales are not a second priority. Priority mixes urgency with value; `dev:ideation` already
computes a gain and a cost per opportunity, ranks by the ratio, and then discards both at filing.

```
rejected: only doors with evidence rate (ideation, survey) — leaves every hand-filed issue unrated
rejected: the developer rates everything in the app — every issue starts unrated, and the doors
          already hold the evidence
rejected: map impact onto P0–P3 — priority is urgency; complexity would still have no source
rejected: an "unrated" chip instead of a dash — a prompt on every card the board did not ask for
```

### 4. An unstarted card opens a sheet, not the workspace

A Backlog or Queued card with no branch opens a sheet over the board: title, issue number, labels,
description, dependencies, Start task, Close. A card with a branch still opens the workspace.

```
rejected: an overview page in the window — the same back-and-forth as the workspace for a read
rejected: the workspace with better defaults — it still shows an empty diff and a dock for work
          that has not started
```

### 5. One control style, on the palette that already exists

The board header holds a capsule search field, a square toggle and a system segmented picker, and
its columns-rules sentence runs off the window. The controls take one height, corner radius and fill
from the tokens; the sentence moves behind an info control.

```
rejected: adopt another app's visual language — a repaint of every screen, and it contradicts the
          design brief's restrained palette with a cool blue accent
rejected: a named external design system — nothing of the sort is installed on this machine
```

### 6. The Files browser lists the whole folder, lazily

Including ignored files, one directory at a time as it is expanded — walking a repository with
`node_modules` up front would hang the window. Selecting a file shows its text through the existing
safe read (size-capped, symlinks refused, nothing resolving outside the repository), with Reveal in
Finder and Open in editor beside it.

```
rejected: tracked files only — misses work in progress, which is what a browser is opened for
rejected: everything but ignored — a second git call, and it still hides what is really there
rejected: no viewer, open in the editor only — the app would hand off for reading a README
```

### 7. Settings sits at the bottom of the sidebar

One shape, recorded so it can be objected to.

## The slices

| # | Issue | Depends on |
|---|---|---|
| 1 | [#60](https://github.com/hasansa007/dev-skill/issues/60) control styles and the sidebar's order | — |
| 2 | [#61](https://github.com/hasansa007/dev-skill/issues/61) the launcher: terminals and the Runs list | — |
| 3 | [#62](https://github.com/hasansa007/dev-skill/issues/62) the unstarted-task sheet | #61 |
| 4 | [#63](https://github.com/hasansa007/dev-skill/issues/63) the card menu's writes | — |
| 5 | [#64](https://github.com/hasansa007/dev-skill/issues/64) the Ideation destination | #61 |
| 6 | [#65](https://github.com/hasansa007/dev-skill/issues/65) impact and complexity, end to end | — |
| 7 | [#66](https://github.com/hasansa007/dev-skill/issues/66) the Files browser | — |
| 8 | [#67](https://github.com/hasansa007/dev-skill/issues/67) background runs and the answer inbox | #61 |

Slices 1–7 are Standard tier. Slice 8 is Deep: it starts a process that writes to a repository with
its permissions granted up front, and that decision is made inside it, before the first run.

## Two gaps found while writing this

**An epic with sub-issues is not recognised as decomposed.** `BoardBuilder.isDecomposedEpic` looks
for `- [ ] #N` checklist lines in the parent's body, mirroring `scripts/dev.py`'s `is_startable`.
`shared/pipeline.md` Phase 5 forbids checkbox slices and requires the `sub_issues` API instead, so a
parent filed the correct way is offered as startable on the board. Both readers need the sub-issue
list. Recorded in `PROJECT_MAP.md`; outside this epic.

**The `sub_issues` snippet in `shared/pipeline.md` Phase 5 cannot run as written.** It captures the
child with `gh issue create … --json id -q .id`, and `gh issue create` has no `--json` flag
(gh 2.92.0). The REST endpoint also wants the issue's **database id**, an integer, not the GraphQL
node id. What filed this epic's eight children:

```bash
NUM=${URL##*/}                                             # gh issue create prints the URL
ID=$(gh api "repos/$R/issues/$NUM" --jq .id)               # database id, an integer
gh api "repos/$R/issues/$PARENT/sub_issues" -F sub_issue_id="$ID"
```

## What this record does not decide

- **What a background run may do without asking.** Slice 8 owns it, and it is that slice's first
  question, not an implementation detail inside it.
- **An Auto mode that starts agents without a click.** ADR 0017 rejected auto-start; this epic does
  not revisit it.
- **A new visual language.** Slice 1 unifies controls on the existing palette and nothing more.
