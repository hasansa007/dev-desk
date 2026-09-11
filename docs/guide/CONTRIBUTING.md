# Maintaining dev-skill

Shared behaviour belongs in `shared/`; command entry points reference it. The sections below preserve the design rationale, policy, and incident history behind the workflow.

Paths and shell examples are relative to the repository root. Reader documentation lives in `docs/guide/`, beside the ADRs (`docs/adr/`), diagrams (`docs/arch/`) and validation reports (`docs/validation/`).

[User guide](GUIDE.md) · [Commands](COMMANDS.md) · [Workflow](WORKFLOW.md)

## The five ideas the design turns on

Understand these before editing anything; most "improvements" are re-learning one of them.

**1. Every rule should be scar tissue.** Nearly all of this came from a specific failure — Phase 12
from a branch that merged without its ADR, Phase 16's migrations-first from a schema arriving after
the code that needed it. **A rule with no incident behind it is a guess.** Write the incident into
the rule; that is why so many carry a date.

> **The date is the marker, and its ABSENCE is information.** A rule carrying a date was paid for
> with a real failure. A rule without one was *reasoned* into existence — plausible, untested, and
> the first thing to suspect when the pipeline fights you. When friction appears, check the
> undated rules before the dated ones; when pruning, they are the cheap cut. Most of Phase 0 and
> the epic decomposition are undated as of 2026-08-04: they are designs, not scars.

**2. A gate is only real if it produces an artifact.** Phase 12 works because its output is a
required `## DOCS` section in the PR — its absence is visible. Gates that produce only a
conversation get skipped and nobody notices. **When adding a gate, ask what it leaves behind.**
`## PIPELINE` is the same idea applied to the phases that produce nothing of their own: it does not
make them leave artifacts, it makes *skipping* them leave one.

**3. Phase 11 is the seam.** Phases 1–10 pass *reasoning*, which exists only in the conversation
that produced it. Phases 11–16 pass *artifacts* — a branch, a diff, a PR number. That is why the
standalone members start at 11 and not earlier, and why an epic cannot resume mid-plan.

**4. Ceremony is the failure mode, not sloppiness.** *A slow pipeline that gets skipped protects
nothing.* Every addition must earn the tier it lands in. Prefer conditional over mandatory.

> **Budget: `shared/pipeline.md` stays at or under 995 lines** (995 at 2026-09-07). Not a style
> preference — attention per rule falls as the file grows, and a rule nobody reaches is worth less
> than no rule. At the ceiling, an addition is only allowed with a deletion in the same commit;
> `wc -l shared/pipeline.md` before you write. The number stays deliberately close to current: this
> file grew 685 → 1014 on rules alone before any ceiling existed, and an unstated ceiling is not a
> ceiling. It has since lost rules — see the note below — which is the reason the gap is kept
> tight rather than comfortable.
>
> **2026-08-23 — raised 950 → 975, because the cheaper move was worse.** Staying under 950 for the
> Short Documentation rule was done by emptying Phase 9's Surgical Protocol into a pointer at the
> Guiding Principles table. Review found this optimised the line count while degrading exactly what
> the count is a proxy for: Phase 9 is the most-read phase in the file, and two relocated rules were
> strictly weaker at the destination — `Clean your own mess` lost *parameter*, `Commitment to flow`
> lost the actionable *delete it*. The bullets were restored and the ceiling moved instead.
> **Relocating a rule away from its point of use is not a deletion**, and does not pay for one.
>
> **2026-08-24 — corrected 975 → 958.** Raising by 25 to absorb 8 left 18 free lines, so the
> deletion-pays-for-addition gate would not have fired again for a long time, and the precedent set
> was *raise the ceiling* — available to every future addition. A ceiling with slack is not a
> ceiling. Take the smallest raise that admits the change, or take none. **960 was itself too
> loose** and was corrected to 958 in the same branch: at 957 the smallest admitting ceiling is
> 958, and 3 free lines would have let the next three additions land without paying anything.
> `ci/pr-gates.yml` now recomputes this rather than trusting the integer written here.
>
> **2026-09-06 — raised 958 → 988.** No deletion was available that would not degrade. The one the
> README has long named — Phase 11 delegating capture to `dev:shots` — does not pay: `dev:shots` owns
> the capture *commands*, Phase 11 only points at them in two lines. The 27-line teardown block is
> not a candidate either: `dev:launch-kill` does not cover the MCP-launched Chrome, so that rule
> lives nowhere else and Phase 11 is its point of use.
>
> **The breach ran silent for four PRs, which is the worse half.** The line above claimed
> `ci/pr-gates.yml` recomputes this; that file had never been installed. Its `line-budget` job now
> runs on its own at `.github/workflows/line-budget.yml`.

