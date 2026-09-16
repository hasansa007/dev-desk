## Phase 4 — Investigation

**For features:** investigation = understanding the affected area — Phase 2's Exploration Fan-Out
when it applies, otherwise targeted reads. The evidence ladder below is for **bugs**.

**For bugs — REQUIRED SUB-SKILL:** use `superpowers:systematic-debugging`. Reproduce BEFORE theorizing, and never assert a cause without a verifying probe (prefer the direct probe over inference).

**When `## Suspected` names a `dev:findings` OR `dev:ideation` run, layers 1–2 are already done** —
two checkers each tried to refute it against the code and could not. Start at layer 3. **Never skip
3–5 on that basis:** both verify against the CODE and never run the app, so a CONFIRMED finding is a
twice-checked hypothesis, not a reproduction. Its report holds the `blocks:` set and the PLAUSIBLE
siblings the issue does not — read it when present, and say so when it is not, since a repo may keep
`docs/` untracked.

Work the evidence layers in order; stop at the first layer that yields a confirmed root cause:

1. **Code audit** — trace the full path end-to-end (UI handler → API/RPC → DB), noting what each layer can and cannot cause (e.g. "this function is transactional, so ITS errors can't leave partial state").
2. **Hypothesis elimination** — list the usual suspects for the symptom class and rule them out one by one with targeted greps/reads, not intuition.
3. **Live probes** — replay the exact calls the client makes, as the real role: REST/RPC with a real token, direct DB reads, seeded fixtures. A probe that surprises you is a probe to distrust first.
4. **Live UI reproduction** — drive the real running app:
   - **Web:** Chrome DevTools MCP (`chrome-devtools` tools) — open the page, read console + network, inject `initScript` error listeners to capture what the console alone won't attribute, screenshot states. Connect to the app the developer already runs — NEVER start a competing dev server. **Kill the MCP's debug browser when the probe is over** — teardown rule + commands in Phase 11.
   - **Mobile:** build/launch via the `dev:launch` skill; drive + capture per the platform pipeline file (adb/uiautomator on Android, simctl on iOS).
5. **Environment check** — a wedged dev server, stale cache, or schema drift can BE the bug or mask it; verify the environment answers before blaming code.

Capture the confirmed reproduction as a failing test when the surface allows it — it becomes Phase 9's RED.

---

