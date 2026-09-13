## Phase 6 — Architecture Alternatives (required for Deep features)

**When:** every Deep-tier feature, any novel design (new module, new data flow, several plausible
shapes), or the developer asks. Phase 5's scope answers are not this gate; "go fast" and "use
agents" change how it runs, never whether. A Deep feature skips it only after "lighter" at Deep's
cost declaration, which makes the Tier Standard. **Skip** for bugs and for work with one obvious
shape that is not a Deep feature — a fan-out that can only produce one answer three times is ceremony.

1. Launch 2–3 `feature-dev:code-architect` agents **in parallel** with forced-different biases:
   - **minimal change** — smallest diff, maximum reuse of what exists
   - **clean architecture** — maintainability, the abstractions you'd want in a year
   - **pragmatic balance** — speed + quality for THIS task's urgency
2. Compare the designs and form your own recommendation for this specific task (small fix vs large
   feature, urgency, blast radius).
3. Present to the developer: one-paragraph summary per approach, a trade-offs comparison, **your
   recommendation with reasoning** — then let them pick. Stop on Ambiguity applies: when the
   approaches genuinely differ, never pick silently.
4. **Write down the losers NOW.** The rejected approaches + why they lost are Phase 12's ADR
   rejected-alternatives section, and the arithmetic is only fresh once. Capture it in the spec
   (`## Rejected Alternatives`) so the ADR is a copy job, not a reconstruction.

---

