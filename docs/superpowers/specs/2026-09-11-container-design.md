# The container: one place that holds the whole family

**Date:** 2026-09-11 · **Status:** draft for review · **Decides:** the system model, the CLI contract a
shell consumes, the first shell (a native Mac app), and where it lives.

**Discussion follow-up:** [Findings and existing issues](2026-09-11-findings-and-existing-issues-design.md)
records the accepted reconciliation direction and the remaining design questions. The job-state
protocol below remains a draft proposal; see the follow-up before implementation. §5's repository
recommendation is no longer open — see "Deliverables A and C landed together," below.

**Accepted entry paths:** [App and CLI task continuity](2026-09-11-app-cli-task-continuity-design.md)
records support for both managed starts and connecting external work, with capability-specific
session continuation and a proposed model for isolated parallel tasks.

**Latest UI discussion:** [Mac app navigation and Insights](2026-09-11-mac-app-navigation-and-insights-design.md)
records the Findings/Survey clarification, proposed navigation and floating chat, provider
options, settings, naming, and remaining blockers. Dev Desk is a working name, not a final choice.

**Accepted platform (2026-09-11):** the maintainer chose a native Mac desktop app after comparing
it with a cross-platform desktop app. This settles the first shell's platform; the runtime contract,
terminal integration, and minimum OS version remain design details to resolve.

**Deliverables A and C landed together (2026-09-11):** §7 planned deliverable A
(`documentation/SYSTEM-MODEL.md` and `docs/arch/dev-system.*`) and deliverable C (the Mac shell)
as separate PRs. Both ship in this one PR at the developer's request — see §7. The repository
layout question below is settled too: one repo, `apps/desk/` (ADR 0012), with the app's first real
reads specified by ADR 0013.

## 1. Why

The family has an engine (22 doors, 17 phases, 4 gates), a truth (git + GitHub), a memory
(`PROJECT_MAP.md`, ADRs, reports, `.dev/` checkpoints) and helpers (the `dev` CLI, four hooks).
What it lacks is the place that holds them: to answer "where are we?" today you read terminal
output, `.dev/ui/*.html`, the GitHub board, the family diagram and a PR body, and assemble the
picture yourself. Nothing shows *what is happening right now*, and nothing lets you start a door
and watch it reach a gate. That is the missing container. It is a cockpit, not another tool.
(`.dev/ui/*.html` was retired 2026-09-11, ADR 0014.)

## 2. System model

Five layers. Each lower layer is authoritative over the one above it.

| Layer | Holds | Written by |
|---|---|---|
| **Truth** | branches, commits · issues, milestones, epics, PRs | git · GitHub, through the doors |
| **Memory** | `PROJECT_MAP.md`, `docs/adr/`, `docs/{survey,ideation}/<date>.md`, `.dev/<branch>.json` | Phase 10/12, `dev:insights`, `dev state checkpoint` |
| **Engine** | the 22 doors, `shared/pipeline.md` (17 phases), 4 human gates: 5 discuss · 6 architecture · 14 merge · 16 prod | prose, executed by `claude` / `codex` |
| **Helpers** | `dev` CLI: `board · state · ui · run · project · doctor` (`ui` retired 2026-09-11, ADR 0014) · hooks: branch-guard, pr-gates, teardown, context-load | `scripts/dev.py`, `hooks/` |
| **Container** | project windows, work views, decisions, chat, and agent outputs | **new** |

**The container does not own repository or tracker truth.** It reads through the shared contract
and acts through the skill/runner or bounded board operations, never by reading its screens back.
The app may own preferences and view state; the shared runner must own execution/session state.
Their persistence contract remains open. This refines the original "owns no state" wording.

### The five jobs of the container

These are original capability groupings, not the latest sidebar labels.

