# Prod Secrets — the pre-flight

The gate answers one question — *does every secret this release reads actually exist, in a scope the
job can read it from?* — and blocks until it does. It cannot answer *is each value correct*; see
**Limits**, and do not let a green sweep be reported as a working release.

## When this runs — at the merge that RELEASES PRODUCTION, wherever that is

Not "at Phase 16". Phase 16 is skipped on single-branch repos (`entry.md`), and on those the Phase 14
merge *is* the release — which is exactly the shape the 2026-08-12 incident happened in, so binding
the gate to a phase number is how it misses the case it was written for.

| Repo shape | The releasing merge | Run this |
|---|---|---|
| two-stage (`staging` → `main`) | the promotion | Phase 16, step 2 |
| single-branch | the Phase 14 merge to `main` | Phase 14, before the merge |

**Asymmetry that governs every judgement call below:** a false *stop* costs a question to the
developer; a false *green* costs a broken release with prod already moved. When unsure, include the
workflow, include the secret, and say why — never drop it to keep the sweep quiet.

---

## §1 — Collect the expected names by READING, not grepping

**Read the workflows as they will exist AFTER the merge** — the head/pre-prod ref, never prod's
current tree. A credential introduced *by this very promotion* is invisible from the prod side, and
a newly added secret is the most common case there is.

```bash
gh api "repos/<owner>/<repo>/contents/.github/workflows?ref=<head-ref>" -q '.[].name'
```

### Which workflows the release can fire

Not only `push: branches`. A release reaches a workflow through any of these, and the ones this gate
missed twice are in the middle rows:

| Trigger | Fired by |
|---|---|
| `push: branches` | the merge itself |
| `push: tags` · `on: release` | a tag or release the merge creates — **the standard store-upload shape** |
| `workflow_run` | completion of another workflow the merge fired — follow the chain |
| `repository_dispatch` · `workflow_dispatch` | an API call or a manual run the runbook describes |
| `workflow_call` | invoked by any workflow above — read the callee too |

**If you cannot prove a workflow is NOT reachable from the release, include it** and say so in the
report. **A sweep that finds zero workflows is a STOP, not a pass** — it means the discovery failed,
and "clean" and "found nothing to check" must never print the same.

### Collect the names, then map them

Collect every `secrets.NAME` and `secrets['NAME']` reference. Two traps:

- **`workflow_call` with an explicit `secrets:` mapping.** The callee's `secrets.FOO` is a
  *parameter* name, not a repo secret. Map it through the caller's `secrets: { FOO: ${{ secrets.REAL_NAME }} }`
  and expect `REAL_NAME`. Only under `secrets: inherit` are the two the same.
- **Optional secrets are not missing secrets.** A reference under a job-level `if:` guard, or a
  `workflow_call.secrets.<name>.required: false`, must not stop the promotion. Report it as optional
  and carry on.

Drop `GITHUB_TOKEN` **case-insensitively** — Actions contexts are case-insensitive, so
`secrets.github_token` is the same auto-injected token, and leaving it on the list blocks every
promotion on that repo forever.

**Say which workflows you swept, by name.**

## §2 — Check each name against the scope the JOB can read

```bash
gh secret list --repo <owner>/<repo> --json name -q '.[].name'
gh api "repos/<owner>/<repo>/environments" -q '.environments[].name'
gh secret list --repo <owner>/<repo> --env <env> --json name -q '.[].name'
gh secret list --org <owner> --json name,visibility,selectedReposURL
```

Pass `--repo <owner>/<repo>` on every call: without it `gh` resolves from the ambient working
directory, which is how a write lands somewhere nobody named.

### Presence in a listing is not availability to the job

Three distinct ways a listed name still arrives empty at run time:

| Scope | Available only when |
|---|---|
| environment | the **job** declares that same `environment:` — never diff environments as a union |
| org, `visibility: selected` | this repo is in `selectedReposURL` |
| org, `visibility: private` | this repo is **private**; on a public repo it lists and arrives empty |

### Read each command's FAILURE, not its blankness

| Outcome | Means | Say |
|---|---|---|
| empty list, exit 0 | the scope is genuinely empty | "no secrets at this scope" |
| `404 .../orgs/<owner>/...` | owner is a user account | "org scope N/A" |
| `admin:org scope` required | the token cannot see org secrets | **"unknown"** — never "missing" |
| any other non-zero | the query failed | report it verbatim |

