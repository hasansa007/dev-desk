# Prod Secrets — the pre-flight

Read by `shared/pipeline.md` → **Phase 16, step 2**. Stack-agnostic: Apple names additionally get
acquisition steps from `prod-secrets-apple.md`, but nothing here is iOS-specific.

The gate answers one question — *does every secret this release reads actually exist?* — and blocks
the promotion until it does. It cannot answer *is each one correct*; see **Limits**.

---

## 1 — Collect the expected names by READING, not grepping

Open every workflow a push to `<prod>` can reach and collect every `secrets.NAME` and
`secrets['NAME']` reference in it. **Follow `workflow_call`**: a caller that passes `secrets:
inherit` names no secret at all, and the deploy job's credentials live in the reusable workflow it
invokes. A workflow fired by `workflow_dispatch` carries no branch — the release runbook says which
one it is.

**A grep cannot do this, and its failures are silent:**

| Shape | What a grep does |
|---|---|
| `branches: [ "main" ]` — quoted | matches nothing; the sweep finds **zero** workflows and passes green |
| `on: workflow_call` (reusable) | never matched, so every secret the release actually reads is invisible |
| `pull_request: branches: [main]` | matched, dragging CI-only secrets into a list that **blocks a release** |
| `secrets['NAME']` | missed — anchored on `secrets.` |

Reading is both shorter and correct. Then drop `GITHUB_TOKEN` **case-insensitively**: Actions
expression contexts are case-insensitive, so `secrets.github_token` is the same auto-injected token,
and leaving it on the expected list blocks every promotion on that repo forever.

**Say which workflows you swept.** "Clean" and "found nothing to check" produce identical output
otherwise, and the second one is the dangerous one.

## 2 — List what exists, in every scope that applies

```bash
gh secret list --repo <owner>/<repo> --json name -q '.[].name'                 # repository
gh api "repos/<owner>/<repo>/environments" -q '.environments[].name'           # then, per environment:
gh secret list --repo <owner>/<repo> --env <env> --json name -q '.[].name'
gh secret list --org <owner> --json name,visibility,selectedReposURL           # only if owner is an org
```

**Pass `--repo <owner>/<repo>` on every call.** Without it `gh` resolves the repo from the ambient
working directory, which is how a write lands somewhere nobody named — the failure `entry.md`'s
write boundary exists for.

### Read each command's FAILURE, not just its blankness

Four outcomes, four different sentences. Collapsing them is how this gate blocks a good release:

| Outcome | Means | Say |
|---|---|---|
| empty list, **exit 0** | the scope is genuinely empty | "no secrets at this scope" |
| `404 .../orgs/<owner>/...` | owner is a **user account** — org scope does not exist | "org scope N/A" |
| `admin:org scope` required | the token cannot see org secrets | **"unknown"** — never "missing" |
| any other non-zero | the query failed | report the error verbatim |

Never route stderr to `/dev/null` here. A silenced permission error is indistinguishable from a repo
with no environments, and every environment secret then reads as missing.

**Do not use `A && B || C` to guard the org call.** It binds left-to-right, so `C` also fires when
**`B`** fails — a real org whose secret listing 403s gets reported as "a user account", and its
secrets as absent. Branch on the two outcomes explicitly, or run the calls separately and read them.

### Presence in a listing is not availability to the job

An org secret with `visibility: selected` that does not include this repo **lists by name** and
arrives as an empty string at run time. Check `visibility`; `selected` means resolve
`selectedReposURL` before calling it present.

## 3 — On a miss: stop, then ask per secret

A missing name stops the promotion. Report it **by name** even when there is no how-to — the name
alone answers *"what do I set"* — and add acquisition steps from `prod-secrets-apple.md` when it
matches one.

Then offer to fix it here, naming the repo you would write to:

> "`ASC_API_KEY` is missing. Checked: repository and environment `production`; org scope N/A
> (`hasansa007` is a user account). Steps are above — give me the path to the `.p8` and I'll set it
> on `hasansa007/<repo>`, or set it yourself and say go."

**State exactly which scopes you checked, and never claim one you skipped.** "Missing from all three
scopes" is false on a personal repo, where there are only two.

**Never ask for a value in chat and never echo one** — a pasted credential lives in the transcript,
in scrollback, and in any log of either, permanently. Ask for a **path**:

```bash
[ -s "$P8" ] || { echo "empty or missing: $P8"; exit 1; }    # THE line that matters
base64 -i "$P8" | gh secret set ASC_API_KEY --repo <owner>/<repo>
```

> **Without that `-s` test, this step causes the incident it was written to prevent.**
> `gh secret set` encrypts an empty value and **exits 0**, and `< <(base64 -i …)` hides a bad path's
> failing status from the enclosing command — unlike a pipe. So a typo'd or placeholder path writes
> an **empty** secret, and a name-only re-check confirms it present.

Setting is a write: ask per secret, never a batch on one nod. Afterwards re-run §1–§2 — the gate
reopens when the sweep is clean, not because a `gh secret set` exited 0.

## Limits — state them in the report

- **Presence, never validity.** A secret set to the wrong value passes identically to a correct one.
  What catches that is an assertion in the workflow, next to each decode — recommend it, do not go
  editing someone's workflow:
  ```bash
  [ -s "$RUNNER_TEMP/AuthKey.p8" ] || { echo "::error::AuthKey.p8 is empty"; exit 1; }
  ```
- **Only what the workflows reference.** A credential read at runtime from a vault, or baked into a
  base image, is outside what any static read can see.

---

> **2026-08-12.** Two TestFlight runs had already failed at the signing step before anyone looked,
> because the repo had **zero** secrets set. Recovery took a full session — read the workflow to
> learn what it consumed, discover the distribution certificate did not exist and had to be created
> at Apple — and then failed *again*, because the API key had been set from a copy-pasted
> placeholder **path**: the archive died on `CryptoKit.CryptoKitASN1Error.invalidPEMDocument`, an
> error naming neither the secret, nor the step, nor the empty file. `base64 --decode` of an unset
> secret writes an empty file and exits **0**, so the step consuming it reported success.
>
> §1–§2 catch the first failure. Only the `-s` test in §3 catches the last one.
