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

The root had the same problem one level up. `GUIDE.md` was a 76-line redirect stub: 18 section
headings, each followed by one "See the documentation" link into `documentation/`. Reader docs lived
in `documentation/`, beside a tracked `docs/` that holds the ADRs, diagrams and specs, and
`documentation/CONTRIBUTING.md` still described `docs/` as the place for "local generated
artifacts". `assets/` held one image, the one README shows. `ci/` held one file, `pr-gates.yml`, a
CI template for other repos, apart from `hooks/pr-gates.sh`, which mirrors it. `test-projects/`
held the test suites and their fixtures, plus six root-level validation and root-cause reports that
are not tests.

The developer decided on 2026-09-11 that each flow's files live together and, after looking at the
root, that the root is tidied in the same PR.

## Decision

**1. A file one flow reads lives in that flow's folder; a file nearly every door reads stays
shared.** Eleven files moved with `git mv`:

| From | To | Read by |
|---|---|---|
| `web/MASTER_PROMPT.md`, `web/FEATURE_PROMPT.md` | `platforms/web/` | root `dev` door |
| `shared/pipeline-web.md` | `platforms/web/` | `shared/pipeline.md` Phase 2 |
| `mobile/MASTER_PROMPT.md`, `mobile/FEATURE_PROMPT.md` | `platforms/mobile/` | root `dev` door |
| `shared/pipeline-{ios,android,kmp}.md` | `platforms/mobile/` | `shared/pipeline.md` Phase 2; `pipeline-kmp.md` |
| `scripts/compliance_auditor.py` | `skills/audit/` | `tests/compliance/`; implements `dev:audit` |
| `shared/prod-secrets.md`, `shared/prod-secrets-apple.md` | `skills/prod/` | `shared/pipeline.md` Phases 14/16, `shared/entry.md`, `hooks/pr-gates.sh` |

`shared/entry.md`, `shared/pipeline.md`, `scripts/dev.py` and `hooks/` stay where they are.

Every live reference names the new path in the form it had. `SKILL.md`'s six prompt paths stay
absolute install paths (ADR 0010); the repo-relative paths in the pipeline, `shared/entry.md`, the
hook message and the docs stay repo-relative. The Phase 2 platform table named the overlays bare, as
siblings of `pipeline.md`. They are no longer siblings, so the table now names them repo-relative,
the way the pipeline already names `prod-secrets.md`. References between files that moved together
(`pipeline-kmp.md` to the iOS and Android overlays, `prod-secrets.md` and `prod-secrets-apple.md` to
each other) are still between siblings and are unchanged. `shared/pipeline.md` keeps its 995 lines.

**2. The root holds entry points and folders that have a reader:** `README.md`, `SKILL.md`,
`PROJECT_MAP.md`, `install.sh`, `.gitignore`, `.claude-plugin/`, `.github/`, `apps/`, `docs/`,
`hooks/`, `platforms/`, `scripts/`, `shared/`, `skills/`, `tests/`. Moved with `git mv`, deleted
with `git rm`:

| From | To |
|---|---|
| `GUIDE.md` | deleted |
| `documentation/*` | `docs/guide/` |
| `assets/*` | `docs/assets/` |
| `ci/pr-gates.yml` | `hooks/pr-gates.yml`, beside `pr-gates.sh`; `ci/` is gone |
| `test-projects/` | `tests/`, fixtures and their in-folder reports included |
| `test-projects/{E2E_VALIDATION,ROOT_CAUSE_MOBILE,ROOT_CAUSE_PIPELINE,ROOT_CAUSE_WEB,VALIDATION_MOBILE,VALIDATION_WEB}.md` | `docs/validation/` |

Live references follow the first decision's rule. Mentions of `GUIDE.md` that cited content now in
the contributing guide (*How to propose a change*, principle 1, the per-type template row) name
`docs/guide/CONTRIBUTING.md`. A door's `documentation/` or `tests/` that means the target repo's own
folder is generic and stays as it is.

## Rejected

