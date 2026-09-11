# Dev Desk — macOS app design prompt

Design a polished native macOS application for developers who manage projects and work with
multiple coding agents. Use **Dev Desk** as the editable working name. The final name is
undecided. Produce a coherent, interactive product design that can guide a later SwiftUI/AppKit
implementation. This is a design assignment, not a request to build a production agent runner.

This prompt is self-contained. Use the concrete choices below for the prototype; choices
explicitly called provisional are design assumptions, not final product decisions.

## Product purpose

Dev Desk brings together project understanding, investigation, planning, implementation,
verification, and human decisions. It is the desktop companion to **dev-skill**, a family of
developer workflows already available through coding agents and a CLI.

Make the relationship between a task, its requirements, branch, agents, evidence, and decisions
the defining experience. A developer should immediately understand what is happening, why it
is happening, what needs their attention, and how to continue the work.

Git and GitHub provide repository and work-tracking facts. The app presents them alongside
agent activity and durable project knowledge. A generated answer does not automatically
become a confirmed finding, an approved plan, or a completed task.

## Platform and visual direction

- Design for native macOS, with a real window title bar, familiar toolbar controls, resizable
  split views, contextual menus, keyboard navigation, and appropriate sheets.
- Use one independent window per project. Multiple projects are separate windows, not a row
  of project tabs and not a project list permanently occupying the sidebar.
- Use system typography appropriate for Mac, with monospaced type reserved for terminals,
  code, paths, and revisions. Use platform-style symbols and clear sentence-case labels.
- Establish a restrained light and dark palette with a cool blue accent. Use color to convey
  selection or meaningful status; pair status colors with text or icons.
- Make the task-and-agent workspace the distinctive visual element. Keep surrounding chrome
  calm, with useful density, careful alignment, and clear separation of navigation and content.
- Prefer lists, split views, and inspectors where they suit the information. Reserve cards
  for the Kanban board and content that benefits from grouping.
- Support a 1440 × 900 reference window and a compact laptop layout around 1100 × 720.
  Collapse optional inspectors and docks before making primary content unusable.
- Include visible keyboard focus, accessible contrast, reduced motion, and meaningful empty
  and error states. Animation should explain user-triggered changes.
- Write the prototype interface in English. Keep text and layout suitable for later localization.

## Project opening and window behavior

Provide an Open Project action and a recent-project picker with three entry paths:

1. Open an existing local folder.
2. Clone a Git repository.
3. Create a new local project.

Opening a project creates its own window; opening an already open project focuses that
window. Opening a folder does not launch an agent. Each project retains its own selected
task, chat, and pane layout. Closing a project window hides its views while managed work
continues; stopping execution is a separate, explicit action.

For a browser-based design prototype, simulate separate Mac windows and make the simulation
clear. Folder selection, cloning, commands, and execution must use sample state only.

## Main project navigation

Use these five sidebar destinations:

| Destination | What the developer does there |
|---|---|
| Board | See tasks, progress, dependencies, and next actions |
| Roadmap | Explore and organize future work, priorities, milestones, and epics |
| Findings | Run Survey and review its results against existing issues |
| Decisions | Answer pending questions and inspect prior decisions |
| Settings | Manage preferences, connections, defaults, and project overrides |

Use **Board** for this prototype because it includes backlog. **Active Board** remains an
alternative name for discussion. A task is the underlying work item; the board is a view.

Place **Ask about this project** in the toolbar. It opens the Insights conversation described
below. Do not add a second Findings destination called Survey or rename Findings to Insights.

## Board and task workspace

Use Kanban columns that distinguish queued work, work in progress, review, and completed work,
with a clear backlog filter or area. Treat these as prototype labels pending the repository's
actual status mapping. Do not imply dragging a card alone proves implementation or review.

Each task card shows a concise goal, issue reference, agent state, and any blocking decision
or dependency. Avoid filling every card with every available technical field.

