## 1. Baseline

- [x] 1.1 Run `plugins/spec-flow/scripts/test-board.sh` and record the PASS/FAIL counts. Every later step compares against this baseline, so a regression is attributable to one step.

## 2. Test-harness groundwork

- [x] 2.1 Split `section()` in `test-board.sh` into `section_in "$text" "$hdr"`, with `section()` delegating as `section_in "$out" "$1"`. Leave the awk body unchanged so every existing call site keeps working.
- [x] 2.2 Drop the stale `sub_issues`, `sub_total` and `sub_completed` keys from all four copies of the `row()` factory in `test-board.sh`. `build_rows` no longer produces them.
- [x] 2.3 Re-run the suite. It must match the 1.1 baseline exactly; these two steps change no rendered output.

## 3. The cap

- [x] 3.1 Declare `DEFAULT_READY_LIMIT = 5` directly above `render_ready` in `board.py`.
- [x] 3.2 Give `render_ready` a `limit=DEFAULT_READY_LIMIT` parameter and slice `ready_rows[:limit]`. Comment that `staged` is already sorted by `(priority, number)` before bucketing, so the first N are the N highest-priority ready issues.
- [x] 3.3 Append the withheld line: `withheld = count_bit(max(0, len(ready_rows) - limit), "more ready", "more ready")`, rendered as `f"  … {withheld} — raise --ready-limit to see the rest"` only when `withheld` is truthy. Comment that `max(0, …)` is the guard, because `count_bit` returns `'-3 more ready'` for a negative.
- [x] 3.4 Add `ready_limit=DEFAULT_READY_LIMIT` as `render_board`'s fourth parameter and pass it to `render_ready` alone. Comment that `compute_next_up` receives the full list, because the cap is a display bound and not a change to what the board considers.

## 4. The flag

- [x] 4.1 Add a `positive_int` callable that raises `argparse.ArgumentTypeError` for a non-integer and for `n < 1`.
- [x] 4.2 Wire `--ready-limit` into `main()`'s parser with `type=positive_int` and `default=DEFAULT_READY_LIMIT`, documenting the default in its help text.
- [x] 4.3 Pass `args.ready_limit` to `render_board` at `board.py:578`. Without this the flag parses, validates and is discarded, and every in-process test still passes.
- [x] 4.4 Confirm by hand that `--ready-limit 0` and `--ready-limit -1` exit non-zero with an empty stdout, and that `--ready-limit 2` changes the CLI render.

## 5. Behavior-preserving refactors

- [x] 5.1 Collapse `render_blocked_on_you`, `render_unrecognized` and `render_in_flight` into one `render_section(header, rows)`. READY becomes that call plus its withheld line.
- [x] 5.2 Re-run the suite. Fixture 3 compares a whole render, so any drift shows here.
- [ ] 5.3 Replace the `r not in blocked_on_you` scans at `board.py:502`, `507` and `515` with a set of blocked-on-you issue numbers. The current form compares whole row dicts field by field, up to 400 staged rows at `ISSUE_LIMIT`.
- [ ] 5.4 Re-run the suite again, separately from 5.2, so a failure attributes to one refactor.

## 6. Assertions

- [ ] 6.1 Extend fixture 4 with `#707` through `#711`, all `status:ready`, `P2`, assigned to `alice` rather than `me`, so `is_blocked_on_you` stays false. This reaches 9 ready rows, of which the first five sorted are `705, 706, 701, 707, 708`.
- [ ] 6.2 Run fixture 4 three times against the same fake PATH: default (5 rows, `4 more ready`, the withheld line is the last line of the block), `--ready-limit 2` (2 rows, `7 more ready`), and `--ready-limit 100` (9 rows, no `more ready` line). Count rows inside the block extracted by `section_in`, not over the whole board.
- [ ] 6.3 Add two usage-error runs against the same PATH asserting non-zero exit, empty stdout and `must be 1 or more` on stderr. Capture `$?` immediately after the assignment; `set -e` is not in effect in this file.
- [ ] 6.4 Add an in-process block asserting next up survives the cut: five assigned P0 ready rows plus an unclaimed P3 `#900`; the next-up line names 900 and `#900` is absent from the rendered rows.
- [ ] 6.5 Add an in-process block asserting length invariance: 6 versus 506 ready rows render the same line count, with `1 more ready` and `501 more ready` present, so the invariance holds by reporting rather than by silence.
- [ ] 6.6 Add an in-process block asserting priority order under the cap: one P0, one P1 and three P3s at `ready_limit=2` render the P0 and P1 only, with `3 more ready`.
- [ ] 6.7 Add an in-process block asserting the boundaries: N ready rows at `ready_limit=N` render all N with no withheld line, and 4 ready rows at `ready_limit=5` render all 4 with no withheld line and no negative count.
- [ ] 6.8 Add an in-process block asserting nothing else is capped: nine blocked-on-you plus nine in-flight rows all render, at two different limits, and no ready issue at limits 1, 5 and 500 produces no READY header and no `more ready` text.

## 7. Prose

- [ ] 7.1 Rewrite the "two unbounded categories" sentence in `board.py`'s module docstring to name the ready-queue bound alongside the backlog and epic counts.
- [ ] 7.2 Rewrite `render_summary`'s comment at `board.py:406-409`. Its claim that "the delivery buckets above are bounded by how many agents can run at once" is false for READY, which is bounded by grooming.
- [ ] 7.3 Document `--ready-limit` in `plugins/spec-flow/skills/board/SKILL.md` beside `--user`: the default of 5, that the remainder reports as a count inside the block, that "next up" still considers every ready issue, and that a large N is the uncap.

## 8. Close out

- [ ] 8.1 Run the full suite once more. It must exit 0 with no pre-existing assertion changed.
- [ ] 8.2 Run `board.py` against this repo at the default and at `--ready-limit 100`, and confirm both renders read correctly.
