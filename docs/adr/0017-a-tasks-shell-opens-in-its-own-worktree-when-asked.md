# 0017 — A task's shell opens in that task's own worktree, and only when asked

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `feat/desk-embedded-shell`

## Context

In the pipeline, each task gets its own branch (`gh-{N}-{slug}`, `shared/pipeline.md` Phase 3) and
its own `.dev/<branch>.json`. A branch is a name, not a folder, and one checkout shows one branch at
a time. So for every task's shell to sit in its own branch at once, each task needs its own folder,
which git calls a worktree.

Until now, cloning and creating a project were Dev Desk's only writes (ADR 0013), and reading a
repository never ran a program that repository controls. That second property is the hardening
that #50 to #53 built.

## Decision

**The folder rule**, applied in this order:
1. **Reuse the worktree where the branch is already checked out.** It is found with
   `git worktree list --porcelain -z`, read with the hardened flags.
2. **If no worktree has the branch, create one** with `git worktree add` at
   `<worktree location>/<project>-<N or branch slug>`. An existing path is never reused.
3. **A task with no branch opens at the project root.** Dev Desk never cuts a branch. The pipeline
   cuts it at the first write.
4. **If creating the worktree fails,** the shell opens at the project root, with git's reason.

**Nothing runs until the user clicks Start shell.** Before the first start, the Shell tab says:
*"Starting a shell runs your login shell and git in this repository, as Terminal would. Only start
one in a repository you trust."* This is where trust changes. Reading a repository never runs its
code. Starting a shell there is the user deciding to work in it.

`git worktree add` runs with the same hardening flags as the reads: hooks, fsmonitor, external diff
and signature programs are all off. New worktrees go in the worktree location from Settings →
Execution (default `~/.devdesk/wt`), a setting that did nothing until now.

## Rejected

- **Always open at the project root.** The shell would sit on whatever branch the checkout has, not
  the task's branch, and two tasks' shells would share one branch.
- **Cut a branch for a task that has none.** The pipeline cuts branches at the first write, and for a
  feature only after Phase 5's go-ahead. Dev Desk cutting them first would contradict it.
- **Start shells automatically when a task opens.** A user's prompt usually runs `git status`, which
  in a hostile checkout runs that repo's fsmonitor. That is exactly what the reader is hardened
  against. Auto-start arrives in step 2 as an explicit Auto mode, with a warning.
- **Put worktrees inside the project, in `.worktrees/`.** They would show up as untracked files in
  the user's checkout unless ignored, and Dev Desk never touches a repo's own `.gitignore`. `.dev/`
  follows the same rule.

## Consequences

- **Dev Desk now writes into a user's repository beyond clone and create.** Each new worktree adds an
  entry under `.git/worktrees/` and a folder under the worktree location. Dev Desk doesn't remove
  them. `git worktree remove <path>` does.
- **A repository's checkout filters (smudge or process) run during `git worktree add`,** as they would
  during any checkout. Flags can't turn off filters whose names are unknown. This falls inside the
  trust line above: the user chose to work in this repository.
- **Worktrees made by other tools are reused, not duplicated,** because rule 1 reads git's own list.
  That covers Superconductor and a hand-run `git worktree add`. Those tools, in turn, don't know
  about the worktrees Dev Desk creates.
- **Sample projects have no folder,** so their docks keep the demo transcripts.
- **The Execution setting now does something.** The Notifications settings still do nothing
  (PROJECT_MAP ORPHANS & PENDING).
