# Development workflow

The pipeline takes a task through investigation, planning, implementation, verification, documentation, review, and release. Its authoritative procedures live in [`shared/pipeline.md`](../../shared/pipeline.md).

## Phases

| Phase | Stage | Main responsibility |
| --- | --- | --- |
| 0 | Filing | Draft an issue, resolve labels, and file it. Standalone only. |
| 1 | Context | Read project maps, architecture, and existing specifications. |
| 2 | Discovery | Identify the stack and perform relevant discovery. |
| 3 | Branch naming | Resolve the branch name; create the branch at the first write. |
| 4 | Investigation | Follow the evidence ladder; reproduce bugs before theorising. |
| 5 | Discussion | Agree on scope and approach before building; split epics when needed. |
| 6 | Architecture | Evaluate distinct alternatives when applicable and record rejected options. |
| 7 | Plan | Write the implementation plan to `specs/`. |
| 8 | Tasks | Break the plan into actionable work. |
| 9 | Implementation | Make focused changes using the surgical implementation protocol. |
| 10 | Quality checks | Run the project's pre-PR checks. |
| 11 | Verification | Collect evidence per checklist item and clean up resources started for verification. |
| 12 | Documentation | Check documentation and architecture decisions against the change. |
| 13 | Code review | Verified findings, spec compliance, and a security pass when the **diff** touches money, auth, migrations, uploads or untrusted input — the trigger is the diff, not the tier. |
| 14 | PR and merge | Prepare the PR, satisfy review gates, and obtain merge approval. |
| 15 | Review cycle | Address feedback and return to Phase 14. |
| 16 | Production | Check secrets and migrations before an approved promotion. |

Phase 0 is invoked through filing commands, outside a full `/dev` run. Issues filed by `dev:survey` or `dev:ideation` supply earlier evidence, but Phase 4 still performs investigation layers 3–5.

## Decision points

The workflow asks before building, when selecting architecture, before merging, and before promoting to production. Other stages normally continue without repeated confirmation.

Standalone verification automatically continues into documentation checks. It does not automatically merge or promote the change.

## What carries across sessions

Planning and implementation depend on the active conversation's reasoning. Later entry points work from persistent artifacts: a branch, diff, or PR. This is why you can invoke verification or review independently.

Phase 15 loops back to Phase 14. It does not advance directly to production.

## Evidence and documentation

- Verification records what was checked, the observed evidence, and any limits.
- The PR's `## PIPELINE` section records completed and skipped phases, including reasons.
- The PR's `## DOCS` section records documentation and decision checks.
- Changed decisions and affected documentation must be accurate before merge.
- Teardown must preserve resources the agent did not start.

## Release environments

[`shared/entry.md`](../../shared/entry.md) resolves repository boundaries and branches. In a two-stage repository, Phase 14 reaches pre-production and Phase 16 promotes to production. When both resolve to the same branch, Phase 16 skips a separate promotion.

## Known gaps

These notes preserve the previous guide's dated validation history. They describe the state at the dates recorded, rather than results from this documentation change.

<details>
<summary>Validation history and recovery considerations</summary>

Honest, as of 2026-08-04:

- **Epic support is new and unexercised (2026-08-04).** The design: file the parent with
  `/dev:create-epic`, split it at Phase 5 into real sub-issues, run `/dev #child` per slice — the
  pipeline stays task-shaped and the sub-issue list is the queue. Never run end to end.
