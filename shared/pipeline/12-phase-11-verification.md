## Phase 11 — Verification Gate (agent-run)

After implementation and commit, **pause** before pushing. Apply `verification-before-completion` — no claims without fresh evidence.

**The agent executes the checklist — the developer is no longer the test runner.** Build the table below, then RUN every row you can reach yourself against the live app:

- **Web:** Chrome DevTools MCP — drive the real flow (click/fill/navigate), read console + network per step, screenshot each end state. New/changed UI components get a screenshot per state variant (and per direction for RTL/LTR products).
- **Mobile:** launch via the `dev:launch` skill, then drive + capture per the platform pipeline file.
- Cover three row classes: the **bug repro** (must now pass), the **new flow** (must work end-to-end), and **existing flows** the diff could plausibly regress (must still work).
- Mark each row ✅/❌ with its evidence (screenshot, console excerpt, network status) — not a narrative claim.
- Rows the agent genuinely cannot reach (real OAuth, real payments, device-only behavior) are handed to the developer explicitly — that short list is all that remains of manual testing.

### Tear down what you started — HARD RULE

Driving the UI leaves processes behind, and they are the agent's mess to clean, not the developer's.
The DevTools MCP launches its OWN Chrome (throwaway profile under
`~/.cache/chrome-devtools-mcp/chrome-profile`) and it keeps running after the checklist: extra
windows, a stale localhost session, a second browser competing for the developer's attention and
their machine. **Kill it in the same turn the UI rows finish, before presenting the evidence.**

```bash
# Find the MCP-launched browser BY ITS PROFILE — never by app name.
ps ax -o pid,command | grep "chrome-devtools-mcp/chrome-profile" | grep -v grep
kill <pid>; sleep 2
ps ax -o pid,command | grep -c "[c]hrome-devtools-mcp/chrome-profile"    # expect 0
```

Kill ONLY what you started, and prove the boundary BEFORE killing anything:

- **Never the developer's own browser.** Match on the MCP `--user-data-dir`; a match on
  `Google Chrome` would take their tabs and their work with it.
- **Never their dev server.** They run it themselves (F5 / the run button) — it is not yours to
  stop, restart, or replace. Confirm it survived: `lsof -nP -iTCP:<port> -sTCP:LISTEN`.
- **Same rule for everything else the phase spawned:** emulators/simulators, docker fixtures,
  tunnels, `run_in_background` shells. If you started it for a check, it does not outlive the check.
- Leave the MCP *server* alone — it relaunches a browser on demand. Only the browser dies.

Report the teardown as one line of the evidence ("debug Chrome killed, 0 left; your :3007
untouched"). An unreported leftover process is the one still running tomorrow.

Present a structured testing table:

```
## Testing Checklist — <TICKET/ISSUE>

| # | Issue | What Was Broken | Expected After Fix | How to Test | Status + Evidence |
|---|-------|-----------------|-------------------|-------------|-------------------|
```

**Pass 1 — Ticket-scoped rows:** One row per acceptance criterion or reported symptom.

**Pass 2 — Diff-scoped regression rows:** Run `git diff <BASE_BRANCH>...HEAD --name-only`. For each changed file ask: "What existing user-visible behavior could have been accidentally affected?" Add a row for every plausible regression.

**Pass 2b — Shared-surface rows: enumerate the CONSUMERS, don't reason about them.** When the diff
touches anything shared — a layout wrapper, a base CSS class, a design token, a component several
pages mount — grep for every consumer and give each one its own row. Not "the pages I edited": the
pages that *use the thing I edited*.

```bash
git diff <BASE_BRANCH>...HEAD -- '*.css' | grep -oE '^\+\.[a-z0-9-]+' | sort -u   # classes touched
grep -rn "page-shell" app --include=*.jsx                                          # then: who mounts each
```

This is not hypothetical. On 2026-07-30 a sticky-footer rule was added to `.page-shell` for the new
informational pages; that class had also wrapped home, `/join` and the course reader since the first
commit. Those three collapsed to fit-content on every screen and it reached production, because the
verification rows covered the pages in the diff and the surfaces I happened to open — HTTP 200s and a
settings dialog — never the home page behind it. **A 200 is not a layout check**, and a row per page
would have caught it in one pass. Related trap worth checking in the same sweep: a shared rule can be
*silently safe* on the page you look at for an unrelated reason (here `.pub` set `width:100%`), which
makes one green page maximally misleading.

**Pass 3 — Make each row runnable.** A row a human can't execute without guessing is not a test. Every row needs the *mechanism*, not the intent: the exact menu path, command, or state change that produces the condition ("DevTools → Network → right-click the `…/status` request → Block request URL, wait 30s"), not "simulate a failed status call".

### The checklist MUST live where the tester looks

Presenting the table in chat only is a FAILURE of this phase — the chat scrolls away and the person testing reads the PR. So:

- **Before a PR exists:** present it in chat, and carry it into the PR body's `## HOW TO TEST` section at Phase 14.
- **PR already open:** post it as a PR comment immediately (`gh pr comment <N> --body ...`).
- Lead with a copy-pasteable **Setup** block (branch checkout, install, run, the automated command + its expected counts) so the tester starts from a known state.

### Rules that make the checklist honest

- **Separate covered from uncovered.** Say which rows the automated tests already cover and which need a human. Then name the ONE row that carries the real risk — usually the happy path through code whose timing or conditions you changed — and say why the unit tests can't reach it.
- **Include a falsification row:** the check that would prove the fix WRONG if it fails (e.g. "an idle course must never trip the timeout"). A checklist that can only confirm you is not a test.
- **Declare what is NOT reachable, never invent steps for it.** If a mapped error can't be triggered through the UI (client-side guard, entitlement panel, server-only branch), say so plainly and say how you verified it instead (read the route's responses / unit test). Fabricated repro steps waste the tester's time and destroy trust in the rest of the list.
- **Paste real output, never a description of output.** Run the command, copy what it actually printed. For an observability change, show the before/after log lines — on this branch vs the base branch — because that delta IS the deliverable.

> Platform-specific build and launch steps are in the platform pipeline file.

**Verification rule:** Before claiming testing is complete, run fresh tests, read full output, and confirm the output supports your claim. Never say "should work" or "probably passes" — evidence precedes claims. State skipped/skipping tests explicitly (e.g. "20 skipped — queue tests need a real Postgres") rather than reporting a bare pass count.

Do NOT push or create a PR until the developer explicitly confirms the prod decision. What they confirm is the EVIDENCE (the executed table + screenshots + the short can't-reach list) — not a request to go test by hand. If issues surface, iterate on fixes within the current branch and re-run the affected rows.

The prod question — *is this production-worthy?* — is asked ONCE, at the end of Phase 13 (after the review is clean); Phase 11 ends by presenting the evidence, not by asking. A yes starts Phase 14, which merges to PRE PROD. The promotion to production itself is confirmed again at Phase 16: this decision approves the WORK, that one approves the RELEASE.

---