> **2026-09-07 — raised 988 → 995 (seven lines, measured).** Phase 4 gained six lines telling it that a `dev:survey`-filed
> issue arrives with ladder layers 1–2 already done adversarially, and that layers 3–5 must run
> anyway because survey checks code and never runs the app. No deletion was available: Phase 13 is
> the standing candidate and is not one — under the "run /code-review" line it carries the
> spec-compliance check, the Deep-tier security triggers and the verdict handling, so cutting it is
> the 2026-08-23 failure exactly. Smallest raise, zero slack.
>
> **2026-09-10 — that protocol now lives in `dev:code-review`.** Phase 13's prose was rewritten in
> place at the same 995 lines to point at the door, so the reasoning above still holds and the
> budget is unchanged. Phase 13 remains a poor deletion candidate for the same reason.

**5. Decisions are not steps.** Automation may skip asking between mechanical stages. It may never
skip a judgment — building, architecture, merging, promoting.

## Where to extend

| Change | Edit |
|---|---|
| Behaviour of any phase | `shared/pipeline.md` — **once**; all 7 entry points read it |
| A stack-specific addition | `platforms/web/pipeline-web.md`, `platforms/mobile/pipeline-{ios,android,kmp}.md` — these overlay Phases 10, 11, 14 only. Each platform's `MASTER_PROMPT.md` and `FEATURE_PROMPT.md` sit beside its overlays |
| A gate that belongs to an **event**, not a phase number | `skills/<door>/<topic>.md`, in the folder of the door that owns the event, with its own *When this runs* table — `skills/prod/prod-secrets.md` binds to the merge that releases production, which is Phase 16 in a two-stage repo and Phase 14 in a single-branch one. Both phases point at it in two lines each. Bolting such a gate to one phase is how it misses the repo shape it was written for; that cost two review passes on 2026-08-12 |
| Platform know-how a phase needs **only sometimes** | `<topic>.md` beside the file that reads it, a **lookup table read on demand** — `skills/prod/prod-secrets-apple.md` is read only when a missing secret matches a name in it. Not an overlay: it modifies no phase, so the phase stays stack-agnostic and costs nothing on repos that never hit it. Reach for this instead of an overlay when the content is *reference*, not *behaviour* |
| Branch/environment resolution | `shared/entry.md` |
| A new standalone member | `skills/<name>/SKILL.md` + a row in both family tables. **Only worth it for Phase 0 or a phase ≥ 11** — the rest pass reasoning, which cannot be handed over |
| A new **tool** (no phase) | Same, but it points at another tool rather than at `pipeline.md` — `launch-kill` reads `launch`'s Phase 2 for discovery. The no-copy rule is the same rule |
| A per-type issue template | the `dev:create-*` member itself — templates are the only thing those three doors hold |
| Dev Desk, the Mac app | `apps/desk/` — board rules mirror `scripts/dev.py` (ADR 0013) — change both |
| Entry routing | `SKILL.md` |

Members are ~60-line doors into the pipeline. **A member that copies pipeline content is a bug** —
they point, never duplicate.

## What not to change without a strong reason

- **The four always-stop gates.** They are the difference between a workflow and an autopilot.
- **The write boundary** (`shared/entry.md`). Name the target `owner/repo` before acting; never write
  outside the resolved repo without an explicit yes naming it; always cut a branch, from the
  resolved pre-prod branch and not from what is checked out. Paid for on
  2026-08-06 — a read-only version of this rule existed and did not stop two PRs being merged into
  another repo on a two-word instruction. **A boundary that only governs reads is not a boundary.**
