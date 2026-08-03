---
name: dev
description: >
  Personal developer workflow for features AND bugs on personal projects — StudyHub
  (studyhub-deploy) is the daily driver; also Irtiqaa and others.
  Accepts: GitHub issue URL or number (#123, github.com/.../issues/N), or a plain feature
  title / bug description.
  Also trigger when user says "start feature", "work on issue", "new branch for",
  "investigate this issue", "fix this bug", or pastes a GitHub issue URL.
allowed-tools: [gh, git]
---

# Dev — Personal Workflow

GitHub issues, features and bugs for personal projects.

---

## Workspace Config

**Lives in `~/Developer/skills/dev-skill/shared/entry.md`** — repo auto-detect, pre-prod branch resolution,
prod branch resolution, and the single-stage detection. It is shared with every `dev-*` sibling,
so it is defined once there and never duplicated here.

---

## Entry 1 — Input Detection & Routing

> **Numbering:** these two are ENTRY steps, not pipeline phases. They run before
> `shared/pipeline.md` starts, and are numbered separately so they never collide with the
> pipeline's own Phase 0 (Context Load). Order is: Entry 1 → Entry 2 → pipeline Phase 0 → Phase 2 → …

| Input | Route |
|---|---|
| `#N`, `github.com/.../issues/N`, GitHub issue URL | **GitHub** flow |
| Any other free text | **Generic** flow |

---

## Entry 2 — Fetch Context

### GitHub Issue

Auto-detect repo:
```bash
git remote get-url origin
# SSH:   git@github.com:owner/repo.git  → owner/repo
# HTTPS: https://github.com/owner/repo  → owner/repo
```

Fetch issue:
```bash
gh issue view <N> --json title,body,labels,assignees,milestone
```

Detect issue type from labels: `bug` → Bug investigation flow; `enhancement` / `feature` → Feature flow.

### Generic (feature title)

No external fetch. The argument text is the feature description / seed.
Read local context: `CLAUDE.md`, `README.md`, `docs/`, `.spec/`.

---

## Phase 10 Additions (GitHub) — overlay, not a separate phase

Applied ON TOP of the pipeline's Phase 10 when the source is a GitHub issue:

- Add `Closes #N` at the end of the PR body
- Apply labels from the source issue where applicable
- Repo is auto-detected from `git remote get-url origin`

---

## The `dev-*` family

`dev` is the full run. Each sibling is a door into the same pipeline at a later floor — use one
directly when the work already exists and only that phase is needed:

| Skill | Phase | Input | Use when |
|---|---|---|---|
| `dev-verify` | 9 | a branch | "does this branch actually work?" |
| `dev-docs` | 9.4 | a diff | "are the ADRs and docs current?" |
| `dev-pre-prod` | 10 | a branch | "PR and merge this to pre prod" |
| `dev-review` | 10.2 ↺ | a PR number | "changes requested" — loops back to 10 |
| `dev-prod` | 10.5 | pre-prod + prod branches | "promote to production" |

They all read the same `shared/pipeline.md`; none of them copies it. Phases 0–8 have no sibling on
purpose — they pass reasoning rather than artifacts, so there is nothing to hand a fresh session.

---

## Shared Pipeline

1. Read `~/Developer/skills/dev-skill/shared/entry.md` — workspace + base-branch resolution, shared with
   every `dev-*` sibling.
2. Read `~/Developer/skills/dev-skill/shared/pipeline.md` and execute all phases from it, incorporating the
   Phase 10 additions defined above.

The pipeline's Phase 2 detects the stack and routes to the matching platform pipeline automatically.

---

## Architecture Prompts (Conditional)

Apply only when `ARCHITECTURE.md` is **missing** from the repo root (first feature on a new project), or when the user explicitly asks to revisit architecture.

### Mobile

| Detected stack | Variant | Prompt location |
|---|---|---|
| `*.xcodeproj` / `Package.swift` only | A — iOS only | `~/Developer/skills/dev-skill/mobile/MASTER_PROMPT.md` |
| `build.gradle*` + Android manifest only | B — Android only | `~/Developer/skills/dev-skill/mobile/MASTER_PROMPT.md` |
| `androidApp/` + `iOSApp/` + `shared/` (KMP) | C — iOS + Android + KMP | `~/Developer/skills/dev-skill/mobile/MASTER_PROMPT.md` |

### Web

| Detected stack | Prompt location |
|---|---|
| `package.json` → Next.js / React / Vue | `~/Developer/skills/dev-skill/web/MASTER_PROMPT.md` |

### Per-Feature Prompts

For every feature (regardless of whether ARCHITECTURE.md exists), use the matching feature prompt as the seed for Phase 5 (Plan Output):

| Stack | Feature prompt |
|---|---|
| Mobile (iOS / Android / KMP) | `~/Developer/skills/dev-skill/mobile/FEATURE_PROMPT.md` |
| Web (Next.js / React / Vue) | `~/Developer/skills/dev-skill/web/FEATURE_PROMPT.md` |

Do not invoke architecture or feature prompts for trivial changes (typos, copy edits, dependency bumps).