Never send stderr to `/dev/null` here — a silenced permission error is indistinguishable from a repo
with no environments. **Do not guard with `A && B || C`**: it binds left-to-right, so `C` also fires
when `B` fails, and a real org whose listing 403s gets reported as a user account.

## §3 — On a miss: stop, then ask per secret

Report every missing name **by name** even without a how-to, and add acquisition steps when one
matches (`prod-secrets-apple.md` — Apple only, and only when the repo is actually an Apple build).
Then offer to fix it here, naming the repo you would write to and the scopes you actually checked:

> "`ASC_API_KEY` is missing. Checked: repository, and environment `production`; org scope N/A
> (`<owner>` is a user account). Give me the path to the `.p8` and I'll set it on `<owner>/<repo>`,
> or set it yourself and say go."

**Never claim a scope you skipped**, and never ask for a value in chat — a pasted credential lives in
the transcript, in scrollback, and in any log of either.

### The write — the earlier form of this was broken, twice

```bash
set -o pipefail                                   # WITHOUT THIS THE REST IS DECORATION
[ -f "$P8" ] && [ -r "$P8" ] && [ -s "$P8" ] || { echo "not a readable non-empty file: $P8"; exit 1; }
B64=$(base64 -i "$P8") || { echo "base64 failed on $P8"; exit 1; }
[ -n "$B64" ] || { echo "encoded to nothing: $P8"; exit 1; }
printf '%s' "$B64" | gh secret set ASC_API_KEY --repo <owner>/<repo>
```

> **Why every line is load-bearing.** Verified 2026-08-13: a pipeline's exit status is its **last**
> command's, so `base64 -i /bad/path | gh secret set` exits **0** and writes an **empty** secret —
> `set -o pipefail` is what makes that fail. `[ -s ]` alone passes on a **directory** and on an
> **unreadable** file, hence `-f` and `-r`. And `gh secret set` encrypts empty input and exits 0, so
> the encoded value is checked before it is ever handed over.
>
> Two earlier versions of this file claimed to prevent the empty write and did not — first with
> `< <(base64 …)`, then with `[ -s ] &&` plus a pipe. Both were verified by testing `base64` alone
> rather than the command that actually ran. Do not "simplify" this block.

**Keep credential files out of the repo.** Write them to `$(mktemp -d)`, never to the working tree —
a `.p8` or `.p12` sitting beside the code is one `git add -A` from being committed. Remove them when
the secret is set, and never `cd` into the repo to run these.

Setting is a write: ask per secret, never a batch on one nod.

### Re-opening the gate

Re-run §1–§2 and require the diff to be empty. **Say what that proves and what it does not**: the
name now exists in a readable scope. It is not evidence the value is right — §1–§2 are a name-only
listing, by design, and the section below is why that matters.

## Limits — state them in the report

- **Presence, never validity.** A secret set to the wrong value passes identically to a correct one.
  What catches that is an assertion in the workflow beside each decode — recommend it, do not go
  editing someone's workflow:
  ```bash
  [ -s "$RUNNER_TEMP/AuthKey.p8" ] || { echo "::error::AuthKey.p8 is empty"; exit 1; }
  ```
- **Only what the workflows reference.** A credential read at runtime from a vault, or baked into a
  base image, is outside what any static read can see.

---

> **2026-08-12.** Two store-upload runs had already failed at the signing step before anyone looked,
> because the repo had **zero** secrets set. Recovery took a full session — read the workflow to
> learn what it consumed, discover the distribution certificate did not exist and had to be created
> at the vendor portal — and then failed *again*, because the API key had been set from a
> copy-pasted placeholder **path**: the archive died on
> `CryptoKit.CryptoKitASN1Error.invalidPEMDocument`, an error naming neither the secret, nor the
> step, nor the empty file. `base64 --decode` of an unset secret writes an empty file and exits
> **0**, so the step consuming it reported success.
>
> That repo was **single-branch** — which is why *When this runs* is a table and not a phase number.
> §1–§2 catch the first failure; only the §3 block catches the last one.
