# Acceptance-criteria coverage: issue 88

Sources: **AC** is an acceptance criterion from the issue.  **Risk** is from section 6 of the architect's design.  **Critic 1** is a finding from the first `design-critic` pass; its raw text is not in the change files, so each row names the finding through the owner decision that resolved it.  **Critic 2** is a finding from the second pass, in `.spec-flow/design-decisions.md`.  **Seam 1** is an owner answer at spec review (S2–S5 and the two redirects in `.spec-flow/design-decisions.md` and `.spec-flow/seam1-feedback.md`).

| Source | Requirement | Covering scenario(s) | Status |
|--------|-------------|----------------------|--------|
| AC | **Presenting to the owner** defines the format: four parts in order, the pre-send check word for word, and the vocabulary ban with its terms | `owner-presentation: A reader opens the contract`; `owner-presentation: The check is in the contract`; `owner-presentation: A reader checks the ban` | ✅ Covered |
| AC | Each option states its effect, pros, cons, and tradeoff; effect only or cost only fails | `owner-presentation: An option states only its effect`; `owner-presentation: An option states only a cost` | ✅ Covered |
| AC | A named issue or PR has `<number>: <title>`, filing date, author, and why it exists; "created this session" when true | `owner-presentation: A question names an older issue`; `owner-presentation: A question names an issue the agent just filed` | ✅ Covered |
| AC | The format covers live questions, issue comments, PR bodies, and `needs-attention` comments | `owner-presentation: A reader checks what the format applies to` | ✅ Covered |
| AC | Every in-scope file points to the format; none holds a copy | `owner-presentation: A reader checks an in-scope file`; `owner-presentation: A reader searches for copies` | ✅ Covered |
| AC | `🆘 Needs attention:` comments and draft-PR open questions point to the format | `owner-presentation: implement stops on a failed gate`; `owner-presentation: Open questions at a draft PR` | ✅ Covered |
| AC | `product-manager` and `architect` prompts follow the format | `owner-presentation: product-manager returns questions`; `owner-presentation: architect returns design options` | ✅ Covered |
| AC | The existing rules stay, none weaker | `owner-presentation: A reader checks the existing rules`; `owner-presentation: A skill's own citation rule` | ✅ Covered |
| AC | No exception allows several questions in one message | `owner-presentation: A reader searches for an exception` | ✅ Covered |
| AC | Several questions: list them up front as bullets, then one per message | `owner-presentation: An agent has several questions` | ✅ Covered |
| AC | `groom` asks each assumption in its own message, with a recommendation | `owner-presentation: The closing pass returns five assumptions` | ✅ Covered |
| AC | `setup` and the Seam 1 review ask each item in its own message | `owner-presentation: setup finds three missing prerequisites`; `owner-presentation: A spec with two overrides` | ✅ Covered |
| AC | Step 1 runs one `gh issue view <M> --json createdAt,author,state,labels` and puts the facts in the question | `backlog-overlap: One hit on the shortlist` | ✅ Covered |
| AC | Step 1 may read that one issue in full when its title is not enough, and no other | `backlog-overlap: A vague title`; `backlog-overlap: A clear title` | ✅ Covered |
| AC | Step 1 offers all four options, each stating what happens | `backlog-overlap: Step 1 asks about a hit` | ✅ Covered |
| AC | "related, a duplicate, or a dependency" no longer appears as the question | `backlog-overlap: A reader searches step 1` | ✅ Covered |
| AC | No hits, no backlog question | ``backlog-overlap: The shortlist is `none` `` | ✅ Covered |
| AC | Close or fold-in: a short comment on M says it closes when this PR merges | `issue-closure: A first record`; `backlog-overlap: The owner picks close` | ✅ Covered |
| AC | Close or fold-in: the PR body has `Closes #M` alongside `Closes #N` | `issue-closure: The owner picked close`; `issue-closure: The owner picked fold-in` | ✅ Covered |
| AC | Fold-in adds M's scope to this issue's acceptance criteria | `backlog-overlap: The owner approves the draft` | ✅ Covered |
| AC | When the PR merges, M is closed and the owner closes nothing by hand | `issue-closure: The PR merges and GitHub closes nothing extra`; `issue-closure: GitHub left M open` | ✅ Covered |
| AC | The choice reaches a PR opened later, in a different session | `issue-closure: A later session opens the PR` | ✅ Covered |
| AC | A PR-body rewrite keeps `Closes #M` | `issue-closure: implement marks the PR ready` | ✅ Covered |
| AC | `Closes #M` holds on the normal, docs, and tech-debt paths | `issue-closure: The owner picked close`; `issue-closure: The docs and tech-debt paths`; `issue-closure: An empty list` | ✅ Covered |
| AC | Leave open or block: no `Closes #M`, no close-on-merge comment on M | `issue-closure: The owner picked block`; `backlog-overlap: The owner picks leave open`; `backlog-overlap: The owner picks block` | ✅ Covered |
| AC | GitHub leaves M open after merge: `finalize` closes it | `issue-closure: GitHub left M open`; `issue-closure: The PR merges and GitHub closes nothing extra` | ✅ Covered |
| AC | The PR closes without merging: M stays open | `issue-closure: The PR closed without merging` | ✅ Covered |
| AC | M already closed at merge: nothing fails, nothing reopens it | `issue-closure: M is already closed` | ✅ Covered |
| Risk | Title injection through issue titles and M's body | `issue-closure: A title with shell characters`; `issue-body-edits: A body with shell characters`; `backlog-overlap: The owner approves the draft` | ✅ Covered |
| Risk | The no-bodies rule gets exactly one new exception | `backlog-overlap: A vague title`; `backlog-overlap: The owner approves the draft` (two narrow exceptions, per Q8) | ✅ Covered |
| Risk | The five-question cap in step 1 should not count backlog hits | `owner-presentation: Step 1 has seven questions` (the cap is removed, per Q14) | ✅ Covered |
| Risk | The Seam 1 "Your options" block must follow the format | `owner-presentation: A spec with two overrides`; task 6.4 | ✅ Covered |
| Risk | The `implement` failure path: residual list is information, body starts with the closing lines, `needs-attention` asks one question | `owner-presentation: Unresolved fix-loop findings`; `owner-presentation: implement stops on a failed gate`; `issue-closure: The docs and tech-debt paths` | ✅ Covered |
| Risk | Blast radius: about 13 prompt files, one JS argument, two scripts | ⚠️ Excluded: an impact statement, not a behavior; recorded in `proposal.md` Impact and `design.md` Risks | ⚠️ Excluded |
| Critic 1 | M stays pickable as "Next up" while N is about to close it (Q4) | `issue-closure: A first record` (the "M blocked by N" link) | ✅ Covered |
| Critic 1 | A concurrent edit erases part of the issue body (Q6) | `issue-body-edits: The owner edits while the agent drafts`; `issue-body-edits: An edit lands inside the window` | ✅ Covered |
| Critic 1 | A search for M's PR finds this PR (Q7) | `backlog-overlap: M has an open PR`; `issue-closure: A reader checks Naming` | ✅ Covered |
| Critic 1 | Fold-in could copy another author's text or invent criteria (Q8) | `backlog-overlap: The owner approves the draft`; `backlog-overlap: The owner edits the draft` | ✅ Covered |
| Critic 1 | A closed M keeps its lifecycle labels (Q9, then C9) | `issue-closure: GitHub left M open`; `issue-closure: M is already closed` | ✅ Covered |
| Critic 1 | A written question has no defined follow-up (Q11) | `owner-presentation: The owner answers on GitHub`; `owner-presentation: The owner answers in the session` | ✅ Covered |
| Critic 2 | 1: parsing ignores code fences; duplicate heading unspecified | `issue-body-edits: A heading inside a code fence`; `issue-body-edits: A duplicate heading` | ✅ Covered |
| Critic 2 | 2: a write between the check and the write goes undetected | `issue-body-edits: An edit lands inside the window` | ✅ Covered |
| Critic 2 | 3: a `close-merged` failure cannot be retried after the worktree is gone | `issue-closure: close-merged fails twice` | ✅ Covered |
| Critic 2 | 4: per-override Seam 1 questions clash with auto-approve, approve-from-comment, the resume marker, and redirect timing | `owner-presentation: Auto-approve with no hard conflict`; `owner-presentation: Auto-approve with a hard conflict`; `owner-presentation: A resumed session with pending entries`; `owner-presentation: The owner keeps the existing behavior on one entry` | ✅ Covered |
| Critic 2 | 5: written questions have no "which is next" state; PR replies unread; `needs-attention` lifecycle; board shows the newest 🆘 comment | `owner-presentation: Three questions for an absent owner`; `owner-presentation: A PR body at a draft stop`; `owner-presentation: A needs-attention series`; `owner-presentation: implement stops on a failed gate` | ✅ Covered |
| Critic 2 | 6: no undo for a record; the loop check covers only direct links | `issue-closure: The owner changes their mind`; `issue-closure: GitHub refuses the link`; `issue-closure: GitHub accepts a loop` | ✅ Covered |
| Critic 2 | 7: briefing "once on return" vs "every time"; a separate message in a live session | `owner-presentation: The owner attaches to a waiting session`; `owner-presentation: The second question in a series` | ✅ Covered |
| Critic 2 | 8: `close-on-merge.sh check` undefined; the body rule also catches issue creators | `issue-body-edits: groom creates an issue` (`check` is dropped, per C8) | ✅ Covered |
| Critic 2 | 9: `close-merged` leaves `blocked`, `merge-on-green`, and native links on M | `issue-closure: GitHub left M open`; `issue-closure: A label survives` | ✅ Covered |
| Critic 2 | 10: step 1 temp files land in the checkout before isolation | `backlog-overlap: Step 1 before isolation`; `backlog-overlap: The fold-in draft is written` | ✅ Covered |
| Seam 1 | Redirect: no per-round question limit in `groom` or `product-manager`; no hard-coded limit anywhere | `owner-presentation: A round returns five questions`; `owner-presentation: A round has more open items than three`; `owner-presentation: A question without a default in a large round`; `owner-presentation: A reader searches for a question limit` | ✅ Covered |
| Seam 1 | Redirect: `issue-body.sh` stops with an error naming the missing section and changes nothing | `issue-body-edits: append on an absent section`; `issue-body-edits: replace on an absent section`; `issue-body-edits: The only match is inside a code fence` | ✅ Covered |
| Seam 1 | S2: only record comments by the pipeline's `gh` user count | `issue-closure: A stranger's comment` | ✅ Covered |
| Seam 1 | S4: the adjacent-behavior reader falls back to the old body section | `issue-body-edits: An issue activated before this change` | ✅ Covered |
| Seam 1 | S5: needs-attention first line `🆘 Needs attention: Question k of n: <the decision>` | `owner-presentation: A needs-attention series`; `owner-presentation: implement stops on a failed gate` | ✅ Covered |
| AC | A live question uses the menu picker, recommended option first, so Enter picks it (added by the owner during implementation) | `owner-presentation: A live question with a recommendation`; `owner-presentation: The owner presses Enter`; `owner-presentation: Too many options for the picker`; `owner-presentation: A written question` | ✅ Covered |
