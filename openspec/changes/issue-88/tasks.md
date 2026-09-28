# Tasks: issue 88, self-contained owner questions, one at a time, and close-on-merge

All paths are under `plugins/spec-flow/` unless stated.

## 1. Before you start

- [ ] 1.1 Check whether `openspec/specs/owner-presentation/spec.md` exists (repo root).  If issue 82's change was archived, rewrite this change's `owner-presentation` delta: move the requirements it supersedes (listed in `overrides.md`) to `## MODIFIED Requirements` or `## REMOVED Requirements`, then run `openspec validate issue-88 --type change --strict --json`.  If issue 77's change was archived (`openspec/specs/idea-refinement/spec.md` exists), add an `idea-refinement` delta to this change: MODIFIED "A round's questions reach the owner one at a time" without the three-per-round clause and without the "more candidate questions than the cap" scenario, and MODIFIED "Assumptions are confirmed in one pass, split by provenance" without the bulk confirm (both listed in `overrides.md`).
- [x] 1.2 Read the committed `**Owner answer:**` line on every `overrides.md` entry, and apply any redirect before any other task.

## 2. `scripts/issue-body.sh` and its test

- [x] 2.1 Write `scripts/test-issue-body.sh` first: a fake `gh` on `PATH` that records every call and serves the body, `lastEditedAt`, and `userContentEdits` from state files, in the pattern of `scripts/test-blocked-dependency.sh`.  Cover: `get` on a present and an absent section; `replace` and `append`; `replace` and `append` on an absent section, each exiting non-zero with an error that names the missing section and the issue, and making no `gh issue edit` call; a target heading present only inside a fence, treated as absent; a `## ` heading inside a ```` ``` ```` fence and inside a `~~~` fence; a duplicate target heading; a content file with a `## ` heading; a moved `lastEditedAt`; a lost edit in the window; a failed confirm, retried once; `$(...)` and backticks in the body and the content; bad arguments exit 2.
- [x] 2.2 Write `scripts/issue-body.sh`: `get`, `replace`, `append`; one fence-aware parser; `replace` and `append` stop with an error naming the missing section, and write nothing, when the target section is absent; `lastEditedAt` pre-check; `userContentEdits` post-check; section confirm with one retry; `mktemp` under `$TMPDIR`, `--body-file`, and a cleanup trap.  `set -euo pipefail`.
- [ ] 2.3 On a scratch issue, confirm that two body edits in quick succession show as two `userContentEdits` entries, so the post-check can tell them apart.  Record the result in a comment at the top of the script.
- [x] 2.4 Run both under macOS `/bin/bash` (3.2): no associative arrays, no `mapfile`, no GNU-only flags.

## 3. `scripts/close-on-merge.sh` and its test

- [ ] 3.1 Verify GitHub's `blocked_by` loop behavior on scratch issues: link A blocked by B, then try B blocked by A, and a three-issue chain.  Record whether GitHub refuses a loop.  If it does not, `record` walks N's `blocked_by` chain itself.
- [x] 3.2 Write `scripts/test-close-on-merge.sh` first, fake `gh` on `PATH`.  Cover: `record` (first run, repeated run, M closed, M missing, M equal to N, GitHub refusing the link, a loop per task 3.1); `withdraw`; replay order of record and withdrawn comments; a record comment by another user ignored; `closes` with zero, one, and two records, and with a comment read failure; `close-merged` for a merged PR with M open, M closed, M carrying `agent:active`, a surviving label, and a PR that is not merged; a title with `$(...)` and backticks; bad arguments exit 2.
- [x] 3.3 Write `scripts/close-on-merge.sh`: `record`, `withdraw`, `closes`, `close-merged`.  `record` sets the link before any comment.  `close-merged` removes `status:*`, `needs-attention`, `blocked`, `merge-on-green`, runs `blocked-dependency.sh sweep <M>`, reports `agent:active`, and reads the labels back.  Titles are fetched by the script and written through `mktemp` files under `$TMPDIR` with `--body-file`.  `set -euo pipefail`.
- [x] 3.4 Run both under macOS `/bin/bash` (3.2).

## 4. `docs/workflow.md`

- [x] 4.1 Rewrite **Presenting to the owner**: keep rule 1; add the `<number>: <title>` citation rule; add the four-part question format with the per-option and per-item rules; the coverage list; the pre-send check word for word; the process-vocabulary ban with its terms; one question per message with the bullet list first; information lists only when nothing needs an answer; no hard-coded limit; the briefing layout; written questions on the issue thread; the 928/971 worked example.
- [x] 4.2 Remove rule 3, rule 4's escape, the "rules split by kind" paragraph, and the "Deliberate batch presentations" list.
- [x] 4.3 In the `needs-attention` bullet, point to the format and state the `🆘 Needs attention: Question k of n: <decision>` first line and that the label stays until the last answer.
- [x] 4.4 Add the issue-body rule: "No stage edits an existing issue body by hand; it uses issue-body.sh.  Creating a new issue is not an edit."  State that the body changes only for requirement changes.
- [x] 4.5 Add the Naming sentence about `Closes #M`.
- [x] 4.6 Update the Tech-debt fast path text to the `🧭 Adjacent specified behavior` comment.
- [x] 4.7 Point the backlog shortlist text to the format.

