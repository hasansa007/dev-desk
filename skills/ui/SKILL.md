---
name: ui
description: >
  Opens the local UI — four self-contained pages under `.dev/ui/` (board, roadmap, ideation,
  insights) plus an index linking them, rendered from what the other doors computed. Rebuilds ONLY
  what is stale, says why each one was stale, then opens the index in a browser. The pages are
  generated output and are never read back as truth: nothing in this family decides anything from them.
  A TOOL, not a phase. It writes only inside `.dev/` and never edits the repo's `.gitignore`.
  Trigger on: "open the ui", "show me the board in a browser", "open the dashboard", "refresh the
  ui", "is the ui up to date", "regenerate the ui pages", "dev ui".
allowed-tools: [git, gh]
---

# ui — the four pages, fresh

A **tool**, not a phase. It shows what the board, roadmap, ideation and insights doors already know,
as local HTML — no server, no network, no account.

## Phase 0 — This door needs the CLI

The pages are produced by `scripts/dev.py`, so unlike the other doors there is no prose fallback:
without the CLI there is nothing to render. Use whichever of these resolves:

```bash
dev ui ...                                        # after install.sh linked it onto PATH
python3 ~/.claude/skills/dev/scripts/dev.py ui ...
```

If neither exists, say so and point at `install.sh`. Do not hand-write HTML to stand in for it.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | check, rebuild what is stale, open the index | this |
| `board` · `roadmap` · `ideation` · `insights` | rebuild that one and open it | all four |
| `check` | report staleness only — write nothing | — |
| `force` | rebuild all four whether stale or not | stale only |

## Phase 2 — Resolve the repo

Read `~/.claude/skills/dev/shared/entry.md` — **the absolute path, because this skill runs inside
somebody else's repo.** The pages describe the resolved repo and are written into its `.dev/ui/`.

## Phase 3 — Check, then say what you found

```bash
dev ui --check
```

It prints each surface as `fresh`, `stale — <reason>`, or `live` for the two that read GitHub, and
exits non-zero only when something is actually stale — `live` never fails it.
**Report the reasons, not just the count.** The rules it applies:

| Surface | Stale when |
|---|---|
| `board`, `roadmap` | **live** — rebuilt on every `dev ui`, because they read GitHub, which changes without a commit and nothing local can prove fresh. Reported, never counted as stale |
| `insights` | built from another commit, or `PROJECT_MAP.md` changed since the build |
| `ideation` | built from another commit, or anything under `docs/ideation/` changed since |
| any | its `.json` or `.html` is missing, or the `.json` will not parse |

## Phase 4 — Rebuild what is stale, then open

```bash
dev ui --open          # rebuilds only the stale surfaces, then opens .dev/ui/index.html
dev ui insights --open # one surface, always rebuilt
dev ui --force --open  # everything
```

`index.html` is rebuilt on every run and shows one card per surface — its counts, the commit it was
built from, or "not built yet". Every page carries a nav bar to the index and the other three.
Every page shows the commit it was built from and says it is not authoritative.

The CLI writes `.dev/.gitignore` (`*`) the first time it creates `.dev/`, so the folder keeps itself
out of git — **never edit the repo's own `.gitignore`**: that is a file this family does not own.
If the command reports a leftover `ui/` at the repo root from an older version, pass that on and let
the developer delete it.

## Phase 5 — Hand off

The pages are a view. To **act** on what they show, use the door that owns it: move a card with
`dev:kanban`, plan with `dev:roadmap`, file a finding through `dev:ideation`. Never offer to edit a
page to change what it says — the next rebuild overwrites it, and the source never saw the edit.

## Never

- **Never treat a page as a source.** Nothing here reads `.dev/ui/` back.
- **Never hand-edit or hand-write a page.** Rebuild it.
- **Never call a GitHub-backed page fresh** because it was built at HEAD — the tracker moves without
  commits.
- **Never edit the repo's `.gitignore`.** `.dev/.gitignore` is the family's own file; the repo's is not.
- **Never delete a root `ui/`.** It may be someone's source code; the CLI only reports its own leftovers.
- **Never render another repo's state** — `shared/entry.md`'s boundary applies.

## Known limits

| | |
|---|---|
| `board` and `roadmap` rebuild every time | They cost a couple of `gh` calls — the price of never showing a stale tracker as fresh |
| Staleness of file-backed pages uses file times | A file restored from an older copy with an old timestamp is not seen as a change; `force` covers it |
| Pages are read-only | Triggering work from them would turn output into input; that needs a local server, not a static page |

## Scar tissue

**2026-09-11 — `/dev:ui` did not exist.** `dev ui` was a CLI subcommand only, so typing the door
form in an agent CLI had nothing to run, and `/dev ui` fell through toward the feature-title guard.
At the same time every page had been built from a commit four behind HEAD, and `PROJECT_MAP.md`
had changed after the insights page was built — so the insights page was wrong in content, not
just in its label. The rebuild used to be all-or-nothing and gave no reason; it now rebuilds only
what is stale and says why.

**2026-09-11 — the pages lived in a root `ui/` with no way between them.** Each repo got a second
folder to ignore — and the ignore rule for it had already hidden `skills/ui/` from git once — and
four unconnected files with no index. The pages moved to `.dev/ui/` beside the phase state, `.dev/`
now ignores itself, and an `index.html` plus a nav bar on every page link them.
