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

**Read the workflows as they will exist AFTER the merge** — that is the *merge result*: everything on
the head ref **plus** anything already on prod that the head lacks. Reading only prod misses a
credential this promotion introduces, which is the most common case; reading only the head misses a
workflow hotfixed straight onto prod, and Phase 16 says outright that pre prod drifts behind prod.

List both refs and take the union, then **read the body of each file** — a directory listing is not
the sweep, it only tells you what to open:

```bash
gh api "repos/<owner>/<repo>/contents/.github/workflows?ref=<head-ref>" -q '.[].name'
gh api "repos/<owner>/<repo>/contents/.github/workflows?ref=<prod>"     -q '.[].name'
gh api "repos/<owner>/<repo>/contents/.github/workflows/<file>?ref=<ref>" -q '.content' | base64 -d
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

### The write — requirements, not an incantation

**Write the commands yourself for the shell you are actually in, and satisfy every line below.**
Three prior versions of this file shipped a specific one-liner as correct and all three were wrong —
`< <(base64 …)`, then `[ -s ] && … | …`, then a BSD-only `base64 -i`. A fixed recipe here is a
liability: it cannot know whether it is running against BSD or GNU `base64`, and each rewrite has
been "verified" by testing a fragment rather than the command that runs.

| Must hold | Because |
|---|---|
| the source is a **regular, readable, non-empty file** | `[ -s ]` alone passes on a directory and on an unreadable file |
| the encoder's **own** exit status is checked | in a pipeline the status is the *last* command's, so a failed encode is invisible behind `gh` |
| the encoding is **unwrapped** (single line) | GNU `base64` wraps at 76 columns by default and its `-i` means `--ignore-garbage`, not `--input`; a wrapped value decodes to garbage in the workflow |
| the encoded value is **non-empty** before it is sent | `gh secret set` encrypts empty input and exits 0 |
| it **round-trips**: decode the encoding and compare byte-for-byte with the source | this is the only check that catches wrapping, truncation, the wrong flag and an empty encode **on any platform** — make it the one you rely on |
| the secret name and source path are **parameters** | this block is reused for `.p8`, `.p12` and `.mobileprovision`; a hardcoded name silently writes the wrong secret |

The round-trip is the load-bearing one. If decode(encode(file)) does not equal the file, stop — do
not set the secret and do not report the name as handled.

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
