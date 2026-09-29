## ADDED Requirements

### Requirement: "Blocked" derives from open native blockers or the `blocked` label

The board SHALL request `blockedBy` in its `gh issue list` fetch and SHALL treat an issue as blocked
when `blockedBy.nodes` holds at least one node with `state == "OPEN"`, or when the issue carries the
`blocked` label. The board SHALL read `blockedBy` in gh's `{"nodes": [...], "totalCount": N}` shape,
and SHALL treat a missing or null `blockedBy` as no native blockers.

#### Scenario: An open native blocker blocks the issue
- **WHEN** an open issue has a native blocker whose state is OPEN
- **THEN** it appears in the "🔒 Blocked" section with that blocker listed as `<number>: <title>`

#### Scenario: Every native blocker is closed
- **WHEN** every native blocker of an issue is CLOSED, whether completed or not planned, and the
  issue has no `blocked` label
- **THEN** the issue is not blocked, does not appear under Blocked, and appears wherever its status
  puts it

#### Scenario: The label alone blocks the issue
- **WHEN** an issue has the `blocked` label and no open native blocker
- **THEN** it appears under Blocked

#### Scenario: A missing or null `blockedBy`
- **WHEN** an issue's `blockedBy` field is absent or null
- **THEN** the board treats it as having no native blockers, and does not fail

#### Scenario: The fetch requests `blockedBy`
- **WHEN** the board runs its `gh issue list` fetch
- **THEN** the `--json` field list includes `blockedBy`

### Requirement: A Blocked row lists every blocker on its own indented line

The Blocked section SHALL render each blocked issue as `- <number>: <title>` on one line, followed by
one indented line per open native blocker, `- <number>: <title>`, and, when the issue carries the
`blocked` label, one indented label line. Closed native blockers SHALL NOT be listed. A native
blocker in another repo SHALL render the same way, with no repo name.

#### Scenario: Several open native blockers, one closed
- **WHEN** an issue has several native blockers, one of them CLOSED
- **THEN** its Blocked row lists every open blocker as `<number>: <title>` on its own indented line
- **AND** the closed blocker is not listed

#### Scenario: A cross-repo native blocker
- **WHEN** an issue's open native blocker is an issue in another repo
- **THEN** that blocker renders as `<number>: <title>`, with no repo name

#### Scenario: Both kinds of blocker on one issue
- **WHEN** an issue has an open native blocker and the `blocked` label
- **THEN** its Blocked row shows the issue on one line, then one indented line per open native
  blocker, then one indented label line

### Requirement: The label line comes from the last `Blocked by:` comment

The label line SHALL be rendered as `- ⛔ Blocked by: <reason>`, from the first line of the last
comment on the issue whose body starts with `Blocked by:` (exact, case-sensitive). When no comment
matches, the label line SHALL read `- ⛔ Blocked by: see issue comments`.

#### Scenario: The label reason comes from an `add-external` comment
- **WHEN** an issue has the `blocked` label and a comment `Blocked by: waiting on upstream PR`
- **THEN** its label line reads `- ⛔ Blocked by: waiting on upstream PR`

#### Scenario: The newest `Blocked by:` comment wins
- **WHEN** an issue with the `blocked` label has two `Blocked by:` comments
- **THEN** the label line shows the reason from the later one

#### Scenario: A later `add` comment does not replace the external reason
- **WHEN** an issue has an `add-external` comment `Blocked by: <reason>`, followed later by an `add`
  comment `⛔ Blocked on #M — …`
- **THEN** the label line still shows the `add-external` reason

#### Scenario: The label with no `Blocked by:` comment
- **WHEN** an issue has the `blocked` label and no comment starting with `Blocked by:`, including one
  whose only blocked comments use the older `⛔ Blocked on #M` or `⛔ Blocked on:` forms
- **THEN** it still appears under Blocked, with the label line `- ⛔ Blocked by: see issue comments`

### Requirement: Blocked issues leave READY and "Next up", and stay in IN FLIGHT and BLOCKED ON YOU

