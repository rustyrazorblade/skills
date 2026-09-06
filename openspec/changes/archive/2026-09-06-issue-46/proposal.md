## Why

`board.py` renders one board for two audiences with opposite needs. Delivery state — what is in
flight, what is waiting on the owner — is small, bounded by the pipeline itself, and is what the
owner actually reads. The ungroomed backlog is unbounded, grows forever, and is a different job
entirely. Rendering both inline means the second crowds out the first: on the repo today the board
prints 22 lines, 12 of which are a backlog dump, and `board/SKILL.md` has the calling model print
that stdout verbatim as its own reply — so the text lands in context twice per invocation and
persists in session history.

The earlier version of this change tried to fix that by capping the backlog's rendered rows. That
was the wrong lever. A cap needs exceptions to stay correct — "next up" must read past it, EPICS
needs a different one, `--full` must undo it — and each exception is a place the board contradicts
itself. The change carried a requirement stating that capping "never changes which issue next up
recommends", which no implementation could violate, because the backlog is sorted before the cap
is applied. An unfalsifiable requirement is a sign the design is working around itself.

The board does not need a smaller backlog rendering. It needs to stop rendering the backlog and
report a count instead.

A second, unrelated defect: "next up" recommends actions on issues that already have an owner —
telling the owner to merge a PR that a live `issue-manager` is already parked on at Seam 2, or to
unblock an issue whose own agent is waiting to tell them the same thing. The board does not drive
issues; it reports on them.

## What Changes

- Replace the BACKLOG and EPICS sections with counts in a single summary line. Neither renders
  per-issue rows.
- Render every section conditionally: a header, count, or suggestion appears only when it has
  content. Nothing renders to fill a slot, and no section prints a zero.
- Narrow "next up" to a single case — the highest-priority unclaimed `status:ready` issue, P0
  before P1 before P2 before P3. Remove the merge-a-green-PR, unblock, and groom-the-backlog
  recommendations: each names an issue that already has an owner driving it.
- Suggest an action only when it is actionable. `/spec-flow:archive` appears when specs are
  pending and is absent otherwise, rather than reporting `specs pending archive: 0`.
- Render priority as a keycap digit (`P1` → `1️⃣`) rather than the literal label text.
- Keep BLOCKED ON YOU rendering its rows unchanged. It reports which background sessions want the
  owner, which is cross-issue discovery no single `issue-manager` can provide. It no longer feeds
  "next up".
- Keep the concurrent comment prefetch, its per-row failure isolation, and the `render_board()`
  decomposition from the earlier revision of this change. The decomposition earns its place here:
  conditional per-section rendering is materially cleaner with one function per section.

## Capabilities

### New Capabilities
- `delivery-board`: `board.py`'s deterministic rendering of the delivery board — bucketing issues
  by lifecycle status, reporting unbounded categories as counts, recommending only unowned work,
  and prefetching comment-derived notes concurrently. No existing capability spec covers
  `board.py`; this is its first.

### Modified Capabilities
(none — `delivery-board` is new)

## Impact

- `plugins/spec-flow/scripts/board.py` — BACKLOG and EPICS section renderers replaced by summary
  counts; `compute_next_up()` reduced to the ready-issue case and no longer takes
  `blocked_on_you` or `backlog`; conditional suggestion rendering; keycap priority formatting;
  `render_board()` decomposed into per-section functions; `prefetch_notes()` and the broadened
  exception handling in `last_comment_matching()` retained.
- `plugins/spec-flow/scripts/test-board.sh` — fixtures and assertions updated to the new render.
- `plugins/spec-flow/skills/board/SKILL.md` — the bucket list drops BACKLOG and EPICS, and the
  judgment step conditional on a backlog groom recommendation is removed as unreachable.
- Out of scope, and unchanged: `ISSUE_LIMIT`, pagination, and how many issues the board retrieves.
  The one fetch-layer edit is subtractive — `subIssues` leaves the `--json` field list because
  nothing reads it once epics stop rendering sub-issue rows. `subIssuesSummary` stays; `is_epic`
  reads it.
