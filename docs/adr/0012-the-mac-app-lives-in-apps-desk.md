# 0012 — The Mac app lives in `apps/desk/`, in this repo

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `feat/dev-desk-mac-app-design`

## Context

[The container spec](../superpowers/specs/2026-09-11-container-design.md) §5 compared one repo
against two and recommended two: `dev-skill` for the contract, a separate `dev-desk` for the app.
Its deciding cost was that every user's skill install would carry an Xcode project they never
build, and that a UI-only change would bump the skill everyone's `install.sh` pulls.

The developer decided the opposite in this session, 2026-09-11: the app lives in `apps/desk/` in
`dev-skill`. The first build covers the whole design on sample data, plus real git/gh reads for
opened folders (ADR 0013) — both land on this branch, alongside the system-model page and
`docs/arch/dev-system.*` (container spec §7 deliverable A).

## Decision

One repo. `apps/desk/` holds an xcodegen `project.yml` (the `.xcodeproj` it generates is
gitignored, never committed) and the local `DeskCore` Swift package — models, sample data, the
git/GitHub reader, and window state, built and tested with `swift test` independent of the app
target.

## Rejected

**A separate `dev-desk` repo** — §5's recommendation. Its install-cost argument doesn't survive
measurement: `du -sh -I .build apps/desk` is 716K at commit `a231561` (`.build/` and
`DevDesk.xcodeproj/` are gitignored, so a clone never carries either; the screen tasks still in
progress will add a little more). `install.sh` only symlinks the clone — it triggers no Swift or
Xcode build — so the disk this adds to every install is a few hundred KB, not the standing Xcode
toolchain tax §5 was pricing.

It lost for a second reason that matters more than the arithmetic: the contract it would need to
agree across two repos — `dev snapshot --json` (container spec §3.1) — is unbuilt, so there is
nothing yet for a version-pinned two-PR discipline to check against. And for now the app and CLI
change together: `LocalGitDataSource` mirrors `scripts/dev.py`'s board rules by hand (ADR 0013), so
a rule change on one side routinely means a change on the other. §5's own two-repo case weakens
once that stops being true.

## Consequences

- A path-filtered `desk.yml` is the CI this decision requires — it does not exist yet; the
  integration task still in progress adds it under that exact name, running `swift test` only when
  `apps/desk/**` changes.
- `tests.yml` and `line-budget.yml` stay untouched. `tests.yml` discovers `test-projects/*/test_*.py`
  only; `line-budget.yml` reads `shared/pipeline.md` and `documentation/CONTRIBUTING.md`'s budget
  line. Neither glob nor grep reaches a Swift file or `apps/`, so a desk-only PR never runs through
  either regardless of `desk.yml`.
- **Revisit trigger, taken from §5 and reversed.** §5's own trigger for merging later was "if the
  app turns out to change in lock-step with the CLI on most PRs" — true now, which is why one repo
  was chosen ahead of that pressure rather than after it. The reverse is this decision's revisit
  condition: if the app stops changing in lock-step with the CLI — many desk PRs land with no
  matching change in `scripts/dev.py` — the shared-repo cost (one clone, one review surface for two
  concerns) stops paying for itself and a split becomes the better trade.

## Evidence

`du -sh -I .build apps/desk` → `716K`, measured at commit `a231561`. `git ls-files apps/desk | xargs
du -ch | tail -1` → `632K` tracked. `apps/desk/.gitignore` excludes `DevDesk.xcodeproj/`, `.build/`
and `DerivedData/`; `find apps/desk -iname DerivedData` found none. `install.sh` contains no Swift
or `xcodebuild` invocation — it only creates symlinks — so this cost is disk, never install-time
CPU.