The board SHALL exclude every blocked issue, by either route, from the READY bucket and from the
"Next up" recommendation. The board SHALL NOT change IN FLIGHT or BLOCKED ON YOU membership because
an issue is blocked; a blocked issue that qualifies for either SHALL appear there and also under
Blocked. The summary's "N blocked" count SHALL include issues blocked by either route.

#### Scenario: A blocked ready issue
- **WHEN** a `status:ready` issue is blocked by an open native blocker or by the label
- **THEN** it does not appear in READY and is not named as "Next up"
- **AND** "Next up" names the next eligible unclaimed ready issue, if one exists

#### Scenario: A blocked in-flight issue
- **WHEN** an issue that is in progress, in review, or addressing is blocked
- **THEN** it still appears in IN FLIGHT, and also under Blocked

#### Scenario: A blocked issue waiting on the owner
- **WHEN** an issue that qualifies for BLOCKED ON YOU is also blocked
- **THEN** it still appears in BLOCKED ON YOU, and also under Blocked

#### Scenario: The summary counts both kinds
- **WHEN** one issue is blocked only by an open native blocker and another only by the label
- **THEN** the summary reports `2 blocked`

### Requirement: IN FLIGHT and BLOCKED ON YOU rows carry a bare `🔒 BLOCKED` marker

A blocked issue's row in IN FLIGHT or BLOCKED ON YOU SHALL carry the bare marker `🔒 BLOCKED`, with
no blocker details. Blocker details SHALL appear only in the Blocked section.

#### Scenario: A blocked in-flight row
- **WHEN** a blocked issue renders in IN FLIGHT
- **THEN** its row carries `🔒 BLOCKED` and no blocker number, title, or reason

#### Scenario: A blocked row waiting on the owner
- **WHEN** a blocked issue renders in BLOCKED ON YOU
- **THEN** its row carries `🔒 BLOCKED` and no blocker number, title, or reason

### Requirement: A blocked stalled issue's spawn command is marked

The Stalled section SHALL mark the spawn command of a blocked issue with `🔒 BLOCKED`.

#### Scenario: A blocked stalled issue
- **WHEN** a stalled issue is blocked by either route
- **THEN** its spawn command line in the Stalled section is marked `🔒 BLOCKED`

#### Scenario: An unblocked stalled issue
- **WHEN** a stalled issue is not blocked
- **THEN** its spawn command line carries no `🔒 BLOCKED` marker

### Requirement: A failed issue fetch fails the board

When `gh issue list` fails, the board SHALL print gh's error and exit non-zero, and SHALL NOT render
a board.

#### Scenario: `gh issue list` fails
- **WHEN** the `gh issue list` call exits non-zero
- **THEN** the board prints the gh error on stderr, exits non-zero, and prints no board on stdout

### Requirement: The test suite covers blocked derivation with a shared row helper

`scripts/test-board.sh` SHALL define its `row(**kw)` helper in one shared place, not one copy per
check, and every pre-existing check SHALL still pass. It SHALL carry a fixture and a passing check
for each of these cases: open native blocker only; several open native blockers with one closed; a
closed native blocker (released); a blocker closed as not planned (released); label only, with the
`Blocked by:` form; label and open native blocker together; an `add-external` comment followed by a
later `add` comment; a blocked ready issue absent from READY and "Next up"; a blocked in-flight
issue with the bare `🔒 BLOCKED` marker; a blocked stalled issue with its spawn command marked; a
cross-repo native blocker; and a failing `gh issue list`. Fixtures SHALL carry `blockedBy` in gh's
real `{"nodes": [...], "totalCount": N}` shape, and the fake `gh` SHALL fail when the board does not
request `blockedBy`.

#### Scenario: One shared row helper
- **WHEN** a reader searches `test-board.sh` for the `row(**kw)` helper definition
- **THEN** it is defined once, and every check that builds rows uses it

#### Scenario: The suite passes
- **WHEN** `plugins/spec-flow/scripts/test-board.sh` runs after this change
- **THEN** every pre-existing check and every blocked-case check passes, and it exits 0

