---
name: launch-kill
description: >
  STOPS this project's local servers — the inverse of `dev:launch`, and a door into the same
  discovery. Resolves the project's port exactly as `dev:launch` does, PROVES each listener belongs
  to this worktree before touching it, then kills the whole process tree from the top so the launch
  script's traps fire — not merely the PID holding the port, which is what leaves orphaned
  background workers behind. Then sweeps workers the project's own launch script names that earlier
  runs orphaned (PPID 1).
  NEVER kills by port number alone (a port is not a project), never pattern-kills machine-wide
  (`pkill -f "next dev"` crosses projects), never touches anything outside the current worktree, and
  leaves shared infrastructure — Docker, a local Supabase stack — running and reported.
  Trigger on: "kill the dev server", "stop the server", "kill all servers", "free the port",
  "shut down the app", "stop the dev environment", "kill whatever is on 3007", "port already in use",
  "clean up the servers".
allowed-tools: [lsof, ps, kill, pgrep]
---

# launch-kill — stop this project's servers

The inverse of `dev:launch`. A **tool**, not a phase: it reads none of `shared/pipeline.md`.

`launch` finds the project and starts it; this finds it **the same way** and stops it. Everything
below is only what killing adds.

**Why it exists rather than `lsof -ti:$PORT | xargs kill`:** that command cannot tell whether the
process is yours, and it kills a leaf. Both are the whole job here.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| Bare integer (`3007`) | This port only; skip discovery | Discover |
| `dry` | Print every verdict, kill **nothing** | Kill |

## Phase 2 — Resolve the boundary — *point, do not restate*

Read `skills/launch/SKILL.md` and use, unchanged:

| From `dev:launch` | For |
|---|---|
| **2.0** | the three resolution rules — installed ≠ reachable · never report absence without your search path · prefer a declaration over a guess |
| **2.1** | `$PROJECT_ROOT` — worktree-safe, `git rev-parse --show-toplevel` first |
| **2.6.2** | the launch script — Phase 5 needs it as the manifest of what a launch spawns |
| **2.2a** | the project's DECLARED entry points (all platforms) — the stop entries live here, so this skill does not guess that filename either |
| **2.6.3** | the port, in its order: arg → dev-script flags → launch script → framework default |
| **2.5.3** | the 8000–8999 static-server range, for servers `launch` 3E started |

**Do not restate that logic here.** Two copies drift, and a drift means killing the wrong port —
or worse. `$PROJECT_ROOT` is not a hint here as it is in `launch`; it is the *only* thing standing
between this tool and the rest of the machine (Phase 3). If discovery is wrong, fix `dev:launch` —
both read it.

> **2026-08-05 — why this points instead of copying.** `launch` 2.1 tested `[ -d "$dir/.git" ]`,
> which is false in a worktree because `.git` is a file there. Measured from a real superconductor
> worktree, it resolved `$PROJECT_ROOT` to **`/`**. For `launch` that means searching the filesystem
> root; for *this* tool `owns()` would then return true for **every process on the machine**. Fixed
> once, in `launch` 2.1, for both. A copy here would have kept the loaded gun.

`$PROJECT_ROOT` is the **current worktree**, and it is a hard boundary. Sibling worktrees of the
same repo are not this project; additional working directories are not this project. If discovery
finds no project, **say so and stop** — never fall back to `$PWD`.

## Phase 3 — Prove ownership BEFORE killing anything

A process's cwd is the oracle:

```bash
owns() {   # 0 if pid $1 has its cwd inside $PROJECT_ROOT
  cwd=$(lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  case "$cwd" in "$PROJECT_ROOT"|"$PROJECT_ROOT"/*) return 0 ;; *) return 1 ;; esac
}
```

Judge every holder of every resolved port (`lsof -nP -iTCP:$PORT -sTCP:LISTEN -t`):

| Verdict | Action |
|---|---|
| cwd inside `$PROJECT_ROOT` | **In scope** — kill it. You invoked this; that is the authorization |
| cwd anywhere else | **Report and leave that port alone.** Print pid, cwd, command |
| no holder | Report the port already free |

