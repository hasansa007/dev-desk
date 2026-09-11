# 0006 — The walkthrough gate always asks; the rule governs depth

Status:  Accepted
Date:    2026-08-31
Commit:  bd70d88  ·  PR #21

## Context

The pipeline gated on **approval** — Phase 5 gets an explicit go-ahead — but a plan can be approved
without being understood, and nothing checked the second thing. The developer's stated purpose for
these doors is to build their own model of the system rather than receive a finished one:
*"the idea is to train the brain muscle and not just rely on you."*

## Decision

`dev:survey` Phase 8 and `shared/pipeline.md` Phase 5 both, per item: state the mechanism and
constraints, **stop**, ask how the developer would handle it, and only then give the proposed
approach and diff the two. If theirs is better, take it and say so.

The **ask always fires**. The objective rule — was a rejected alternative recorded? — governs
**depth**: whether an alternatives block appears. Either way the alternatives line is printed, even
when empty, because that line is how the developer audits whether something was presented as
mechanical when it was actually a decision.

`just do it` skips immediately, without argument.

## Rejected

- **Explain, then check** — present the reasoning, then ask the developer to restate it. Tests
  comprehension of *the presenter's framing*, not whether they would have found it, and produces
  fluent agreement over a wrong model. Weakest of the options despite looking like a sensible middle.
- **Annotated design only, never ask** — free, and much better than a bare plan, but passive.
  Reading a rationale feels like understanding and mostly is not.
- **Fire only when a real fork exists, at the agent's discretion** — fewest interruptions, but it
  puts the agent in charge of deciding when the developer gets to think, and invites rationalising a
  fork as mechanical.
- **A per-invocation `--walk` flag** — fully explicit, but only fires when the developer already
  remembered they wanted it, which is the moment they least need reminding.

**The developer's two selections conflicted** — "always you-first" fires on everything, "objective
rule" fires only on a real fork. Resolved as recorded above, and flagged as a resolution rather than
a reading.

## Consequences

Every finding and every plan now costs a round trip. That is the point, and it is also the risk: on a
tired day the skip becomes reflex. Not fixable — pretending otherwise would make it a trap rather
than a tool.

Showing the plan first defeats the gate entirely. The tell is a message containing both the question
and the answer.

## Evidence

None from a live run — this ADR records a design decision taken in conversation, and the gate had not
yet fired on a real finding when it was written. Recorded because it existed **nowhere else**: it was
chosen in chat, and one conflict in it was resolved on the agent's judgment.
