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
allowed-tools: [node, git, rg, gh]
---

# arch — draw the system, and prove the drawing

A **tool**, not a phase. It maps to no phase number, takes a target (a repo, a subsystem, a diff,
or a plain description), and returns one artifact. It never edits code and never files an issue.

`dev:docs` checks that prose is current. `dev:issues` renders a board as text. `dev:shots` captures
a running UI. This is the only door that draws the **shape** of a system — the thing prose serves
worst, and the thing someone needs when onboarding, reviewing a design, or presenting the work.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| A target (`the build pipeline`, `web/app/lib`, a description) | what to draw | required |
| `architecture` · `workflow` · `sequence` · `dataflow` · `lifecycle` | force the type | pick it from Phase 4's table |
| `--showcase` | the strict quality profile, for a deck | `standard` |
| `--open` | open the artifact when it passes | off |
| `--out <path>` | where the HTML lands | the repo's scratch dir, never the repo |

**Nothing is written into the repository by default.** A diagram committed to a repo becomes
`dev:docs`'s problem forever — see *Known limits*. Landing one is a deliberate, separate act.

## Phase 2 — Resolve the renderer

Archify is a **hard dependency** and this skill does not pretend otherwise. Resolve it in this
order and stop at the first hit:

1. An `archify` directory already extracted under the scratch dir
2. A global install (`npx skills` put it in the agent's skill directory)
3. Fetch `archify.zip` from the repo and extract it into the scratch dir

```bash
node <archify>/bin/archify.mjs doctor
```

**Export `ARCHIFY_UPDATE_CHECK_DISABLED=1` on every invocation.** Upstream performs a periodic
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

Ask the renderer rather than guessing — it answers with a confidence level and says what to include:

```bash
node <archify>/bin/archify.mjs guide "<one sentence describing the system>"
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
- **`workflow` · `sequence` · `dataflow` · `lifecycle` — evidence is UNAVAILABLE.** Draw them, and
  **say in the handoff that the diagram is unevidenced.** That sentence is the only thing standing
  between the picture and a reader who assumes it was checked, because nothing in the artifact
  itself will say so.
- A description-only diagram (no repository) is legitimate, and must be **labelled as such** in
  the artifact's own cards.

The pin is proven, not trusted: a line past end-of-file, a path absent at that commit, and an
unknown SHA each fail with their own rule code — `repository-evidence/line-out-of-range`,
`/file-missing`, `/revision-unavailable`. Verification is local, so a **private** repository works.
That is what makes an evidenced architecture diagram worth more than the prose it replaced; on the
other four types, only the spoken caveat does.

## Phase 6 — Author, validate, repair, deliver

```bash
node <archify>/bin/archify.mjs validate <type> <ir.json>
node <archify>/bin/archify.mjs deliver  <type> <ir.json> <out.html>
```

The validator returns machine-readable repairs — a stable rule code, the exact subject, measured
evidence, and the supported repair controls. Apply them; do not guess.

**The repair loop is capped at 8 cycles.** At the cap, do not keep tuning geometry — **simplify the
diagram**. The renderer's own guidance is the right instinct: *supporting detail belongs in cards,
not in more edges*. Deleting a node and moving its fact to a card is a better diagram, not a
compromise.

**Default `quality_profile: "standard"`.** `composition/label-route-clearance` is `showcase`-only
and strict; on a dense diagram it costs cycles without changing what the reader learns. `--showcase`
is for a deck, where the polish is the point.

Report the receipt verbatim when it passes — `N/N artifact checks`, the profile, the `sha256`.

## Rules

- **Never write into the repository without being asked.** Default output is the scratch dir.
- **Never present an unvalidated diagram.** If `deliver` did not pass, there is no artifact.
- **Never claim runtime behaviour.** Reach, routes, and roles are *authored* relationships. The
  diagram says what the code is wired to do, never what production actually did.
- **Never draw from memory of a codebase.** Re-read at the commit you are pinning to.
- **Say which commit.** The artifact is only as true as the SHA it was built from.

## Never

- Never fall back to an unvalidated renderer when Archify is unavailable — stop instead.
- Never mark a node evidenced without opening the file and the lines.
- Never leave `ARCHIFY_UPDATE_CHECK_DISABLED` unset.
- Never commit an artifact as part of unrelated work — landing one is its own decision.

## Known limits

| | |
|---|---|
| Evidence is `architecture`-only | `--repo-root` is refused on the other four types. They can be drawn but never proven, so they carry a spoken caveat where architecture carries a guarantee. Verified 2026-08-31 against Archify 2.16.0 |
| `guide` cannot say "I don't know" | It falls back to `architecture` + `confidence: low` for anything it fails to keyword-match, which is indistinguishable from a real recommendation. Pick the type yourself when confidence is low |
| Exports drop the evidence | Repository evidence is embedded for the Semantic Passport and Node Finder only. A PNG or SVG pulled out of the viewer carries none of it, so the image is not the artifact — the HTML is |
| Diagram rot is worse than prose rot | A picture reads as authoritative long after it stops being true. Any artifact committed to a repo needs an owner in `dev:docs`; until that exists, keep output out of the tree |
| The validator checks form, not truth | Schema, layout, routes and clearance all pass on a diagram that describes the wrong system. Phase 5 is the only thing standing between the two |
| Upstream is young | Archify was created 2026-04-15. Popular is not audited; nobody in this family has read its source |
| Its README is partly a funnel | It carries sponsor referral links. Read the technical claims on their merits |
| Layout is hand-tuned | Passing `showcase` on a dense diagram means the agent adjusting pixel offsets against a validator. That is the cost, and it is why `standard` is the default |

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
the text above.** An architecture map of a real eleven-stage pipeline
(`hasansa007/studyhub-deploy` at `4cb7c05`), 12 components, every one pinned and verified:
`9/9 artifact checks`, `sha256 b539a7135671`, **two** validate cycles rather than eight — because
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