#### Scenario: The fake `gh` guards the field list
- **WHEN** the board's issue-list call omits `blockedBy`
- **THEN** the fake `gh` fails, and the suite fails

## MODIFIED Requirements

### Requirement: "Next up" names only unclaimed ready work, in priority order
The system SHALL recommend at most one issue under "next up", and SHALL draw that recommendation
only from issues carrying the `status:ready` label with no assignee that are not blocked, by an open
native blocker or by the `blocked` label. The system SHALL order those candidates by priority label,
P0 before P1 before P2 before P3, with unprioritized issues last.

#### Scenario: Several ready issues at different priorities
- **WHEN** unclaimed `status:ready` issues exist at P2 and P0
- **THEN** "next up" names the P0 issue

#### Scenario: No ready issues exist
- **WHEN** no unclaimed `status:ready` issue exists
- **THEN** no "next up" line is rendered at all

#### Scenario: The highest-priority ready issue is blocked
- **WHEN** the highest-priority unclaimed `status:ready` issue is blocked, and a lower-priority
  unclaimed `status:ready` issue is not
- **THEN** "next up" names the lower-priority issue

#### Scenario: Every unclaimed ready issue is blocked
- **WHEN** every unclaimed `status:ready` issue is blocked
- **THEN** no "next up" line is rendered at all

### Requirement: Concurrent comment prefetch preserves existing note content
The system SHALL fetch the comment-derived notes of issues carrying the `blocked` label or the
`needs-attention` label concurrently (not serially), without changing the number of `gh` calls
made per labeled issue. The `needs-attention` note SHALL keep its existing content. The `blocked`
label note SHALL come from the last comment starting with `Blocked by:` (exact, case-sensitive), and
SHALL NOT come from a `⛔ Blocked on` comment. An issue blocked only by a native link SHALL NOT
trigger a comment fetch.

#### Scenario: Needs-attention notes render unchanged
- **WHEN** one or more issues carry the `needs-attention` label
- **THEN** their comment-derived `attention_note` renders with the same content as before the change

#### Scenario: A `blocked` label note comes from the `Blocked by:` comment
- **WHEN** an issue carries the `blocked` label and has both a `Blocked by: <reason>` comment and a
  later `⛔ Blocked on #M — …` comment
- **THEN** its label note is `<reason>` from the `Blocked by:` comment

#### Scenario: A native-only blocked issue fetches no comments
- **WHEN** an issue is blocked only by an open native blocker, with no `blocked` label
- **THEN** the board makes no comment fetch for it

### Requirement: Per-row failure isolation during concurrent prefetch
The system SHALL isolate failures in the concurrent comment prefetch so that one issue's failed
`gh issue view --json comments` call (whether a process error or a malformed-JSON response)
falls back to a fixed placeholder note for that issue alone, without aborting the batch or
affecting any other issue's note. For a `blocked` label carrier, the placeholder renders as the
label line `- ⛔ Blocked by: see issue comments`.

#### Scenario: One issue's comment fetch fails during the concurrent prefetch
- **WHEN** `gh issue view ... --json comments` fails (process error or malformed JSON) for one
  blocked/needs-attention issue during the concurrent prefetch
- **THEN** that issue falls back to `"see issue comments"` — for a `blocked` label carrier, the
  label line `- ⛔ Blocked by: see issue comments` — and other rows' notes are unaffected, and no
  single failure aborts the batch

### Requirement: The board's recommendation considers every ready issue

`compute_next_up` SHALL receive the full, uncapped list of ready issues that are not blocked. A
withheld issue that is not blocked SHALL still be eligible as the board's recommendation.

#### Scenario: Next up names an issue the cap withheld
- **WHEN** the five highest-priority ready issues are all assigned and a lower-priority ready issue is unclaimed and not blocked
- **THEN** the "Next up" line names that unclaimed issue
- **AND** that issue does not appear among the rendered READY rows

#### Scenario: A blocked withheld issue is not recommended
- **WHEN** the only unclaimed ready issue beyond the cap is blocked
- **THEN** "Next up" does not name it
