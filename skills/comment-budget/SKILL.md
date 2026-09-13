---
name: comment-budget
description: >
  Brings EXISTING code to the Short Documentation budget — one line, not a paragraph, not zero.
  Classifies every comment into restates / compressible / carries-what-the-signature-cannot /
  name-smell, and every undocumented function into needs-a-line, so it enforces BOTH halves of the
  budget rather than only driving toward zero. It never renames and never edits logic.
  Two gates per module, both BEFORE that module's commit: the code with comments AND docstrings
  stripped must be byte-identical, and every protected comment present before must still be present after — the
  first proves no logic moved, and only the second can catch a deleted pragma or licence header.
  Reports by default; writing needs `--apply`.
  Trigger on: "trim the comments", "apply the documentation rule to this repo", "these docstrings
  are too long", "strip the redundant comments", "bring this codebase to the comment budget".
allowed-tools: [git, rg, grep, python3, make, npx, node, bash, npm, pnpm, yarn, pytest, go, cargo, gradle, mvn]
---

# comment-budget — bring existing code to the documentation budget

**Scope — and why the name says "comment".** This door governs **comments and docstrings**, but they
are not equally protected, and the name follows the protection rather than the surface area.

| | Gate | In scope |
|---|---|---|
| **Comments** | check 2 keeps a full inventory — a deleted pragma or licence header **fails the run** | always |
| **Docstrings** | **no gate.** A docstring is a string expression, so check 2 cannot see it and check 1 strips it from both sides | only when the repo does NOT generate docs from them |

Where a repo configures sphinx, typedoc, godoc, Dokka or javadoc, docstrings are a build artifact,
**excluded in discovery**, and never visited — which is their only protection. There the door really
is a comment door. Everywhere else docstrings are in scope and carry the same one-line budget, with
*"these docstrings are too long"* routing here.

**Say which case the repo is in before touching anything.** Getting it wrong in the doc-generating
direction silently changes a published site, and no gate will catch it.

A **tool**, not a phase. It maps to no phase number and runs no pipeline phase — but it is not a
`nothing` loader: it applies **Short Documentation**, so it reads that rule from
`~/.claude/skills/dev/shared/pipeline/00-principles.md` (Guiding Principles) and the budget in
`~/.claude/skills/dev/shared/pipeline/18-output-and-universal-rules.md` (Universal Rules) before
classifying anything. Restating the rule here would give this repo two versions of it.

Phase 9 applies that rule to code being written **now**. Nothing applied it to code already on
disk. That gap is the whole reason this exists.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| A path (`app/lib`) | Scope to that subtree | Whole repo |
| `--apply` | Write the changes | **Report only** |
| `--rename` | Print the name-smell backlog in full | A count (Phase 6) |

Report is the default **because** whole-repo is the scope: a bare invocation that rewrote every
file would be a destructive default, and the scope is what makes it destructive.

## Phase 2 — Never touch

Things shaped like comments that are **load-bearing**. Each looks exactly like the prose this tool
deletes, and removing any changes behaviour or breaks a build:

- **Pragmas and directives** — `eslint-disable`, `@ts-expect-error`, `# noqa`, `# type:`,
  `//go:build`, `#pragma`, `# pylint:`, `@SuppressWarnings`
- **Licence and copyright headers**
- **Generated files, vendored trees, anything `.gitignore`d** — never edit what a build rewrites
- **Comment-shaped text inside string literals** — a `//` in a URL, a `#` in a regex
- **Doc-generation input.** If the repo configures typedoc, sphinx, godoc, Dokka or javadoc, those
  docstrings are a **build artifact**. Exclude by default and say so — deleting them silently
  changes a published site. Universal Rules carries the same carve-out for code being written.

**Three of these five are gated; two are scoping.** The pragmas and the licence headers are comments, so they are
check-2's inventory and a missing one fails the run. **Doc-generation input is excluded in
discovery, not gated** — a sphinx or javadoc docstring is a string expression, so check 2 (comments)
cannot see it and check 1 strips it from both sides. Never visited is the only protection it has.
Generated/vendored trees and comment-shaped text inside string literals are **not** comments, so
check 2 cannot see them. A vendored tree is caught by nothing at all — skip it in discovery. A
mangled string literal *is* caught, by CHECK 1, but **only if the stripper is string-aware**: that
requirement is what turns check 1 into this class's guard, which is why it is not optional.

## Phase 3 — Classify, never sweep

A regex pass is the wrong instrument: the rule **keeps** the line carrying what the signature
cannot, and that is a judgment. Five buckets, because the budget has two edges:

| Bucket | Test | Action |
|---|---|---|
| **RESTATES** | Says what the code or types already say — `@param repo: string`, an AAA banner | delete |
| **COMPRESSIBLE** | A paragraph that says one thing | collapse to one line |
| **CARRIES** | Precedence, units, a spec quirk, a workaround, a perf trade-off | **keep, untouched** |
| **NAME-SMELL** | The comment exists only because the name is bad | **keep it, change nothing**, report the rename |
| **UNDOCUMENTED** | A function whose signature cannot carry its contract and has no line at all | **propose** the missing line |