Selecting a task opens its workspace with:

- A header with the goal, issue, branch, execution state, and relevant next action.
- Four detail tabs: **Activity**, **Requirements**, **Changes**, and **Evidence**.
- A compact agent list showing the primary agent and supporting agents.
- A resizable **Agents & Terminals** dock, with bottom and side placements.
- **Focus** and **Parallel** viewing modes.

Requirements includes acceptance criteria. Changes includes changed files and a readable
diff. Evidence shows checks and results with their limitations. Activity shows meaningful
events and expandable tool details. Pipeline progress may appear here without requiring a
separate top-level Map destination.

Parallel mode lets the developer observe multiple independent tasks in the same project.
Each task has its own requirements, branch, isolated checkout, and primary agent. Keep
dependencies visible; running tasks in parallel does not guarantee their changes integrate.

## Agent and terminal interaction

A terminal is a view of execution, not the identity of a task. Opening another view must
not appear to launch a duplicate agent. Offer output panes side by side or stacked.

Represent three different agent capabilities honestly:

| Capability | Appropriate interaction |
|---|---|
| Interactive session | Open terminal and send input when supported |
| Activity-only helper | View progress and request follow-up through the coordinating agent |
| Completed helper result | Read evidence/result and request a follow-up assignment |

Use actions such as **Open terminal**, **View activity**, **Continue**, **Stop**, and
**Request follow-up** only where meaningful. Do not render every helper as an independently
resumable terminal. Distinguish running, waiting for input, blocked, ended, failed, and stopped.

Show both managed work and **Connect existing work**:

- Managed work can start through the app or CLI and be discovered from the other surface.
- Connecting external work preserves its checkout, branch, and uncommitted changes.
- Some external work supports repository tracking only; some supports session continuation;
  some supports a live connection. Show available actions rather than promising all three.
- **Attach** opens a view of a running session; **Continue** resumes an ended session when
  supported; **Start with handoff** creates a new session from task artifacts.
- A handoff is visibly a new session, including when changing providers.

## Findings: the Survey surface

Findings is where the developer launches Survey, selects previous survey runs, and reviews
the results. Survey is the process; findings are its outputs. Insights chat remains separate.

A finding displays the observed problem, source locations, inspected revision, verification
limits, and links to candidate or existing issues. Distinguish code inspection from runtime
reproduction. Provide filters such as New, Known with new evidence, Needs a decision, and
Previously closed or declined.

Design a comparison view for reconciling a finding with an existing issue:

- Same problem: link the finding and propose adding new evidence.
- Related but independent problem: keep separate with a relationship.
- Possible duplicate: compare scope and evidence before choosing a canonical issue.
- Closed issue: inspect possible recurrence; closure alone does not establish a fix.
- Previously declined work: show the earlier reason.
- Unconfirmed observation: retain it without presenting it as a confirmed issue.

Several findings can support one issue. Repeated surveys should preserve history without
creating repeated tickets. Show unavailable search separately from an empty result. Make
proposed tracker updates reviewable; do not simulate silent issue creation on opening a view.

## Roadmap and Decisions

Roadmap contains considered ideas and committed work. Show features, improvements, and
critical concerns, with work type, priority, and commitment as separate properties. Group
work into themes, milestones, and epics, linking to Board tasks instead of duplicating them.
An urgent confirmed defect can enter the Board directly with its roadmap context retained.

Other repositories may become reference sources later; do not invent a cross-project work
aggregator or automatic competitor-feature import in this design.

Decisions has **Needs attention** and **History** views. A decision shows its question,
task, evidence, options, and chosen answer with rationale. Questions can occur outside formal
pipeline gates. Include a changed-context state explaining why an old answer needs review.
Do not expose internal question IDs or protocol fields as ordinary product UI.

## Insights as a floating project conversation

Design a nonmodal chat panel opened from **Ask about this project**. It can float within the
project window or dock beside the workspace. The developer can still inspect the board,
changes, and terminal. Closing and reopening the panel preserves the conversation.

