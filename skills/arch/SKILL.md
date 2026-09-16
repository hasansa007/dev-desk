---
name: arch
description: >
  Draws a VERIFIABLE diagram of a system — architecture, workflow, sequence, data flow, or
  lifecycle — where every node points at real code at a real commit, and hands back one
  self-contained HTML file whose viewer can export PNG/SVG.
  Renders through Archify (https://github.com/tt-a1i/archify): this skill authors typed JSON IR,
  Archify compiles and validates it deterministically. The validator checks that a diagram is
  well-FORMED; this skill is what makes it TRUE — evidence-backed nodes are mandatory wherever the
  renderer can prove them, because a picture is trusted more than prose precisely because it looks
  checked.
  Declines to draw a target too small to need a diagram.
  Trigger on: "draw the architecture", "map this system", "diagram the pipeline", "show me how
  this fits together", "architecture diagram", "sequence diagram", "data flow diagram",
  "visualize the codebase", "make a diagram for the deck".
allowed-tools: [node, npx, git, rg, curl, unzip]
---

# arch — draw the system, and prove the drawing

A **tool**, not a phase. It maps to no phase number, takes a target (a repo, a subsystem, a diff,
or a plain description), and returns one artifact. It never edits code and never files an issue.

`dev:docs` checks that prose is current. `dev:kanban` renders a board as text. `dev:shots` captures
a running UI. This is the only door that draws the **shape** of a system — the thing prose serves
worst, and the thing someone needs when onboarding, reviewing a design, or presenting the work.

## Phase 0 — Load the contract

1. Read `~/.claude/skills/dev/shared/entry.md` and apply it — **the absolute path, because
   this skill runs inside somebody else's repo.** It resolves the repo and defines the **write
   boundary**, which this door needs more than most: it is the only tool that writes a ~750 KB file
   into the tree by default.
2. Read `~/.claude/skills/dev/shared/pipeline/00-principles.md` (**Guiding Principles**) and
   `~/.claude/skills/dev/shared/pipeline/18-output-and-universal-rules.md` (**Universal Rules**)
   only. A tool runs no phase, so Right-Size has nothing to size; Simplicity First is what lets
   Phase 3 refuse a diagram.

**Name the repo before writing, and cut a branch.** `dev:findings` requires that for one markdown
report; this door lands two files and one of them is three-quarters of a megabyte.

**A committed local repo with no `origin` is drawable — do not block on the remote.** The gate is a
resolvable commit to pin to, not a GitHub identity: `git rev-parse HEAD` must succeed, so there is a
SHA every node can cite. When `git remote get-url origin` resolves, name the diagram `owner/repo`;
when there is **no** remote, fall back to the checkout's own directory name and say which was used.
The write boundary still holds — cut a branch and land the files under the invoked repo's `docs/arch/`
exactly as below. Only refuse for the repository's sake when there is **no commit at all** (`HEAD`
does not resolve): there is then nothing to pin to, and the diagram cannot be evidence of anything.
One exception: an **evidenced `architecture`** diagram needs a GitHub `origin` — Archify fails
`repository-evidence/url-invalid` without a github.com URL and checks it against `origin`. With no
remote, draw the four unevidenced types; for `architecture`, ask for the remote rather than drop evidence.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| A target (`the build pipeline`, `web/app/lib`, a description) | what to draw | required |
| `architecture` · `workflow` · `sequence` · `dataflow` · `lifecycle` | force the type | pick it from Phase 4's table |
| `--showcase` | pass `--quality showcase` to `validate` and `deliver` | `--quality standard` |
| `--open` | pass `--open` to `deliver` | off |
| `--out <path>` | where the HTML lands | `docs/arch/<name>.html` in the invoked repo |
| `--scratch` | keep it out of the tree — a throwaway look | off |

