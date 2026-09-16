# Getting started

First install, first run, and the four situations you can be in.

[Commands](COMMANDS.md) · [Guide](GUIDE.md) · [Workflow](WORKFLOW.md)

---

## 1. Install

```bash
git clone https://github.com/hasansa007/dev-skill.git && dev-skill/install.sh
```

The installer symlinks the checkout into every agent CLI on the machine that uses the
`skills/<name>/SKILL.md` convention — Claude Code, Codex, Antigravity — and skips the ones that are
absent. It is safe to rerun.

**Installing is required, not optional.** Every path inside the family resolves through the install
root (`~/.claude/skills/dev/…`), which is what lets it run on any machine regardless of where you
cloned it. A clone that has never been installed has no root to resolve against.

Reload with `/reload-skills` in Claude Code, or restart your CLI.

### Check the environment before your first run

```bash
python3 ~/.claude/skills/dev/scripts/dev.py doctor
```

```
git repo        ok    /path/to/your/project
origin          ok    you/your-repo
base branch     ok    main
.dev/ ignored   WARN  NOT ignored — add '.dev/' to .gitignore
gh auth         ok    authenticated
python          ok    3.11.9
skill root      ok    /Users/you/.claude/skills/dev
```

| Row | If it warns |
|---|---|
| `git repo` | Run from inside the project you want to work on |
| `origin` | Add a remote — the family resolves `owner/repo` from it |
| `gh auth` | `gh auth login`. Without it the filing doors cannot reach GitHub; Dev Desk records work in `docs/backlog/` instead and files it later ([ADR 0027](../adr/0027-work-without-a-tracker-is-recorded-locally-and-promoted-on-request.md)) |
| `.dev/ ignored` | Add `.dev/` to `.gitignore`. **Nothing edits your `.gitignore` for you** — that would be this family writing into a repo it does not own |
| `skill root` | Run `install.sh` |

`python3` is optional. The CLI is a convenience; every door works without it.

---

## 2. First run — just type `/dev`

Bare `/dev` **orients**: it looks at the repo and offers the two or three doors that fit where you
actually are. It is read-only — it never cuts a branch and never starts work.

```
/dev
```

It will land you in one of four situations.

---

## 3. The four situations

### A · A brand-new project, nothing built yet

There is no tracker to read and nothing to read for findings, so start by describing the thing:

```text
/dev a CLI that converts CSV to Parquet with a --schema flag
```

The pipeline investigates, **stops at Phase 5 to agree the scope with you**, proposes architecture
alternatives when they genuinely differ, then builds, verifies and opens a PR. On a repo with no
`ARCHITECTURE.md`, it runs the architecture prompt for your detected stack first.

You approve four things and nothing else: what to build (5), which approach (6), when to merge (14),
and when to promote to production (16).

### B · An existing project you already know

Point it at the work:

```text
/dev #496                                   an issue number or URL
/dev the course list loses its scroll position
```

To capture something without building it now:

```text
/dev:create-bug   something is broken
/dev:create-issue a feature or task
/dev:create-epic  work spanning several branches
```

### C · An existing project you have inherited — bugs and findings

You do not know what is wrong yet. Two doors read the code and tell you, and **neither invents
anything** — every finding is verified against the code by two independent checkers before it can be
filed, and anything they cannot confirm is held in the report rather than filed.

```text
/dev:findings       what is WRONG — defects, and architectural drift between the patterns in use
/dev:ideation     what is WORTH DOING — performance, security, quality
```

Both write a dated report first — `docs/findings/<date>.md`, `docs/ideation/<date>.md` — and filing to
your tracker is a separate step you confirm. They walk you through the findings one at a time,
asking how *you* would handle each before showing you an answer.

**Run one, not both, unless you mean to.** They discover the same flows and fan out the same way, so
running both doubles the largest spend in the family. **Defects first** — what is broken changes
which improvements are worth making.

> An opportunity is filed as `enhancement`, never as a bug. Filing improvements as bugs makes the
> board lie about how broken the app is.

### D · You have findings — roadmap and improvements

A pile of issues is not a plan. `dev:roadmap` groups evidence into **themes**, writes each accepted
one as a GitHub **milestone** with **epic parents** underneath, and records the ones you decline so
they are never re-proposed.

```text
/dev:roadmap
```

It reads only what the repo already wrote down: your `findings` and `ideation` reports, the repo's own
`## Known gaps` / `## Known limits` sections, `PROJECT_MAP.md`'s `ORPHANS & PENDING`, and
unmilestoned issues. **If the repo records nothing, it says so and offers to generate evidence
first** rather than inventing a plan — an invented theme shapes months of work before anyone
notices it rested on nothing.

The **active milestone is the board's QUEUE**. That is the link between planning and doing.

