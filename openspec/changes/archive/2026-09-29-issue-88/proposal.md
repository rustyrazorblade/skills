## Why

When a spec-flow agent asks the owner a question, the question often leaves out what the owner needs to answer it.  It does not say what the named issues are, when they were filed, or by whom.  The decision is buried inside an option.  The options use pipeline terms instead of saying what each one does.  In one case the owner replied "is 928 new? I am confused what you're asking me."  The owner had filed 928 three weeks earlier.

Agents also still ask several questions in one message.  The contract from issue 82 allows it in named exceptions: `groom`'s bulk assumption confirm, `setup`'s check batch, and the Seam 1 tables.  The owner has one input box.  The owner cannot answer questions in bulk.  In the owner's words: "single question is the only path for me to be comfortable."

A third gap sits behind the example question.  "Close 928 when the 971 PR merges" has nothing behind it today.  The owner would have to close 928 by hand.  The owner does not want to close issues manually.

Two more owner rules came out of the design stop.  The issue body changes only when the requirements change; everything else is a comment, so people and agents can follow along.  And every edit of an existing issue body goes through one script that cannot silently erase someone else's edit.

## What Changes

All paths are under `plugins/spec-flow/`.

**The owner-question contract (`docs/workflow.md`, "Presenting to the owner")**

- The section is rewritten.  It stays the only full statement of the rules.
- Kept: plain terms before any identifier, with an identifier only as a trailing tag.  Added to the contract: `<number>: <title>` on its own `-` line.
- New question format, four parts in order: the decision as the first line, in one plain sentence; what each referenced item is (`<number>: <title>`, filing date, author, one line on why it exists, and "created this session" when true); why the decision comes up now; the options, each with its concrete effect, pros, cons and tradeoff, with exactly one marked as recommended.
- New pre-send check, word for word: "Could the owner answer this after switching tabs, with no other context, and without opening a file or a link?"
- New ban on process vocabulary (overlap, dependency link, seam, fast path, lens, stop) unless the same sentence says in plain words what it does.
- One question per message, no exceptions.  Several questions are first listed as bullets, then asked one per message.  Anything that needs the owner's decision is its own message.  A list may be shown only when nothing in it needs an answer.
- Removed: rule 3 (the owner may override to a batch), rule 4's escape for withholding a recommendation, the "rules split by kind" paragraph, and the list of deliberate batch presentations.
- The briefing: in the same turn, the briefing and the bullet list of questions come first, then a horizontal rule, then the first question.  Later questions in the series carry no briefing.
- Written questions live only on the issue thread, as comments: "Question k of n", all n listed, only question k asked, and the line "Reply here; the next question follows when the session resumes."  A needs-attention series uses the `🆘 Needs attention:` prefix.  A PR body carries information only, plus "Questions about this PR are on the issue."  The next question goes where the owner answered.  A reply is confirmed with "✅ Question k answered: …".  No polling.
- No hard-coded limit on the number of questions: the five-question cap in `activate` step 1 and the three-questions-per-round limit in `groom` and `product-manager` are both removed.
- Naming gets one sentence: a PR that also carries `Closes #M` is found by a search for issue M's PR too.
- A new rule: no stage edits an existing issue body by hand; it uses `scripts/issue-body.sh`.  Creating a new issue is not an edit.  The body changes only for requirement changes.

**Pointers, not copies**

Each file below points to the contract at the place it asks the owner something, and loses any exception it had.  No file copies the four parts.

- `agents/issue-manager.md`: pointer; the briefing rule reworded ("each time you return to the session, or after a review has run", and the same-turn layout); the relay paragraph loses the batch override; the no-bodies rule gets two narrow exceptions (a backlog hit whose title is not enough, and the issue being folded in); the `needs-attention` comment asks one question.
- `agents/project-manager.md`: pointer next to its `<number>: <title>` rule; the board and archive text no longer call themselves batch exceptions; the archive confirm is one question.
- `agents/product-manager.md` and `agents/architect.md`: each drafted question or option list follows the format.
- `agents/product-manager.md`: a round returns every question it cannot settle from the record or the repo; the "at most three per round" limit is removed from the description, the return format, and the open-questions rule.
- `skills/activate/SKILL.md`:
  - Step 1: the five-question cap is removed; the backlog-hit question is rewritten (below); the scope rewrite goes through `issue-body.sh`; all temp files go under `$TMPDIR` via `mktemp`.
  - Step 4: each design choice and each debt item is its own message.
  - Step 5: the tech-debt adjacent-behavior list becomes a `🧭 Adjacent specified behavior` comment.
  - Step 7: the per-override Seam 1 flow (below); the "Your options" block follows the format.
- `skills/groom/SKILL.md`: each closing-pass assumption is asked in its own message with a recommendation; the bulk-confirm exception is removed; every question a round returns is relayed, one at a time, with no per-round limit (the "at most three per round" rule and the "More than three candidates?" rule are removed, and the description drops "asking at most three questions").
- `skills/setup/SKILL.md`: the check results are shown as information; each item needing an answer is asked in its own message; the batch exemption is removed.
- `skills/address/SKILL.md` and `skills/implement/SKILL.md`: pointers; each unresolved fix-loop finding that needs a decision is its own question on the issue; the PR body holds findings as information only.
- `skills/implement/SKILL.md` and `skills/implement/implement.workflow.js`: read the adjacent-behavior comment; every PR-body write starts with the `closes` block.
- `skills/finalize/SKILL.md`: runs `close-on-merge.sh close-merged`.

**Backlog hits in `activate` step 1**

