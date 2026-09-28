## Context

This change has two halves.  Most of it edits instruction prose: the owner-question contract in `docs/workflow.md` and the prompt files that point to it.  The rest is code: two new bash scripts, their tests, and one new required argument on `implement.workflow.js`.

The design was settled at `activate`: one `architect` pass, two `design-critic` passes, and the owner's answers at the design stop.  The architect's proposal is in `.spec-flow/architect-design.md`.  The owner's answers are in `.spec-flow/design-decisions.md` and in the `🧭 Design decided` comment on the issue.  Where the owner chose differently from the architect, the owner's choice is the design below.  The architect's recommendation then appears only under **Alternatives Considered**, marked as an owner override.  Some later answers supersede earlier ones; the design applies the latest.

No domain expert was consulted, so this document has no Domain Facts section.

All paths are under `plugins/spec-flow/` unless stated.

## Goals / Non-Goals

**Goals:**

- One question format, defined once in `docs/workflow.md`, that every owner question follows, live or written.
- One question per message, with no exceptions anywhere in the plugin.
- A backlog-hit question that states the facts about the other issue and offers four options named by what they do.
- Close-on-merge that needs no manual step, survives a new session, and survives every PR-body rewrite.
- Issue-body edits only for requirement changes, through one script that cannot silently erase another edit.

**Non-Goals:**

- Pulling issue bodies over the whole backlog.
- Changing how the blocking option works.
- Auto-closing issues from any decision other than the `activate` step 1 backlog-hit question.
- Changing any PR lookup (`Closes #N in:body`).
- Splitting `activate` step 1.  That is 89: spec-flow: split activate step 1 into claim/shortlist validation and owner review.

## Capabilities

The spec is split four ways.  Each capability has one reason to change.

- `owner-presentation` (extended): how any agent asks the owner anything.  Issue 82 created it.
- `backlog-overlap` (new): the backlog-hit question in `activate` step 1.  It is the only place that decides close-on-merge or fold-in.
- `issue-closure` (new): the close-on-merge record, `close-on-merge.sh`, the PR-body lines, and `finalize`'s fallback.
- `issue-body-edits` (new): `issue-body.sh`, and the rule that the body changes only for requirement changes.

`issue-closure` and `issue-body-edits` are kept apart.  The close-on-merge record is a comment, not a body edit, so the two share no mechanism.

## Decisions

### The contract rewrite in `docs/workflow.md`

"Presenting to the owner" is rewritten and stays the only full statement of the rules.  It holds these parts:

1. **Plain terms before any identifier.**  Unchanged from issue 82: an internal identifier appears only as a trailing tag; a relayed finding is translated; a cited file or line says what is there.
2. **Citations.**  An issue or PR is written as `<number>: <title>` on its own `-` line.  This rule was copied into about eight Rules sections but was missing from the contract.  The copies stay (Q16).
3. **The question format.**  Four parts, in this order:
   1. The decision, as the first line, in one plain sentence.
   2. What each referenced item is: `<number>: <title>`, the filing date, the author, and one line on why it exists.  If the agent created the item this session, the question says so.
   3. Why the decision comes up now, in one or two sentences.
   4. The options.  Each has its concrete effect, its pros, its cons, and the tradeoff the choice makes.  Exactly one is marked as recommended.  An option that states only its effect, or only a cost, does not meet the format.
4. **Coverage.**  The format covers live questions in the session, questions written into issue comments, questions written into PR bodies (which now hold none; see below), and `needs-attention` comments.
5. **The pre-send check**, word for word: "Could the owner answer this after switching tabs, with no other context, and without opening a file or a link?"  If not, the agent rewrites the question.
6. **The process-vocabulary ban.**  No overlap, dependency link, seam, fast path, lens, or stop in a question, unless the same sentence says in plain words what it does.
7. **One question per message, no exceptions.**  Anything that needs the owner's decision is its own message.  A list may be shown only when nothing in it needs an answer.  When an agent has several questions, it lists them all first as bullets, for context, then asks them one per message.  This covers each unresolved fix-loop finding, each Seam 1 override or conflict, each `groom` assumption, each design choice, and each debt item.
8. **No hard-coded limit** on the number of questions.  The owner may run a conversation as long as they want.
9. **One worked example**: the 928/971 question, rewritten to the format.

