---
name: docs
description: >
  Check that docs, ADRs and PROJECT_MAP are current for a branch's diff BEFORE it merges — prices
  and limits, decisions with their rejected alternatives, env vars, migrations, new modules, and
  work deliberately deferred. Produces the PR body's `## DOCS` section.
  Trigger when the user says "are the docs updated", "check the ADRs", "docs gate", "did we write
  this decision down", "is PROJECT_MAP current", or before merging anything that changed a number
  or a decision.
allowed-tools: [gh, git]
---

# Dev — Docs & Decisions Gate

Standalone entry into **Phase 12 — Docs & Decisions Gate** of the dev pipeline.

## Input

A branch, or any diff: `git diff <BASE_BRANCH>...HEAD`.

## Run

1. Read `~/Developer/skills/dev-skill/shared/entry.md` and apply it.
2. Read `~/Developer/skills/dev-skill/shared/pipeline.md` → execute **Phase 12** against the diff.
3. Output the `## DOCS` section verbatim, ready to paste into the PR body.

## Why this exists as its own entry point

This gate has **failed in execution before.** A funnel branch merged with green suites and a full
verification table but no ADR and a stale `PROJECT_MAP` claim — caught only because the developer
thought to ask. Making it invocable means the question "are the docs actually current?" can be
asked directly, at any time, instead of depending on remembering it mid-run.

The rationalization it counters: *"suites green + evidence table done = ready."* It is not. The
ADR is part of the diff.

## The check

| If the diff contains… | Then update… |
|---|---|
| a changed price, limit, cap or plan | the monetization/pricing doc — every number AND why it is that number |
| a decision with a rejected alternative | a new ADR — including the alternative and why it lost |
| a new/changed env var, migration or runbook step | the release/ops doc |
| a new module, flow or entry point | `PROJECT_MAP.md` (`TECH_STACK` / `SYSTEM_FLOW`) |
| work deliberately deferred | `ORPHANS & PENDING` — not a memory of it |
| a moved/renamed/deleted file that any `docs/arch/*.json` cites | the diagram — re-pin it, or delete it |

## The check that actually fails things

The table above asks whether the right document was **touched**. That is the easy half. The gate is
whether **every claim in the section you touched is still true** — a partial edit passes the
touched-test while leaving the doc lying.

For each doc the diff modifies, reread the **whole paragraph around the edit** — not your diff of
it — and ask of each sentence: *is this still true after this branch?* Fix or delete what is not.

Observed 2026-08-03: a branch added its ADR **and** updated its PROJECT_MAP
paragraph — green on every row of the table — while leaving three claims in that same paragraph
describing a rail the dialog no longer has. One mention had been fixed, three had not. **A partial
sweep is indistinguishable from a complete one from the outside**, so the pass criterion is the
reread, not the edit.

## Committed diagrams — the one doc check that is mechanical

`dev:arch` lands evidenced architecture diagrams in `docs/arch/` as a `.html` beside the
`.architecture.json` that produced it. Every component in that IR is pinned to a file and line range
at one commit, so unlike prose, a stale diagram can be **detected by running something**.

**Validating the IR as it is pinned proves nothing.** Its `meta.repository.revision` names a commit
that still exists, and the cited files still exist *at that commit*, so the check passes forever no
matter what the branch did. Verified 2026-08-31: renaming a cited file and re-running `validate` on
the committed IR returned `ok`. The revision must be bumped to the branch's HEAD **first** — only
then does the same rename return `repository-evidence/file-missing`.

Probe a COPY. Never rewrite the committed IR's revision to make a check pass:

```bash
export ARCHIFY_UPDATE_CHECK_DISABLED=1
HEAD_SHA=$(git rev-parse HEAD)
for ir in docs/arch/*.architecture.json; do
  probe=$(mktemp)          # bare mktemp — a ".json" suffix breaks the template on macOS
  python3 -c "import json,sys;d=json.load(open(sys.argv[1]));\
d['meta']['repository']['revision']=sys.argv[2];json.dump(d,open(sys.argv[3],'w'))" "$ir" "$HEAD_SHA" "$probe"
  node <archify>/bin/archify.mjs validate architecture "$probe" --repo-root . >/dev/null 2>&1 \
    && echo "OK: $ir" || echo "STALE: $ir"
  rm -f "$probe"
done
```

