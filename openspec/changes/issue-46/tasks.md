## 1. Retained from the first implementation

These landed under the original scope and survive the re-scope unchanged. Nothing to redo; listed
so the change's task list matches what is actually on the branch.

- [x] 1.1 Broaden `last_comment_matching()`'s exception handling to catch `json.JSONDecodeError`
      alongside `subprocess.CalledProcessError`, returning `None` in both cases.
- [x] 1.2 `prefetch_notes(issues)` — scan for `blocked`/`needs-attention` labels, submit one
      `last_comment_matching()` call per (issue, note-kind) pair into a second
      `ThreadPoolExecutor(max_workers=4)` block, return two `{issue_number: str | None}` dicts.
- [x] 1.3 In `main()`, rebind `blocked_reason_fn`/`needs_attention_note_fn` to dict lookups
      against `prefetch_notes()`'s results. `build_rows()` unchanged.
- [x] 1.4 Decompose `render_board()` into one function per rendered section, reducing
      `render_board()` itself to bucket computation plus ordered section calls.

## 2. Remove the capping design

- [x] 2.1 Delete `BACKLOG_DISPLAY_CAP`, `EPIC_SUBISSUE_DISPLAY_CAP` and the `capped()` helper.
- [x] 2.2 Remove the `--full` flag from `argparse` and drop the `full` parameter from
      `render_board()` and every section function that threads it.
- [x] 2.3 Delete `test-board.sh`'s fixture 5 and every cap/`--full` assertion in fixtures 2, 3
      and 4. Keep those fixtures' prefetch and failure-isolation assertions.

## 3. Backlog and epics become counts

- [x] 3.1 Replace `render_backlog()` and `render_epics()` with counts contributed to the summary
      line. Neither renders a per-issue row.
- [x] 3.2 Leave `ISSUE_LIMIT` and pagination alone — this change alters rendering, not how much
      the board retrieves.
- [x] 3.3 Drop `subIssues` from `fetch_issues()`'s `--json` field list, and the `sub_issues`,
      `sub_total` and `sub_completed` row keys from `build_rows()`. Nothing reads them once epics
      report as a count. Keep `subIssuesSummary` — `is_epic` reads its `total`.

## 4. Conditional rendering

- [x] 4.1 Make every section function return no lines when it has no content, so a section with
      nothing to report leaves no header, no count and no blank line behind.
- [x] 4.2 Rewrite the summary line to omit any count that is zero, rather than rendering
      `blocked: 0`-style entries.
- [x] 4.3 Move the archive suggestion out of the summary line into its own conditional line,
      rendered only when specs are pending and naming how many.

## 5. Narrow "next up"

- [x] 5.1 Reduce `compute_next_up()` to the single ready-issue case: unclaimed `status:ready`,
      sorted by `priority_key`, returning the top row or `None`.
- [x] 5.2 Drop its `blocked_on_you` and `backlog` parameters and update the call site.
- [x] 5.3 Delete the merge-a-green-PR rung, the unblock rung and its four action strings, and the
      backlog-groom fallback.
- [x] 5.4 Confirm `render_next_up()` emits nothing when `compute_next_up()` returns `None`.
- [x] 5.5 Leave `blocked_on_you` bucketing and `render_blocked_on_you()` intact — the section
      still renders, it just no longer feeds a recommendation.

## 6. Keycap priority

- [x] 6.1 Add a priority → keycap mapping (`P0` → `0️⃣` … `P3` → `3️⃣`) beside `PRIORITY_ORDER`.
- [x] 6.2 Replace `render_row()`'s `{row['priority'] or '--':3}` with the keycap plus a literal
      space. Do not use format-width padding: a keycap is three codepoints but renders in about
      two cells, so `:3` misaligns every row.
- [x] 6.3 Render a fixed-width blank for an issue with no priority label, matching the keycap's
      display width so columns stay aligned.

## 7. Tests

- [x] 7.1 Assert the summary line reports an ungroomed count and that no ungroomed issue renders
      as its own row.
- [x] 7.2 Assert two renders differing only in backlog size produce the same number of lines.
- [x] 7.3 Assert no empty section header, no zero count and no `specs pending archive: 0` text
      appears when the corresponding content is absent.
- [x] 7.4 Assert "next up" names the P0 issue when unclaimed ready issues exist at P0 and P2.
- [x] 7.5 Assert no "next up" line renders when no unclaimed ready issue exists, including when
      the backlog is non-empty.
- [x] 7.6 Assert "next up" does not recommend merging a green in-review PR, across all three
      liveness states (🟢 active, 🟡 claimed, 🔴 stalled).
- [x] 7.7 Assert a `needs-attention` issue renders under BLOCKED ON YOU with its attach
      instruction while "next up" does not name it.
- [x] 7.8 Assert the archive suggestion renders with its count when specs are pending.
- [x] 7.9 Assert a `P1` row's priority column shows `1️⃣` and not the text `P1`, and that a
      prioritized and an unprioritized row in the same section stay column-aligned.
- [x] 7.10 Confirm the retained prefetch transparency and failure-isolation assertions still pass
      unchanged.
- [x] 7.11 Run the full suite and confirm it exits 0. Run `shellcheck test-board.sh` and confirm
      it is clean — `main`'s copy is, and this change must not regress it.

## 8. Skill documentation

- [x] 8.1 Update `skills/board/SKILL.md`'s bucket list — BACKLOG and EPICS no longer render as
      sections.
- [x] 8.2 Remove SKILL.md's judgment step. It was conditional on "next up" recommending a backlog
      issue to groom, which no longer happens, leaving the step unreachable. Nothing replaces it:
      the board now reports state and recommends only unowned ready work, both decided by the
      script.
