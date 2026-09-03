## ADDED Requirements

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

### Requirement: `render_board()` is decomposed into one function per section
The system SHALL structure `render_board()` as one function per rendered section, each returning
its own lines, so that a section's conditional presence is decided in one place rather than
inline within a single large function.

#### Scenario: A section with no content contributes no lines
- **WHEN** a per-section render function is called with no rows to render
- **THEN** it returns no lines, and the assembled board contains no trace of that section

### Requirement: Test suite covers the new render
The system's test suite (`test-board.sh`) SHALL cover the summary-count rendering of backlog and
epics, the absence of every empty section and zero count, the narrowed "next up" behavior
including its silence when no ready work exists, the conditional archive suggestion, keycap
priority rendering and column alignment, and the concurrent prefetch's transparency and
failure-isolation behavior.

#### Scenario: Test suite passes after the change
- **WHEN** `plugins/spec-flow/scripts/test-board.sh` is run after this change
- **THEN** it exits 0
