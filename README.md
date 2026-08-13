# dev-skill

A personal development workflow for Claude Code: take a GitHub issue or a plain description from
"what should this do?" all the way to production, without skipping the gates that matter.

`/dev` is the full run. Three `/dev:create-*` members file the work item before it starts; five more
are doors into the same pipeline at later phases, for when the work already exists and only that
stage is needed — plus `/dev:launch`, a tool the pipeline calls to launch the app.

> **New here? Read [GUIDE.md](GUIDE.md).** Part 1 is what to type and what it will ask you;
> Part 2 is how to change it and what not to. This README is the repo's own structure.

---

## Layout

```
~/Developer/skills/dev-skill/            ← this repo IS the `dev` plugin
├── .claude-plugin/plugin.json    name: dev · skills: ["./"]
├── SKILL.md                      name: dev — the full run; entry routing + family table
├── shared/
│   ├── entry.md                  workspace + pre-prod/prod branch resolution (read by all)
│   ├── pipeline.md               ALL the behavior — Phases 0 → 16
│   ├── pipeline-{web,ios,android,kmp}.md   platform overlays on Phases 10/11/14
│   ├── prod-secrets.md           the releasing merge's secrets gate — Phase 16, or 14 if single-branch
│   └── prod-secrets-apple.md     Apple acquisition steps — read only on a missing secret
├── ci/pr-gates.yml               NOT installed — a PR-body check, kept beside the rules it enforces
├── hooks/                        4 Claude Code hooks — Phases 1, 3, 11(teardown), 12, 14, 16
│   └── README.md                 what a hook can enforce, install blocks, the fired.log query
├── web/  mobile/                 architecture + feature prompts (conditional)
└── skills/
    ├── create-bug/SKILL.md       → /dev:create-bug    Phase 0
    ├── create-issue/SKILL.md     → /dev:create-issue  Phase 0
    ├── create-epic/SKILL.md      → /dev:create-epic   Phase 0
    ├── verify/SKILL.md           → /dev:verify     Phase 11
    ├── docs/SKILL.md             → /dev:docs       Phase 12
    ├── pre-prod/SKILL.md         → /dev:pre-prod   Phase 14
    ├── review/SKILL.md           → /dev:review     Phase 15  ↺
    ├── prod/SKILL.md             → /dev:prod       Phase 16
    ├── launch/SKILL.md           → /dev:launch     no phase — a TOOL
    ├── launch-kill/SKILL.md      → /dev:launch-kill  no phase — `launch` inverted
    ├── shots/SKILL.md            → /dev:shots      no phase — capture, iOS/Android/web
    └── issues/SKILL.md           → /dev:issues     no phase — the tracker view; bare /dev routes here
```

Every phase skill reads `shared/pipeline.md`. **None of them copies it.** Behavior changes go in
`shared/`, once.

### `dev:launch`, `dev:launch-kill` and `dev:shots` — members of a different kind

The other eight are **phases** (three filing, five staged); these three are **tools**. They map to no
phase number and read none of the pipeline — one detects the project and launches it
(`/dev:launch ios sim`, `/dev:launch android emulator`, `/dev:launch web`), one stops what it
started, one captures screens from it. Phases 4 and 11 call `launch` for mobile targets, and it is
equally useful alone on a throwaway prototype.

They are three verbs on one noun — start it, stop it, shoot it — and the latter two are **doors into
`launch`**, not copies of it. `shots` reads `launch` 2.1–2.6 for discovery and Phase 3 to get the app
up, which is how it inherits the rule that matters most for a capture: *if a server is already
listening, reuse it and start nothing.* Restarting the developer's app to photograph it is the
failure this design forecloses.

Phase 11 should delegate its evidence capture to `dev:shots` rather than restate the commands.
That edit is **not** made: `shared/pipeline.md` sits at 938 of its 950-line budget, and `GUIDE.md`
requires an addition there to name its deletion. The delegation is documented here and in the tool
until a deletion pays for it.

`launch-kill` is a **door into `launch`**, exactly as the phase members are doors into
`shared/pipeline.md`: it points at `launch` 2.1 / 2.5.3 / 2.6.2 / 2.6.3 for project root, ports and
the launch script, and restates none of it. Two copies of port resolution drift, and a drift here
kills the wrong port. Discovery bugs get fixed in `launch`, once — which is how `2.1`'s worktree bug
(`[ -d "$dir/.git" ]` is false when `.git` is a file) got fixed for both at the same time.

What it adds is the **boundary**. It proves a process belongs to *this worktree* by its cwd before
touching it, and kills the tree from the top so the launch script's traps fire. Killing the port
holder alone orphans every background process the script started: three `worker.py` processes were
found leaked that way on 2026-08-05, one per dev session, all still polling the same local queue.
The line `launch` used to print — `lsof -ti:<PORT> | xargs kill` — is that bug.

The name is deliberately **not** `run`: Claude Code ships a built-in `run` skill, and a member
called `dev:run` reads as a namespaced flavour of it rather than a different tool.

It belongs in this repo because it is the pipeline's only **personal-skill** dependency. Everything
else the pipeline reaches for — `superpowers:*`, `/code-review`, `security-review`,
`frontend-design`, `supabase`, `feature-dev:*` — is a plugin that installs anywhere. `dev:launch` is
the one that would simply be missing after a clone, taking mobile verification down with it and
leaving nothing to explain why.