- **Put `web/` under `skills/launch/`.** `dev:launch` never reads it. Its only "web/" mention,
  `skills/launch/SKILL.md:148`, is a folder inside the *target* project ("root or one level down:
  web/, app/, frontend/"), not this repo's `web/`. The prompts' one reader is the root `dev` door,
  so under `launch/` they would sit beside a door with no use for them, and apart from the web
  overlay they belong with.
- **Leave things as they are.** The developer wants one folder per flow. As it stood, changing the
  web platform meant editing `web/` and `shared/`, and `shared/` held six files that only one flow
  reads beside the two that every door reads.
- **Keep `GUIDE.md`.** It duplicated the section lists of the guide pages and nothing else: 18
  headings from `GUIDE.md`, `WORKFLOW.md`, `COMMANDS.md` and `CONTRIBUTING.md`, each pointing at its
  page, and one line saying the guide had moved. No file linked to it, and one of its anchors
  (`#docs-is-not-in-the-clone--and-switching-branches-deletes-it`) already pointed at a
  CONTRIBUTING section that had been renamed.
- **Keep `documentation/` beside `docs/`.** Two docs roots, and a reader can't tell which holds
  what. The contributing guide itself still described `docs/` as untracked scratch after ADR 0009
  had tracked it.
- **Keep `ci/`.** A one-file folder, kept apart from the hook it mirrors.
- **Keep the name `test-projects/`.** `tests/` is the conventional name, and the six reports are not
  tests.

## Consequences

- **Install paths changed.** Anyone with personal notes, aliases or prompts pointing at the old
  paths (`~/.claude/skills/dev/web/…`, `…/mobile/…`, `…/shared/pipeline-*.md`,
  `…/shared/prod-secrets*.md`, `…/scripts/compliance_auditor.py`, or `…/ci/pr-gates.yml` as the
  template's copy source) must update them. ADR 0010 carries a *Later* note naming the flow-folder
  paths; the template's header now copies from `~/.claude/skills/dev/hooks/pr-gates.yml`.
- **Outside links to the old paths break**: GitHub URLs to `GUIDE.md`, `documentation/*`,
  `assets/dev-journey.png`, `ci/pr-gates.yml` or anything under `test-projects/`.
- **`install.sh` is unaffected.** It symlinks the repo root into each CLI's skills directory, so
  every moved file resolves through the same link. It names none of them, and neither do
  `.gitignore` or `.claude-plugin/`.
- **`hooks/` now holds one file that is not a hook.** Nothing installs it: `hooks/README.md` links
  the four hooks by name (`for f in branch-guard pr-gates teardown context-load`), never `hooks/*`,
  and now says that `pr-gates.yml` is the CI template.
- **The CI glob changes.** `tests.yml` discovers `tests/*/test_*.py`. The test files compute the repo
  root as `../..`, which still holds from `tests/<area>/`; the compliance test imports the auditor
  by putting `skills/audit/` on `sys.path`.
- **`line-budget.yml` reads the new path**, `docs/guide/CONTRIBUTING.md`, for the ceiling and the
  stated count. The budget line's wording is unchanged, so its grep still parses it.
- **GitHub still won't surface the contributing guide.** It looks for `CONTRIBUTING.md` only at the
  root, in `docs/` and in `.github/`, and `docs/guide/` is one level too deep.
  `documentation/CONTRIBUTING.md` wasn't surfaced either.
- **Dated records keep the old paths:** the validation, root-cause and reproduction reports (now in
  `docs/validation/` and under `tests/`), ADR 0009's and ADR 0010's Decisions (each has a *Later*
  note), the other landed ADRs' prose, and the dated specs and plans. They record what was true
  when they were written.
- **The two diagram IRs, `docs/arch/dev-family.architecture.json` and
  `dev-journey.architecture.json`, still cite the flow-folder moves' old paths.** Both pins were
  already orphaned and recorded for a redraw in PROJECT_MAP's ORPHANS & PENDING. The moves are
  added to that entry; each IR must name the new paths before it can be re-pinned at a commit after
  the move. The root tidy moved no path any IR cites.

## Evidence

```
git status --short
→ decision 1: 11 renames (R), e.g. web/MASTER_PROMPT.md -> platforms/web/MASTER_PROMPT.md
→ decision 2: 50 renames (R) and 1 deletion (D GUIDE.md), e.g.
  documentation/CONTRIBUTING.md -> docs/guide/CONTRIBUTING.md, ci/pr-gates.yml -> hooks/pr-gates.yml

wc -l shared/pipeline.md
→ 995 before and after both decisions

for f in tests/*/test_*.py; do PYTHONPATH=. python3 "$f" 2>&1 | tail -2; done
→ compliance 7/7 · rollback 5/5 · board 34/34 · project 16/16 · run 16/16 · state 17/17

the run steps of line-budget.yml and tests.yml, extracted and run with bash -eo pipefail
→ pipeline.md 995 / 995 — documented count and ceiling verified.   (exit 0)
→ 6 suites passed.   (exit 0)

every relative markdown link in README.md, PROJECT_MAP.md, SKILL.md, hooks/README.md,
docs/guide/, docs/adr/ and docs/validation/, resolved against its own file
→ 73 resolve, 0 missing

git ls-files | cut -d/ -f1 | sort -u
→ .claude-plugin .github .gitignore PROJECT_MAP.md README.md SKILL.md apps docs hooks install.sh
  platforms scripts shared skills tests
```
