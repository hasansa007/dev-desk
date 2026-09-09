# Rollback & Recovery Workflow

Implement the designed-but-unbuilt rollback workflow that classifies AI-driven changes (code-only, additive migration, destructive migration) and executes the appropriate recovery strategy. When a change breaks production, the developer invokes /dev:rollback which analyzes the change type, proposes a recovery plan, and executes it with human approval.

## Rationale
No competitor offers a rollback workflow for AI-driven changes (market gap-7). When Devin, Copilot Workspace, or any AI agent breaks production, developers are left to manually debug and revert. This is a unique differentiator that directly addresses the pain point 'No rollback or recovery workflow when AI-driven changes break production.' The classification system (code-only vs migration) is already designed, making this a planned feature awaiting implementation.

## User Stories
- As a developer, I want to quickly recover from AI-driven changes that break production so that downtime is minimized and I don't have to manually debug the agent's work
- As a team lead, I want rollback classification (code-only vs migration) so that the recovery strategy matches the risk level of the change

## Acceptance Criteria
- [ ] Given a broken production deployment, when the developer runs /dev:rollback, then the system classifies the change as code-only, additive migration, or destructive migration
- [ ] Given a code-only change, when rollback is executed, then a revert commit is created and verified before merge
- [ ] Given an additive migration, when rollback is executed, then the system proposes backward-compatible remediation steps
- [ ] Given a destructive migration, when rollback is executed, then the system warns about data implications and requires explicit confirmation
- [ ] The rollback workflow pauses for human approval before executing any recovery action
- [ ] A rollback evidence trail is recorded in the PR body for audit purposes
