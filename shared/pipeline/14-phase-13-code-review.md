## Phase 13 — Code Review Gate (AI, verified findings)

`dev:code-review` owns this gate: it runs the `code-review` skill against `git diff <BASE_BRANCH>...HEAD` as its engine — a verified fan-out beats a single self-review pass — then adds the **spec-compliance check** (each acceptance criterion mapped to real code in the diff, never to an implementer's claim) and the conditional security pass. Invoke the door, not the engine, or the protocol around it is skipped.

**Deep tier — add a security pass.** When the diff touches money, auth or entitlements, migrations,
file upload/storage, or anything that accepts untrusted input, also run `security-review` against
the same diff. The review engine optimises for correctness and is not a substitute for someone reading
the diff specifically looking for the exploit.

Address findings by verdict and severity:
- **CONFIRMED critical/important:** fix immediately, before proceeding
- **PLAUSIBLE:** judge against the actual code — fix or refute with a one-line reason (never silently drop)
- **Minor / style:** document for later; optionally run `/simplify` for quality-only cleanups

After review fixes, re-run the affected Phase 11 rows if any logic changed (agent-run, as above). If only cosmetic fixes (comments, imports, formatting), skip re-verification.

Then ask: "Review clean, verification evidence attached. Want me to push and create a PR?"

---