---

## Installing

This is a **skills-dir plugin**: a plugin living directly in `~/.claude/skills/`, with no
marketplace and no `~/.claude/plugins/cache/`. One symlink installs the whole family.

```bash
ln -sfn ~/Developer/skills/dev-skill  ~/.claude/skills/dev
```

It auto-loads next session as `dev@skills-dir`; `/reload-plugins` loads it immediately. Members
then invoke as `/dev:verify`, `/dev:launch`, and so on — **the namespace comes from
`.claude-plugin/plugin.json`, not from the directory names**, which is why the members are called
`verify` and `launch` rather than `dev-verify` and `dev-launch`.

Without that manifest the same tree registers **nothing**: plain skill discovery is flat
(`~/.claude/skills/<name>/SKILL.md`, exactly one level) and would never look inside `skills/`.
The manifest is the single file that turns a nested directory into a namespace.

**Verify against the loaded skill list, not the filesystem.** A `SKILL.md` on disk proves nothing
about registration — check `claude plugin list` and the session's skill list.

---

## The pipeline

| Phase | | Sibling |
|---|---|---|
| **0** | **Filing** — draft, resolve real labels, create. Standalone only; a `/dev` run never reaches it | `dev:create-*` |
| 1 | Context Load — `PROJECT_MAP.md`, `ARCHITECTURE.md`, existing spec | |
| 2 | Tech Stack & Discovery — stack detect, conditional explorer fan-out | |
| 3 | Git Branch Naming | |
| 4 | Investigation — evidence ladder, reproduce before theorising | |
| **5** | **Discuss Before Building** — plain-language, explicit go-ahead; conditional UI discussion **and epic decomposition** | |
| 6 | Architecture Alternatives — 3 forced-different biases, losers recorded | |
| 7 | Plan Output — written to `specs/` | |
| 8 | Task Breakdown | |
| 9 | Implement — surgical protocol | |
| 10 | Pre-PR Quality Checks | |
| **11** | **Verification Gate** — agent-run, evidence per row, teardown → chains to 12 | `dev:verify` |
| **12** | **Docs & Decisions Gate** — ADRs before merge | `dev:docs` |
| 13 | Code Review Gate — `/code-review`, + `security-review` on Deep | |
| **14** | **PR → Review → Merge → Pre Prod** | `dev:pre-prod` |
| **15** | **Review Cycle** — a LOOP back into Phase 14, never forward | `dev:review` |
| **16** | **Prod Promotion** — secrets pre-flight, then migrations, never autonomous | `dev:prod` |
| — | *(no phase)* — build & launch the app | `dev:launch` |
| — | *(no phase)* — stop this project's servers | `dev:launch-kill` |
| — | *(no phase)* — capture screens from the running app | `dev:shots` |
| — | *(no phase)* — the tracker: current, next, stats | `dev:issues` |

### Why these phase members and not others

Phases 1–8 pass **reasoning** between each other, and reasoning lives only in the conversation that
produced it — there is no artifact to hand a fresh session. From Phase 11 on, every phase takes
something durable (a branch, a diff, a PR number), which is exactly what makes it independently
invocable.

Phase 0 qualifies from the other side of that seam: it runs *before* any reasoning exists, takes
only a description, and produces an issue number. Nothing to hand over, because nothing has been
worked out yet.

Phase 13 is deliberately absent: it is twenty lines that mostly say "run `/code-review`", so run
`/code-review`.

---

## Design rules

- **Right-size first.** Every task is triaged Light / Standard / Deep before starting, and the tier
  is stated. Light is the default. *A slow pipeline that gets skipped protects nothing.*
- **It runs straight through; there is no mode question.** Phases 5, 6, 14 and 16 stop regardless —
  those are decisions, not steps. Running automatically skips the ceremony, never the judgment.
- **Never end silently.** Wherever a run stops — the last phase, a gate, a blocker — it names the
  next phase and asks. Entering at Phase 12 never leaves you guessing what followed it.
- **Skipping leaves a trace.** Every PR carries `## PIPELINE`: tier, what ran, what was skipped and
  **why**, and what each gate caught. It is also the only record of whether a rule ever earned its
  place, which is what makes rules removable.
- **Pre prod ≠ prod.** Phase 14 reaches pre prod only. Promotion is Phase 16, needs its own
  confirmation, and never happens autonomously.
- **Evidence before assertions.** No "should work" — run it, read the output, paste what it printed.
- **Docs before merge.** A price, limit, decision or env var that changed without its ADR is an
  unfinished diff.
- **One pipeline, many doors.** Members never copy `shared/pipeline.md`; they point into it.
- **The resolved repo is a write boundary.** Name the target `owner/repo` and branch *before* acting,
  never write outside the resolved repo without an explicit yes naming it, and always cut a branch so
  there is something reviewable before anything lands. Defined once in `shared/entry.md`.
- **A result is not a claim.** Say what a command's output *means* and what bounds it — scope
  limiters, values carrying two meanings, a substituted predicate — not just where you looked.
  `dev:launch` 2.0 rule 2 catches the empty result; this catches the plausible non-empty one that
  answered a narrower question. Defined once in `shared/entry.md`.

---

## Editing

Edit here — `~/.claude/skills/dev` symlinks to this repo. After changing anything under
`shared/`, every phase skill picks it up with no further action.
