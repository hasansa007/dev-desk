# 0023 — The gate ran late, and took the fold with it

Status:  Accepted
Date:    2026-09-12
Commit:  (this branch)  ·  `fix/desk-delete-hardening-and-one-card-shape`
Amends:  0022 (decisions 1 and 4), 0021 (card anatomy)

## Context

[#69](https://github.com/hasansa007/dev-skill/pull/69) was merged on request with Phase 13 skipped.
The PR body said so rather than claiming a gate it had not run, and the omission mattered more than
usual: that diff added the first code in this app that can destroy work. The gate ran afterwards,
against the merged diff `e8c421d..744bb01`, and returned fifteen findings. Each was verified against
the code before it was accepted; one was narrowed and one sub-point refuted.

Three of them contradict decisions ADR 0022 had just made.

**The delete was the only unhardened git call in the app.** `GitCommand.read` exists to neutralise
programs a repository controls — `core.fsmonitor`, `core.hooksPath`, external diff, the signature
verifiers — and every invocation goes through it, *including the `worktree add` write* at
`TaskFolder.swift:163`. `BranchWrite` passed argv raw. `git branch -D` fires `reference-transaction`
hooks, so a hostile repository ran its own program during the one operation that destroys. This is
the class ADR closed by #57 had just shut. `BranchWriteTests` asserted the *arguments* and never the
*invocation*, which is exactly why nothing caught it.

**An uncounted branch was read as a branch with nothing to lose.** `unmergedCount` was set only on
branch cards; the sheet read `?? 0`. A pull request's card — which `pullRequestTask` gives a branch
and no count — therefore offered a one-press delete under the sentence *"its commits are in the base
branch already, so nothing is lost"*, about a branch nothing had counted. The repository already
carries this scar once, in `0a660d5`: *judge promisor flags by git's boolean rule, fail closed.*

**Fourteen days never answered the question it was invented for.** ADR 0022 recorded the guess
honestly and even named the escape hatch — one constant, movable "when the repository says
otherwise". The repository said otherwise immediately: #69's own PR body established that the
nineteen branches were **abandoned, not stale**, at one and two days old. No threshold catches that.
A fold keyed on age was answering a question about intent with a measurement of time.

## Decision

**1. The stale fold is deleted, not tuned.** `BranchAge.staleAfter`, `isStale`, `showStale`, the
`Show stale (N)` toggle and its count are gone. `BranchAge.label` stays — a card still reads
`6 commits ahead · 8 d ago`, because the *date* was never the problem; hiding rows by it was. ADR
0022 decision 2 (newest-first) and decision 3 (the branch menu) stand, and they are what actually
clears a dead branch.

**2. Every git invocation is hardened, the destructive one included.** `GitCommand.read` names the
flags, not the operation; a write needs them more than a read does. A test now pins the invocation
shape, beside the one that pins it for reads.

**3. An uncounted branch is not a branch counted at zero.** `BranchWrite.requiresTypedName(unmerged:)`
returns true for nil, the confirmation has an arm that says plainly that nothing has counted it, and
the sheet reads the count **once, on open**, so a reload cannot lower the gate while it is raised.

**4. `-d` runs first every time, even when the name has been typed.** ADR 0022 claimed git's own
refusal as a layer of the design. It was not one: a branch card exists only for a branch with
unmerged commits, so every delete the board could reach was already `-D`, and the safe flag was
decoration. Now the safe attempt always runs, and `-D` runs only after git itself has refused. A
typed name authorises the escalation; it does not skip the attempt. A count read up to two minutes
ago no longer forces what git would have allowed safely.

**5. Delete is offered only on a plain local branch card.** An open pull request points at its head,
which makes that branch the opposite of abandoned. Pull request cards keep terminal, compare and copy.

**6. Every card has one anatomy** — title, `age · commits ahead`, impact and complexity, a dash
wherever nothing is known — so an issue card and a branch card are the same shape. Issue and pull
request cards carry the branch facts they already held and were discarding. This extends ADR 0021's
one-dialog rule to the card that opens it.

## Consequences

- **The board shows every branch again**, however old. The column sort is the only thing ranking
  them, and `BoardOrder.newestFirst` is now a tested function: dated newest-first, undated after in
  the order the builder produced. The previous inline sort put every *undated* card above real work
  and left an all-undated column — a queue — to an unstable sort, which would have quietly permuted
  `dev.py`'s priority ranking.
- **A forced delete costs two git calls** when the branch really is unmerged. That is the price of
  the refusal being real, and it is paid only on the destructive path.
- **ADR 0022's consequence about a hidden stale branch no longer applies**, because nothing hides.
- **The dead error cases are gone.** `checkedOut` and `unmergedNeedsConfirmation` carried user-facing
  sentences no code path could reach; git's own stderr is shown instead, under a banner that now
  names the thing that failed rather than saying "the tracker was not changed" about a branch.
- **Two findings are filed, not fixed**: [#70](https://github.com/hasansa007/dev-skill/issues/70) the
  refresh ring counts down to a reload on a different schedule, and
  [#71](https://github.com/hasansa007/dev-skill/issues/71) a decomposed epic in BACKLOG gets no chips
  and no Build. Both need a decision rather than a correction, so neither was made quietly here.

## Alternatives rejected

```
rejected: keep the fold, move the threshold into Settings — a preference for a question age cannot
          answer; a setting would have made the wrong axis configurable rather than removing it
rejected: fold on evidence instead of age — head already in the base, or a merged/closed PR. This is
          a real idea and it may come back, but it is new behaviour, and this branch is a review's
          fix list, not a feature
rejected: keep -D as the board's only path and explain in the ADR why -d is unreachable — an ADR that
          explains away a claim it made two days earlier is how a record stops being evidence
rejected: drop `force` entirely and always run -d — then a branch with unmerged commits could never
          be deleted from the app at all, which is the gap #69 existed to close
rejected: give BranchWrite its own hardening list — one list, or the next write added forgets a flag
```