- Before asking about a hit M, the agent runs one `gh issue view <M> --json createdAt,author,state,labels` and puts those facts in the question.  If the title is not enough to say why M exists, it reads that one issue in full.
- The question offers four options, each named by what it does: close M when this PR merges; leave M open, unchanged; make one block the other (the existing `blocked-dependency.sh add` path); fold M's scope into this issue.
- The close option is not recommended, and its cons say why, when M is already in progress: `agent:active`, a status past `status:ready`, or an open PR.
- Fold-in: the agent reads M in full, drafts the new criteria in its own words, shows them in one follow-up question with "approve as written" recommended, and writes them only after approval.

**Seam 1, one question at a time**

- Each `overrides.md` entry gets a committed `**Owner answer:**` line.  Unanswered entries drive the questions.
- The Seam 1 comment shows the spec as information, lists the pending questions, and asks the first.
- "Keep the existing behavior" is recorded as a redirect.  The plan is regenerated once, after every entry is answered.  Answers on unchanged entries are kept.
- `.spec-flow/seam1-last-shown-sha` is written only after the final approve question is asked.
- Auto-approve answers each entry "accept as written" and records that.  A hard conflict always stops.

**New script: `scripts/issue-body.sh`**

- Subcommands `get <N> <heading>`, `replace <N> <heading> <file>`, and `append <N> <heading> <file>`, each on one `## ` section.  When the target section is absent, `replace` and `append` stop with an error that names the missing section, and change nothing.
- Fence-aware parsing: a `## ` line is a heading only outside ```` ``` ```` and `~~~` fences.  A duplicate target heading is an error that names the issue and changes nothing.
- Records GraphQL `lastEditedAt` at read.  Re-checks it just before the write and re-reads if it moved.
- After the write, reads `userContentEdits`.  If any other edit landed between the read and the write, it prints the lost version's timestamp and editor and exits non-zero.  It confirms its section landed and no section was lost; it retries once, then errors.
- Writes through a `mktemp` file under `$TMPDIR` and `--body-file`, and cleans up on exit.
- New test: `scripts/test-issue-body.sh`, fake `gh` on `PATH`.

**New script: `scripts/close-on-merge.sh`**

- `record <N> <M>`: sets the native "M blocked by N" link first.  If GitHub refuses it, a loop included, it posts nothing and reports.  Then it posts a `🔗 Closes on merge` comment on N and a plain comment on M ("Closes when the PR for <N>: <title> merges.").  Idempotent.
- `withdraw <N> <M>`: posts `🔗 Closes on merge: withdrawn <M>` on N, removes the link, and comments on M "No longer closes with <N>: <title>."
- `closes <N>`: prints `Closes #N`, then one `Closes #M` per active record.
- `close-merged <N> <PR>`: acts only for a merged PR.  Closes each recorded issue still open, never reopens a closed one, and cleans each one as `finalize` cleans N: removes `status:*`, `needs-attention`, `blocked` and `merge-on-green`, and runs `blocked-dependency.sh sweep`.  It reports `agent:active` and does not remove it.  It reads the labels back and fails if one survives.
- New test: `scripts/test-close-on-merge.sh`, fake `gh` on `PATH`.

**`implement.workflow.js`**

- A new required argument `alsoCloses`: an array of issue numbers, empty allowed.  The script throws if it is missing, not an array, or holds anything but positive integers other than `issue`.  The tech-debt draft PR body starts with `Closes #<issue>` and one `Closes #M` line per entry.

**What the owner experiences**

- Every question opens with the decision.  It says what each named issue is, when it was filed and by whom, and why the question comes up now.  Every option says what happens, its pros, its cons, and the tradeoff, with one recommended.
- Never more than one question in a message, live or written.  A series is listed first, then asked one by one.
- A backlog duplicate can be closed or folded in with one answer.  It closes when this PR merges.  The owner closes nothing by hand.
- The issue body changes only when the requirements change.  Everything else arrives as a comment.

## Capabilities

### New Capabilities

- `issue-closure`: the close-on-merge record, `close-on-merge.sh` and its test, the `Closes #M` PR-body lines, and the `finalize` step that closes what GitHub left open.
- `issue-body-edits`: `issue-body.sh` and its test, and the rule that the body changes only for requirement changes, through that script.
- `backlog-overlap`: the backlog-hit question in `activate` step 1: the facts fetched, the four options, the in-progress warning, and fold-in.

### Extended Capabilities

- `owner-presentation`: added by issue 82's change, which is not archived yet.  This change adds requirements to it.  See `overrides.md` for the requirements of issue 82 that this change supersedes.  It also carries the requirements that replace two of issue 77's `idea-refinement` rules, the bulk assumption confirm and the three-questions-per-round limit; issue 77's change is not archived yet either.

## Impact

- New scripts: `scripts/issue-body.sh`, `scripts/close-on-merge.sh`, `scripts/test-issue-body.sh`, `scripts/test-close-on-merge.sh`.  All bash 3.2, `gh` only, no OpenSpec.
- One new required argument on `implement.workflow.js`.  Every caller in `skills/implement/SKILL.md` passes it.
- About 13 prompt files change.  No label, board, or schema change.
- A PR that closes M is also found by a search for M's PR.  Lookups are unchanged; the close option warns when M is already in progress.
- Existing issues that carry a `## Adjacent specified behavior (must be preserved)` body section keep working: readers fall back to it when no comment exists.
- Out of scope: pulling issue bodies over the whole backlog; changing the blocking path; auto-closing from any decision other than the `activate` step 1 backlog-hit question; splitting `activate` step 1 (filed separately as 89: spec-flow: split activate step 1 into claim/shortlist validation and owner review).
- Plugin version: the owner is asked before any bump (current 0.49.0).
