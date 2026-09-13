## Phase 12 — Docs & Decisions Gate (BEFORE any merge)

Code ships faster than the paper trail, and the gap is invisible until someone reads the docs and
believes them. Before the review gate, run `git diff <BASE_BRANCH>` — two dots, per the door:

| If the diff contains… | Then update… |
|---|---|
| a changed price, limit, cap or plan | the monetization/pricing doc — every number AND the reason it is that number |
| a decision with a rejected alternative | a new ADR in the decisions log — including the alternative and why it lost (Phase 6 ran? its losing designs go here verbatim) |
| a new/changed env var, migration or runbook step | the release/ops doc |
| a new module, flow or entry point | `PROJECT_MAP.md` (`TECH_STACK` / `SYSTEM_FLOW`) |
| work deliberately deferred | `ORPHANS & PENDING`, not a memory of it |

### The check is ACCURACY, not presence — reread what you edited

The table above asks whether the right document was *touched*. That is not the gate. **The gate is
whether every claim in the section you touched is still true**, and a partial edit passes the
touched-test while leaving the doc lying.

For each doc the diff modifies, reread the **whole paragraph or section around your edit** — not
your diff of it — and ask of each sentence: *is this still true after this branch?* Fix or delete
what is not. A doc that describes the previous design in three sentences and the new one in one is
worse than an untouched doc, because it reads as current.

Observed 2026-08-03, and it is why this subsection exists: a branch correctly added its ADR
**and** updated the PROJECT_MAP paragraph — green on every row of the table above — while
leaving three claims inside that same paragraph describing a rail the dialog no longer has. One
"rail" mention had been fixed, three had not. **A partial sweep looks identical to a complete one
from the outside**, so the pass criterion is the reread, not the edit.

Two rules that make this worth doing:

- **Write the alternatives you REJECTED, with their arithmetic.** A log that lists only what was
  chosen cannot tell a future reader why the obvious other path is wrong — so they will re-propose
  it, and you will re-argue it from memory.
- **State what is decided but NOT built.** A doc describing behaviour that does not exist yet is
  worse than silence; mark it explicitly as pending with what it needs.
- **A change that implements PART of a decision must record the remainder.** Shipping half an ADR
  silently is how a decisions log starts describing a system that does not exist — go back to that
  ADR and write which half is live and which is still intent.

Do not open the merge until this passes. Docs written after the merge get written from memory, and
memory keeps the conclusion while losing the reason.

**The output of this phase is the PR body's `## DOCS` section** — the gate lives inside an artifact
that is always produced, so it cannot be silently skipped. A PR without a `## DOCS` section is not
ready to merge. Observed failure mode this closes (2026-07-31): a feature branch with green suites
and a full verification table merged with its ADR unwritten and a stale PROJECT_MAP claim, caught
only because the developer asked — "suites green + evidence table done" is NOT this gate.

---