Epics are filed as **parents only**. Slices are cut later, on the first `/dev #E`, once
investigation has actually happened — a wrong slice boundary is expensive, because each slice
becomes a branch, a PR and a promotion.

---

## 4. Insights, new features and brainstorming

```text
/dev:insights how does authentication work here?
/dev:insights                      ← with no question, it offers four to start from
```

It answers from evidence with `file:line` citations — never from memory of what a framework usually
does — and it **routes** rather than half-answering: a question another door owns goes to that door.

| You ask | It routes to |
|---|---|
| *draw the architecture* | `dev:arch` — an evidenced diagram, every node pinned to real code at a real commit |
| *what is broken* | `dev:findings` |
| *what could be better / is it secure* | `dev:ideation` |
| *what should we build next* | `dev:roadmap` |

Whatever is **durable** gets folded into `PROJECT_MAP.md` — the file the pipeline reads at Phase 1
and uses to skip re-exploring an area at Phase 4. That is the point of the door: a session ends and
the map does not.

**For a new feature you are still thinking through, just describe it** — `/dev <description>` stops
at Phase 5 to agree scope before any code exists, which is the brainstorming step. You do not need a
separate door for it.

---

## 5. Picking work up again

```text
/dev                 orients, and offers to resume anything in flight
/dev:kanban          the board: queued, in flight, in review, done
```

The board's columns are computed from `git` and `gh` every run, so they cannot go stale. If a run
checkpointed its phase into `.dev/`, the card also shows `planning` / `coding` / `validation` — but
**git wins any disagreement**, and no state file means no phase claim at all.
`.dev/` ignores itself, so nothing needs adding to your `.gitignore`.

### Seeing it in a window

Dev Desk, the Mac app in `apps/desk/`, shows the board and the roadmap. It also runs a shell and the
task's agent in each task's own folder. See [its README](../../apps/desk/README.md) and
[System model](SYSTEM-MODEL.md). To move a card between QUEUE and BACKLOG, or cancel one with a
reason, ask `/dev:kanban`: its Move and Cancel happen in the conversation. Ideation reports and the
project map have no screen yet — read them where they live, `docs/ideation/<date>.md` and
`PROJECT_MAP.md`.

### Seeing it as a real board on github.com

The `/dev:kanban` board is text. If you want a draggable one, `dev project` mirrors the same columns into a
GitHub Projects v2 board. **One-time setup:**

```bash
gh auth refresh -s project                       # 1. the scope; opens a browser
gh project create --owner "@me" --title "dev"    # 2. note the number it prints

# 3. give it options that match the columns — the DEFAULT board does not
gh project field-create <N> --owner "@me" --name "Status" --data-type SINGLE_SELECT \
  --single-select-options "Backlog,Queue,In Progress,PR Open,In Review,Done,Blocked"

gh project item-add <N> --owner "@me" --url <issue-url>   # 4. add issues
```

Then, from the repo:

```bash
python3 ~/.claude/skills/dev/scripts/dev.py project --number <N>          # dry run
python3 ~/.claude/skills/dev/scripts/dev.py project --number <N> --apply  # write
```

View it at `github.com/users/<you>/projects/<N>`.

**Step 3 is not optional busywork.** A new GitHub board ships with `Todo · In Progress · Done`.
Against those, `in_progress` and `done` map, and **`queue`, `pr_created`, `human_review` and
`deferred` have no matching option** — they are reported as unmappable and skipped, because
inventing an option would reshape a board this family does not own. `queue` deliberately does *not*
fall back to `Todo`: merging it with `backlog` would silently erase the queue distinction the
milestone design exists for.

**It only ever writes outward.** The columns are still computed from git each run, so the project
cannot become a second source of truth — drag a card and the next run moves it back. Without the
scope, the adapter says so and everything else works unchanged.

From the board you can move a card, cancel it with a reason, or delete it — delete asks you to
confirm against the printed `owner/repo#N` and refuses outright when a merged PR references the
issue or when an epic still has open children.

---

## 6. What it will always stop and ask you

Four gates, by design. Running "automatically" means it does not ask between mechanical steps — it
never means unattended.

| Gate | Why it cannot be automatic |
|---|---|
| Phase 5 — discuss | the go-ahead is yours by definition |
| Phase 6 — architecture | the approaches genuinely differ; you pick |
| Phase 14 — merge | the release decision, made once against the evidence |
| Phase 16 — production | never autonomous |

Plus anything destructive: deleting an issue, promoting to prod, or a rollback.

---

## 7. Where to look next

| | |
|---|---|
| [COMMANDS.md](COMMANDS.md) | every door, with worked examples |
| [GUIDE.md](GUIDE.md) | depth tiers, other CLIs, troubleshooting |
| [WORKFLOW.md](WORKFLOW.md) | all 17 phases and the decision points |
| [CONTRIBUTING.md](CONTRIBUTING.md) | how the family is built, and why the rules exist |