| Job | Answers | Reads | Acts through |
|---|---|---|---|
| **Home** | what is running, what waits on me, what is next | `snapshot.runs`, `.jobs`, `.inbox`, `.board.queue` | — |
| **Map** | where each run sits in the 17 phases | `snapshot.runs[].phase` | — |
| **Tracker** | board · roadmap · ideation · insights | `snapshot.board/roadmap/reports/insights` | `dev board move`, `dev jobs start create-issue` |
| **Launcher** | start a door on an issue, watch its log | `.dev/jobs/<id>.log` | `dev jobs start / stop` |
| **Inbox** | gate questions waiting for my answer | `snapshot.inbox` | `dev jobs answer` |

## 3. The contract (`scripts/dev.py`, this repo)

JSON on stdout, non-zero exit on failure, stderr for the reason. Four additions to the CLI.

### 3.1 `dev snapshot --json`

One document per repo, replacing four separate reads:

```json
{ "contract": 1, "repo": "owner/name", "base": "main", "head": "5daa610…", "generated_at": "…",
  "board":    { "active_milestone": "v2", "active_why": "…", "columns": {…}, "epics": […] },
  "roadmap":  { "milestones": […], "epics": […] },
  "reports":  { "survey": […], "ideation": […] },
  "insights": { "sections": […] },
  "runs":     [ { "branch": "feature/x", "issue": 12, "phase": 9, "phase_group": "coding",
                  "phases_completed": [1,2,3,4,5,6,7,8], "head_sha": "…", "updated_at": "…" } ],
  "jobs":     [ { "id": "j-0007", "door": "dev", "args": ["#12"], "agent": "claude",
                  "status": "waiting", "branch": "feature/x", "session": "…",
                  "started_at": "…", "log": ".dev/jobs/j-0007.log" } ],
  "inbox":    [ { "job": "j-0007", "gate": 6, "asked_at": "…",
                  "question": "Two architectures fit …" } ] }
```

Any surface that cannot be read says so in place (`"board": {"unavailable": "gh not authenticated"}`)
— an auth failure and an empty tracker must never render the same. `runs` are advisory, as
everywhere: git wins any disagreement, and the shell shows the phase with the same `· advisory`
mark the board uses.

### 3.2 `dev jobs`

**Draft command shapes, not a validated protocol.** The original checkpoint-derived outcome
rules were rejected in review. Explicit task outcomes and identified questions must replace
them before these commands are implemented; see the continuity and reconciliation notes.

| Verb | Does |
|---|---|
| `start <door> [args…] [--agent claude\|codex]` | spawns the door detached: `claude -p --output-format stream-json --verbose "<prompt>"` or `codex exec --json "<prompt>"`, the same prompt `dev run` builds today. Writes `.dev/jobs/<id>.json` and streams stdout to `.dev/jobs/<id>.log`. Returns the job. |
| `list` · `show <id>` | the job records; `show` adds the tail of the log |
| `stop <id>` | SIGTERM the process group; status `stopped`; log kept |
| `answer <id> "<text>"` | `claude -p --resume <session> "<text>"` / `codex exec resume <session> "<text>"`, appending to the same log; status back to `running` |

**Outcome requirements:** distinguish process exit, end of turn, waiting for input, blocked
work, completed work, failure, and explicit stop. Exit zero does not establish completion,
including for doors without checkpoints. Current checkpoint writes include the phase in
`phases_completed`, so the originally proposed incomplete-gate test cannot identify waiting.
Questions also occur outside the four gates. Identify each question and its validity context;
reject duplicate resumes and stale answers. Provider session IDs and resumability must be
verified independently of branch state. The exact event/state schema remains open.

"Convert this ideation finding into a task" is `dev jobs start create-issue "<finding text>"`: the
judgment stays in the door, the shell only starts it.

### 3.3 `dev events --follow`

NDJSON, one object per line, until the client closes the pipe. Watches `.dev/` (state files, jobs)
by polling mtimes every second — stdlib only, no fsevents dependency — and emits:

```
{"type":"run.phase",  "branch":"feature/x","phase":9,"phase_group":"coding"}
{"type":"job.status", "id":"j-0007","status":"waiting"}
{"type":"inbox.new",  "job":"j-0007","gate":6,"question":"…"}
{"type":"job.log",    "id":"j-0007","line":"…"}          # only with --logs
```

GitHub changes without a commit and without a file, so a shell re-runs `snapshot` on a timer (30 s,
and immediately after any of its own writes) for the board and roadmap. Events are for what
happens on this machine; the timer is for what happens on github.com.

### 3.4 `dev board move <N> --to queue|backlog|cancel [--reason "…"]`

The `plan_board_move` the served board already uses, as a CLI verb, so the shell and the browser
run the identical bounded write. Same refusals: git-derived columns, epic cancels, delete, a
cancel with no reason.

**Retired 2026-09-11, ADR 0014:** the served board and `plan_board_move` were deleted with
`/dev:ui`, so this verb would re-add the planner rather than wrap it.

### 3.5 What the contract deliberately does not offer

- No `delete` — 7.2's hard gate needs a conversation, and `dev:board` has it.
- No "run through the gates" flag. The four gates are why the pipeline is trusted.
- Runner metadata must have a defined owner and location. Skill-authorized project edits and
  GitHub writes retain their existing scope; `.dev/` is not the only output of a skill run.
- No unsupported agent capability exposed as working. Gemini's official headless interface
  is now documented in the latest discussion; no Gemini adapter is implemented or validated.

## 4. The first shell: dev-desk, a native Mac app

**Platform accepted; implementation proposed:** a native macOS app, using SwiftUI with AppKit
where needed. The maintainer chose the Mac app after comparing it with a cross-platform desktop
shell, with Swift and Xcode already identified as the maintainer's tools. macOS 14+ remains a
proposed minimum pending terminal and dependency validation. The first build already ships macOS
14 as its floor (`apps/desk/DeskCore/Package.swift`, `apps/desk/project.yml`); that can still move
if terminal or dependency validation forces it.

The design includes task-oriented terminal views, notifications, and a menubar badge. Terminal
rendering and session transport require separate validation; no terminal library is selected yet.
The app and CLI should use a shared runner independent of the app window lifecycle, as proposed
in the task-continuity note. Existing CLI/browser surfaces remain available where supported (the
browser pages were retired 2026-09-11, ADR 0014);
agent choice does not determine whether the Mac app can be used.

The table below is historical, not the current navigation specification. The latest UI note
proposes Board, Roadmap, Findings, Decisions, and Settings with project chat and an agent dock.
Separate project windows supersede the repo sidebar below; process management must follow the
shared runner contract rather than the lifecycle of an individual window.

| Part | Behaviour |
|---|---|
| **Sidebar** | the repos you have added — the only thing the app stores itself (UserDefaults). One repo = one boundary; there is no cross-repo board. |
| **Home** | three lists from the snapshot: RUNNING (jobs + their run phase), WAITING (inbox), NEXT (board QUEUE, then ordered BACKLOG). |
| **Map** | the 17 phases as a track, four gates marked, one marker per run at `runs[].phase`; a job's marker pulses while `running`. Data-driven, drawn in SwiftUI; the Archify diagram stays the documentation picture. |
| **Tracker** | board (drag → `board move`), roadmap, ideation (each finding has *Make task*), insights (folded sections) — the same four surfaces as `.dev/ui`. |
| **Jobs** | the log viewer: stream-json rendered as turns, tool calls collapsed; *Stop*. |
| **Inbox** | the gate question, the run's branch and issue, an answer box → `jobs answer`. |
| **Menubar extra** | badge = inbox count; `inbox.new` posts a native notification with the question's first line. |
| **Process layer** | one `Process` per `dev …` call; one long-lived `dev events --follow` per open repo, reconnected if it dies. `dev` is found on `PATH` or at `~/.claude/skills/dev/scripts/dev.py`. |