Removed from the issue 82 text: rule 3 (the owner may override to a batch), rule 4's escape for withholding a recommendation, the "rules split by kind of presentation" paragraph, and the "Deliberate batch presentations" list.  Showing information stays allowed: the board, a rendered spec, `setup`'s check results, a residual-findings list in a PR body.  None of these may carry a question.

### Briefing placement

The briefing is its own block, not part of each question.  It is sent each time the owner returns to the session, or after a review has run.  In the same turn, the agent sends the briefing and the bullet list of upcoming questions, then a horizontal rule, then the first question.  Later questions in the series carry no briefing.  Each question still carries parts 2 and 3 of the format, so it reads cold on its own.

`agents/issue-manager.md` changes "Re-orient them first, every time" to "each time you return to the session, or after a review has run", and describes the same-turn layout.

### Written questions: the issue thread is the state

- Written questions go only on the issue, as comments.  A comment says "Question k of n", lists all n as bullets, and asks only question k in the format.  It ends with "Reply here; the next question follows when the session resumes."
- In a needs-attention series, each question comment's first line is `🆘 Needs attention: Question k of n: <the decision>`.  The board already shows the newest comment that starts with `🆘 Needs attention:`, so it shows the open question with no board change.
- A PR body carries information only, plus the line "Questions about this PR are on the issue."
- The next question goes where the owner answered.  A reply on GitHub is picked up when the `issue-manager` next runs, because the owner attached or sent a message.  There is no polling.
- The newest owner reply after question k is the answer to question k.  The agent confirms it with a comment "✅ Question k answered: <the answer in one line>", then posts question k+1 as a new comment and asks it in the session.  An unclear reply gets one confirm question before the agent records anything.
- The `needs-attention` label stays until the last question in the series is answered.

### Seam 1, one question at a time

- Each entry in `overrides.md`, under both sections, has a stable `###` heading and, once answered, a committed `**Owner answer:**` line.  The pending questions are the entries with no answer line.
- The Seam 1 comment shows the spec as information, lists the pending questions as bullets, and asks the first.  Each later entry is its own question.  The final question is "approve the plan?".
- An answer of "keep the existing behavior" is recorded as a redirect.  The agent regenerates the plan once, after every entry has an answer, and keeps the answers on entries the regeneration did not change.
- `.spec-flow/seam1-last-shown-sha` is written only after the final approve question is asked.  A resumed session with pending entries asks the next pending entry, not the whole render.
- Under auto-approve, the agent answers each entry "accept as written" and commits that answer.  A hard conflict still always stops for the owner.

### `activate` step 1: backlog hits

- For each hit M, before asking, the agent runs one `gh issue view <M> --json createdAt,author,state,labels` and puts those facts in the question.  If the title is not enough to say why M exists, it reads M's full text.  It reads no other backlog issue in full.  This is the first narrow exception to the no-bodies rule in `agents/issue-manager.md`.
- The question offers four options, each stated by what happens:
  - **Close M when this PR merges.**  Runs `close-on-merge.sh record <N> <M>`.
  - **Leave M open, unchanged.**  Nothing is written.
  - **Make one block the other.**  Runs the existing `blocked-dependency.sh add`, in either direction.  That path may post its own blocking comment on M.
  - **Fold M's scope into this issue.**  Runs `record` too, and adds M's scope to this issue's acceptance criteria.
- The close option is not recommended, and its cons say why, when M is already in progress: M carries `agent:active`, M's status is past `status:ready`, or M has an open PR.  Closing M then would close work someone else is doing.
- Fold-in: the agent reads M in full (the second narrow no-bodies exception), drafts the new criteria in its own words, and shows them in one follow-up question with "approve as written" recommended.  After approval, it writes them with `issue-body.sh append <N> "Acceptance criteria" <file>`.  The draft file is deleted after the write.
- The five-question cap on step 1 is removed.
- An empty shortlist asks no backlog question.

### `scripts/issue-body.sh`

```
issue-body.sh get     <N> <heading>          # stdout: the section's content; exit 1 if absent
issue-body.sh replace <N> <heading> <file>   # replace the section's content; add it at the end if absent
issue-body.sh append  <N> <heading> <file>   # append lines to the section; add it at the end if absent
```

