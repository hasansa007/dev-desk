# Architecture Decision Records

One file per decision, `NNNN-kebab-title.md`. The number is allocated by reading this directory,
never guessed. A landed ADR's `## Decision` is never edited — it is superseded by a new one and its
`Status:` updated to point there. An ADR with an empty `## Rejected` is a note, not an ADR.

Owned by `dev:docs`, which requires one for any diff carrying a decision with a rejected
alternative. See [0001](0001-adrs-live-in-docs-adr.md) for the convention itself.

| # | Decision | Status |
|---|---|---|
| [0001](0001-adrs-live-in-docs-adr.md) | ADRs live in `docs/adr/`, numbered, superseded rather than edited | Accepted |
| [0002](0002-diagrams-land-in-the-repo.md) | Evidenced diagrams land in `docs/arch/`, with their IR beside them | Accepted |
| [0003](0003-the-staleness-probe-bumps-the-revision.md) | The diagram staleness probe bumps the revision to HEAD | Accepted |
| [0004](0004-compare-cited-paths-not-the-whole-tree.md) | Compare cited paths, not the whole tree, before advancing a pin | Accepted |
| [0005](0005-re-assert-head-before-validating.md) | Re-assert HEAD before validating, not only at the start | Accepted |
| [0006](0006-ask-for-their-approach-before-showing-yours.md) | The walkthrough gate always asks; the rule governs depth | Accepted |
| [0007](0007-raise-the-pipeline-line-ceiling-to-988.md) | Raise the pipeline line ceiling to 988, and install the check | Accepted |
| [0008](0008-replace-the-board-and-surveyor-rather-than-extend-them.md) | Replace the board and surveyor rather than extend them | Accepted |