**The artifact lands in the repo it was drawn from, next to its IR — every type, not only
`architecture`.** Write BOTH `docs/arch/<name>.<type>.json` and `docs/arch/<name>.html`, where `<type>`
is the diagram's own type: `.architecture.json`, `.dataflow.json`, `.workflow.json`, `.sequence.json`
or `.lifecycle.json`. **Never land an artifact without its IR** — the JSON is what `dev:docs`
re-validates later, and an HTML with no IR beside it cannot be checked by anything. The type-suffixed
name is what lets a reader — and Dev Desk's Diagrams screen, which lists `docs/arch/` and takes each
file's kind from its sidecar — tell which type a file is, and it keeps the four unevidenced IRs out of
`dev:docs`'s `docs/arch/*.architecture.json` staleness glob, which would have nothing to re-check in them.

**For `architecture` this is safe because the pins are re-checkable.** An evidenced architecture
diagram is not prose: `archify validate architecture <ir> --repo-root .` re-runs every pin at the
current commit and fails loudly when a cited file or line has moved. That is why `dev:docs` can own it
— see *Known limits* for what that check still cannot catch. For the other four types it is safe only
because the artifact says, in its own cards, that it was never checked — see below and Phase 5.

**Write into `$SCRATCH` instead — never a guessed path in the tree — when:**

- **`docs/` is git-IGNORED.** Check before writing, in whatever repo you were invoked in:
  ```bash
  git check-ignore -q docs/ && echo "docs/ is ignored here — use \$SCRATCH"
  ```
  A path under an ignored directory produces an untracked file that **looks** committed: `deliver`
  reports a path, the developer sees a green receipt, and nothing is in the diff. Say which it was.
  **A `docs/` that does not exist yet is NOT ignored — create it and write `docs/arch/` in the tree.**
  "Not tracked" is not the test; only an *ignored* `docs/` forces scratch. A brand-new `docs/arch/<name>.html`
  is exactly what should land, and it becomes tracked the moment it is added — do not divert it to scratch
  merely because the folder is new.

- `--scratch` was passed, or the diagram is a throwaway look at someone else's code
- **the target is not the invoked repo.** `docs/arch/` means *this* repo's `docs/arch/`; a diagram of
  another checkout does not land here. Draw it to `$SCRATCH` and say so

**The four unevidenced types are NOT a scratch trigger.** `workflow`, `sequence`, `dataflow` and
`lifecycle` land in `docs/arch/` exactly as `architecture` does. Nothing can re-check them, so the
caveat travels WITH the artifact instead of being enforced by hiding it: the diagram must carry a
visible "unevidenced" statement in its own cards — `meta`/card text in the IR, so the rendered viewer
shows it — and the handoff must repeat it (Phase 5). Hiding them was tried and it produced nothing:
Dev Desk reads diagrams only from `docs/arch/`, so a `dataflow` written to `$SCRATCH` was a diagram the
Diagrams screen reported as never drawn, on every retry (ADR 0033).

**Headless runs** — a prompt that says nobody can answer (Dev Desk's Diagrams screen runs this door
with `claude -p` / `codex exec`). A question there is printed, the process exits 0, and the caller
reads a finished run that drew nothing. So: no target means the whole project; do **not** cut a
branch or stash, write only the new `docs/arch/<name>.*` files on the current branch and leave every
other change untouched; never ask — if something truly blocks, fail with the reason.

## Phase 2 — Resolve the renderer

Archify is a **hard dependency** and this skill does not pretend otherwise. Resolve it in this
order and stop at the first hit:

1. `~/.claude/skills/archify/` — a skills-dir install, the shape README's Installing section uses
2. `~/Developer/skills/archify/` — a checkout under the developer's own tree
3. An `archify` directory already extracted under `$SCRATCH`
4. Fetch and extract, then **say the version you got**

**Try both; neither is guaranteed, and they are not the same shape.** On the authoring machine
(2026-09-07) `~/.claude/skills/` holds only *symlinks* — `dev` and `study` — pointing at
`~/Developer/skills/`, and archify is a plain 7.3 MB checkout at rung 2 with no symlink at rung 1.
A machine that installed archify the way README installs this family would be the reverse. Naming
only one rung sends the other machine to the network fallback, re-downloading an unpinned
`main.zip` every session.

