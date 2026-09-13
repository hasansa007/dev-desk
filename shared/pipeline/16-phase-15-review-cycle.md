## Phase 15 — Review Cycle (loops BACK to Phase 14)

**This is a loop, not a stage.** Human review comments arrive while the PR is still OPEN. Its
last step is `push`, never `merge` — you re-enter Phase 14's pre-merge gates and go round again
until the review is clean. It happens BEFORE pre prod, and long before Phase 16's promotion.

**Name the gates you are re-entering: 12 (docs) and 13 (review).** Pushing is not the end — the
diff changed, so the gates that were clean no longer are. **Review fixes are a classic way for an
ADR to drift out of date silently**: the decision gets revised in code while the doc still records
the version the reviewer objected to. Phase 12 reads "BEFORE any merge", not "once, early" — it
runs again on every turn of this loop.

**Trigger:** "changes requested", "review feedback", "fix PR comments", PR URL with review, or mention of reviewer feedback.

1. **Fetch PR review comments:**
   ```bash
   gh pr view <PR_NUMBER> --comments
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/reviews
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments
   ```

2. **Present review feedback as structured list:**
   ```
   ## Review Changes — <TICKET/ISSUE>

   ### Comment 1 (reviewer: @username)
   File: path/to/file:42
   > quoted review comment

   **Proposed fix:** description of what to change
   ```

3. Follow the `receiving-code-review` skill protocol:
   - Restate each requirement in your own words
   - Check against actual codebase context before implementing
   - **Push back** with technical reasoning when suggestions break existing functionality, violate YAGNI, or conflict with established architecture
   - Implement one item at a time with testing

4. Ask for confirmation: "Here's the plan to address review comments. Proceed?"

5. After fixes: commit (new commit — never amend), push.

---

