## Phase 16 — Prod Promotion (conditional)

**When:** the repo has a two-stage model — a pre-prod branch that feature PRs merge into, plus a
separate promotion to production. **Skip** when the repo has a single branch model, where Phase
14's merge already reached prod.

Phase 14 left the change in PRE PROD. Production is a SECOND release with its OWN gate: the
evidence that cleared Phase 11 was gathered against pre prod, and the two environments differ
precisely where the risk lives (real keys, real payment provider, real storage backend, real
data volume).

1. **Verify in pre prod first.** Run the rows only a deployed environment can answer — the ones
   Phase 11 handed over as unreachable. A green local suite is not pre-prod verification.
2. **Check the release's secrets BEFORE anything irreversible** — `skills/prod/prod-secrets.md`, in full.
   A miss stops the promotion; it is not a warning beside the ask at step 6.

3. **Migrations reach prod BEFORE the promotion merge** — never after, never during. The merge
   releases code that expects the new schema; a schema arriving second is an outage. Rehearse on
   pre prod, dry-run against prod, then apply, then merge — `supabase` skill for the mechanics.
4. **Never merge while a build is running.** Two releases racing produce a deployment you cannot
   attribute and a rollback that restores the wrong thing.
5. **Read what is actually in the promotion.** It is a diff of already-reviewed commits, so it
   needs no second code review — but it does need `git log <prod>..<pre-prod> --oneline`.
   Anything you did not expect stops the promotion until you know why it is there.

   **Zero commits is its own outcome — name it and STOP.** An empty promotion is not "nothing to
   check, so proceed": it means pre prod and prod are already the same commit, and opening the PR
   regardless fires a real production deploy for no change. Say it plainly — *"staging and main are
   on the same commit; there is nothing to promote"* — and do not open it. Then report what IS in
   flight and where it is stuck, because an empty promotion nearly always means something never
   reached pre prod. Observed 2026-08-04: an unmerged PR sat at Phase 14 while a promotion was
   attempted.
6. **The promotion is the developer's call, and it is confirmed HERE, again.** Phase 11's prod
   decision approved the WORK; this one approves the RELEASE, and the two are days apart.
   Present four things — what is in the promotion, what was verified in pre prod, migrations
   applied, and **step 2's sweep with its scopes** — then ask. Never promote autonomously.

**When the promotion merge auto-deploys:** feature PRs target the pre-prod branch; the
`<pre-prod> → <prod>` merge RELEASES PROD, so the merge IS the gate. Pre prod drifts behind prod —
catch up with `git push origin origin/<prod>:<pre-prod>`. The repo's runbook has the full flow.

---