- **Parsing.**  One shared parser.  A line that starts with `## ` is a heading only outside a ```` ``` ```` or `~~~` fence.  A section runs from its heading to the next heading outside a fence, or to the end.  `###` lines belong to the section.  The target matches `## <heading>` exactly.
- **Errors that change nothing:** a duplicate target heading (the message names the issue and the heading); a content file that holds a `## ` heading outside a fence.
- **Pre-check.**  The script reads the body and GraphQL `lastEditedAt` together.  Just before the write it reads `lastEditedAt` again.  If it moved, it re-reads the body and re-applies its one-section change to the new body.
- **Post-check.**  After the write, it reads `userContentEdits` and the body.  If any edit other than its own landed between its read and its write, it prints each lost version's timestamp and editor and exits non-zero.  It does not retry, because a retry could overwrite the other edit again.  The stage stops and tells the owner; the old text is recoverable from GitHub's edit history.
- **Confirm.**  If no other edit landed, it confirms its section holds the new content and every other section is still there.  If not, it retries once, then errors.
- **Safety.**  Every write goes through a `mktemp` file under `$TMPDIR` and `gh issue edit --body-file`.  Nothing the script reads is placed in argv.  A trap removes its temp files on exit.
- **The rule** in `docs/workflow.md`: "No stage edits an existing issue body by hand; it uses issue-body.sh.  Creating a new issue is not an edit."  The body changes only for requirement changes: the `activate` step 1 scope rewrite and fold-in.

### The adjacent-behavior list moves to a comment

`activate` step 5's tech-debt branch posts the list as a comment whose first line is `🧭 Adjacent specified behavior`, instead of appending a body section.  Readers use the newest such comment: `implement/SKILL.md`, `implement.workflow.js`'s tech-debt prompt, `activate` step 7's tech-debt render, and `docs/workflow.md`'s Tech-debt fast path.  An issue activated before this change has only the body section, so a reader falls back to it when no comment exists.

### `scripts/close-on-merge.sh`

```
close-on-merge.sh record       <N> <M>    # link M blocked by N, then comment on N and on M
close-on-merge.sh withdraw     <N> <M>    # withdrawn marker on N, remove the link, comment on M
close-on-merge.sh closes       <N>        # stdout: Closes #N, then Closes #M per active record
close-on-merge.sh close-merged <N> <PR>   # only for a merged PR: close and clean each recorded M
```

- **The record** is a set of comments on issue N.  A record comment's first line is `🔗 Closes on merge`, and its next line is `- <M>: <title>`.  A withdrawal comment's first line is `🔗 Closes on merge: withdrawn <M>`.  `closes` and `close-merged` replay every such comment in order: a record adds M, a withdrawal removes it.  The result is the set of active records.  Only comments written by the authenticated `gh` user count.
- **`record`** checks that M is a number, differs from N, and is open.  It sets the native "M blocked by N" link first.  An existing link counts as present.  If GitHub refuses the link, a loop included, it posts nothing and reports GitHub's error.  Then it posts the record comment on N and the comment "Closes when the PR for <N>: <title> merges." on M.  It skips either comment if it is already there.  Setting the link keeps M off the board's ready list and out of "Next up" until N closes.
- **Loop check.**  GitHub's behavior for a `blocked_by` loop is verified during implementation.  If GitHub does not refuse a loop, `record` walks N's `blocked_by` chain itself and refuses when M is on it.
- **`withdraw`** posts the withdrawal comment on N, removes the "M blocked by N" link, and comments "No longer closes with <N>: <title>." on M.
- **`closes`** prints `Closes #<N>`, then one `Closes #<M>` line per active record, in record order.  It exits non-zero if it cannot read N's comments, so no caller writes a PR body that silently drops a line.
- **`close-merged`** reads the PR's state.  For any state but `MERGED` it exits non-zero and closes nothing.  For each active M:
  - M open: close it with a comment naming N and the PR.
  - M already closed: do not reopen it, and do not fail.
  - Either way, clean M exactly as `finalize` cleans N: remove `status:*`, `needs-attention`, `blocked`, and `merge-on-green`, and run `blocked-dependency.sh sweep <M>`.
  - `agent:active` on M is reported and never removed.  Another session may own M.
  - Read M's labels back.  A surviving label from the removal list is a failure.
