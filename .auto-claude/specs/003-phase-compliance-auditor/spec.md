# Phase Compliance Auditor

Build a mechanical check that cross-references self-reported ## PIPELINE sections against actual tool-call evidence (file writes, git operations, test runs) to detect phases that were skipped but not reported as skipped. Currently, a run that skips a phase AND omits it from the Skipped: line is invisible — this feature makes that detectable.

## Rationale
The self-reporting gap is dev-skill's most critical trust vulnerability. Competitor tools like Cursor (pain-1-1) and CLAUDE.md files (pain-6-1) are pure guidance with zero enforcement. Dev-skill's value proposition rests on 'enforcement, not just guidance' — but self-reported sections undermine that claim. This auditor closes the gap between claimed and actual enforcement, directly strengthening the core differentiator against all competitors.

## User Stories
- As a developer, I want to know which pipeline phases were actually executed (not just reported) so that I can trust the verification evidence in my PRs
- As a team adopting dev-skill, I want mechanical proof that quality gates were run so that I can rely on the pipeline for compliance

## Acceptance Criteria
- [ ] Given a completed pipeline run, when the auditor is invoked, then it compares ## PIPELINE reported phases against evidence of actual execution
- [ ] The auditor detects when a phase was skipped but not listed in the Skipped: line
- [ ] The auditor produces a compliance report showing matched phases (reported + evidence), unmatched phases (reported but no evidence), and hidden skips (not reported, no evidence)
- [ ] The compliance report is appended to the PR body under a ## COMPLIANCE section
- [ ] False positive rate is below 10% — phases that legitimately produce no tool-call artifacts are handled