The panel includes:

- Project and workspace context, plus an optional selected task, finding, or file attachment.
- Visible, removable context attachments and an agent/model selector.
- Conversation history, a composer, and a clear indication when the agent is reading evidence.
- Answers with navigable source references.
- Contextual actions such as **Run survey**, **Explore roadmap**, or **Save project knowledge**.

Use the dev-skill Insights behavior: answer from evidence, route specialized work to its
own workflow, and retain only durable, supported knowledge in PROJECT_MAP.md within the
user's authorization. Do not save all chat as project truth or label chat speculation as a
verified finding. Keep the primary interaction simple; source details can expand on demand.

Project exploration starts read-only. An implementation request creates or continues scoped
work through the appropriate workflow. Asking about the project does not silently steer a
currently coding agent. **Continue task conversation** explicitly targets that task session.

## Agent connections and settings

Support the design of a user-selectable agent connection, with an app default, project
override, and explicit conversation selection. Codex, Claude, and Gemini are possible
providers; the first production integration has not been selected or validated.

Use Codex as a sample connected agent, Claude as another example, and Gemini as an available
connection concept. Label these as illustrative prototype states, not claims about installed
tools or completed integrations. Do not hard-code model-version names or prices.

Settings groups:

- General: startup and window behavior.
- Appearance: system/light/dark, density, and terminal typography.
- Agents and Defaults: preferred connection and available model choices.
- Accounts and Connections: GitHub and supported agent authentication, connection state.
- Notifications: decisions, completion, and failures.
- Execution: workspace placement and relevant run defaults.
- Project overrides: branches, environments, and checks inherited from repository settings.

Show the selected connection's capabilities. Do not assume all providers have equivalent
resume or attachment behavior. Do not promise consumer subscriptions cover direct API usage.
Changing providers must never silently replace the current conversation's identity.

## Sample project content

Use a project called **StudyHub** with these illustrative tasks:

| Task | State and content |
|---|---|
| #42 Preserve course-list position | Running with a primary Codex agent, an activity-only reviewer, and a verifier result |
| #57 Improve exam recovery | Waiting for an architecture decision with a Claude session |
| #63 Investigate slow lesson search | Connected external checkout with repository tracking only |

For #42, the user report says returning from a lesson resets scroll position. A Survey
finding identifies related navigation code and proposes attaching evidence to #42. Mark it
as code-inspected rather than reproduced. Use realistic illustrative paths and label all
sample evidence as demo content.

Include a second project window called **dev-skill** to demonstrate project independence.

## Required output and prototype coverage

Deliver a short design rationale, compact design tokens, component inventory, and an
interactive prototype or linked high-fidelity screens. Prioritize the task workspace,
agent dock, and Insights panel; develop the other destinations consistently.

Make these flows inspectable:

1. Open a project in its own window and restore it without starting duplicate work.
2. Open #42, inspect requirements/changes/evidence, and compare two agent outputs.
3. Switch between Focus and Parallel views.
4. Open an activity-only helper and request follow-up through its coordinator.
5. Review and answer #57's pending decision.
6. Inspect #63's limited connection and offer an explicit handoff.
7. Compare a Survey finding with #42 and preview the proposed evidence update.
8. Open, dock, close, and reopen Insights while retaining its context.
9. Explore a cited answer and a proposed workflow handoff from chat.
10. Inspect Roadmap, decision history, and agent settings.

Include empty-project, disconnected-agent, unavailable-GitHub, failed-run, and stale-decision
states. Critical controls should have meaningful prototype behavior. Keep demo actions local:
do not start real agents, modify repositories, create issues, or send network requests.

End with the unresolved design choices and the smallest implementation slice suggested by
the prototype. Keep terminal transport, backend architecture, and provider compatibility
notes in the handoff documentation rather than ordinary user-facing screens.
