# PROJECT_MAP

The pipeline's memory. Phase 1 loads it; Phase 4 skips its exploration fan-out when this file
already covers the area — so **an entry here that is wrong costs more than one that is missing.**

Maintained by `dev:insights` (Phase 5), and by Phase 10 of any `/dev` run.
Created 2026-09-10.

---

## TECH_STACK

**This repo is a skill family, not an application.** It ships prose that agents execute, plus a
small deterministic helper.

| | |
|---|---|
| Doors | 21 × `skills/<name>/SKILL.md`, plus the root `SKILL.md` |
| Shared contracts | `shared/entry.md` (workspace + write boundary), `shared/pipeline.md` (17 phases; 11–14 each have a door), `shared/pipeline-{web,ios,android,kmp}.md`, `shared/prod-secrets*.md` |
| Helper CLI | `scripts/dev.py` — **stdlib only**, Python 3.9-compatible. `state` · `board` · `run` · `doctor` · `project` · `ui` |
| Compliance | `scripts/compliance_auditor.py` — stdlib only |
| Hooks | `hooks/*.sh` — bash + `jq`, installed into `~/.claude/hooks/` |
| Tests | stdlib `unittest`, one file per script under `test-projects/<area>/test_*.py`, run as `PYTHONPATH=. python3 <file>` |
| CI | `.github/workflows/` — `line-budget.yml`, `tests.yml`. Each installed **on its own**; `ci/pr-gates.yml` is a template for *other* repos and is deliberately never installed here |
| Install | `install.sh` symlinks the clone into each CLI's skills dir as `dev`, and links `scripts/dev.py` as the `dev` command into `~/.local/bin` (or `~/bin`) when one is already on `PATH` |

**Paths inside the family are the INSTALL path** (`~/.claude/skills/dev/…`), never the clone path.
Absolute on purpose: doors run inside somebody else's repo, where a relative `shared/entry.md`
resolves to nothing.

**Agent CLIs with verified non-interactive invocations:** `claude -p`, `codex exec`. Antigravity
and Gemini are not supported — see ORPHANS.

## SYSTEM_FLOW

**One pipeline; every door is an entry into it at a different floor.**

```
bare /dev ─▶ dev:kanban (board) ─▶ name an issue ─▶ /dev #N
#N | free text ─▶ Phases 1-8 (reason) ─▶ 9-10 (build) ─▶ 11-13 (gates) ─▶ 14 (PR ▸ merge)
```

**Four gates stop for a human on purpose:** Phase 5 (discuss), 6 (architecture), 14 (merge),
16 (prod). Everything between them runs without asking.

**The stocking loop** — what puts work on the board:

```
dev:survey    defects + architectural drift ─┐
dev:ideation  perf / security / quality      ├─▶ docs/{survey,ideation}/<date>.md
                                             │
dev:roadmap   reads those + the repo's own recorded gaps + ORPHANS & PENDING below
              └─▶ milestone (= dev:kanban's QUEUE) + epic parents, PARENTS ONLY
                  └─▶ /dev #E ─▶ Phase 5 cuts slices ─▶ children
                      └─▶ dev:kanban 7.3 closes the epic, then the milestone
```

**Two axes on the board.** Columns come from `git`/`gh` and cannot be stale. The
`planning`/`coding`/`validation` phase comes from `.dev/<branch>.json` and **can** lie — so git wins
every disagreement, and no state file means no phase claim at all.

**This repo is SINGLE-STAGE.** No `staging` or `develop` on the remote, so `main` is both pre-prod
and prod: the Phase 14 merge *is* the production merge, Phase 16 is skipped, and its secrets
pre-flight moves up into Phase 14.

**`docs/` is tracked here** (changed 2026-09-10) so an ADR can be part of the diff that introduces
its decision. Skills still probe `git check-ignore -q docs/` per repo, because the answer differs.

## ORPHANS & PENDING

**Doors that exist but have never been exercised.** Each says so in its own `## Scar tissue`:

| | |
|---|---|
| `dev:kanban` Phase 7 | no write has been made through it — move, cancel and delete are unproven, as is the QUEUE column |
| `dev:ideation` | never run |
| `dev:roadmap` | never written a milestone |
| `dev:insights` | never run; this file is the first thing its Phase 5 would maintain |
| `dev:code-review` | never run — the `--quick` path, the spec-compliance table and the re-verification trigger are designed, not observed |

**Repo state that blocks parts of the design:**

- **No `epic` label** in this tracker, so `dev:kanban` 4.1's epic-progress logic cannot fire.
  `dev:roadmap` Phase 6 offers to create it; nothing creates it silently.
- **No `roadmap-declined` label**, so the declined-theme round trip is untested.
- **No `project` token scope**, so `dev project`'s live path — listing, field discovery and item edits — has never run. Its planning core is fixture-tested.
- **0 open issues, 0 milestones** — every board render so far has been of an empty tracker.

**Deferred deliberately:**

- **`LICENSE` and publishing** — repo is `PRIVATE` with `licenseInfo: null`. Public distribution
  needs both; without a licence nobody may use it even once public.
- **Whether the CLI may append `.dev/` to a *target* repo's `.gitignore`.** Currently it will not —
  `dev doctor` reports and prints the line to add. Writing into a repo the family does not own needs
  an explicit yes naming that repo.
- **Changelog generation** — deferred, not rejected.

**Known environment gaps:**

- **Antigravity CLI is not installed**, though `install.sh` links skills into its directory. The
  binary on `PATH` is a shim that reports the real CLI missing, so `dev run --agent antigravity` is
  refused rather than guessed. Gemini has no confirmed non-interactive invocation either.