```bash
export ARCHIFY_UPDATE_CHECK_DISABLED=1              # every invocation, see below
# only if 1 and 2 both miss:
curl -sSL -o "$SCRATCH/archify.zip" https://github.com/tt-a1i/archify/archive/refs/heads/main.zip
unzip -q -o "$SCRATCH/archify.zip" -d "$SCRATCH"
ARCHIFY=<the archify/ directory inside the extracted tree>
node "$ARCHIFY/bin/archify.mjs" doctor
node -e 'console.log(require("./package.json").version)' # RECORD this in the handoff
```

The fetch is an unpinned branch archive over an unauthenticated download, and this skill's whole
premise is proof — so the version is **recorded, not assumed**. Behaviour here is verified against
**2.16.0**; if `doctor` reports another major, say so before trusting the receipt format or
`--repo-root` semantics.

**`ARCHIFY_UPDATE_CHECK_DISABLED=1` on every invocation.** Upstream performs a periodic
update-reminder GET; it is documented and disableable, and a skill that runs it silently on the
developer's behalf has made a networking decision that is not its to make.

If `doctor` fails, say what failed and stop. **Do not fall back to hand-written SVG or a Mermaid
block** — the whole value here is the validator, and an unvalidated picture that looks the same is
the failure this skill exists to prevent.

## Phase 3 — Refuse the diagrams that are not worth drawing

Before reading any code, ask what the picture would show that a sentence does not. **Decline and
say why** when:

- The target is one function, one file, or a linear call chain with no branch
- The answer is a list, not a shape — "which routes exist" is `rg`, not a diagram
- Nothing about the target is contested, surprising, or hard to hold in the head

A door that renders on demand for anything is the over-engineering this family exists to refuse.
A declined diagram costs a sentence; a drawn one costs the reader's trust when it turns out to
restate the obvious.

## Phase 4 — Pick the type, then read the code

**Pick the type from the table below.** `guide` exists and may be consulted, but it is not the
default and its answer is not authoritative:

```bash
node "$ARCHIFY/bin/archify.mjs" guide "<one sentence describing the system>"
```

**`guide` is keyword-matched, and `architecture` + `confidence: low` is its NO-MATCH fallback, not
a recommendation.** `xyzzy` returns byte-identical output to a textbook lifecycle question. Read
`low` as *"the renderer did not recognise this"* and pick the type from the table below yourself.
Do not split the question and re-ask: both halves come back with the same fallback, so the loop
cannot converge.

| Type | Answers |
|---|---|
| architecture | what exists, who owns it, how it connects |
| workflow | order, branches, exceptions across lanes |
| sequence | one interaction over time |
| dataflow | sources, transforms, stores, boundaries |
| lifecycle | states, retries, waits, terminal outcomes |

Then read the real code. Every node and every edge comes from something you have opened — the
stage list from the orchestrator, the model from the config, the lane from the queue table. A node
you cannot point at is a node that does not go in.

## Phase 5 — Evidence wherever the renderer can prove it

Archify's repository evidence — each node pinned to a file and line range at one commit and checked
against a real Git object — is **`architecture`-only**. The other four types reject `--repo-root`
outright: *"--repo-root is currently supported for architecture diagrams only."* So the rule is
scoped to what can be proven, and stated out loud where it cannot.

- **`architecture` — evidence is MANDATORY.** Every component carries `sources` (1–3 entries, repo
  relative POSIX paths, optional line ranges), pinned through `meta.repository` to one **full
  40-character SHA**, never a branch. A component that cannot be evidenced is **refused, not
  drawn** — say which one and why. Validate and deliver with `--repo-root`, or nothing is checked.
- **`workflow` · `sequence` · `dataflow` · `lifecycle` — evidence is UNAVAILABLE.** Draw them, land
  them in `docs/arch/` like any other type, and **label them unevidenced twice**: in the artifact's
  own cards — `meta`/card text in the IR stating that the diagram was drawn from reading the code,
  not proven against a commit — and again in the handoff. The label in the cards is what stands
  between the picture and a reader who opens it months from now assuming it was checked; the handoff
  sentence is for the reader who is here now. Neither replaces the other.
