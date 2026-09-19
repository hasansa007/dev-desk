# 0047 — Diagrams are Architecture, Data flow and one Sequence per flow

Status:  Accepted
Date:    2026-09-19
Commit:  (this commit)
Amends:  ADR 0033 — the five kinds become three; ADR 0046 decision 14 — Diagrams' kinds are chips in the
header's second row.

## Context

The Diagrams screen listed the five types `dev:arch` can draw — Architecture, Workflow, Data flow, Sequence,
Lifecycle — each as a single drawing of the whole project. Asked which were duplicates, the honest answer was:
Workflow is a sequence with lanes; Lifecycle only means something for one named subject; and a Sequence of
"the whole project" is a second architecture diagram. studyhub-deploy's `docs/arch/` showed the cost — six
drawings for three kinds, one data flow saved under an architecture file name.

## Decision

1. **Three kinds: Architecture, Data flow, Sequence.** Workflow and Lifecycle are dropped from the screen and
   from `dev:arch`'s offer (Archify still renders them). Asked for either, `dev:arch` draws the sequence of the
   flow it names.
2. **The kinds are chips in the header's second row** — the same `FilterChip` Work's filters use. One is
   always on; a green dot says the kind has a drawing.
3. **Architecture and Data flow are one drawing each** of the whole project, filling the screen, with
   Regenerate in the header.
4. **Sequence is one drawing per flow.** Its flows are listed on the left, like Work's milestones, each
   saying whether it is drawn and where it was named.
5. **Every source of flows counts the same, and none is required.** The list is the union of: the named views
   (`meta.views`) of the newest Architecture drawing, of the newest Data flow drawing, and the flows the
   newest findings hunt read (its *Per flow* table). A flow two sources name by the same words is one row. A
   sequence drawn for a flow no source names any more stays listed as *Drawn earlier*. A project with none of
   these — any project before its first drawing or hunt — types a flow at the foot of the list, or in the
   empty pane, and draws it.
6. **A flow's sequence is named for its flow**: `docs/arch/<repo>-sequence-<flow slug>.html`, passed to
   `dev:arch` in the prompt. The file name is how the drawing finds its row again; no field is added to
   Archify's IR, whose schema this family does not own.
7. **`dev:arch` names the flows** in every Architecture and Data flow drawing, as `meta.views` labelled the
   way a user says them — so the next drawing feeds the list.

## Alternatives rejected

- **Require an Architecture drawing before Sequence.** Most projects have never drawn one; a hunt, or a
  typed name, is enough to know what to draw.
- **One source wins** (Architecture first, the hunt as fallback). Rejected by the developer: the sources are
  equal, whichever is ready.
- **A flow field in the sequence IR.** Archify's schema is not ours; an unknown key is a validation risk on
  the next Archify release. The file name carries it instead.

## Consequences

- **Different words for the same flow are not merged.** studyhub-deploy's first render listed 19 flows: the
  Architecture drawing says *Build path*, the Data flow *Build a course*, the hunt *build-create*, *build-grow*
  and *build-rework*. Matching is by exact words (as a slug), because a guessed merge would hide a real flow.
  The fix is upstream — one flow list per project that `dev:arch` and `dev:findings` both read and write — and
  is left open until the developer decides it.
- A sequence drawn before this ADR (`studyhub-build-sequence`) keeps showing, as *Drawn earlier*.