**UNDOCUMENTED is why this is not a comment-stripper.** The budget is one line, *not zero*; a tool
with only the first four buckets moves every repo toward zero and calls that success. Under
`--apply` a proposed line is written only where the contract is genuinely unrecoverable from the
signature — never as a blanket pass.

**NAME-SMELL is kept, not fixed.** The rule says fix the name, but a rename touches call sites and
this tool's safety rests on touching none. Half the rule applied safely beats the whole rule
applied to a diff nobody can verify.

## Phase 4 — Order of operations

**A module is one directory of source files, not a package and not a file.** Take the deepest
directory that directly contains source, and never recurse into a child in the same pass. It is the
unit of classification, gating and commits in **both** modes, which is why it is defined here and
not inside the write path. It has to stay small so that one module's classification fits in one
context — the constraint *Never classify more than one module at a time* rests on.

**Without `--apply` — the default — nothing is written.** No branch is cut, no file is edited, no
commit is made, and a dirty worktree is not an obstacle, because classification is a read. Run
Phase 3 over each module in turn, then go straight to Phase 6 and offer `--apply`. Everything below
is `--apply`'s path, not the tool's.

Preconditions, checked only under `--apply`, **in this order**:

1. Record the project's test and lint commands **as the project states them** — a `make lint`, a
   `./scripts/lint`, an `npx tsc`, a `golangci-lint`. Enumerating linters per ecosystem needs a new
   entry forever; running the recorded command is the mechanism. Then **run both now**. Green
   before is what makes red after mean something; without that baseline a pre-existing failure gets
   reported as a pragma this tool deleted. A red baseline is a **stop**, not a caveat. No lint
   command is a **reported gap**, not a pass — check 2's hazard class fails lint, never tests.
2. `git status --porcelain` is **empty** — checked *after* step 1, because test and lint runs write
   caches and coverage files. A dirty tree means an unrelated edit gets swept into a commit labelled
   comment-only, and Phase 5 then compares against a baseline that was never this skill's.
3. The repo is a write boundary (`shared/entry.md`): name `owner/repo`, cut a new branch.

**Steps 1 and 2 are reads and come before step 3 deliberately.** A baseline that stops the run must
stop it before a branch exists, or the one case the stop was written for — a repo whose suite is
already red — leaves an orphan branch behind.

Then, **per module, in this order**:

```
classify → apply → CHECK 1 → CHECK 2 → lint + tests → commit that module
```

Nothing is committed before its own gates pass. A module that fails a gate is **reverted in the
worktree and reported**, and the run stops — the earlier modules stay committed and reviewable,
which is what commit-per-module is for.

**Never classify more than one module at a time.** Per-comment judgment across a whole repo does
not fit one context; a classifier that runs out mid-module and keeps going degrades toward *delete*,
which is the one failure mode that looks like success. If a module cannot be finished, **stop and
say which module and how far it got**. Never fall back to a pattern match.

## Phase 5 — The two gates

They answer different questions, and neither can do the other's job.

```
CHECK 1 — CODE UNTOUCHED     strip_docs(before) == strip_docs(after)
                             strip_docs = comments + docstrings (see below)
CHECK 2 — PROTECTED INTACT   every Phase 2 comment present before is present after
```

**Check 1 proves no logic moved.** Any byte of difference means the tool edited code. Stop.

**Check 1 can never prove a comment survived** — deleting comments is the operation it exists to
permit. Delete an `eslint-disable`, a `# noqa` or a licence header and both sides strip
*identically*, so check 1 goes green on exactly the five categories Phase 2 calls load-bearing.
**Check 2 is the only gate that sees this**, which is why Phase 2's list is an inventory rather than
advice, and why lint runs alongside the tests: a removed pragma fails lint and no test.

**A docstring is not a comment.** In Python, and in any language whose doc lives in a string
expression, the one allowed line sits *inside* the function and is part of the AST. So CHECK 1 is
defined over **comments and docstrings** there, not comments alone — strip both from each side, or
collapsing the docstring this tool exists to collapse trips the gate it must pass. Phase 2's
string-literal exclusion means *incidental* `//` and `#` inside ordinary strings, never the
docstring itself. A language where this split is unclear is one to report and skip, not guess at.

Comment-stripping must be **string-aware**. A naive strip corrupts `http://` and any regex holding
a `#` — the same defect `dev:launch` 2.2a documents for JSONC. A stripper that cannot prove itself
string-aware makes check 1 worthless in both directions.

If the repo has no test suite, say so. A missing suite is a reported gap, not a silent pass.

## Phase 6 — Report

State what was scanned, what changed, what was **kept and why**, and what was **proposed**.

The name-smell backlog prints as a count, or in full when `--rename` was passed.

The kept list is the part worth reading — it is the evidence judgment happened rather than pattern
matching. A run that keeps nothing is a **finding about the run**: the budget is one line, not zero,
so a repo with no comment carrying precedence, units or a workaround is likelier a classifier that
collapsed to "delete everything" than a repo that had none.

## Next — ask, never stop flat

- Report only → offer `--apply`, naming the branch it would cut.
- Applied → the branch is unreviewed. `dev:code-review` on the diff, then `dev:pre-prod` for the PR.
- Name-smells found → offer `dev:create-issue` so the backlog becomes an issue, not scrollback.
