# Design — board presentation

## Context

This design replaces the one that shipped with the first implementation of issue 46. That design
capped the BACKLOG section's rows and each epic's sub-issue list, with a `--full` flag to disable
both. It is recorded here in outline because the reason it failed is the reason this design has
the shape it does.

## D1. Why capping was the wrong lever

Two symptoms, one cause.

**The cap needed exceptions.** "Next up" had to read past it, EPICS needed a separate cap with
different semantics, and `--full` had to undo both. Each exception is a place the board's output
stops meaning one thing.

**One exception was unfalsifiable.** The spec required that capping "never changes which issue
next up recommends". No implementation could violate it: `backlog` is sorted by
`(priority_key, number)` before any cap is applied, and the cap takes a prefix, so the
top-priority row is always inside the displayed set. The requirement described a bug that the sort
order already made unreachable — and the two tests written for it would have passed whether or not
the cap leaked into the recommendation.

The cause underneath both: the board rendered two categories with opposite growth from one
function. Delivery state is bounded by the pipeline — an issue only reaches `status:in-progress`
because an agent is driving it, and there is a small ceiling on how many run at once. The
ungroomed backlog is bounded by nothing and grows forever. Capping was an attempt to make the
second fit beside the first.

## D2. Counts, not caps

An unbounded category is reported as a number. Bounded categories render their rows.

| category | growth | rendering |
|---|---|---|
| blocked on you, in flight, ready | bounded by the pipeline | rows |
| ungroomed backlog, epics | unbounded | count only |

This removes the cap, the `--full` flag, the `capped()` helper and the invariance requirement in
one move, because none of them has anything left to act on. It also makes a property the caps
could only approximate exactly true: **the board's rendered length no longer varies with the size
of the backlog.** That is the property worth testing, and it is the one the spec now states.

## D3. Every line is conditional

No header, count, or suggestion renders unless it has content. A section with nothing to report
contributes zero lines — not a header with nothing beneath it, and not a `blocked: 0` entry in the
summary.

The consequence worth stating: an absent line is information. When the archive suggestion is on
screen there is something to archive; when it is absent there is not. A board that renders
`specs pending archive: 0` forces the reader to parse a number to learn nothing happened.

The failure mode to watch is stray whitespace. Each existing section appends a trailing `""` after
its rows to separate itself from the next. A section that returns early must not leave that blank
line behind, or removing sections produces a board with growing gaps where content used to be.
Hence the spec's scenario asserts absence of the *header*, not merely absence of rows.

## D4. The board reports; it does not direct owned work

"Next up" previously recommended four things. Three of them named an issue that already had an
agent driving it:

- **merge this green PR** — that issue's `issue-manager` is alive and parked at Seam 2. It is
  already waiting to tell the owner exactly this.
- **unblock this** — likewise; the agent posted the `🆘` comment that the board is reading.
- **groom this backlog issue** — the backlog's own job, not the delivery board's.

Only the fourth — activate an unclaimed `status:ready` issue — names work with no owner at all.
That is the one that survives, and it is the whole of "next up" now: highest priority first, P0
through P3, and silence when there is nothing.

The distinction is between reporting and directing. BLOCKED ON YOU keeps rendering its rows,
because *discovering* which of several background sessions wants you is cross-issue information no
single `issue-manager` can provide. What it stops doing is telling the owner to act on an issue
another agent owns.

A rejected alternative: gate the merge recommendation on the liveness marker, showing it only when
a row is 🔴 (no `agent:active` label, so nothing is driving it). This was rejected because it is
right for the wrong reason — it would make the recommendation *accurate* while leaving the board
in the business of directing work it does not own. It also cannot be made correct: an
`issue-manager` that dies uncleanly never removes its label, so an abandoned issue sits 🟡
indefinitely and never reaches 🔴.

## D5. Keycap priority rendering

`P0`–`P3` render as `0️⃣`–`3️⃣`.

One implementation hazard, because the board is column-aligned plain text: a keycap emoji is three
codepoints — the digit, U+FE0F, and U+20E3 — so Python counts `"1️⃣"` as length 3 while a terminal
draws it in roughly two cells. The existing `f"{row['priority'] or '--':3}"` would therefore pad
every prioritized row differently from every unprioritized one, and the columns after it would
drift.

The fix is to stop using format-width padding for this field: emit the keycap followed by a
literal space, and a fixed-width blank of matching display width when an issue has no priority
label. All four keycaps are the same width, so alignment holds without measurement.

## D6. Retained from the first implementation

Three pieces survive the re-scope, and are already implemented and tested on the branch.

- **Concurrent comment prefetch** (`prefetch_notes()`) — orthogonal to rendering; it changes when
  `gh` calls happen, not what is printed.
- **Per-row failure isolation**, including `json.JSONDecodeError` handling — same.
- **`render_board()` decomposed into one function per section** — this one earns its place here
  rather than merely surviving. Conditional rendering (D3) is a per-section decision; with one
  function per section each decides for itself and returns nothing when it has nothing. Inlined in
  a single function, the same behavior is a thicket of nested conditionals around a shared `out`
  list, which is what the original code was.

Its requirement did change: the decomposition no longer promises byte-for-byte identical output,
because the output is deliberately changing now. It promises structure — one function per section,
so a section's presence is decided in one place.

## D7. Explicitly out of scope

- **Bounding what the board retrieves.** `ISSUE_LIMIT` and pagination are untouched; that is a
  real concern but a different one, and it needs GraphQL pagination.

  The one fetch edit this change does make is subtractive, and follows from the rendering change
  rather than reopening the fetch question: with epics reporting as a count, nothing reads the
  `subIssues` node list, so it leaves the `--json` field list along with the three dead row keys
  it fed. `subIssuesSummary` stays — `is_epic` tests its `total`. Keeping a query field that no
  code reads would have been the pin producing a worse result than the rule it protects.

  Note also that a fetch bound would not reduce context cost: `board.py` is a script, and only its
  stdout enters a model's context — the raw JSON never does. Rendering is the only lever on
  tokens, which is why this change is a rendering change.
- **A separate backlog agent** and the view that would serve it. The owner is grooming
  interactively for now. The accepted consequence is that this board shows a count where it used
  to show rows, with no replacement view yet.
- **Autopilot** — automatically serving or starting the top ready item, and the conflict detection
  that would require. The conflict question already has machinery worth reusing (the
  backlog-overlap search `project-manager` runs at spawn time), but none of it belongs here.
