# 0015 — Files live with the flow that reads them

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `refactor/flow-folders`

## Context

The family's top level mixed two kinds of file. `shared/entry.md` and `shared/pipeline.md` are read
by nearly every door. Beside them in `shared/` sat six files that only one flow reads: four platform
overlays, which only the Phase 2 platform table routes to, and the production secrets pre-flight
with its Apple lookup table. The platform prompts had top-level folders of their own, `web/` and
`mobile/`, read only by the root `dev` door's Architecture Prompts and Per-Feature Prompts tables,
so a platform's prompts and its overlay lived in two places. `scripts/compliance_auditor.py` sat
beside `scripts/dev.py`, although it implements `dev:audit`'s checks and nothing but its own test
imports it.

The developer decided on 2026-09-11 that each flow's files live together.

## Decision

A file one flow reads lives in that flow's folder; a file nearly every door reads stays shared.
Eleven files moved with `git mv`:

| From | To | Read by |
|---|---|---|
| `web/MASTER_PROMPT.md`, `web/FEATURE_PROMPT.md` | `platforms/web/` | root `dev` door |
| `shared/pipeline-web.md` | `platforms/web/` | `shared/pipeline.md` Phase 2 |
| `mobile/MASTER_PROMPT.md`, `mobile/FEATURE_PROMPT.md` | `platforms/mobile/` | root `dev` door |
| `shared/pipeline-{ios,android,kmp}.md` | `platforms/mobile/` | `shared/pipeline.md` Phase 2; `pipeline-kmp.md` |
| `scripts/compliance_auditor.py` | `skills/audit/` | `test-projects/compliance/`; implements `dev:audit` |
| `shared/prod-secrets.md`, `shared/prod-secrets-apple.md` | `skills/prod/` | `shared/pipeline.md` Phases 14/16, `shared/entry.md`, `hooks/pr-gates.sh` |

`shared/entry.md`, `shared/pipeline.md`, `scripts/dev.py`, `hooks/` and `ci/` stay where they are.

Every live reference names the new path in the form it had. `SKILL.md`'s six prompt paths stay
absolute install paths (ADR 0010); the repo-relative paths in the pipeline, `shared/entry.md`, the
hook message and the docs stay repo-relative. The Phase 2 platform table named the overlays bare, as
siblings of `pipeline.md`. They are no longer siblings, so the table now names them repo-relative,
the way the pipeline already names `prod-secrets.md`. References between files that moved together
(`pipeline-kmp.md` to the iOS and Android overlays, `prod-secrets.md` and `prod-secrets-apple.md` to
each other) are still between siblings and are unchanged. `shared/pipeline.md` keeps its 995 lines.

## Rejected

- **Put `web/` under `skills/launch/`.** `dev:launch` never reads it. Its only "web/" mention,
  `skills/launch/SKILL.md:148`, is a folder inside the *target* project ("root or one level down:
  web/, app/, frontend/"), not this repo's `web/`. The prompts' one reader is the root `dev` door,
  so under `launch/` they would sit beside a door with no use for them, and apart from the web
  overlay they belong with.
- **Leave things as they are.** The developer wants one folder per flow. As it stood, changing the
  web platform meant editing `web/` and `shared/`, and `shared/` held six files that only one flow
  reads beside the two that every door reads.

## Consequences

- **Install paths changed.** Anyone with personal notes, aliases or prompts pointing at the old
  paths (`~/.claude/skills/dev/web/…`, `…/mobile/…`, `…/shared/pipeline-*.md`,
  `…/shared/prod-secrets*.md` or `…/scripts/compliance_auditor.py`) must update them. ADR 0010
  carries a *Later* note naming the new ones.
- **`install.sh` is unaffected.** It symlinks the repo root into each CLI's skills directory, so
  every moved file resolves through the same link, and it names none of them.
- **The compliance test imports the auditor from `skills/audit/`**, by putting that folder on
  `sys.path`. `tests.yml` still discovers `test-projects/*/test_*.py` unchanged.
- **Dated records keep the old paths:** the `test-projects/` validation and root-cause reports,
  ADR 0010's Decision, and the 2026-09-10 spec. They record what was true when they were written.
- **The two diagram IRs, `docs/arch/dev-family.architecture.json` and
  `dev-journey.architecture.json`, still cite the old paths.** Both pins were already orphaned and
  recorded for a redraw in PROJECT_MAP's ORPHANS & PENDING. The moves are added to that entry; each
  IR must name the new paths before it can be re-pinned at a commit after the move.

## Evidence

```
git status --short
→ 11 renames (R), e.g. web/MASTER_PROMPT.md -> platforms/web/MASTER_PROMPT.md,
  scripts/compliance_auditor.py -> skills/audit/compliance_auditor.py

wc -l shared/pipeline.md
→ 995 before, 995 after

for f in test-projects/*/test_*.py; do PYTHONPATH=. python3 "$f" 2>&1 | tail -2; done
→ compliance 7/7 · rollback 5/5 · board 34/34 · project 16/16 · run 16/16 · state 17/17

git grep -n -E '(^|[^/a-z])(web|mobile)/(MASTER|FEATURE)_PROMPT|shared/pipeline-(web|ios|android|kmp)|shared/prod-secrets|scripts/compliance_auditor' -- . ':!docs/arch/*.html'
→ only this ADR, ADR 0010's Decision, the 2026-09-10 spec, the test-projects/ reports and the two
  diagram IRs
```
