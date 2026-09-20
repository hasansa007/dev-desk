# Dev Pipeline — Shared Phases

The phases now live as one file per phase under `shared/pipeline/`. A door that executes a single
phase should read **only that phase's file**; a full `dev` run reads them in order.

`00-principles.md` and `18-output-and-universal-rules.md` apply to **every** run regardless of phase —
read both no matter which phase you execute.

| Phase | File (install path) |
|---|---|
| Guiding Principles, Right-Size, Run Mode (every run) | `~/.claude/.dev-root/shared/pipeline/00-principles.md` |
| Phase 0 — Filing | `~/.claude/.dev-root/shared/pipeline/01-phase-00-filing.md` |
| Phase 1 — Context Load | `~/.claude/.dev-root/shared/pipeline/02-phase-01-context-load.md` |
| Phase 2 — Tech Stack & Project Discovery | `~/.claude/.dev-root/shared/pipeline/03-phase-02-tech-stack.md` |
| Phase 3 — Git Branch Naming | `~/.claude/.dev-root/shared/pipeline/04-phase-03-branch-naming.md` |
| Phase 4 — Investigation | `~/.claude/.dev-root/shared/pipeline/05-phase-04-investigation.md` |
| Phase 5 — Discuss Before Building | `~/.claude/.dev-root/shared/pipeline/06-phase-05-discuss.md` |
| Phase 6 — Architecture Alternatives | `~/.claude/.dev-root/shared/pipeline/07-phase-06-architecture.md` |
| Phase 7 — Plan Output | `~/.claude/.dev-root/shared/pipeline/08-phase-07-plan-output.md` |
| Phase 8 — Task Breakdown | `~/.claude/.dev-root/shared/pipeline/09-phase-08-task-breakdown.md` |
| Phase 9 — Implement | `~/.claude/.dev-root/shared/pipeline/10-phase-09-implement.md` |
| Phase 10 — Pre-PR Quality Checks | `~/.claude/.dev-root/shared/pipeline/11-phase-10-pre-pr-checks.md` |
| Phase 11 — Verification Gate | `~/.claude/.dev-root/shared/pipeline/12-phase-11-verification.md` |
| Phase 12 — Docs & Decisions Gate | `~/.claude/.dev-root/shared/pipeline/13-phase-12-docs.md` |
| Phase 13 — Code Review Gate | `~/.claude/.dev-root/shared/pipeline/14-phase-13-code-review.md` |
| Phase 14 — PR Creation → Review → Merge → Pre Prod | `~/.claude/.dev-root/shared/pipeline/15-phase-14-pr-and-merge.md` |
| Phase 15 — Review Cycle | `~/.claude/.dev-root/shared/pipeline/16-phase-15-review-cycle.md` |
| Phase 16 — Prod Promotion | `~/.claude/.dev-root/shared/pipeline/17-phase-16-prod-promotion.md` |
| Output Header Format, Universal Rules (every run) | `~/.claude/.dev-root/shared/pipeline/18-output-and-universal-rules.md` |
