# Duplicates — the one rule every filing door applies before it files

Read by `dev:create-issue` / `create-bug` / `create-epic` (Phase 0), `dev:findings` (Phase 9),
`dev:roadmap` (Phase 6), and stated for the developer in Dev Desk's Add Task (ADR 0045). **One copy**:
a door that needs a variation adds it at its own point of use and cites this file, never restates it.

**Why it exists.** Issue numbers only grow; the open count is what a filing door can make worse. On
2026-09-16/17 two runs filed 23 issues into studyhub-deploy, and 4 of them restated open issues nobody
had linked (see `dev:roadmap` → Scar tissue). Every door read the tracker; none acted on what it read.

## 1 — Search before drafting

With a tracker — per path when the item names files, per key phrase when it does not:

```bash
gh issue list --repo <owner/repo> --state open --search "<path | key phrase> in:title,body" \
  --json number,title,milestone,body
```

Without one (ADR 0027) — the same words over `docs/backlog/*.md`, titles and bodies.

**A failed search is not an empty one.** If `gh` errors, say so and stop: a failed dedupe files
everything as new (`dev:board` Phase 3's rule).

## 2 — Decide, per match

| The new item… | Then |
|---|---|
| is the **same fix / same outcome** as an open issue | **file nothing.** Comment what is new on #N (evidence, a case, a bullet) and hand #N back as the result |
| is **one piece** of an open umbrella or epic | file it, attach it as a **sub-issue** of that parent (`sub_issue_id` = `.id`, not the number) |
| is in the **same area, different mechanism** | file it, `related to #N` in its body |
| matches nothing | file it |

**Only the same fix site, or the same user-visible outcome, merges.** Same file, same label or the
same word is `related` at most. A wrong merge hides a real item; a wrong split costs one close.
**Uncertain → do not merge:** file it and name *possible duplicate of #N* in the body and the reply.

## 3 — Place it

Every filed item lands in an open milestone whose description covers it
(`gh api repos/<o>/<r>/milestones`), or is named as **unplaced** in the door's result. Placing is a
lookup, not a theme decision: **only `dev:roadmap` creates milestones.**

## 4 — Say the net

End with one line: `opened <n> · merged into existing <n> · related <n> · open <before> → <after>`.
A door that filed one issue says `opened 1`; a door that merged says so — *"no new issue: added to #700"*
is a complete, good result.