- A description-only diagram (no repository) is legitimate, and must be **labelled as such** in
  the artifact's own cards. **Precedence:** "no repository" means no repository was given — it is
  never a way out of evidencing an architecture diagram of code you can read. If a repo is in
  scope, the first bullet governs and a component you cannot evidence is refused.

**Resolve the commit before reading anything, and pin to that:**

```bash
SHA=$(git -C <repo> rev-parse HEAD)   # record it ONCE, before opening any file
git -C <repo> status --porcelain      # must be EMPTY
```

A dirty tree is one failure the validator cannot catch: you read line 160 in the working file, the
pinned blob is 40 lines shorter, and the range still validates — against different bytes than you
read. Commit or stash first, or pin to a commit whose blobs are what you actually opened.

**`status --porcelain` does NOT cover the other half, and this is the one that has actually bitten.**
It reports whether the tree is dirty, never whether **HEAD is still the commit you resolved**. A
branch switch, a `pull`, a `reset`, another agent, or the developer working in a second terminal all
move HEAD while leaving `status` perfectly empty. Both checks then pass, and every pin resolves —
against a commit whose files you never opened.

So re-assert it **immediately before `validate`**, not only at the start:

```bash
[ "$(git -C <repo> rev-parse HEAD)" = "$SHA" ] || echo "HEAD MOVED — every read is void"
git -C <repo> status --porcelain      # still empty
```

**If HEAD moved, re-READ. Do not re-pin.** Bumping the SHA to the new HEAD makes the artifact
validate and is a lie: the line numbers came from files you opened at the old commit. Re-pinning is
only ever legitimate when the cited paths are byte-identical — see the pin rule under *Rules*.

> **2026-08-31 — how this was found.** A run resolved `gh-14-dev-arch@98f9216`, read the skills, and
> was about to pin. Between the first read and the pin the repo moved to `main@4209057`.
> `status --porcelain` was empty at both ends. `shared/entry.md` was 272 lines in the tree and 241 at
> the SHA about to be pinned; `skills/survey/SKILL.md` 290 vs 161. A citation of line 244 would have
> validated green against a 241-line file at the *other* commit, or failed for a reason that looked
> like a typo. Caught by hand, by comparing `git show <sha>:<file> | wc -l` against the worktree —
> which is the check this section now requires.

The pin is proven, not trusted: a line past end-of-file, a path absent at that commit, and an
unknown SHA each fail with their own rule code — `repository-evidence/line-out-of-range`,
`/file-missing`, `/revision-unavailable`. Verification is local, so a **private** repository works.
That is what makes an evidenced architecture diagram worth more than the prose it replaced; on the
other four types, only the caveat written into their cards and repeated in the handoff does.

## Phase 6 — Author, validate, repair, deliver

```bash
node "$ARCHIFY/bin/archify.mjs" validate architecture <ir.json> --repo-root <repo>
node "$ARCHIFY/bin/archify.mjs" deliver  architecture <ir.json> <out.html> --repo-root <repo>
# the other four types take neither --repo-root nor evidence:
node "$ARCHIFY/bin/archify.mjs" validate <type> <ir.json>
```

**`--repo-root` is what makes the evidence checked.** Omit it and Archify never opens the repo, no
`repository-evidence/*` rule can fire, and the run still prints `N/N artifact checks` — the exact
"looked checked, was only checked for form" artifact this skill exists to prevent. If the receipt
came from a run without `--repo-root`, it is not evidence of anything but layout.

The validator returns machine-readable repairs — a stable rule code, the exact subject, measured
evidence, and the supported repair controls. Apply them; do not guess.

**The repair loop is capped at 8 cycles.** At the cap, do not keep tuning geometry — **simplify the
diagram**: delete a node and move its fact to a card. That is the renderer's own guidance
(*supporting detail belongs in cards, not in more edges*) and it produces a better diagram, not a
compromise.

**Simplifying gets 2 further cycles, and then the run STOPS.** Report the last validator output,
say which nodes were already dropped, and hand back no artifact — never loop toward an empty
diagram, and never end silently. Ten total cycles with nothing to show is a real answer: this target
does not fit one picture, and it should be split or drawn at a coarser grain.