No ask-gate — the rule is deterministic. Its entire safety is that this phase runs **before**
Phase 4, never after.

## Phase 4 — Kill the tree, from the top

The port holder is a leaf, and a deeper one than it looks. Measured on a real Next app 2026-08-05: the
listener on `:3007` was `next-server`, a **child of `next dev`**, six levels below the chain root.
Killing it leaves `railway run`, two shells, `npm`, `node` and `worker.py` up — the port frees for a
moment and the app is still half running.

**4.1 — Climb** while the ancestor is owned **and is not a harness or interactive shell**
(`*shell-snapshots*`, `-zsh`, `-bash`, `-sh`, `login`, `Code Helper`); stop at PPID ≤ 1.

> Ownership is the right test for *whether* to kill and the wrong one for *where to stop climbing*.
> The shell that started the server usually has its cwd in the project too — on 2026-08-05 the
> parent of `railway run` was a Claude Code `zsh -c` whose cwd was `$PROJECT_ROOT`. Climbing on
> ownership alone kills the session that launched the app. The command test is what stops it.

**4.2 — snapshot, `kill -TERM` the root, poll, then reap.** SIGTERM so the launch script's own
`trap … EXIT INT TERM` unwinds its children; SIGKILL first skips every trap and manufactures the
orphans this tool exists to clear.

```bash
descendants() { for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; descendants "$c"; done; }
KIDS=$(descendants "$ROOT")            # BEFORE the kill — see below
alive() { { echo "$ROOT"; echo "$KIDS"; } | while read -r p; do
            [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo "$p"; done; }

kill -TERM "$ROOT" 2>/dev/null         # rung 1: the root relays, if it relays at all
i=0; while [ $i -lt 3 ] && [ -n "$(alive)" ]; do i=$((i+1)); sleep 1; done

if [ -n "$(alive)" ]; then             # rung 2: TERM the members directly, so INNER traps fire
  alive | while read -r p; do owns "$p" && kill -TERM "$p" 2>/dev/null; done
  i=0; while [ $i -lt 7 ] && [ -n "$(alive)" ]; do i=$((i+1)); sleep 1; done
fi
{ echo "$ROOT"; echo "$KIDS"; } | while read -r p; do
  [ -n "$p" ] || continue
  kill -0 "$p" 2>/dev/null || continue
  owns "$p" && kill -KILL "$p" 2>/dev/null
done
```

**Snapshot the descendants BEFORE the SIGTERM.** Deriving them afterwards finds nothing: the moment
the root dies its grandchildren reparent to init, and `pgrep -P` can no longer see them. This is the
same ordering `dev.sh`'s own trap needed.

> **2026-08-05 — the snapshot is the mechanism, not the safety net.** Measured end to end: SIGTERM to
> the chain root was **swallowed**. The root was `railway run`, which does not forward the signal to
> its `sh -c` child, so the launch script's trap never ran, the poll burned its full 10s budget, and
> all six processes died by SIGKILL from the reap. Zero orphans — but only because the snapshot
> existed. **Do not count on the trap firing.** A wrapper that does not forward signals (`railway`,
> some `docker` and `npx` shims) turns the reap into the primary path. Sending SIGTERM to the
> snapshot members too, before escalating, gives inner traps their chance without depending on the
> root to relay it.

**Poll; do not `sleep 2` once.** A tree whose launch script has a *buggy* trap is exactly the case
this tool exists for, and those take longer than a fixed guess to settle.

**Re-check `owns` before each SIGKILL** — PIDs recycle inside that window.

> **Run these under `sh`/`bash`, not `zsh`.** zsh does not word-split parameter expansions, so a
> plain `for p in $KIDS` iterates **once** with the whole list as a single bogus pid — every `kill`
> silently fails and every `kill -0` returns "gone". Observed 2026-08-05: that shape reported three
> orphans killed while all three were still running. The `echo | while read` form above is correct
> in both shells.

