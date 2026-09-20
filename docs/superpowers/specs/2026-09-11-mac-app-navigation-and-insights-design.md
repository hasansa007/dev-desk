# Mac app: navigation, project chat, and naming

**Date:** 2026-09-11

**Status:** discussion record; accepted choices and proposals are distinguished below.
No app implementation, provider selection, or final product name is approved by this note.

**Related:** [container](2026-09-11-container-design.md) ·
[task continuity](2026-09-11-app-cli-task-continuity-design.md) ·
[issue reconciliation](2026-09-11-findings-and-existing-issues-design.md)

**Reusable design brief:** [Dev Desk app design prompt](../../design/dev-desk-app-design-prompt.md).
It chooses explicit prototype defaults without treating open product choices as accepted.

## Decision inventory

| Topic | Status | Direction |
|---|---|---|
| First platform | Accepted | Native macOS app |
| Project navigation | Accepted | Separate window per project |
| Starting and connecting work | Accepted | Both managed app/CLI starts and connection to external work |
| Parallel work | Product direction accepted; mechanics proposed | Tasks carry individual requirements, branches, workspaces, and agent sessions |
| Findings name and meaning | Accepted clarification | Findings is the app surface for Survey and its results |
| Decisions | Retain, as requested | Pending decisions and prior decisions with rationale |
| Roadmap | Requested inclusion; details proposed | Future features, improvements, priorities, and committed plans |
| Settings | Requested inclusion; groups proposed | General, appearance, defaults, accounts, and more |
| Board label | Open | User suggested Active Board; Board was recommended if backlog is also included |
| Insights placement | User proposed floating chat; details proposed | Project-scoped conversation, optionally docked |
| Agent integration/default | Open | Support an adapter boundary; select and validate an initial integration |
| Product name | Open | Dev Desk remains the working name and current recommendation |

## Proposed project navigation

| Main destination | Purpose |
|---|---|
| Board | Board view of tasks, their progress, dependencies, and next actions |
| Roadmap | Considered and committed future work, grouped into themes, milestones, and epics |
| Findings | Run Survey, inspect evidence, and reconcile findings with existing issues |
| Decisions | Answer pending questions and inspect earlier decisions and their rationale |
| Settings | App preferences and project-specific overrides |

A task is the underlying work item; the board is its view. If named Active Board, define
whether backlog lives there or is reached through a separate filter. Do not silently remove
unplanned work to make the label fit. Git/GitHub remain authoritative for work status.

Insights is not an additional primary destination in this proposal. It is available from
the project toolbar and contextual actions such as asking about a finding or selected code.
Agents and Terminals are a workspace dock. Activity, Requirements, Changes, and Evidence are
task-detail tabs. The earlier Home/Map/Tracker/Jobs/Inbox navigation is superseded by this
proposal; useful summaries and phase progress can appear within these destinations.

## Findings means Survey

The user's clarification is a product mapping: **Findings = the Survey surface**. Survey is
the investigation process; findings are its evidence and results. Keep that distinction in
data without adding two competing navigation destinations or renaming the skill.

Proposed controls: start a survey, inspect prior runs and inspected commits, review evidence
and verification limits, compare candidate issues, and link or propose new work. Repeated
surveys preserve observation history and reuse known relationships. Use the reconciliation
note for duplicate, recurrence, and declined-work handling.

The issue detail may carry evidence from survey, ideation, reviews, and user reports. That
broader provenance model does not expand the Findings tab into a catch-all inbox. Ideation
remains a distinct skill; its entry from Roadmap or project chat is proposed, not settled.

## Roadmap and Decisions

Roadmap should hold proposed features, useful improvements, must-have work, and critical
concerns such as security. Keep work type, urgency, and commitment separate: an interesting
feature is not automatically scheduled, and an urgent confirmed defect can go directly to
the Board while retaining its roadmap relationship. Published milestones and epic parents
follow the existing roadmap skill; speculative suggestions do not become commitments by
being displayed. Do not create duplicate work records across Roadmap and Board.

The intended role of other GitHub repositories is still unresolved: references, inspiration,
dependencies, or additional work sources have different implications. No cross-repository
aggregation or automatic import is approved.

Decisions includes current questions and history, with task, relevant evidence, options,
chosen answer, and rationale. Questions can occur outside the four pipeline gates. A
question must have an identity and validity context so an answer cannot approve obsolete
work. Final storage and lifecycle belong in the runner/evidence contract.

## Proposed Insights conversation

Use a nonmodal floating conversation panel that can be pinned beside the workspace. It
should leave the Board and terminal usable while discussing the project. Closing the panel
hides the view; reopening retrieves its conversation. The persistence mechanism is open.

Show the project, selected branch/workspace, optional task or finding context, and selected
agent in the header. Context attachments should be visible and removable. Switching projects
does not silently mix their conversations. Starting another project chat is explicit.

