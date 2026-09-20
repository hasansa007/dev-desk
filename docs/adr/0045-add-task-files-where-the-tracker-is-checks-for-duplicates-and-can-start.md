# 0045 — Add Task files where the tracker is, checks for duplicates first, and can start the work

Status:  Accepted
Date:    2026-09-19
Commit:  (this commit)
Amends:  ADR 0027 — *"filing writes one markdown file per item to `docs/backlog/`"* now holds only when there
is no reachable tracker, for Add Task as for every other door. `AddTaskSheet`'s *"even when the project has a
tracker"* is reversed.

## Context

Add Task took a title and notes and wrote a `docs/backlog/` file — always, tracker or not — and did nothing
else. A task typed there had no number, so it could not name a `gh-<N>-` branch; no one looked for the issue
it might already be; and starting it was a second, separate act.

The developer's actual way of adding work was the chat: describe it in bullets and a few sentences, have it
checked against what is already tracked, filed, and started on its own branch. They asked for that to be the
feature: *"the add task should have its own steps so that it will work in its separate new branch with the
given bullets and job description"*, and — on where it goes — *"check if github repo is setup, what about
documented that locally?"*, with *both* an Add and an Add-and-start.

The same week showed what filing without a duplicate check costs: a roadmap run and a findings run filed
23 issues into one tracker, 4 of them restating open issues (studyhub-deploy, 2026-09-16/17; see the
`dev:roadmap` scar tissue). `dev:create-issue`, `create-bug` and `create-epic` search for nothing either.

## Decision

**Add Task has four steps, the same with or without GitHub; only the destination changes.**

1. **Input: title, bullets, description.** The bullets are the task's `## Done when` — the list `/dev` reads
   as its acceptance criteria and `dev:board` 7.3 evaluates. The description is the prose around them.
2. **Destination, resolved when the sheet opens, and shown before anything is typed.** ADR 0027's three
   "no GitHub" situations plus one:

   | Check | Fails → |
   |---|---|
   | `git remote get-url origin` | no remote → local |
   | `gh auth status` | signed out → local, the sheet says *sign in to file on GitHub* |
   | `gh repo view --json hasIssuesEnabled` — gh can see it | unreachable → local |
   | …and Issues are enabled | disabled → local |

   The sheet prints the result — **→ GitHub issue in owner/repo** or **→ docs/backlog (signed out)**. A failed
   check never renders as an empty tracker (`dev:board` Phase 3's rule).
3. **Duplicate check, before the confirm button means anything.** As the title settles, the sheet runs a
   plain search — `gh issue list --state open --search "<title words> in:title,body"` with a tracker,
   `docs/backlog/*.md` titles and bodies without one — and lists what it found under the fields:
   *"#700 · آية/حديث citations are model-asserted — Open it instead"*. The search only **proposes**. The
   judgment — same fix site means the same task, same area means related — is the developer's here, and the
   agent's under `shared/duplicates.md` when a door files.
4. **File, then optionally start.**

   | | **Add** | **Add & start** |
   |---|---|---|
   | tracker | `gh issue create` with the three fields and an optional milestone from the open ones — no agent run | the same, then Start on `#N` |
   | none | a `docs/backlog/` file, as ADR 0027 | the same, then Start on the entry |

   **Start is the existing task run**, unchanged: a fresh worktree detached at origin's base
   (`FreshBaseWorktree`), where `/dev` cuts the branch at the pipeline's first write — immediately for a bug
   (the reproduction is the first write), after Phase 5's go-ahead for a feature. **Add & start never cuts
   the branch itself.** Naming a feature's branch before the discussion frames *whether* as *yes*
   (`shared/pipeline/04-phase-03-branch-naming.md`).

**A local entry records its branch.** When `/dev` cuts a branch for a `docs/backlog/` entry, it writes
`branch: feature/<slug>` into the entry's header — the one link a local card has to git, which today has
none (`LocalBacklog`: *"a local card has no branch"*). Promoting it later adds `issue: #N`; the branch keeps
its name, because renaming a branch that has work on it breaks every worktree and remote that tracks it.

**Add files no labels.** Priority, impact and complexity are judgments, and Add runs no agent. An unlabelled
issue is honest; a guessed `P1` ranks the board wrong. `/dev`'s Phase 0 or `dev:board` labels it.

## Alternatives rejected

- **Keep Add local-only and promote from the card** (the behaviour this amends). Every Add & start would then
  file twice — once to disk, once to GitHub — and the branch would be named before the number existed.
- **File through `dev:create-issue`.** It is an agent run: seconds to minutes, per task, for a title the
  developer already wrote. Add is a form; the agent's value (template, labels) is the part Add deliberately
  leaves to `/dev`.
- **Let the duplicate search decide.** A keyword match cannot tell the same fix site from the same word; an
  automatic "this is #N" would hide real, distinct work — the wrong-merge cost `dev:findings` Phase 2 names.
- **Cut the branch in Add & start.** Contradicts Phase 3's timing for features, and a card whose branch
  exists before its approach was approved reads as started when it was only described.
- **Always create a worktree on Add.** A task that is only recorded should cost nothing; the worktree belongs
  to the run.

## Consequences

- With a tracker, a typed task is a real issue at once: `gh-<N>-` branches, `Closes #N`, the milestone as
  the Queue column all work for it without a promotion step.
- Without one, nothing changes from ADR 0027 except the `branch:` line.
- The duplicate check is a proposal the developer can ignore. A duplicate typed on purpose is still filed.
- `shared/duplicates.md` is the one statement of the matching rule for every filing door —
  `dev:findings`, `dev:roadmap`, `dev:create-issue`, `create-bug`, `create-epic` — so the copies do not drift.
