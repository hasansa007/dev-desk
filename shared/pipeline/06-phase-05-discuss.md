## Phase 5 — Discuss Before Building (REQUIRED)

**This gate comes before any design, plan, or code.** Phase 6 designs, Phase 7 plans, Phase 9
builds — this is where you find out whether the right problem is even being solved. It runs here,
after Phase 4, so the discussion is informed: for bugs the root cause is confirmed; for features
the affected area is understood. (Phase 3's branch already exists by now — that's fine, a branch
is cheap and reversible. An approach committed to without discussion is neither.)

Use `superpowers:brainstorming` — explore intent, requirements and shape **in plain language**,
then get an **EXPLICIT go-ahead** before producing a plan or touching code.

**This stop and Phase 6's are the same stop — the decision pack.** Do not hand back here, take an
answer, and hand back again for the architecture: run Phase 6's fan-out while you have the
conversation, and present the clarifications, the approaches with your recommendation, and the slice
plan (count and bill, Phase 8) in ONE message. Two hand-backs bought nothing but latency — ADR 0049.
When Phase 6 does not apply the pack is just this gate, unchanged.

**Skip only for trivial changes** (typo, copy edit, dependency bump). A plan written without this
step is a guess with formatting on it.

How to run it:

- **Plain language, not file paths.** If the developer has to read a diff to follow the proposal,
  it isn't a discussion yet.
- **Step by step — one thread at a time.** Do not dump a roadmap and ask for approval of all of it.
- **Name ambiguities and contradictions explicitly, and STOP.** Never implement a silent guess;
  a wrong assumption discovered at Phase 9 costs the whole branch.
- **Propose, then wait.** "Go ahead" is a specific thing the developer says. Inferring it from
  their interest in the topic is how unrequested work gets built.

### Ask for THEIR approach before you show yours (REQUIRED)

Approving a plan and understanding it are different things, and only one of them is checked by
"go ahead". This step checks the other, because the developer has said the point of the pipeline is
to build their model of the system rather than to hand them a finished one.

**Order matters and is not negotiable:**

1. State the problem and the constraints you found in Phase 4 — the mechanism, what the code already
   does, what cannot change. Plain language.
2. **Ask how they would approach it. Then stop and wait.**
3. Only after they answer, give your approach and **diff the two out loud**: where you agree, where
   you differ, what their version would cost that theirs might not have priced in. **If theirs is
   better, take it and say so.**
4. Print the alternatives line either way — `rejected: <option> — <why it lost>` per line, or
   `alternatives considered: none — one correct form`. Printed even when empty: that line is how
   they audit whether something was presented as mechanical when it was actually a decision.

**Showing your plan first defeats this entirely.** A plan on screen is an anchor; what comes back is
a reaction to it, not an independent approach, and no amount of asking afterwards recovers what was
lost. This is the single easiest step in the pipeline to perform the form of while destroying the
substance — the tell is a message that contains both the question and your answer.

**`just do it` skips it, immediately and without argument.** Both this and Phase 5's own
decomposition subsection are stop-gates, not persuasion.

Feeds Phase 7: the approach that survives this is the one the plan is written from, and the
`rejected:` lines become the ADR's alternatives at Phase 12 rather than being reconstructed from
memory after the merge.

### Decomposition — when this is several tasks (conditional)

**When:** the work spans several branches, surfaces or sessions — whether or not it arrived labelled
an epic. **Skip** when it is one task, which is most of them.

This is the only phase that can do it. Phase 0 filed the item before anything was known; by here,
context load, discovery and investigation have all run, so the seams are **observed rather than
imagined** — and a wrong seam is expensive, because each child becomes its own branch, PR and
promotion. (These are epic CHILDREN, not Phase 9's in-ticket slices: a child ships on its own, a
slice cannot.)

1. **Propose the children in plain language** — with dependencies and the order you would take them.
   Each must be **independently shippable**. A child that cannot reach pre prod without another is
   not a child; fold it into the one it depends on.
2. **Wait.** Phase 5 is a stop-gate and filing children is a write.
3. **Then file each as its own labelled issue and attach it to the parent:**

````bash
N=$(gh issue create --title "..." --label "..." --body "..." | sed 's#.*/##')   # create prints the URL
gh api repos/<owner>/<repo>/issues/<PARENT>/sub_issues -F sub_issue_id="$(gh api repos/<owner>/<repo>/issues/$N --jq .id)"
````

   **`sub_issue_id` is the issue's DATABASE id, never its number** — and `gh issue create` has no
   `--json`, so the id is read back with `gh api`. Verified 2026-09-12, gh 2.92.0, filing #60–#67.

4. **Never `- [ ]` checkbox lines for children.** A checklist in the parent body is invisible to every
   board query, carries no label, and cannot be worked by `/dev #N`.
5. **Continue this run on the FIRST child, and say which.** The parent is a tracker — it takes no
   branch and stays open until its children close. Later children are their own `/dev #N` runs: the
   sub-issue list IS the queue, it lives on GitHub, and it therefore survives the session that
   created it. Nothing about an epic is held in the conversation.

### UI discussion (conditional)

**Skip entirely for backend-only work.** When the change adds or alters anything the user sees,
settle the design here — before the plan, and long before the build:

1. **Does this pattern already exist?** Consistency is weighted heavily: parallel flows should
   reuse the same shell, the same CTA verb, and the same dialog SIZE. Find the closest existing
   surface and start from it. Actively call out and kill per-flow divergences — a second dialog
   footprint for the same job is a bug, not a variation.
2. **Reuse the design system, never invent a parallel one.** Use the `frontend-design` skill.
3. **Mock anything visually novel and get the mock APPROVED before implementing.** An approved
   mock costs minutes to change; a built screen costs hours, and by then it is defended.
4. **Say which states you are designing** — empty, loading, error, RTL/LTR — before building the
   happy path only.

---