Run it three ways before trusting it — this loop was checked against a clean tree, against a cited
file renamed, and against the rename reverted, returning **OK / STALE / OK**.

Run it over every `docs/arch/*.architecture.json` in the repo — not only the ones this branch
touched, because any diff can move a file some other diagram cites.

A `repository-evidence/*` failure means the diagram cites code this branch moved, renamed or deleted.
**That fails the gate.** Fix it by re-reading the system at the new commit and re-running `dev:arch`
— which legitimately advances the pin — or by deleting the diagram. Never by editing the SHA in place.

**The committed pin records the commit at which someone actually read the code**, which is why the
gate probes a copy and leaves it alone. Advancing it without re-reading converts the one honest thing
the artifact carries into a false claim.

### The probe misses a pure line SHIFT — check touched files separately

A pin that still RESOLVES can still be wrong. Insert 30 lines near the top of a cited file and every
range below it slides down: the file exists, the lines exist, `validate` returns `ok`, and the pins
now quote different code. Observed 2026-08-31 — a 30-line insert at `shared/pipeline.md:306` moved
six cited ranges and the probe stayed green.

Compare against the **working tree**, not `$BASE...HEAD`. The three-dot form only sees committed
work, so running the gate before committing reports "no cited file touched" while the file sits
modified on disk — verified the same day, on this very check.

So run the cheap set-intersection too, and treat any overlap as **re-read required**:

```bash
BASE=$(git merge-base origin/main HEAD)
git diff --name-only "$BASE" > /tmp/touched   # bare $BASE, NOT $BASE...HEAD —
                                              # ...HEAD misses uncommitted work
python3 - <<'EOF'
import json,glob
touched=set(open('/tmp/touched').read().split())
for ir in glob.glob('docs/arch/*.architecture.json'):
    cited={s['path'] for c in json.load(open(ir))['components'] for s in c['sources']}
    hit=sorted(cited & touched)
    print(f"{ir}: {'RE-READ ' + ', '.join(hit) if hit else 'no cited file touched'}")
EOF
```

**A hit is not automatically a failure** — the branch may have changed a file the diagram cites in a
region it does not cite. It means *a human opens those ranges and confirms they still say what the
node claims*, then re-`deliver`s if they moved. Unlike the probe, this cannot be automated away,
because "does line 556 still start Phase 11" is a question about meaning.

**What this cannot catch, and you must still eyeball:** every pin can resolve while the diagram is
wrong. A node deleted from the system, an edge that no longer exists, a lane that was merged — all
leave the cited files exactly where they were. The command proves the diagram still points at real
code; only a person can say it still draws the real shape. So when a branch changes the ARCHITECTURE
rather than just moving files, open the HTML and look at it.

## Output

Either the list of ADRs and docs updated in this branch, or the explicit line:

> none needed — checked: no price/limit, no decision-with-alternative, no env/migration,
> no new module, no deferred work, no doc made stale, no `docs/arch/` diagram invalidated

Either way, state the reread: *"reread §X and §Y in full — N claims corrected"*, or *"reread §X in
full — still accurate"*. An unstated reread did not happen.

If the repo has any `docs/arch/*.architecture.json`, state the diagram result too — *"N/N diagrams
re-validated at `<sha>`"*, or which one went stale and what was done. Say when there are none.

A PR without a `## DOCS` section is not ready to merge.

## Guards

- **Write the alternatives you REJECTED, with their arithmetic.** A log listing only what was
  chosen cannot tell a future reader why the obvious other path is wrong — so they will re-propose
  it, and you will re-argue it from memory.
- **State what is decided but NOT built.** A doc describing behaviour that does not exist is worse
  than silence — mark it pending, with what it needs.
- **A change implementing PART of a decision must record the remainder.** Go back to that ADR and
  write which half is live and which is still intent.
- Docs written after the merge get written from memory, and memory keeps the conclusion while
  losing the reason. **Run this before the merge, never after.**

## Next — ask, never stop flat

This gate is read-only and mid-pipeline, so finishing it is not finishing anything. End by naming
the rest and asking (`entry.md` → *Never end silently*):

> "Docs gate clean — ADR written, the PROJECT_MAP section reread. Next is Phase 13 (`/code-review`)
> on the same diff, then `dev:pre-prod` (Phase 14) opens the PR and merges to `<pre-prod branch>`.
> Continue?"
