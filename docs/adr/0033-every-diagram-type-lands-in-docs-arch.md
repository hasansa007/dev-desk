# 0033 — Every diagram type lands in `docs/arch/`, labelled rather than hidden

Status:  Accepted
Date:    2026-09-15
Commit:  —  ·  working branch
Amends:  0002 (Evidenced diagrams land in `docs/arch/`, with their IR beside them)

## Context

Dev Desk's Diagrams screen offers five kinds. Four of them — Workflow, Data flow, Sequence,
Lifecycle — can never appear. Generating one always ends in the banner *"No Data flow diagram was
drawn … The last dev:arch run finished without drawing this diagram"*, and *Try again* produces the
same banner every time. The developer confirmed the loop is identical for Workflow and Lifecycle.
Observed in the field: `~/Developer/questxp/docs/arch/` holds only `questxp.architecture.json` and
`questxp.html`; the other four kinds read "Not generated".

The app is not the defect. `apps/desk/DeskCore/Sources/DeskCore/Local/ArchDiagrams.swift:26` fixes
`folder = "docs/arch"`; `list(repositoryRoot:)` (line 30) scans that one directory for `*.html` and
takes each file's kind from the `diagram_type` of its sidecar JSON (line 69);
`newest(kind:repositoryRoot:)` (line 52) returns nil when no file of that kind is there. The
`ProjectWindowModel.swift:194` `recordDiagramGenerateResult(kind:)` sets the failure banner exactly
when the kind's file is still missing after the run ends.

The door is. `skills/arch/SKILL.md` Phase 1 listed, among the triggers for writing to `$SCRATCH`:
*"the diagram is one of the four **unevidenced** types — nothing can re-check it, so it must not sit
in the tree wearing the same authority as an evidenced one."* That is 0002's Decision, and it is
followed to the letter: a `dataflow` run writes its files outside the repository, the app looks only
inside it, and the banner is the honest report of what it found. Two rules, each correct alone,
compose into a diagram that cannot be seen.

A second defect sits beside it. Phase 1 named the IR `docs/arch/<name>.architecture.json` for every
type. Archify's own examples name the IR by its type — `product-analytics.dataflow.json`,
`agent-tool-call.workflow.json`, `agent-run.lifecycle.json`, `async-job-roundtrip.sequence.json` in
`~/Developer/skills/archify/examples/` — and Dev Desk's tests assume that shape
(`ArchDiagramsTests.swift:23` writes `dev-journey.workflow.json`, line 38 `flows.dataflow.json`). A
dataflow IR called `<name>.architecture.json` misnames itself, and `dev:docs`'s staleness probe would
glob it and try to re-validate it as architecture.

0002's worry was authority: a picture in the tree looks checked. That worry was real, but hiding the
file is the wrong answer to it. A label on the artifact answers it directly — the reader who opens
the diagram sees "unevidenced" in its own cards — and it answers it for the reader who finds the file
months later, which a sentence in a session handoff never could.

## Decision

`dev:arch` lands **every** type in the invoked repo's `docs/arch/`, as `docs/arch/<name>.<type>.json`
beside `docs/arch/<name>.html` — `.architecture.json`, `.dataflow.json`, `.workflow.json`,
`.sequence.json`, `.lifecycle.json`. Never an artifact without its IR; the type-suffixed name is what
tells a reader, and the Diagrams screen, which type a file is.

The four unevidenced types carry their caveat **with** the artifact: a visible "unevidenced"
statement in the IR's own `meta`/card text, repeated in the handoff. The caveat is enforced by
labelling, not by hiding. This reverses that one clause of 0002.

`$SCRATCH` keeps its other triggers unchanged: `--scratch`, a git-ignored `docs/`, and a target that
is not the invoked repo. The architecture-evidence mandate, `--repo-root`, the HEAD re-assertion and
the repair-loop caps are untouched.

## Rejected

- **Keep the four types in `$SCRATCH` and teach Dev Desk to read the scratch directory** — the
  scratch directory is per-session and evaporates with it; a diagram the app can show today and not
  tomorrow is the rot 0002 was written against, in a new place. It also puts a second source of
  truth beside `docs/arch/`, and the app would then be reading files no commit has ever recorded.
- **Drop the four kinds from the Diagrams rail** — the door draws them; a rail that does not list
  them hides a capability the door has, and the handoff would still name a file the app refuses to
  show.
- **Grey the four kinds out as "unsupported"** — they are supported; they are unevidenced. Calling
  the caveat "unsupported" tells the reader the wrong thing, and it leaves the door writing files to
  a place nobody reads.
- **Name every IR `.architecture.json` and read the type from inside it** — it keeps a misnamed file
  in the tree, breaks `dev:docs`'s glob, and disagrees with the renderer's own examples for no gain.

## Consequences

- Up to four more ~750 KB self-contained HTML files may accumulate per repository, one per kind,
  each in the repo's history.
- Those four carry no re-checkable pins, so `dev:docs` cannot detect their rot; its probe still globs
  `docs/arch/*.architecture.json` only, deliberately, and their presence in `docs/arch/` is expected
  rather than a gap. Their staleness is a human's to notice, which is what the in-card label is for.
- The Diagrams screen now shows what the door drew, for every kind, and the permanent retry loop is
  gone without a Swift change.
- 0002's Decision stands for architecture; only its `$SCRATCH` clause for the four types is amended.