## 5. Agents

- [x] 5.1 `agents/issue-manager.md`: pointer to the format; briefing timing ("each time you return to the session, or after a review has run") and same-turn layout; remove the batch override from the relay paragraph; add the two narrow no-bodies exceptions (a hit whose title is not enough, and the issue being folded in); the `needs-attention` comment asks one question in the format; written questions on the issue thread.
- [x] 5.2 `agents/project-manager.md`: pointer next to its `<number>: <title>` rule; the board and archive text stop calling themselves batch exceptions; the archive confirm is one question.
- [x] 5.3 `agents/product-manager.md`: each drafted question follows the format.
- [x] 5.4 `agents/product-manager.md`: remove the per-round question limit.  The description's "up to three questions" becomes "the questions it cannot settle"; "What a round returns" drops "plus at most three questions"; the open-questions item replaces "Ask at most three per round ... anything past three stays here as an assumption and is available to a later round" with: return every question you cannot settle from the record or the repo, ranked by how much the answer changes the work, each with a recommended default.
- [x] 5.5 `agents/architect.md`: each drafted question and option list follows the format.

## 6. Skills

- [x] 6.1 `skills/activate/SKILL.md` step 1: remove the five-question cap; the facts fetch per hit; the one-issue full read; the four options; the in-progress warning; the `record` calls; fold-in with its draft question and `issue-body.sh append`; the scope rewrite through `issue-body.sh replace`; `mktemp` under `$TMPDIR` for every temp file; pointer to the format.  Remove "related, a duplicate, or a dependency".
- [x] 6.2 `skills/activate/SKILL.md` step 4: each design choice and each debt item is its own question; pointer to the format.
- [x] 6.3 `skills/activate/SKILL.md` step 5: the tech-debt list becomes a `🧭 Adjacent specified behavior` comment; `overrides.md` entries get stable `###` headings and an `**Owner answer:**` line once answered.
- [x] 6.4 `skills/activate/SKILL.md` step 7: the per-entry Seam 1 flow; the redirect and one regeneration; `.spec-flow/seam1-last-shown-sha` written after the final approve question; auto-approve records "accept as written"; a hard conflict stops; the tech-debt render reads the comment with the body fallback; the options block follows the format; update the skill's description and intro text about "up to five" questions.
- [x] 6.5 `skills/groom/SKILL.md`: ask each closing-pass assumption in its own message with a recommendation; remove the bulk-confirm exception.
- [x] 6.6 `skills/groom/SKILL.md`: remove the per-round question limit.  The description drops "asking at most three questions"; step 4's "and up to three questions" becomes "and its questions"; "Relaying questions. One at a time, at most three per round." becomes one at a time, every question the round returns, listed first as bullets; delete the "More than three candidates?" bullet; reword "a round that asks three has not thereby failed it" so it names no number.  Keep the no-default drop rule and its `**Dropped:**` entry.
- [x] 6.7 `skills/setup/SKILL.md`: show check results as information; ask each item in its own message; remove the batch exemption text.
- [x] 6.8 `skills/address/SKILL.md`: pointer; each finding needing a decision is its own question on the issue.
- [x] 6.9 `skills/implement/SKILL.md`: every PR-body write (step 2b, step 4c, the failure path, step 5) starts with `close-on-merge.sh closes <N>` and goes through `--body-file`; stop if `closes` fails; PR bodies carry information only plus "Questions about this PR are on the issue."; each unresolved finding is its own question; pass `alsoCloses` to the workflow; read the adjacent-behavior comment with the body fallback.
- [x] 6.10 `skills/implement/implement.workflow.js`: required `alsoCloses` with validation; the tech-debt PR body starts with `Closes #<issue>` and one `Closes #M` per entry; the tech-debt prompt reads the `🧭 Adjacent specified behavior` comment with the body fallback.
- [x] 6.11 `skills/finalize/SKILL.md` step 2: run `close-on-merge.sh close-merged <N> <PR>` before step 3; retry once; on a second failure, stop with the worktree kept and name the open issue and the surviving labels.

## 7. Checks

- [x] 7.1 Search the plugin for any text that allows several questions in one message or a batch override.  None may remain.
- [x] 7.2 Search the plugin for a hard-coded question limit ("at most three", "up to three questions", "up to five", "per round" next to a number).  None may remain.
- [x] 7.3 Search the plugin outside `docs/workflow.md` for a copy of the four-part format.  None may remain.
- [x] 7.4 Search the plugin for `gh issue edit` with `--body` on an existing issue outside `scripts/issue-body.sh`.  None may remain.
- [x] 7.5 Walk every acceptance criterion in `ac-coverage.md` against the edited files.
- [x] 7.6 Run `scripts/test-issue-body.sh`, `scripts/test-close-on-merge.sh`, and `scripts/test-blocked-dependency.sh`.

## 8. Version

- [ ] 8.1 Ask the owner whether to bump the plugin version.  The current version is 0.49.0 in `.claude-plugin/plugin.json`.  No `.codex-plugin/plugin.json` exists.  Ask for the new version before changing anything.
