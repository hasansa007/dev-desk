## Phase 0 — Filing (standalone entry only)

Creating the work item. Reached ONLY from `dev:create-bug` / `dev:create-issue` /
`dev:create-epic` — a `/dev` run never executes it, because by then the item exists. It produces one
issue number and stops.

### Filing is intake, not work

- **Not investigation.** The report describes the symptom; Phase 4 finds the cause. No repro
  attempts, no grepping, no reading the handler — a filing door that debugs turns a one-minute
  capture into an afternoon, and the item still is not filed.
- **Not decomposition.** An epic is filed as ONE issue. Its slices are cut at Phase 5, where context
  load, discovery and investigation have actually happened; here they would be imagined.
- **Not a branch.** Phase 3 owns branch timing and cuts at the first WRITE. A branch opened here
  would pre-commit a decision Phase 5 has not made yet.

The whole phase is one turn. If it is taking three, it has become the work.

### The sequence

1. **Resolve the repo** — `entry.md` → Workspace Resolution. An issue filed into the wrong tracker
   is invisible where it is needed and noise where it landed.
2. **Read 2–3 existing issues of the same type before drafting** — `gh issue list --limit 10 --json
   number,title,labels`, then `gh issue view <N>`. This is Universal Rules' *read 2–3 examples first*
   applied to the tracker: an issue that does not look like its neighbours gets triaged like an
   outsider's.
3. **Search for the item before drafting it** — `~/.claude/.dev-root/shared/duplicates.md`, steps
   1–2. A match on the same outcome ends the phase: comment on #N and hand #N back, filing nothing.
   Step 2 above reads issues for their *style*; this reads them for their *content*, and is a
   different search.
4. **Resolve the labels that EXIST** — `gh label list --limit 60`. **Never pass a label absent from
   that output.** `gh issue create --label <unknown>` fails outright, and the reflex fix — drop the
   label, file anyway — produces an unlabelled issue that no board query will ever surface. A
   missing label is a taxonomy decision: ask, never create one silently.
5. **Draft the whole thing, then ask at most TWO questions.** Draft first, never interview: a fixed
   questionnaire is the ceremony this pipeline exists to refuse, and it guarantees the item gets
   filed later or never. Ask only where a wrong guess changes the issue materially — *"every course
   or only long lists?"* changes it; *"what priority?"* does not, so propose one. Mark every
   inference as one: *"(assumed: RTL only — correct me)"*. **Zero questions is the good outcome, not
   a shortcut.**
6. **Show the draft — title, body, labels, milestone — before it exists.** Filing is cheap to do and public to
   undo; an issue edited three times in its first minute was public in all three.
7. **Create it, place it, then hand off** — `duplicates.md` steps 3–4: a milestone that covers it
   (`gh issue create --milestone`), a sub-issue link to its parent, and the net line — then
   `entry.md` → *Never end silently*.

````bash
gh issue create --title "<title>" --label "<resolved labels>" --body "$(cat <<'EOF'
<body>
EOF
)"
````

### Rules

- **One item per invocation.** Three problems in one description are three issues — say so and ask
  which to file, or file the first and name the rest. Silently folding them into one produces the
  issue that later gets half-closed.
- **The type is a default, not a contract.** `dev:create-bug` pointed at something plainly a feature
  files a feature and says so. Stop on Ambiguity outranks the door you came through.
- **These issues never auto-close** — `Closes #N` does not fire in a repo whose feature PRs target
  pre prod. `dev:prod` → *Next* offers the write-back; that is where they close.

> The per-type templates live in the three `dev:create-*` members — that is the only thing that
> differs between them, and it is the only thing they hold.

---

