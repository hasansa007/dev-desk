# dev-skill

A personal development workflow for Claude Code: take a GitHub issue or a plain description from
"what should this do?" all the way to production, without skipping the gates that matter.

`/dev` is the full run. Five siblings are doors into the same pipeline at later phases, for when
the work already exists and only that stage is needed — plus `dev-run`, a tool the pipeline calls
to launch the app.

---

## Layout

```
~/Developer/skills/dev-skill/            ← this repo; its root IS the `dev` skill
├── SKILL.md                      name: dev — entry routing + the family table
├── shared/
│   ├── entry.md                  workspace + pre-prod/prod branch resolution (read by all six)
│   ├── pipeline.md               ALL the behavior — Phases 1 → 16
│   └── pipeline-{web,ios,android,kmp}.md   platform overlays on Phases 10/11/14
├── web/  mobile/                 architecture + feature prompts (conditional)
│
├── dev-verify/SKILL.md           → Phase 11
├── dev-docs/SKILL.md             → Phase 12
├── dev-pre-prod/SKILL.md         → Phase 14
├── dev-review/SKILL.md           → Phase 15  ↺
├── dev-prod/SKILL.md             → Phase 16
└── dev-run/SKILL.md              → no phase — a TOOL: build & launch iOS/Android/web
```

Every phase skill reads `shared/pipeline.md`. **None of them copies it.** Behavior changes go in
`shared/`, once.

### `dev-run` — a member of a different kind

The other five are **phases**; `dev-run` is a **tool**. It maps to no phase number and reads none
of the pipeline — it detects the project and launches it (`/dev-run ios sim`,
`/dev-run android emulator`, `/dev-run web`). Phases 4 and 11 call it for mobile targets, and it is
equally useful alone on a throwaway prototype.

It belongs in this repo because it is the pipeline's only **personal-skill** dependency. Everything
else the pipeline reaches for — `superpowers:*`, `/code-review`, `security-review`,
`frontend-design`, `supabase`, `feature-dev:*` — is a plugin that installs anywhere. `dev-run` is
the one that would simply be missing after a clone, taking mobile verification down with it and
leaving nothing to explain why.

---

## Installing

Skill discovery is **flat**: Claude Code looks for `~/.claude/skills/<name>/SKILL.md`, exactly one
level down, and a directory without a `SKILL.md` at its root registers nothing — silently, with no
warning. The family is nested here for authoring, and each entry is symlinked out individually so
discovery still sees a flat layout:

```bash
ln -sfn ~/Developer/skills/dev-skill         ~/.claude/skills/dev
for s in dev-verify dev-docs dev-pre-prod dev-review dev-prod dev-run; do
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
| **11** | **Verification Gate** — agent-run, evidence per row, teardown | `dev-verify` |
| **12** | **Docs & Decisions Gate** — ADRs before merge | `dev-docs` |
| 13 | Code Review Gate — `/code-review`, + `security-review` on Deep | |
| **14** | **PR → Review → Merge → Pre Prod** | `dev-pre-prod` |
| **15** | **Review Cycle** — a LOOP back into Phase 14, never forward | `dev-review` |
| **16** | **Prod Promotion** — migrations first, never autonomous | `dev-prod` |
| — | *(no phase)* — build & launch the app | `dev-run` |

### Why only five siblings

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
- **Prefix siblings, never nest them for discovery.** `dev-prod`, not `dev/prod`.

---

## Editing

Edit here — `~/.claude/skills/*` are symlinks to these files. After changing anything under
`shared/`, every phase skill picks it up with no further action.
