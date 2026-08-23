---
name: trim
description: >
  Brings EXISTING code to the Short Documentation budget — one line, not a paragraph, not zero.
  Classifies every comment it finds into restates / compressible / carries-what-the-signature-cannot
  / name-smell, then deletes and compresses only the first two. It NEVER renames and NEVER edits
  logic: the run is rejected unless the code, with all comments stripped, is byte-identical before
  and after. Where a comment exists only because the name is bad, the comment STAYS and the rename
  is reported, because renaming touches call sites and this tool touches none.
  Reports by default; writing needs `--apply`. Commits per module so a large diff stays reviewable
  and a bad module reverts alone.
  Trigger on: "trim the comments", "apply the documentation rule to this repo", "these docstrings
  are too long", "strip the redundant comments", "bring this codebase to the comment budget".
allowed-tools: [git, rg, grep]
---

# trim — bring existing code to the documentation budget

A **tool**, not a phase. It maps to no phase number and reads none of `shared/pipeline.md`'s phases.

The rule it applies is **Short Documentation**, defined in `shared/pipeline.md` → Guiding
Principles, and its budget in Universal Rules. Read it there. Restating it here would give this
repo two versions of one rule, and the first edit to either makes them disagree.

Phase 9 applies that rule to code being written **now**. Nothing applied it to code already on
disk. That gap is the whole reason this exists.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| A path (`app/lib`) | Scope to that subtree | Whole repo |
| `--apply` | Write the changes | **Report only** |
| `--rename` | Print the rename backlog in full rather than a count | Count |

**Report is the default and whole-repo is the scope** — those two facts are chosen together. A bare
invocation that rewrote every file in the repo would be a destructive default, and the scope is
exactly what makes it destructive.

## Phase 2 — Never touch

Things shaped like comments that are **load-bearing**. Removing any of these changes behaviour or
breaks a build, and each one looks exactly like the prose this tool deletes:

- **Pragmas and directives** — `eslint-disable`, `@ts-expect-error`, `# noqa`, `# type:`,
  `//go:build`, `#pragma`, `# pylint:`, `@SuppressWarnings`
- **License and copyright headers**
- **Generated files, vendored trees, and anything `.gitignore`d** — never edit what a build rewrites
- **Comment-shaped text inside string literals** — a `//` in a URL or a `#` in a regex is not a comment
- **Doc-generation input.** If the repo configures typedoc, sphinx, godoc, Dokka or javadoc, those
  docstrings are a **build artifact**, not decoration. Detect the config, exclude by default, and
  say that you did — deleting them silently changes a published site.

## Phase 3 — Classify, never sweep

A regex pass is the wrong instrument: the rule **keeps** the line that carries what the signature
cannot. Every comment lands in exactly one bucket, and only the first two are ever written.

| Bucket | Test | Action |
|---|---|---|
| **RESTATES** | Says what the code or the types already say — `@param repo: string`, `// fetch the branches`, an Arrange/Act/Assert banner | delete |
| **COMPRESSIBLE** | A paragraph that says one thing | collapse to one line |
| **CARRIES** | Precedence, units, a spec quirk, a workaround, a perf trade-off — anything the reader cannot recover from the signature | **keep, untouched** |
| **NAME-SMELL** | The comment exists only because the name is bad | **keep the comment, change nothing**, report the rename |

**NAME-SMELL is kept, not fixed.** The rule says fix the name — but a rename touches call sites,
and this tool's safety rests entirely on touching none. Half the rule applied safely beats the whole
rule applied to a diff nobody can verify. The backlog is the other half's input, not its output.

## Phase 4 — Apply

Only with `--apply`.

- **Commit per module** — one commit per directory, each carrying its own counts. The tool cannot
  know how large the diff is until it has run, so it slices at every size rather than deciding
  after the fact. A bad module reverts alone; a reviewer walks commits, not 100 files.
- The repo is a **write boundary** (`shared/entry.md`): name `owner/repo` and the branch before the
  first commit, and work on a new branch, never the main line.

## Phase 5 — Falsification — the check that makes the diff trustworthy

The tool claims to touch only comments. That claim is **mechanically checkable**, so check it:

```
strip_all_comments(before) == strip_all_comments(after)    # per file, byte-identical
```

Any byte of difference means it edited logic. **Reject the run** — do not report it with a caveat.

Second gate: the test suite is green **before and after**. A comment-only diff that turns a suite
red means something load-bearing was removed — a pragma, a directive, a doc-generation input — and
Phase 2 has a hole. Report which check failed rather than the aggregate.

If the repo has no test suite, say so; a missing suite is a reported gap, not a silent pass.

## Phase 6 — Report

State what was scanned, what changed, what was **kept and why**, and the rename backlog as a count.

The kept list is the part worth reading: it is the evidence the tool exercised judgment rather than
matching a pattern. A run that keeps nothing at all is a **finding about the run**, not a clean
result — the budget is one line, not zero, so a repo with zero comments carrying precedence, units
or a workaround is more likely a classifier that collapsed to "delete everything".

## Next — ask, never stop flat

- Report only → offer `--apply`, naming the branch it would cut.
- Applied → the branch is unreviewed. `/code-review` on the diff, then `dev:pre-prod` for the PR.
- Renames flagged → offer `dev:create-issue` so the backlog becomes an issue instead of scrollback.