- **The result-domain rule** (`shared/entry.md`). Say what an output *means* and what bounds it, not
  just where you looked. Paid for on 2026-08-06 → 08 — four confident wrong answers in one session,
  each a plausible **non-empty** result to a question narrower than the one asked. The empty-result
  rule (`dev:launch` 2.0 rule 2) existed the whole time and could not fire, because nothing was ever
  empty. **A rule that only governs absence does not govern reporting.**
- **Teardown rules.** Never kill a process you did not start. This one protects the developer's own
  session.
- **"Prefer the project's own launch script."** A bare `npm run dev` boots a differently configured
  app, and the difference is invisible until something breaks in a way you cannot reproduce.
- **Phase 12's accuracy rule.** *"Was the doc touched?"* is the easy half. A partial edit passes it
  while leaving the doc lying.

## How to propose a change

**Evidence first — the same standard the pipeline applies to code.**

1. **Name the incident.** What went wrong, on what date, in which run? "It would be better if…"
   is not an input. This whole file's last five fixes came from one real run.
2. **Say what artifact proves it.** If the gate cannot leave evidence behind, it will be skipped.
3. **Say which tier pays for it.** Everything mandatory taxes every task forever.
4. **Say what it replaces — and now you can prove it.** The pipeline grew from 685 lines in the
   repo's first commit to a peak of 1014 without ever losing a rule, because deletion was never
   safe: you cannot remove on a hunch what was added after an incident. `## PIPELINE`'s `Gates:`
   line is what makes it safe. Query the history —

   ```bash
   gh pr list --state merged --limit 100 --json body -q '.[].body' | grep '^Gates:'
   ```

   — and a gate that has read `clean` across twenty PRs is a rule you can retire with evidence, not
   nerve. **Every addition names its deletion**, justified either by that query or by pointing at
   where the rule is already written. An addition that removes nothing pays a permanent tax on every
   future task.

## `docs/` IS tracked here — and an untracked/tracked transition deletes files

**Changed 2026-09-10.** This repo previously git-ignored `docs/`, so its ADRs, diagrams and reports
lived on one machine only. They are now **tracked**: the docs gate requires an ADR to be *part of
the diff* that introduces the decision, which an ignored path can never satisfy — `0001-adrs-live-in-docs-adr`
and `0002-diagrams-land-in-the-repo` were both falsified by their own storage.

The skills still write into `docs/` in whatever repo they run in, and still check
`git check-ignore -q docs/` before doing so — that check exists because the answer differs per repo,
and it now returns *not ignored* here.

> **The trap works in BOTH directions, and it has fired once.** Moving between a commit where
> `docs/` is tracked and one where it is not changes the working tree either way. `git rm --cached` untracks a file and leaves it on
> disk — but a later `git checkout` or `git pull` that moves you from a commit where `docs/` **was**
> tracked to one where it is not will **delete those files**. Being git-ignored does not protect
> them; that only applies to files Git was never tracking. On 2026-09-07 the untracking merge
> succeeded and the very next `checkout main && pull` removed 13 of 14 files, silently, in the
> command that reported success.
>
> **Recover them from the last commit that tracked them:**
>
> ```bash
> git restore --source=89102eb --worktree -- docs/
> ```
>
> `--worktree` restores the files without re-staging them, so they stay untracked. `89102eb` is the
> last commit on `main` where `docs/` was tracked. To find it again without that SHA, locate the
> commit that DELETED them and take its **parent** — the deleting commit itself no longer has the
> files:
>
> ```bash
> git restore --source="$(git log -1 --format=%H --diff-filter=D -- docs/adr)^" --worktree -- docs/
> ```
>
> **The current direction, until this lands on `main`.** `docs/` is tracked on
> `feature/tracker-and-pipeline-state` and untracked on `main`, so checking out `main` from that
> branch **removes the 16 tracked files from disk**. Unlike 2026-09-07 this is *recoverable* —
> they are committed on the branch, so switching back restores them — but the removal is still
> silent. The window closes when the branch merges and `main` tracks them too.

**Anything under `docs/` you want other people to have must be copied somewhere tracked.** The
journey image was the worked example: it sat in a root `assets/` folder so the README rendered on
GitHub while `docs/` was ignored, and moved to `docs/assets/` once `docs/` was tracked (ADR 0015).
A decision's losing options belong in the **PR body** for the same reason — see
`dev:docs`.
