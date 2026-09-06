# delivery-board Specification

## Purpose
TBD - created by archiving change issue-46. Update Purpose after archive.
## Requirements
### Requirement: Unbounded categories report as counts, never as rows
The system SHALL report the ungroomed backlog and the epic list as counts in the board's summary
line, and SHALL NOT render a per-issue row for either. The board's rendered length SHALL NOT grow
with the size of the backlog or the number of epics.

#### Scenario: A large ungroomed backlog
- **WHEN** `board.py` renders a repo with 15 ungroomed issues
- **THEN** the summary line reports `15 ungroomed` and no ungroomed issue is rendered as its own
  row

#### Scenario: Backlog size does not change board length
- **WHEN** `board.py` renders the same repo state twice, differing only in the number of
  ungroomed issues
- **THEN** both renders produce the same number of lines

### Requirement: Every section renders only when it has content
The system SHALL render a section header, a count, or a suggested action only when that element
has content to report. The system SHALL NOT render an empty section, a zero count, or a
placeholder line standing in for absent content.

#### Scenario: No issues are waiting on the owner
- **WHEN** no issue is blocked on the owner
- **THEN** the BLOCKED ON YOU header does not appear at all, rather than appearing with no rows
  beneath it

#### Scenario: Nothing is pending archive
- **WHEN** no OpenSpec changes are pending archive
- **THEN** no archive line and no `specs pending archive: 0` text appears anywhere in the output

### Requirement: "Next up" names only unclaimed ready work, in priority order
The system SHALL recommend at most one issue under "next up", and SHALL draw that recommendation
only from issues carrying the `status:ready` label with no assignee. The system SHALL order those
candidates by priority label, P0 before P1 before P2 before P3, with unprioritized issues last.

#### Scenario: Several ready issues at different priorities
- **WHEN** unclaimed `status:ready` issues exist at P2 and P0
- **THEN** "next up" names the P0 issue

#### Scenario: No ready issues exist
- **WHEN** no unclaimed `status:ready` issue exists
- **THEN** no "next up" line is rendered at all

### Requirement: "Next up" never recommends an issue that already has an owner
The system SHALL NOT recommend merging a pull request, unblocking a stopped agent, or grooming a
backlog issue under "next up". Each of those names work already driven by another agent — an
issue's own `issue-manager`, or the backlog's — and the board reports state rather than directing
work it does not drive.

#### Scenario: A green PR is waiting on the owner's review
- **WHEN** an issue is `status:in-review` with a green PR awaiting the owner
- **THEN** "next up" does not recommend merging it, regardless of whether that issue's
  `issue-manager` session is live, stalled, or absent

#### Scenario: The backlog is the only work available
- **WHEN** no unclaimed `status:ready` issue exists and the backlog is non-empty
- **THEN** "next up" recommends nothing, rather than falling back to a grooming suggestion

### Requirement: BLOCKED ON YOU reports rows without recommending them
The system SHALL continue to render a row for each issue blocked on the owner, including its
attach instruction, PR and CI state, and liveness marker. That section SHALL NOT feed the "next
up" recommendation.

#### Scenario: An agent is stopped waiting on the owner
- **WHEN** an issue carries `needs-attention` and its agent is parked
- **THEN** its row renders under BLOCKED ON YOU with its attach instruction, and "next up" does
  not name it

### Requirement: Suggested actions are conditional on being actionable
The system SHALL render a suggested command only when the condition it addresses currently holds.

#### Scenario: Specs are pending archive
- **WHEN** one or more OpenSpec changes are pending archive
- **THEN** the board renders a `/spec-flow:archive` suggestion naming how many are pending

### Requirement: Priority renders as a keycap digit
The system SHALL render an issue's priority as the corresponding keycap emoji — `P0` as `0️⃣`,
`P1` as `1️⃣`, `P2` as `2️⃣`, `P3` as `3️⃣` — rather than the literal label text. An issue with no
priority label SHALL render a fixed-width blank in that position, so rows stay column-aligned.

#### Scenario: A prioritized issue renders
- **WHEN** a row for a `P1` issue is rendered
- **THEN** its priority column shows `1️⃣` and not the text `P1`

#### Scenario: An unprioritized issue renders alongside prioritized ones
- **WHEN** rows for a `P1` issue and an issue with no priority label render in the same section
- **THEN** both rows' subsequent columns remain aligned with each other

### Requirement: Concurrent comment prefetch preserves existing note content
The system SHALL fetch blocked/needs-attention issues' comment-derived notes concurrently (not
serially) while preserving the exact note content each issue would have received under the
previous serial implementation, and without changing the total number of `gh` calls made.

#### Scenario: Blocked/needs-attention notes render unchanged
- **WHEN** one or more issues carry the `blocked` or `needs-attention` label
- **THEN** their comment-derived notes (`blocked_note`, `attention_note`) render with the same
  content as before the change

### Requirement: Per-row failure isolation during concurrent prefetch
The system SHALL isolate failures in the concurrent comment prefetch so that one issue's failed
`gh issue view --json comments` call (whether a process error or a malformed-JSON response)
falls back to a fixed placeholder note for that issue alone, without aborting the batch or
affecting any other issue's note.

#### Scenario: One issue's comment fetch fails during the concurrent prefetch
- **WHEN** `gh issue view ... --json comments` fails (process error or malformed JSON) for one
  blocked/needs-attention issue during the concurrent prefetch
- **THEN** that issue's row falls back to `"see issue comments"` exactly as today, and other
  rows' notes are unaffected — no single failure aborts the batch

### Requirement: `render_board()` delegates every section to a render function
The system SHALL structure `render_board()` so that every rendered section is produced by a render
function returning its own lines, and a section's conditional presence is decided inside that
function rather than inline within a single large function. Sections whose rendering is identical
apart from the header MAY share one parameterized helper; what this requirement fixes is that the
presence decision lives in a render function, not that each section has a function of its own.

#### Scenario: A section with no content contributes no lines
- **WHEN** a section's render function is called with no rows to render
- **THEN** it returns no lines, and the assembled board contains no trace of that section

#### Scenario: Sections sharing a helper each decide their own presence
- **WHEN** several sections are rendered through one shared parameterized helper
- **THEN** each still renders only when it has rows, and an empty one contributes no lines

### Requirement: Test suite covers the new render
The system's test suite (`test-board.sh`) SHALL cover the summary-count rendering of backlog and
epics, the absence of every empty section and zero count, the narrowed "next up" behavior
including its silence when no ready work exists, the conditional archive suggestion, keycap
priority rendering and column alignment, and the concurrent prefetch's transparency and
failure-isolation behavior.

#### Scenario: Test suite passes after the change
- **WHEN** `plugins/spec-flow/scripts/test-board.sh` is run after this change
- **THEN** it exits 0

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

