# dev-skill

A personal development workflow for Claude Code: take a GitHub issue or a plain description from
"what should this do?" all the way to production, without skipping the gates that matter.

`/dev` is the full run. Five members are doors into the same pipeline at later phases, for when
the work already exists and only that stage is needed — plus `/dev:launch`, a tool the pipeline calls
to launch the app.

---

## Layout

```
~/Developer/skills/dev-skill/            ← this repo IS the `dev` plugin
├── .claude-plugin/plugin.json    name: dev · skills: ["./"]
├── SKILL.md                      name: dev — the full run; entry routing + family table
├── shared/
│   ├── entry.md                  workspace + pre-prod/prod branch resolution (read by all)
│   ├── pipeline.md               ALL the behavior — Phases 1 → 16
│   └── pipeline-{web,ios,android,kmp}.md   platform overlays on Phases 10/11/14
├── web/  mobile/                 architecture + feature prompts (conditional)
└── skills/
    ├── verify/SKILL.md           → /dev:verify     Phase 11
    ├── docs/SKILL.md             → /dev:docs       Phase 12
    ├── pre-prod/SKILL.md         → /dev:pre-prod   Phase 14
    ├── review/SKILL.md           → /dev:review     Phase 15  ↺
    ├── prod/SKILL.md             → /dev:prod       Phase 16
    └── launch/SKILL.md           → /dev:launch     no phase — a TOOL
```

Every phase skill reads `shared/pipeline.md`. **None of them copies it.** Behavior changes go in
`shared/`, once.

### `dev:launch` — a member of a different kind

The other five are **phases**; `dev:launch` is a **tool**. It maps to no phase number and reads none
of the pipeline — it detects the project and launches it (`/dev:launch ios sim`,
`/dev:launch android emulator`, `/dev:launch web`). Phases 4 and 11 call it for mobile targets, and
it is equally useful alone on a throwaway prototype.

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
| 1 | Context Load — `PROJECT_MAP.md`, `ARCHITECTURE.md`, existing spec | |
| 2 | Tech Stack & Discovery — stack detect, conditional explorer fan-out | |
| 3 | Git Branch Naming | |
| 4 | Investigation — evidence ladder, reproduce before theorising | |
| **5** | **Discuss Before Building** — plain-language, explicit go-ahead; conditional UI discussion | |
| 6 | Architecture Alternatives — 3 forced-different biases, losers recorded | |
| 7 | Plan Output — written to `specs/` | |
| 8 | Task Breakdown | |
| 9 | Implement — surgical protocol | |
| 10 | Pre-PR Quality Checks | |
| **11** | **Verification Gate** — agent-run, evidence per row, teardown | `dev:verify` |
| **12** | **Docs & Decisions Gate** — ADRs before merge | `dev:docs` |
| 13 | Code Review Gate — `/code-review`, + `security-review` on Deep | |
| **14** | **PR → Review → Merge → Pre Prod** | `dev:pre-prod` |
| **15** | **Review Cycle** — a LOOP back into Phase 14, never forward | `dev:review` |
| **16** | **Prod Promotion** — migrations first, never autonomous | `dev:prod` |
| — | *(no phase)* — build & launch the app | `dev:launch` |

### Why only five phase members

Phases 1–8 pass **reasoning** between each other, and reasoning lives only in the conversation that
produced it — there is no artifact to hand a fresh session. From Phase 11 on, every phase takes
something durable (a branch, a diff, a PR number), which is exactly what makes it independently
invocable.

Phase 13 is deliberately absent: it is twenty lines that mostly say "run `/code-review`", so run
`/code-review`.

---

## Design rules

- **Right-size first.** Every task is triaged Light / Standard / Deep before starting, and the tier
  is stated. Light is the default. *A slow pipeline that gets skipped protects nothing.*
- **Pre prod ≠ prod.** Phase 14 reaches pre prod only. Promotion is Phase 16, needs its own
  confirmation, and never happens autonomously.
- **Evidence before assertions.** No "should work" — run it, read the output, paste what it printed.
- **Docs before merge.** A price, limit, decision or env var that changed without its ADR is an
  unfinished diff.
- **One pipeline, many doors.** Members never copy `shared/pipeline.md`; they point into it.

---

## Editing

Edit here — `~/.claude/skills/dev` symlinks to this repo. After changing anything under
`shared/`, every phase skill picks it up with no further action.
