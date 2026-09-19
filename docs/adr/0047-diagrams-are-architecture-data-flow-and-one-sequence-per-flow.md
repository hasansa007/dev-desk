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
4. **Sequence is one drawing per flow.** Its flow is picked from a menu beside the chips — drawn flows first,
   each with where it was named, then *Draw another flow…* — so every kind draws full width (ADR 0046
   decision 15). It was a list on the left for one build; the drawing jumped sideways between chips.
5. **Every source of flows counts the same, and none is required.** The list is the union of: the named views
   (`meta.views`) of the newest Architecture drawing, of the newest Data flow drawing, and the flows the
   newest findings hunt read (its *Per flow* table). A flow two sources name by the same words is one row. A
   sequence drawn for a flow no source names any more stays listed as *Drawn earlier*. A project with none of
   these — any project before its first drawing or hunt — types a flow in *Draw another flow…*, or in the empty
   pane, and draws it.
6. **A flow's sequence is named for its flow**: `docs/arch/<repo>-sequence-<flow slug>.html`, passed to
   `dev:arch` in the prompt. The file name is how the drawing finds its row again; no field is added to
   Archify's IR, whose schema this family does not own.
7. **`dev:arch` names the flows** in every Architecture and Data flow drawing, as `meta.views` labelled the
   way a user says them — so the next drawing feeds the list.

8. **One flow list per project, `docs/flows.md`** (added the same day, after the first render listed 19 flows
   for about 8). One bullet per flow — `- Build a course — also: Build path, build-create` — and the app folds
   every `also:` name into that flow's row, drawings included. `dev:arch` uses the list's names for its views
   and sequences; `dev:findings` puts every flow id it hunts on it. Either door adds a line for a flow it names
   first. The list is optional: without it, rows merge only on identical words. studyhub-deploy's list took its
   Sequence menu from 19 rows to 9.

## Alternatives rejected

- **Require an Architecture drawing before Sequence.** Most projects have never drawn one; a hunt, or a
  typed name, is enough to know what to draw.
- **One source wins** (Architecture first, the hunt as fallback). Rejected by the developer: the sources are
  equal, whichever is ready.
- **A flow field in the sequence IR.** Archify's schema is not ours; an unknown key is a validation risk on
  the next Archify release. The file name carries it instead.

## Consequences

- **Different words for the same flow are merged only by `docs/flows.md`**, never guessed: a guessed merge
  would hide a real flow. A project without the list sees one row per distinct name until one is written.
- A sequence drawn before this ADR (`studyhub-build-sequence`) keeps showing, as *Drawn earlier*.
