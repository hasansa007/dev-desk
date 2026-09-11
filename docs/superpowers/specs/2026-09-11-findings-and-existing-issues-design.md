# Findings and existing issues: discussion decisions

**Date:** 2026-09-11

**Status:** direction accepted in discussion; implementation contract still proposed

**Related:** [container draft](2026-09-11-container-design.md) ·
[navigation and Insights](2026-09-11-mac-app-navigation-and-insights-design.md)

**Later UI clarification:** the app's Findings destination is the Survey surface. The broader
multi-source evidence model below applies to issue relationships; it does not turn that
destination into a combined Survey/Ideation/Insights inbox.

## Context and acceptance boundary

The maintainer already had dev-skill and compared it with a third-party desktop workflow tool
that covers similar ground. The discussion explored how a visual container could expose
dev-skill's value without merely adding the same screens. The comparison used that tool's
README and agent instructions, not a running application audit.

The maintainer accepted the proposed direction for filtering existing issues and reconciling
survey/ideation findings with them. This records that direction, not approval of a schema,
new command, autonomous GitHub writes, repository split, or app implementation.

## Agreed direction

An issue represents work. A finding represents evidence. Several findings, from different
runs or sources, can support one issue. A survey should improve the existing backlog before
offering new tickets. Preserve the original issue's intent, history, and authorship.

Each finding retains its source, observation date, inspected commit, evidence, and verification
limits. Code inspection must not be presented as runtime reproduction. Source is multi-valued
on an issue: a user report may later gain survey, ideation, and code-review evidence.

| Relationship to existing work | Proposed action |
|---|---|
| Same problem as an open issue | Link the finding; propose adding genuinely new evidence |
| Related problem with an independent fix | Keep separate; explain the relationship |
| Part of an existing epic | Link to the epic or propose a child issue |
| Possible duplicate | Show the comparison; hold filing and consolidation for review |
| Current evidence matches a closed bug | Investigate recurrence or incomplete resolution; closure alone proves neither |
| Previously declined improvement | Show the decision; reconsider only with a documented change in circumstances |
| New, confirmed problem | Propose a new issue |
| Unconfirmed finding | Retain in the report; do not file as a confirmed problem |

Matching first retrieves candidates using behavior, feature names, error messages, and code
locations, then compares issue details, mechanism, and scope. A shared file or similar title
alone does not establish duplication. A user-authored issue need not contain a code path.
An incomplete or failed search must not be presented as proof that a finding is new.

Consolidating two existing issues means selecting a canonical issue, preserving unique
information and links, and proposing closure of the duplicate with a clear reference.
Do not delete history or silently replace a user's description. Proposed external writes
must be concrete and reviewable, and executed only within the user's authorization.

## Proposed interface

Use one work view with evidence attached to issues. Findings awaiting a decision have a
review view; they do not become a competing authoritative backlog.

Filters discussed:

- Needs a decision: ambiguous matches, new findings, or proposed scope changes.
- New: findings not yet linked to existing work.
- Known with new evidence: existing issues enriched by this run.
- Work in progress: linked branches or PRs, derived from repository/tracker facts.
- Previously closed or declined: show the reason alongside current evidence.
- Source: user, survey, ideation, or review; allow multiple sources.

These filters can overlap. Relationship, evidence strength, and work status are separate
dimensions; being linked to an issue does not make a finding verified or the issue complete.

Example: issue #42 reports that returning from a lesson resets the course list's scroll
position. A survey identifies the mechanism in navigation code. Propose attaching that
evidence to #42, explicitly marked as code-inspected if it has not been reproduced live.
A different defect in the same component remains independently tracked.

## Existing behavior and gaps

- [Survey Phase 2](../../../skills/survey/SKILL.md) already searches open issues by file path
  and symptom and holds uncertain matches. It does not yet define the reconciliation model above.
- [Ideation Phase 2](../../../skills/ideation/SKILL.md) also searches closed issues and respects
  prior declines. Its explanation that a closed bug is fixed is too strong for this design.
- Current path-based retrieval can miss natural-language issues that name no source file.
- The current design needs a durable relationship and decision record so repeated surveys
  do not repeatedly ask the same question or append the same evidence.

## Next design decision: ownership and lifecycle

Resolve where finding identity, issue links, and accepted/declined matching decisions live,
including what survives a restart, another survey, changed code, or a renamed file.

Recommended approach, not yet accepted: keep versioned finding evidence with the repository's
survey/ideation artifacts; keep issue work status and published discussion in GitHub; keep
the app a reader and action surface. Choose the exact machine-readable representation and
decision owner before freezing the snapshot contract. Local caches must be reconstructible.

Define a stable finding identity separately from a per-run observation. Repeated observations
should retain provenance without producing duplicate issue updates. A changed mechanism or
scope may require a new finding; matching confidence is not a permanent identity guarantee.

## Recommended next exercise

Before implementing the app, walk a small representative set of real issues and findings
through a read-only reconciliation report. Include a path-free user report, a related but
distinct bug, a closed bug, a declined improvement, and a repeat observation. Use actual
examples when available and label constructed examples explicitly.

For every row, show the candidate issue, evidence for and against the relationship, proposed
action, and the exact information that would be added. No tracker writes are part of this
exercise. Success means known work remains visible, independent bugs stay separate, and
an unchanged repeated observation creates no additional work or repeated decision request.

## Other container questions still open

- Product emphasis: decision/evidence views were recommended as the differentiator; this
  is not a claim that competing tools lack verification or human review.
- Entry-path scope is now resolved: support both managed starts and connecting external work.
  [App and CLI task continuity](2026-09-11-app-cli-task-continuity-design.md) records the decision;
  provider-specific session capabilities and ownership remain to be designed.
- Job outcome protocol: current checkpoint writes mark the phase completed, so the original
  draft's incomplete-gate predicate cannot be produced by that command. Turns also stop
  outside numbered gates; exit zero without a checkpoint is not proof of task completion.
- Job/session ownership, restart recovery, question-specific answers, and stale approvals.
- Concurrency policy: one mutating job per checkout was recommended for the first version.
- One versus two repositories: the original draft recommends two; review suggested keeping
  one while the contract evolves. No final choice was made in this discussion.

This note adds no runtime behavior and does not change the existing skill instructions.