**Default `quality_profile: "standard"`.** `composition/label-route-clearance` is `showcase`-only
and strict; on a dense diagram it costs cycles without changing what the reader learns. `--showcase`
is for a deck, where the polish is the point.

Report the receipt verbatim when it passes — `N/N artifact checks`, the profile, the `sha256`.

## Rules

- **Never write a diagram of ANOTHER repo into this one.** `docs/arch/` is for the invoked repo's own
  system; anything else goes to `$SCRATCH`.
- **Never land an artifact without its IR.** The `<name>.<type>.json` beside the `<name>.html` is what
  keeps it honest — and what tells a reader which type it is.
- **Never present an unvalidated diagram.** If `deliver` did not pass, there is no artifact.
- **Never claim runtime behaviour.** Reach, routes, and roles are *authored* relationships. The
  diagram says what the code is wired to do, never what production actually did.
- **Never draw from memory of a codebase.** Re-read at the commit you are pinning to.
- **Re-assert HEAD before validating.** Resolving the SHA once at the start proves nothing if the
  branch moves while you read. A clean `status` does not mean a still HEAD.
- **Say which commit.** The artifact is only as true as the SHA it was built from.
- **Pin to a commit that is already on the base branch when you can.** A squash or rebase merge
  rewrites the branch's commits, so a pin to the branch tip becomes unreachable and a fresh clone
  fails `repository-evidence/revision-unavailable`. It keeps validating on the machine that built it,
  because the orphaned object survives in `.git` until `gc` — green locally, broken for everyone else.
  - **Branch does NOT touch any cited path** → pin to the base branch's HEAD. It survives every merge
    strategy, because it is already an ancestor. Nothing to do afterwards.
  - **Branch DOES touch a cited path** → the correct pin cannot exist until the merge lands. Deliver
    against the branch, then **re-pin as a follow-up** once merged.
- **Before advancing a pin, compare the CITED PATHS — never the whole tree.** The artifact lives in
  `docs/arch/`, so committing it guarantees the trees differ; a whole-tree check therefore says
  "re-read" every single time and gets ignored, which is worse than no check.
  ```bash
  git diff --name-only <old-pin> HEAD          # what actually moved
  # intersect that with the IR's source paths — empty means the pin may advance
  ```
  **Empty intersection means the new commit holds byte-for-byte the code that was read**, so
  advancing the pin states no new claim. **A non-empty intersection means re-read those ranges** —
  and re-read them for LINE SHIFTS too, not just deletions: an insert above a cited range moves it
  while `validate` stays green.

## Never

- Never fall back to an unvalidated renderer when Archify is unavailable — stop instead.
- Never mark a node evidenced without opening the file and the lines.
- Never leave `ARCHIFY_UPDATE_CHECK_DISABLED` unset.
- Never commit an artifact as part of unrelated work — landing one is its own decision.

## Known limits

| | |
|---|---|
| Evidence is `architecture`-only | `--repo-root` is refused on the other four types. They can be drawn but never proven, so they carry a written caveat — in their own cards and in the handoff — where architecture carries a guarantee. Verified 2026-08-31 against Archify 2.16.0 |
| `guide` cannot say "I don't know" | It falls back to `architecture` + `confidence: low` for anything it fails to keyword-match, which is indistinguishable from a real recommendation. Pick the type yourself when confidence is low |
| Exports drop the evidence | Repository evidence is embedded for the Semantic Passport and Node Finder only. A PNG or SVG pulled out of the viewer carries none of it, so the image is not the artifact — the HTML is |
| Diagram rot is caught late, not never | A picture reads as authoritative long after it stops being true, so `dev:docs` re-validates every committed IR against the current commit and fails when a pin no longer resolves. That catches a MOVED file or line — it cannot catch a diagram whose pins all still resolve while the shape it draws is wrong. Structural rot still needs a human. Owner added 2026-08-31 |
| The validator checks form, not truth | Schema, layout, routes and clearance all pass on a diagram that describes the wrong system. Phase 5 is the only thing standing between the two |
| Upstream is young | Archify was created 2026-04-15. Popular is not audited; nobody in this family has read its source |
| Its README is partly a funnel | It carries sponsor referral links. Read the technical claims on their merits |
| Layout is hand-tuned | Passing `showcase` on a dense diagram means the agent adjusting pixel offsets against a validator. That is the cost, and it is why `standard` is the default |