- **Titles** are fetched by the script and written through a `mktemp` file and `--body-file`.  No LLM-composed argv carries a title.
- **Temp files** go under `$TMPDIR` via `mktemp`, and a trap removes them on exit.

### PR-body writers

Every PR-body write in `implement` starts with the output of `close-on-merge.sh closes <N>`: step 2b's draft PR, step 4c's docs path (which reuses step 2's mechanics), the failure path's residual-findings write, step 5's rewrite at ready, and the tech-debt draft PR in `implement.workflow.js`.  If `closes` fails, the stage stops and tells the owner.  It never writes a body without the lines.

`implement.workflow.js` takes a required `alsoCloses` argument: an array of positive integers, empty allowed, none equal to `issue`.  The script throws if it is missing or malformed.  `implement/SKILL.md` builds it from `closes <N>` minus the first line.

Because the record is on the issue, not in the session, a choice made in `activate` reaches a PR opened later, in any session.

### `finalize`

Step 2 runs `close-on-merge.sh close-merged <N> <PR>` after it closes N and before step 3 removes the worktree.  On failure it retries once.  If it still fails, it stops before step 3, keeps the worktree, and tells the owner which M is still open and which labels remain.  This matches the existing stop rule for a surviving label on N.

### Temp files in `activate` step 1

Every temp file step 1 writes goes under `$TMPDIR` via `mktemp`: the shortlist, the question drafts, and the fold-in draft.  Step 1 may run before isolation is confirmed, so a temp file must never land in the checkout.

### Choices made while writing the spec

These are small choices the decisions did not state.  The owner can redirect any of them at Seam 1.

- Only record comments authored by the authenticated `gh` user count.  A public repo lets anyone comment, and a stranger's `🔗 Closes on merge` comment must not close issues.
- `append` and `replace` add the section at the end of the body when it is absent.
- A tech-debt reader falls back to the old body section when no `🧭 Adjacent specified behavior` comment exists.
- A needs-attention question's first line is `🆘 Needs attention: Question k of n: <the decision>`.

## GitHub facts verified

- GraphQL `lastEditedAt` on an issue moves on a body or title edit.
- `updatedAt` also moves on comments and label changes, so it is too coarse for the pre-check.
- The REST ETag is coarse in the same way.
- GitHub has no conditional write for an issue body.  That is why the post-write `userContentEdits` check exists.
- GitHub's behavior for a `blocked_by` loop is not verified yet.  It is verified during implementation (task 3.1).

## Alternatives Considered

Each entry is one option presented at the design stop.  "Owner override" marks a decision where the owner chose differently from the architect's recommendation.

### Q1: where the close-on-merge record lives (superseded by the storage follow-up)

- **A `## Closes on merge` section in issue N's body (architect's recommendation, first chosen, then superseded).**  The owner later set a general rule: "Generally speaking, I don't want the issue body updated unless the requirements change. I would rather have comments so people and agents can follow along. If there's additional info, it should be added as a comment."  A close-on-merge record is not a requirement change.
- **A marker comment on N.**  Rejected at first as harder to parse than a section.  It became the chosen design in the storage follow-up.
- **A gitignored file in the worktree.**  Rejected: it fails the criterion that the choice reaches a PR opened in a different session.
- **A committed file.**  Rejected: the docs path has no commit, and it ties the record to OpenSpec.

### Storage follow-up (supersedes Q1 and the tech-debt body append)