## Phase 5 — Sweep the orphans

Only when Phase 2 found a launch script — no script, no spawned children, nothing to leak.
Candidates are **PPID 1 and owned**. Keep one only if a `basename` of its command tokens satisfies
**both**:

1. it **names a script file** — `.py` `.js` `.mjs` `.cjs` `.ts` `.sh` `.rb` `.php`; and
2. it appears **verbatim** in the launch script.

> **Rule 1 is the safety of this phase, not tidiness.** Matching any token in the script also
> matches the *wrappers* — `railway`, `npm`, `uv`, `docker`, `supabase` — which appear in every
> command the project launches. An extension requirement excludes all of them by construction.
> **2026-08-05, caught by dry-running this phase before it shipped:** an agent's soak test
> (`railway run … hosted_build.py`) was live; had it been orphaned, `railway` appears at
> `dev.sh:90` and passed the first draft's only filter. The sweep would have killed another
> session's build and called it an orphaned worker.

Print the matched token and script line per orphan. A kill whose reason is invisible cannot be audited.

## Phase 6 — Verify — this is a GATE, not a report line

Re-check every port, then **re-run Phase 5**. If it still finds orphans, sweep again — up to three
rounds — and only then report. Report a non-zero final count as a **failure**, naming the survivors.

> **2026-08-05 — the first real run left an orphan, and this phase let it through.** Run against a
> tree started *before* `dev.sh`'s trap fix, `launch-kill` freed `:3007`, killed the whole launch
> chain and correctly spared both the soak test and Supabase — then left `worker.py` 67016 alive at
> PPID 1. Two faults stacked: 4.2 derived its descendant list *after* the SIGTERM (finding none),
> and this phase merely *counted* orphans instead of acting on the count. A tool whose job is
> clearing orphans must **converge**, not snapshot — especially since killing a tree with a buggy
> trap is what manufactures them.

**A running process holds the trap it was started with.** Fixing a launch script on disk does not
disarm an already-running one, so a server started before the fix still orphans its worker when
killed. Phase 5 is what covers that gap, which is why it must run to zero.

Then report:

```
## launch-kill: <project>            /path/to/<project>
Killed   :3007  tree of 7, rooted at 66434
         railway run → sh → { npm → next dev → next-server ; sh → worker.py }
Killed   orphan worker.py ×3   (PPID 1, matched "worker.py" at .vscode/dev.sh:112)
Left up  Docker / local Supabase :54321-54327  — shared across worktrees
Left up  :3000  node next dev  cwd=<another-repo>/web  — NOT this project
:3007 free · 0 orphaned workers
```

**The "left up" lines are the point, not filler** — an unreported survivor is the process still
running tomorrow, and this report is the only artifact the tool leaves behind.

**Name the project's own stop entries; run none of them.** 2.2a discovers them from
`launch.json`/`tasks.json` rather than guessing a filename, and they routinely sit next to a
**destructive** sibling — a real pair reads `⏹ Stop local` and `⏹ Stop local + WIPE database`, one
`--wipe` apart. Listing both is useful; picking one is not this skill's call. It stops servers, not
databases.

**Exit 143 is SUCCESS — say so before the user reads it as a crash.** `143 = 128 + 15` = terminated
by SIGTERM, i.e. Phase 4.2 worked. When the dev server was started by a harness-tracked background
command, that command's wrapper shell sits one level *above* the chain root (4.1 stops there), so it
survives the kill just long enough to report its child's status — and the harness renders it as
*"Background command … failed with exit code 143"*. Observed on the first real run, 2026-08-05.
A `137` there means SIGKILL: the trap never ran, so **check Phase 5 twice**.

## Never

- **Kill by port number alone** — `:3000` here is a different project's app.
- **Pattern-kill machine-wide.** 2026-08-05: a project's own `.vscode/stop.sh` did
  `pkill -f "next dev"`, which would have taken an UNRELATED project's `:3000` with it.
