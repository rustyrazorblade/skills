## ADDED Requirements

### Requirement: The READY bucket renders at most `--ready-limit` rows

The board SHALL render no more than `--ready-limit` READY rows, default 5, taken from the front of the priority-sorted ready list. The flag SHALL NOT change the sort order or which issues belong to the bucket.

#### Scenario: The default cap applies with no flag
- **WHEN** the board renders with 9 qualifying ready issues and no `--ready-limit` flag
- **THEN** the READY block contains exactly 5 rows

#### Scenario: An explicit limit replaces the default
- **WHEN** the board renders with 9 qualifying ready issues and `--ready-limit 2`
- **THEN** the READY block contains exactly 2 rows

#### Scenario: Exactly at the cap renders every row
- **WHEN** the board renders with N qualifying ready issues and `--ready-limit N`
- **THEN** the READY block contains all N rows
- **AND** no withheld-count line appears

#### Scenario: Below the cap renders every row
- **WHEN** the board renders with 4 qualifying ready issues and the default limit of 5
- **THEN** the READY block contains all 4 rows
- **AND** no withheld-count line appears, and no negative count is rendered

#### Scenario: The rendered rows are the highest priority ones
- **WHEN** the ready list holds one P0, one P1 and three P3 issues and the limit is 2
- **THEN** the P0 and the P1 render
- **AND** none of the three P3 issues renders

#### Scenario: No qualifying ready issue renders nothing at all
- **WHEN** no issue qualifies for the READY bucket, at any limit
- **THEN** no READY header, no rows and no withheld-count line appear

### Requirement: Withheld ready rows report as a count on one line

When the cap withholds rows, the board SHALL report the withheld count on one line inside the READY block, directly under the rendered rows, naming the remedy. Rendered rows plus withheld count SHALL equal the total qualifying ready issues. The line SHALL be absent when nothing is withheld.

#### Scenario: The withheld line reports the count and the remedy
- **WHEN** the board renders 9 qualifying ready issues at the default limit of 5
- **THEN** the last line of the READY block reads `  … 4 more ready — raise --ready-limit to see the rest`
- **AND** 5 rendered rows plus 4 withheld equals the 9 total

#### Scenario: The count tracks an explicit limit
- **WHEN** the board renders 9 qualifying ready issues at `--ready-limit 2`
- **THEN** the withheld line reports `7 more ready`

#### Scenario: A single withheld row reads as singular
- **WHEN** the board renders 6 qualifying ready issues at the default limit of 5
- **THEN** the withheld line reports `1 more ready`, not `1 more readys`

#### Scenario: Rendered length does not track the size of the ready queue
- **WHEN** two boards differ only in that one holds 500 more qualifying ready issues than the other
- **THEN** both renders have the same line count
- **AND** each reports its own withheld count, so the invariance holds by reporting rather than by silence

### Requirement: The board's recommendation considers every ready issue

`compute_next_up` SHALL receive the full, uncapped ready list. A withheld issue SHALL still be eligible as the board's recommendation.

#### Scenario: Next up names an issue the cap withheld
- **WHEN** the five highest-priority ready issues are all assigned and a lower-priority ready issue is unclaimed
- **THEN** the "Next up" line names that unclaimed issue
- **AND** that issue does not appear among the rendered READY rows

### Requirement: The cap applies to the READY bucket alone

No other bucket SHALL be capped by `--ready-limit`.

#### Scenario: Other buckets render in full whatever the limit
- **WHEN** the board holds 9 blocked-on-you issues and 9 in-flight issues, at any `--ready-limit`
- **THEN** all 18 rows render

### Requirement: `--ready-limit` below 1 is a usage error

The board SHALL reject a `--ready-limit` value below 1 before any GitHub call, exiting non-zero and printing no board.

#### Scenario: Zero is rejected
- **WHEN** the board runs with `--ready-limit 0`
- **THEN** it exits non-zero, prints no board on stdout, and reports the usage error on stderr

#### Scenario: A negative value is rejected
- **WHEN** the board runs with `--ready-limit -1`
- **THEN** it exits non-zero, prints no board on stdout, and reports the usage error on stderr

#### Scenario: A valid value reaches the render
- **WHEN** the board runs from the command line with `--ready-limit 2` over 9 qualifying ready issues
- **THEN** the rendered board contains 2 READY rows, not the default 5

### Requirement: Bucket rendering stays behavior-preserving

Collapsing the per-bucket render helpers and replacing the bucket-membership scans SHALL NOT change any rendered board.

#### Scenario: Existing renders are unchanged
- **WHEN** the bucket-render helpers are one shared helper and bucket membership is computed from a set of issue numbers
- **THEN** every pre-existing `test-board.sh` assertion passes and the suite exits 0

### Requirement: The board documents how its length is bounded

The board's own documentation SHALL name every mechanism that bounds its rendered length.

#### Scenario: The flag is documented with its default
- **WHEN** a reader opens `skills/board/SKILL.md`
- **THEN** it names `--ready-limit`, states the default of 5, and says "next up" still considers every ready issue

#### Scenario: The docstring no longer claims two unbounded categories
- **WHEN** a reader opens `board.py`'s module docstring and `render_summary`'s comment
- **THEN** neither claims that only the ungroomed backlog and the epic list are unbounded