- **`🔗 Closes on merge` comments on N, replayed in order, with a withdrawn marker (chosen; owner override of the architect's D1).**
- **Keep the body section.**  Rejected by the owner's comments-not-body rule, quoted above.
- **Keep the tech-debt adjacent-behavior list in the body.**  Rejected by the same rule; it becomes a `🧭 Adjacent specified behavior` comment.

### Q2: which PR-body writers carry `Closes #M`

- **Every write starts with `close-on-merge.sh closes <N>`; `implement.workflow.js` takes a required `alsoCloses` (chosen, architect's D2).**
- **A `sync-pr` command run after every write.**  Rejected: a write that forgets the follow-up drops the lines until the next sync.
- **Only step 5 adds it.**  Rejected: fails the criteria for the draft PR and every other path.

### Q3: where `finalize` learns which issues to close

- **The issue-N record, via `close-merged <N> <PR>`, which checks the merge itself (chosen, architect's D3).**
- **The merged PR's `closingIssuesReferences`.**  Rejected: it misses the case where a body rewrite dropped the keyword.

### Q4: keeping M off "Next up" (not in the issue)

- **`record` sets the native "M blocked by N" link itself and posts its own plain comment; the comment is idempotent; a loop is refused (chosen; owner override).**
- **`record` calls `blocked-dependency.sh add <M> <N>`, whose `⛔ Blocked on` comment serves as the comment on M (architect's D4 recommendation).**  Rejected by the owner: the comment on M should say M closes with N's PR, not that M is blocked.
- **Remove `status:ready` from M.**  Rejected: it changes M's lifecycle state for a fact the link already records.
- **Do nothing.**  Rejected: the board could offer M as next work while N is about to close it.

### Q5: the blocking comment on M

- **Allowed; the blocking path is unchanged (chosen).**  The AC was reworded so that "make it block" forbids only a close-on-merge comment on M.
- **Forbid any comment on M.**  Rejected: it would change the blocking path, which is out of scope.

### Q6: concurrent edits erasing an issue body

- **Re-read the live body just before each write (first chosen, then generalized).**  The owner: "there is a bunch of other race conditions that could happen. this is a general problem, not specific to this workflow."
- **A shared `scripts/issue-body.sh` used by every issue-body writer, one named `##` section per call, with a `lastEditedAt` pre-check and a post-write confirm (chosen in the follow-up; owner override).**  The architect had proposed only a script-owned write inside `close-on-merge.sh`.
- **`close-on-merge.sh check <N>` at the end of step 1.**  Dropped by C8.

### Q7: a search for M's PR also finds this PR

- **Change no lookups; the close option warns and is not recommended when M is in progress; one sentence in Naming (chosen, architect's D5).**
- **Filter searches to bodies that start with `Closes #<own N>`.**  Rejected: it changes four lookups for a rare case.
- **Write `Resolves #M` instead.**  Rejected: GitHub treats it the same, so it solves nothing.

### Q8: fold-in

- **Read M in full, draft the criteria in the agent's own words, show them in one follow-up question with "approve as written" recommended, and write only after approval (chosen).**
- **Copy M's criteria verbatim.**  Rejected: M's text is another author's words and is data, not instructions.
- **Write first, show after.**  Rejected: the body changes only on an approved requirement change.

### Q9: M's labels on close (superseded by C9)

- **Remove `status:*` and `needs-attention`, keep priority, never touch `agent:active` (first chosen, replaced by C9).**
- **Leave M's labels alone.**  Rejected: a closed M with `status:ready` misleads the board.

### Q10: what counts as a question

- **Anything that needs the owner's decision is its own message; a list may be shown only when nothing in it needs an answer (chosen; owner override).**  The owner: "the issue is specifically about the UX of being asked 5 questions. i only have a single input to respond. if I have questions or want to dicuss an issue, things get confusing. single question is the only path for me to be comfortable"
- **"Showing information is not asking": a render may list several items, and a written artifact may carry several questions (architect's D6 recommendation).**  Rejected by the owner, quoted above.
- **Forbid showing several items at all.**  Rejected: the board and a rendered spec are information, not questions.

### Q11: how a written question is followed up

- **The next question goes where the owner answered; a GitHub reply is picked up when the `issue-manager` next runs; no polling (chosen).**
- **Poll the issue for replies.**  Rejected: a standing poll loop costs a session and is against the plugin's single-check rule.

### Q12: withholding a recommendation

- **Drop the escape; every question marks exactly one recommended option (chosen, architect's D7).**
- **Keep the escape for pure preference.**  Rejected: the owner always needs a recommendation.

### Q13: briefing placement

- **The briefing is its own block, with the list of upcoming questions; each question opens with its decision on line 1 (chosen; owner override).**
- **Line 1 is the decision; the briefing becomes parts 2 and 3 of the question (architect's D8 recommendation).**  Rejected by the owner.

### Q14: the five-question cap in `activate` step 1

- **Remove the cap entirely; no hard-coded limit (chosen; owner override).**  The owner: "I don't want a hard coded limit. User should be able to have as long as a conversation as they want. they could use a grilling session, or a session like this with 15 questions."
- **Keep the cap, and do not count backlog hits toward it (architect's risk note).**  Rejected by the owner.

### Q15: nearby debt, splitting `activate` step 1

- **File a separate ungroomed issue (chosen).**  Filed as 89: spec-flow: split activate step 1 into claim/shortlist validation and owner review.
- **Fold it into this change.**  Rejected: it doubles the blast radius.

### Q16: the copied `<number>: <title>` rules

- **Leave the copies; add the new format pointer next to each one (chosen).**
- **Replace each copy with a pointer.**  Rejected for this change; it is a separate cleanup.

### C1: section parsing

- **One shared parser; a `## ` line is a heading only outside fences; a duplicate target heading is an error that changes nothing; tests cover both (chosen).**
- **A plain line match.**  Rejected: issue 76 has a `## ` heading inside a fence.
- **Edit the first matching heading.**  Rejected: it may edit the wrong section.

### C2: a write that lands between the check and the write

- **After the write, read `userContentEdits`; if another edit landed, print its timestamp and editor and exit non-zero (chosen).**
- **Rely on the `lastEditedAt` pre-check alone.**  Rejected: GitHub has no conditional write, so the window stays open.
- **Retry automatically.**  Rejected: a retry could overwrite the other edit again.

### C3: `close-merged` fails in `finalize`

- **Retry once; if it still fails, stop before step 3 with the worktree kept, and tell the owner which M is open and which labels remain (chosen).**
- **Warn and continue.**  Rejected: once the worktree is gone, `gh` cannot infer the repo, so nobody can retry from that session.

### C4: per-override Seam 1 questions

- **Committed `**Owner answer:**` lines; pending entries drive the questions; one regeneration after all answers; the last-shown marker written after the final approve question; auto-approve records "accept as written"; a hard conflict always stops (chosen).**
- **Keep the Seam 1 tables as one batch.**  Rejected by Q10.

### C5: written-question state

- **The issue thread is the state: "Question k of n" comments, PR bodies information only, "✅ Question k answered" confirmations, `needs-attention` until the last answer (chosen).**
- **Put questions in PR bodies too.**  Rejected: PR replies are not read, and the state would split across two places.

### C6: undo for a close-on-merge record

- **`withdraw <N> <M>` posts a withdrawn marker, removes the link, and comments on M; `record` adds the link first and posts nothing if GitHub refuses; the loop behavior is verified during implementation (chosen).**
- **No undo; the owner deletes the comment.**  Rejected: the owner does not want manual steps.

### C7: briefing timing and layout

- **Same turn, visually separate: briefing and question list, a horizontal rule, the first question; later questions carry no briefing; sent each time the owner returns or after a review (chosen).**
- **A separate message before the first question.**  Rejected: in a live session it would wait for an answer that is not needed.

### C8: `close-on-merge.sh check` and the body-edit rule

- **Drop `check`; the rule reads "No stage edits an existing issue body by hand; it uses issue-body.sh.  Creating a new issue is not an edit." (chosen).**
- **Keep `check`.**  Rejected: it was undefined, and the record is no longer in the body.

### C9: cleaning M on close (supersedes Q9)

- **Remove `status:*`, `needs-attention`, `blocked`, and `merge-on-green`; run `blocked-dependency.sh sweep`; report `agent:active` only; read back, and a surviving label stops per C3 (chosen; owner override of the narrower Q9 set).**
- **The Q9 set.**  Rejected: it left `blocked`, `merge-on-green`, and native links on a closed M.

### C10: temp files in `activate` step 1

- **Every temp file under `$TMPDIR` via `mktemp`; scripts clean up on exit; the fold-in draft deleted after posting (chosen).**
- **Files in the checkout.**  Rejected: step 1 may run before isolation, so a file could land in the primary checkout.

## Risks / Trade-offs

- **Title injection.**  Titles are written only by the scripts, through temp files and `--body-file`.  M's body is data when it is read for fold-in.
- **The no-bodies rule.**  Exactly two narrow exceptions are added, each for one named issue.
- **A search for M's PR finds this PR too.**  Accepted; the close option warns when M is in progress.
- **Blast radius.**  About 13 prompt files, one required JS argument, two new scripts with tests, no label, board, or schema change.
- **Issue 82's requirements.**  Several of them contradict this change and are not archived yet.  `overrides.md` lists each one; task 1.1 handles the archive order.
- **Many more messages.**  One question per message makes a long session longer.  The owner chose this explicitly.