Errors are shown where they belong: a surface's `unavailable` reason in that panel, never a blank;
a job that died with no state change becomes `failed` with its log one click away; `dev` missing
shows the `install.sh` line.

## 5. One repo or two

**Decided 2026-09-11: one repo — ADR 0012.** The recommendation below was two repos; the developer
chose the opposite. The table and its reasoning stay as the record of the rejected option — see the
ADR for why it lost, measured rather than assumed.

The app is a client of the contract. The question is whether it lives beside the contract.

| | **Two repos** — this repo (then named `dev-skill`) + `dev-desk` | **One repo** — `apps/desk/` in `dev-desk` |
|---|---|---|
| Skill install (`install.sh` symlinks the clone) | prose + one Python file | the same **plus the Xcode project**, in every user's `~/.claude/skills/dev` |
| A UI-only change | a dev-desk commit; the skill is untouched | bumps the skill; every install pulls it |
| A contract change | **two PRs that must agree** (CLI here, app there); the app pins a minimum `dev` version and `dev snapshot` reports `"contract": 1` | one PR, one diff, one review |
| CI | unchanged here; Xcode build there | `line-budget` and the test runner must skip `apps/`; add an Xcode job |
| Reading the whole system | two places; the spec and system-model page here point at the app | one place |
| Licence / publishing (still open) | the app can be public before the skill is | one decision for both |
| Fits the family's own rule "keep the thing beside what it enforces" | the *contract* is beside the CLI, which is what the rule is about | also true, and the diagram + hooks precedent points here |

**Recommendation: two repos.** The deciding cost is the first row — every user's skill install would
carry an Xcode project they never build — and the second: a skill that bumps when a button moves
is a skill people stop updating. The price is the matching-PR row, and it is paid with a contract
version number that both sides check. Revisit if the app turns out to change in lock-step with the
CLI on most PRs.

## 6. Testing

- **Contract, here:** stdlib `unittest`, one file per verb. Agents are a fake `claude`/`codex`
  script on `PATH` that emits canned stream-json and exits at a chosen phase, so `waiting` /
  `done` / `failed` are each pinned. A fixture `.dev/` drives `events`. The snapshot tests write
  their documents to `test-projects/state/fixtures/snapshot-*.json`.
- **App:** XCTest decodes those same fixture files, so both sides test the same documents; a UI
  test drives one drag against a fake `dev` on `PATH`.

## 7. Order of work

| | Deliverable | Repo |
|---|---|---|
| A | `documentation/SYSTEM-MODEL.md` (section 2 as a page) + `docs/arch/dev-system.*` rendered with `dev:arch` | dev-desk |
| B | `snapshot`, `jobs`, `events`, `board move`, `"contract": 1`, tests; the `/dev:ui` and `dev:board` doors learn the verbs (`/dev:ui` retired 2026-09-11, ADR 0014) | dev-desk |
| C | Mac shell: project windows, Board, task details, agent outputs, Decisions, then remaining views from the latest UI note | `dev-desk` (`apps/desk/`, decided — ADR 0012) |

Each was planned as its own PR. **A and C shipped together in one PR, at the developer's
request** — this branch carries the system-model page and diagram (A) alongside the first Mac
shell build (C), reading sample data plus real git/GitHub for opened folders (ADR 0013) rather than
waiting on B. B — `snapshot`, `jobs`, `events`, `board move` — remains unbuilt and its own PR,
whenever it lands.

## 8. Non-goals

No competing repository/tracker truth in the app. No delete. No unattended run through the gates.
No cross-repo views in the first shell. No unverified provider capabilities. No Rust: it was considered
for the shell (Tauri) and declined for now because it adds a toolchain the maintainer does not have,
for a portability the first user does not need; the contract is shell-agnostic, so a Tauri shell can
be added later without touching this repo.