- **Touch anything outside the current worktree**, including a sibling worktree of the same repo —
  that usually means another live session. Report it.
- **Climb into a harness or interactive shell** (4.1).
- **Stop shared infrastructure.** Docker and a local Supabase stack are shared across worktrees.
- **SIGKILL first.**

## Known limits

| | |
|---|---|
| `case` treats `$PROJECT_ROOT` as a glob | A path containing `*`, `?` or `[` matches wrongly. None observed |
| A process that `cd`s out after starting | Reads as unowned, survives. cwd is a snapshot, not provenance |
| A sibling worktree holding this port | Reported, never killed — by design. Run this from that worktree |
| An orphaned **extensionless** binary (`./bin/worker`) | Not swept. A missed orphan is recoverable; a wrong kill is not |
| A root that sets `trap "" TERM` (`SIG_IGN`) | `SIG_IGN` is inherited across fork/exec, so the whole subtree ignores TERM and **rung 2 cannot help** — only the SIGKILL reap ends it. Verified 2026-08-05. Distinct from a root that merely fails to *forward*, where rung 2 works |
| Simulators, emulators, MCP debug Chrome | Out of scope — no port. Chrome is Phase 11 + `hooks/teardown.sh` |

## Scar tissue

**2026-08-05 — killing the port holder orphans the background worker.** Three `worker.py` processes
were found alive with PPID 1, started Aug 1, Aug 4 and Aug 4 — one leaked per dev session. All three
carried `DATABASE_URL=…127.0.0.1:54322`, the same local `build_jobs` queue as the live worker: four
consumers racing for the same jobs, three running code up to five days stale.

`.vscode/dev.sh` runs the worker in a `( … ) &` subshell and traps `kill $WLOOP`, where `$WLOOP` is
the **subshell**, not the worker. Killing the listener makes `npm` exit, which fires the trap, which
kills the subshell — and `worker.py` reparents to init and polls on. `lsof -ti:3007 | xargs kill`,
which `dev:launch` printed as its "Stop:" line until this tool replaced it, is exactly that command.

**The durable fix belongs in `dev.sh`** — trap the worker's own PID, or kill the process group. This
tool cleans up after the bug; it does not remove it.

**2026-08-05 — first real run.** It freed `:3007`, killed the 7-process chain, spared
the soak test and Supabase — and left one orphan, because 4.2 listed descendants *after* the kill
and Phase 6 only counted them. Both fixed above. A dry run had passed cleanly the same day: dry mode
never kills, so it cannot expose a defect that only appears *after* something dies. **A dry run is
not a run.**

**2026-08-05 — second run, end to end, clean.** Server started from the fixed `dev.sh`, then killed
by this tool with an unrelated project deliberately left running on `:3000` as a foreign control:

```
:3007 free · worker.py count=0 · no leftover chain
other project :3000 still up · supabase :54321 up
```

It also falsified the phase's own rationale: SIGTERM at the root was swallowed by `railway run`, the
trap never fired, the poll ran its full budget and SIGKILL did the work. Right outcome, wrong reason
— which is why 4.2 now TERMs the members directly before escalating.

**Proven:** Phases 3–6 end to end, the pre-kill snapshot, the ownership boundary (a live foreign
server survived), and the orphan sweep.

**2026-08-05 — rung 2, tested against both failure shapes.** Root that does not *forward* TERM
(the `railway` case): rung 1 left the children orphaned, rung 2 reached them directly, their own
traps fired and cleaned up — **no SIGKILL needed**. Root that *ignores* TERM via `trap "" TERM`:
useless, because `SIG_IGN` is inherited across fork/exec, so the whole subtree ignores it and only
the reap ends it. Both shapes end at zero survivors; they differ only in whether the shutdown is
graceful.

**Undated, therefore unproven:** the harness-shell stop list in 4.1 beyond the one `zsh -c` shape it
has met, and the extension gate on a project whose worker is not a `.py`.