## Next — ask, never stop flat

This door returns an artifact, and an artifact nobody decides about is a file in a temp directory.
So close by naming the decision (`entry.md` → *Never end silently*):

> "Delivered `docs/arch/<name>.html` beside `docs/arch/<name>.<type>.json` on `<branch>` —
> `N/N artifact checks`, `<profile>`, `sha256 <…>`, pinned to `<sha>`. It is in the tree, uncommitted.
> Landing it makes it `dev:docs`'s to keep current — want it committed, or dropped?"

Report the path the files actually took: `docs/arch/` in the invoked repo by default, or the
`$SCRATCH` path and which Phase 1 trigger sent it there. Say the commit, and say what is **not**
proven: an architecture diagram carries evidence; for the other four types say *unevidenced* here, as
the artifact's own cards already do — they carry only that label and your word.

**Never open the delivered HTML** — no `open <file>`, no `--open`. Dev Desk moves to its Diagrams tab
and renders the file inline the moment this run ends; a browser window on top of that is noise.

## Undated, therefore unproven

Exercised once, on 2026-08-31: `architecture`, `standard`, evidence with `--repo-root`, the
tamper-refusal codes, and the repair-by-simplification rule.

**Never run:** `--showcase`, `--open`, `--out`, the fetch-and-extract path in Phase 2, the Phase 3
refusal gate, the 10-cycle stop, and the four non-architecture diagram types. They are written from
the schema and the CLI's own help, not from a run — treat the first use of each as its own trial.

## Scar tissue

**2026-08-31 — the trial that produced this skill.** A data-flow map of an eleven-stage build
pipeline across two execution lanes took **eight** validate cycles to pass. Two of the failures were
real defects that would have shipped: an edge routed straight through an unrelated node, and
diagonal segments the renderer rejects outright. The rest were label clearance under `showcase`, and
the fix that finally worked was not more geometry — it was deleting a node and moving its fact into
a card, which is the renderer's own advice and produced the better diagram.

The artifact passed `9/9 artifact checks` and **had no evidence backing at all**. It looked
checked, because it was — for form. Every node was still just an assertion. That gap is why Phase 5
exists, and it is the single thing to get right if any of the rest is rewritten.

**2026-08-31, later the same day — the first run that actually used evidence found three defects in
the text above.** An architecture map of a real eleven-stage build pipeline in another repository,
12 components, every one pinned to a verified commit: `9/9 artifact checks`,
`sha256 b539a7135671`, **two** validate cycles rather than eight — because
the one failing edge was deleted and its fact moved to a card, which is this skill's own advice and
had never been tried.

What the run overturned:

- **Evidence is `architecture`-only.** Phase 1 offered five types and Phase 5 made evidence
  mandatory for all of them, so four of the five would have been undrawable: Phase 5 forbade an
  unevidenced node and Phase 2 forbade falling back. The `opt-in` claim came from an upstream README
  sentence that scopes it to architecture, read as if it were general. **Nobody caught it because
  the trial above never evidenced anything.**
- **`guide`'s `confidence: low` is a no-match fallback**, not a weak recommendation, and the old
  advice — *split the question and ask again* — cannot converge, because both halves return the
  same fallback. `xyzzy` scores identically to a well-formed lifecycle question.
- **`PNG/SVG exports` overstated the handoff.** They are a viewer button, and per upstream's own
  schema notes they carry no repository evidence.

What the run *confirmed*, and is worth keeping: the verification is real, not decorative. A line
past end-of-file, a path absent at the commit and an unknown SHA are each refused with a distinct
rule code, and because the check runs against a local clone it works on a **private** repository.
