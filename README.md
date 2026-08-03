# dev-skill

A personal development workflow for Claude Code: take a GitHub issue or a plain description from
"what should this do?" all the way to production, without skipping the gates that matter.

`/dev` is the full run. Five siblings are doors into the same pipeline at later phases, for when
the work already exists and only that stage is needed.

---

## Layout

```
~/Developer/skills/dev-skill/            ← this repo; its root IS the `dev` skill
├── SKILL.md                      name: dev — entry routing + the family table
├── shared/
│   ├── entry.md                  workspace + pre-prod/prod branch resolution (read by all six)
│   ├── pipeline.md               ALL the behavior — Phases 0 → 10.5
│   └── pipeline-{web,ios,android,kmp}.md   platform overlays on Phases 8/9/10
├── web/  mobile/                 architecture + feature prompts (conditional)
│
├── dev-verify/SKILL.md           → Phase 9
├── dev-docs/SKILL.md             → Phase 9.4
├── dev-pre-prod/SKILL.md         → Phase 10
├── dev-review/SKILL.md           → Phase 10.2  ↺
├── dev-prod/SKILL.md             → Phase 10.5
│
└── run/SKILL.md                  a TOOL, not a phase — build & launch iOS/Android/web
```

Every `dev-*` skill reads `shared/pipeline.md`. **None of them copies it.** Behavior changes go in
`shared/`, once.

### Why `run` is here

`run` maps to no phase and reads none of the pipeline — it builds and launches an app, and it is
just as useful on its own for a throwaway prototype (`/run ios sim`, `/run android emulator`,
`/run` on an HTML directory). It keeps its plain name for exactly that reason.

It ships here because it is the pipeline's only **personal-skill** dependency. Phases 4 and 9 call
it to build and launch mobile targets, and everything else the pipeline reaches for —
`superpowers:*`, `/code-review`, `security-review`, `frontend-design`, `supabase`,
`feature-dev:*` — is a plugin that installs anywhere. `run` is the one that would simply be
missing after a clone, and mobile verification would fail with nothing to explain why.

---

## Installing

Skill discovery is **flat**: Claude Code looks for `~/.claude/skills/<name>/SKILL.md`, exactly one
level down, and a directory without a `SKILL.md` at its root registers nothing — silently, with no
warning. The family is nested here for authoring, and each entry is symlinked out individually so
discovery still sees a flat layout:

```bash
ln -sfn ~/Developer/skills/dev-skill         ~/.claude/skills/dev
for s in dev-verify dev-docs dev-pre-prod dev-review dev-prod run; do
  ln -sfn ~/Developer/skills/dev-skill/"$s"  ~/.claude/skills/"$s"
done
```

Discovery follows the **symlink** name, not the real directory name — which is why the repo can be
called `dev-skill` while the skill registers as `dev`.

**Verify against the loaded skill list, not the filesystem.** A `SKILL.md` existing on disk proves
nothing about it being registered. New skills usually appear on the next session start.

---

## The pipeline

| Phase | | Sibling |
|---|---|---|
| 0 | Context Load — `PROJECT_MAP.md`, `ARCHITECTURE.md`, existing spec | |
| 2 | Tech Stack & Discovery — stack detect, conditional explorer fan-out | |
| 3 | Git Branch Naming | |
| 4 | Investigation — evidence ladder, reproduce before theorising | |
| **4.2** | **Discuss Before Building** — plain-language, explicit go-ahead; conditional UI discussion | |
| 4.5 | Architecture Alternatives — 3 forced-different biases, losers recorded | |
| 5 | Plan Output — written to `specs/` | |
| 6 | Task Breakdown | |
| 7 | Implement — surgical protocol | |
| 8 | Pre-PR Quality Checks | |
| **9** | **Verification Gate** — agent-run, evidence per row, teardown | `dev-verify` |
| **9.4** | **Docs & Decisions Gate** — ADRs before merge | `dev-docs` |
| 9.5 | Code Review Gate — `/code-review`, + `security-review` on Deep | |
| **10** | **PR → Review → Merge → Pre Prod** | `dev-pre-prod` |
| **10.2** | **Review Cycle** — a LOOP back into Phase 10, never forward | `dev-review` |
| **10.5** | **Prod Promotion** — migrations first, never autonomous | `dev-prod` |

### Why only five siblings

Phases 0–8 pass **reasoning** between each other, and reasoning lives only in the conversation that
produced it — there is no artifact to hand a fresh session. From Phase 9 on, every phase takes
something durable (a branch, a diff, a PR number), which is exactly what makes it independently
invocable.

Phase 9.5 is deliberately absent: it is twenty lines that mostly say "run `/code-review`", so run
`/code-review`.

---

## Design rules

- **Right-size first.** Every task is triaged Light / Standard / Deep before starting, and the tier
  is stated. Light is the default. *A slow pipeline that gets skipped protects nothing.*
- **Pre prod ≠ prod.** Phase 10 reaches pre prod only. Promotion is Phase 10.5, needs its own
  confirmation, and never happens autonomously.
- **Evidence before assertions.** No "should work" — run it, read the output, paste what it printed.
- **Docs before merge.** A price, limit, decision or env var that changed without its ADR is an
  unfinished diff.
- **Prefix siblings, never nest them for discovery.** `dev-prod`, not `dev/prod`.

---

## Editing

Edit here — `~/.claude/skills/*` are symlinks to these files. After changing anything under
`shared/`, all six skills pick it up with no further action.
