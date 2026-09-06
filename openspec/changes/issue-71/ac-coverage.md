# Acceptance-criteria coverage — issue-71

One row per acceptance criterion on the issue, and one per risk the architect's design surfaced. Scenario names are given as `<capability>: <scenario title>`.

| Source | Requirement | Covering scenario(s) | Status |
|--------|-------------|----------------------|--------|
| AC | No flag, 9 ready issues -> exactly 5 rows render | `delivery-board: The default cap applies with no flag` | ✅ Covered |
| AC | 4 rows withheld -> one line reports `4 more`; rendered plus withheld equals the total | `delivery-board: The withheld line reports the count and the remedy` | ✅ Covered |
| AC | `--ready-limit 2` with 9 ready -> 2 rows, withheld reports 7 | `delivery-board: An explicit limit replaces the default`, `delivery-board: The count tracks an explicit limit` | ✅ Covered |
| AC | Ready count at or below the cap -> all rows render, no withheld line appears | `delivery-board: Exactly at the cap renders every row`, `delivery-board: Below the cap renders every row` | ✅ Covered |
| AC | P0, P1 and three P3s with `--ready-limit 2` -> the P0 and P1 render, no P3 does | `delivery-board: The rendered rows are the highest priority ones` | ✅ Covered |
| AC | Top 5 ready all assigned, a lower-priority ready issue unclaimed -> "Next up" still names that issue | `delivery-board: Next up names an issue the cap withheld` | ✅ Covered |
| AC | Two renders differing only by 500 extra ready issues have the same line count | `delivery-board: Rendered length does not track the size of the ready queue` | ✅ Covered |
| AC | 9 blocked-on-you and 9 in-flight issues -> all 18 render, whatever `--ready-limit` is | `delivery-board: Other buckets render in full whatever the limit` | ✅ Covered |
| AC | No qualifying ready issue -> no header, no rows, no withheld line, at any limit | `delivery-board: No qualifying ready issue renders nothing at all` | ✅ Covered |
| AC | `--ready-limit 0` or `--ready-limit -1` -> non-zero exit, usage error, no board printed | `delivery-board: Zero is rejected`, `delivery-board: A negative value is rejected` | ✅ Covered |
| AC | `test-board.sh` passes every pre-existing assertion and exits 0 | `delivery-board: Existing renders are unchanged` | ✅ Covered |
| AC | `--ready-limit` documented in `skills/board/SKILL.md` with its default; the `board.py` docstring no longer claims only two categories are unbounded | `delivery-board: The flag is documented with its default`, `delivery-board: The docstring no longer claims two unbounded categories` | ✅ Covered |
| AC | Exactly N ready rows at `--ready-limit N` -> all N render, no withheld line | `delivery-board: Exactly at the cap renders every row` | ✅ Covered |
| AC | `main()` passes `args.ready_limit` to `render_board`, so `--ready-limit 2` changes the CLI render | `delivery-board: A valid value reaches the render` | ✅ Covered |
| AC | The four render helpers are one `render_section`, and every bucket renders as it did before | `delivery-board: Existing renders are unchanged` | ✅ Covered |
| AC | Bucketing uses a set of issue numbers, not `r not in blocked_on_you` | `delivery-board: Existing renders are unchanged` | ✅ Covered |
| Risk | Live behavior changes for a repo with more than five ready issues, with no opt-in | `delivery-board: The withheld line reports the count and the remedy` — the line is the disclosure and names the flag that restores the old behavior | ✅ Covered |
| Risk | The withheld line reports a count, not which issues, so an owner hunting a specific ready issue must raise the limit | `delivery-board: The withheld line reports the count and the remedy` — the remedy clause is what makes the count actionable | ✅ Covered |
| Risk | The signature change reaches five call sites; the fifth, `main()`, is invisible to every in-process test | `delivery-board: A valid value reaches the render` — exercises the CLI, not the in-process function | ✅ Covered |
| Risk | `count_bit` returns `'-3 more ready'` for a negative, so removing `max(0, …)` as redundant renders a negative count below the cap | `delivery-board: Below the cap renders every row` — asserts no negative count is rendered | ✅ Covered |
| Risk | The folded-in refactors change code the cap does not otherwise touch | `delivery-board: Existing renders are unchanged` — fixture 3 compares a whole render | ✅ Covered |
| Risk | `--ready-limit -1e3` errors with `expected one argument` rather than the `must be 1 or more` message | — | ⚠️ Excluded — still exit 2 with no board printed, which is the behavior the criterion requires; the differing message is not an acceptance criterion and pinning argparse's internal wording would make the suite brittle |
| Risk | If issue 71 is archived and `issue-46` never is, the archived capability carries the cap requirement without the "unbounded categories" requirement the rewritten docstring describes | — | ⚠️ Excluded — an archive-sequencing risk, not a behavior of the board; both changes are queued for the same bulk archive pass |
| Risk | The folded-in render-helper collapse contradicts the letter of `issue-46`'s "one function per section" requirement | — | ⚠️ Excluded — a conflict between two in-flight specs, not a criterion this change's scenarios can satisfy; it is raised for the owner's decision in `overrides.md` |