- **Rollback workflow implemented (`/dev:rollback`).** Answers *"prod is broken, now what."*
  Implements the 2026-08-08 design separating code from schema: Phase 16 applies schema BEFORE code,
  so a rollback reverses code-then-schema, and only the first half reverses:

  | Case | Reversible | How |
  |---|---|---|
  | **Code-only promotion** — no migration in the diff | **yes, always** | revert the promotion merge on the prod branch. Any platform that deploys on merge redeploys on revert — no platform rollback feature is involved |
  | **Additive migration** — new nullable column, new table, new index | **yes**, code only | old code ignores the new schema, so leave it forward. Must be *identified*, never assumed |
  | **Destructive migration** — drop, rename, narrowing type, overwriting backfill | **no** | the data is already gone. What exists is point-in-time **restore**, which also reverts every unrelated write since. That is not a rollback, and it is never autonomous |

  The `/dev:rollback` door's first job is **classification, not execution**: read the promotion
  diff, classify each migration, and refuse the third case while naming what a restore would cost.
  Phase 16 already computes the input it needs — `git log <prod>..<pre-prod>` — and already requires
  migrations applied before the merge, which is exactly what makes the three cases separable.

  **The trap it avoids:** reverting the promotion merge on the prod branch does **not**
  revert pre prod, so the next promotion re-introduces the bad commit. `/dev:rollback` (`skills/rollback/SKILL.md`)
  reverts on **both** branches via dual-branch synchronization and pauses for explicit human approval before touching any branch.
- **New-project path barely tested.** The `ARCHITECTURE.md`-absent branch and both MASTER_PROMPTs
  have never run.
- **The gate log has a mechanism but no data.** `## PIPELINE`'s `Gates:` line was added 2026-08-04
  to fix this; until ~20 PRs carry it, pruning is still guesswork. This buys visibility, not
  enforcement — see the self-reporting limit in the last bullet.
- **`dev:pre-prod`, `dev:review`, `dev:prod` — and where they CAN be exercised.** As of 2026-08-05
  `dev:pre-prod` has run end to end once, on a two-stage repo: branch → PR → gates → merge to the
  pre-prod branch. `dev:review` and the `pre-prod → prod` half of `dev:prod` still never have.
  **They cannot be proven in this repo, by construction, and running them here is not a gap to
  close — it is a category error.** This repo is single-stage: `entry.md` resolves pre prod and prod
  both to `main`, so Phase 16 correctly skips itself, and there is no feature branch to PR because
  commits land on `main` directly (which is also why `branch-guard.sh` is deliberately not installed
  here). Proving them needs a repo with a real `staging` → `prod` split **and** something worth
  promoting. Until that happens the honest status is *unexercised*, not *broken* — and an
  `/dev:prod` here reporting "single-stage, nothing to promote" is the skill working, not failing.
- **Phase Compliance Auditor implemented (`/dev:audit`).** Solves the self-reporting gap where an agent
  claims phases in `## PIPELINE` but silently bypasses them or leaves skips unrecorded. Mechanically cross-references
  claimed phases against tool-call and repository evidence, detects hidden skips and bare skips, and appends
  a `## COMPLIANCE` audit report to the PR body.
- **Enforcement is part mechanical as of 2026-08-05.** ~5 of 17 phases produce a durable artifact;
  the rest depend on the reader complying, and `## PIPELINE` / `## DOCS` are self-reported — a run
  that skips a phase *and* omits it from `Skipped:` is now caught mechanically by `/dev:audit`. Four hooks in `hooks/` now
  make Phases 1, 3, 12, 14 and 16 — plus Phase 11's teardown rule, though not its checklist —
  mechanical **where they touch a tool call**. That qualifier is the whole limit: a hook checks
  presence of state at a tool boundary, so Phases 4–8 are unreachable by construction, on the same
  seam that gives them no `dev-*` door. Pipe-tested only, **zero real runs**; `hooks/README.md`
  separates the three dated fixes from the undated design. `hooks/pr-gates.yml`'s `required-sections` job stays
  **uninstalled** — `hooks/pr-gates.sh` supersedes it locally, and it would fail every PR here since
  these are not `/dev` runs. Its `line-budget` job **is** installed, at
  `.github/workflows/line-budget.yml` (2026-09-06): it reads three files and compares three numbers,
  so none of that reasoning applies to it. That is the repo's only mechanical PR check.

</details>

[Command reference](COMMANDS.md) · [Contributing](CONTRIBUTING.md)