The panel exposes [dev:insights](../../../skills/insights/SKILL.md):

- Answer from repository evidence with navigable file/line references; distinguish code from
  documentation and record the inspected revision when appropriate.
- Route investigations to Survey, opportunities to Ideation, plans to Roadmap, and diagrams
  to Arch. A conversational suspicion is not a confirmed finding.
- Offer durable, supported repository knowledge for PROJECT_MAP.md within the user's write
  authorization. Conversation history is not itself durable project knowledge.

Start project exploration with read-only capabilities. Requests to investigate or implement
work route to the appropriate skill with visible scope. Existing authorization remains valid;
the panel does not introduce a fresh confirmation for every ordinary action.

A project chat is distinct from a running task agent's conversation. An explicit Continue
task action targets the existing session when supported. Never send exploratory questions
into a coding agent silently or start a competing writer in its checkout. Switching providers
creates an explicit handoff if the original session cannot be continued.

## Agent connections and defaults

The app needs an agent integration to inspect the real project and invoke skills. A text
chat widget alone does not supply repository access, tool execution, or resumable sessions.

| Approach | Benefit | Responsibility/cost |
|---|---|---|
| Official agent interface or CLI adapter | Reuse an agent's tools and supported session mechanisms | Validate authentication, events, permissions, cancellation, resume, and version compatibility |
| Direct model API | Control the full conversation and tool experience | Build and maintain the tool loop, context handling, sessions, permissions, and usage reporting |

Recommendation: use the same agent connection layer for project chat and task execution,
with capabilities selected for each. Begin with one proven integration; keep the interface
open to others. A provider default is user-configurable, with a project override and explicit
per-conversation selection. Do not silently switch providers after failure or equate support
for headless output with support for attaching an arbitrary live terminal.

Official interfaces inspected on 2026-09-11, not end-to-end integration tests:

- [Codex App Server](https://learn.chatgpt.com/docs/app-server) exposes conversations,
  authentication, approvals, and streamed agent events for custom clients. Its documentation
  marks the app-server command and WebSocket transport experimental and unsupported for
  production workloads. It is a candidate for a prototype, not a validated production choice.
  Local CLI inspection found codex-cli 0.153.4; help output does not prove integration behavior.
- [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview) provides the Claude
  Code tool loop and context management through Python/TypeScript. Its documentation also
  describes CLI subprocess use for other languages. Packaging and account access need validation.
- [Gemini CLI headless mode](https://geminicli.com/docs/cli/headless/) documents structured
  JSON and streaming events without an interactive terminal. This establishes an integration
  candidate; live attachment and continuation need separate verification.

Authentication and billing depend on the chosen integration. Do not promise that an existing
consumer subscription covers direct API usage. Settings should show connection state,
supported capabilities, and the selected agent/model without requiring every provider.

## Settings and project opening

Proposed app settings groups: General, Appearance, Agents and Defaults, Accounts and
Connections, Notifications, and Execution. Project settings expose relevant overrides for
branches, environments, checks, and workspace placement while respecting repository config.
The exact global-settings window versus project-settings layout remains open.

The proposed project picker offers an existing folder, a clone URL, or a new local project.
Opening a project does not start an agent. Focus an existing project window when already
open. Native restoration and project identity still need definition.

## Design exploration already shown

Two local interactive concepts explored a focused task workspace and then separate project
windows with multiple agent outputs. The latest demonstrated opening/restoring project
windows, Focus/Parallel layouts, task-detail tabs, terminal/activity/result capabilities,
coordinator follow-up, decisions, and connecting existing work. These are simulated controls,
not evidence of a working runner or terminal integration. No browser validation was claimed.
Roadmap, Settings, and floating Insights need a revised concept after this discussion.

## Naming proposal

**Dev Desk** is the current recommendation: a workspace for projects, decisions, and agents,
with a clear relationship to dev-desk. The name is not accepted merely because it appeared
in mockups. Two alternatives for discussion are **Relay**, emphasizing continuity between
agents and surfaces, and **Workbench**, emphasizing the developer's working environment.
No trademark, domain, or store-name availability check has been performed. Naming does not
determine the repository layout, bundle identifier, or final distribution strategy.

## Next blocker and proof

The next implementation blocker is a shared task/session/question contract and a verified
initial agent integration. Define identity, workspace ownership, explicit outcomes, pending
questions, restart recovery, and capability discovery before freezing snapshot/jobs/events.
The terminal renderer, initial provider, repository layout, minimum OS, evidence storage,
and final name remain open choices.

Recommended bounded proof: start one isolated task through a managed entry point, display
its output, answer an identified question, close/reopen its view, and continue from the other
surface without duplicate execution. Also represent an external checkout with no accessible
session honestly. Run the separate reconciliation exercise described in the findings note.
These are proposed checks, not completed implementation or tests.
