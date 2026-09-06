# Overrides and conflicts — issue-71

## Overrides existing behavior

None — this change only adds new requirements.

`openspec/specs/` holds only `explain/`. The `delivery-board` capability has no committed baseline, so this change's delta carries no `## MODIFIED Requirements` and no `## REMOVED Requirements` section, and there is no baseline requirement text to show a before-and-after against.

## Conflicts with other in-flight changes

Five other changes are open. Four touch a different capability and cannot conflict:

- `issue-42` — `walkthrough`. No overlap.
- `issue-50` — `repo-config`, `test-policy`. No overlap.
- `issue-53` — `repo-config`. No overlap.
- `openspec-aware-explain-view` — `explain`. No overlap.

`issue-46` also touches `delivery-board`, and one of its requirements genuinely conflicts.

### Conflict: `render_board()` is decomposed into one function per section

`issue-46`'s requirement reads:

> The system SHALL structure `render_board()` as one function per rendered section, each returning its own lines, so that a section's conditional presence is decided in one place rather than inline within a single large function.

This change collapses `render_blocked_on_you`, `render_unrecognized` and `render_in_flight` into a single parameterized `render_section(header, rows)`, called once per section. Taken literally, the codebase then no longer has one function per section, so the requirement's letter is contradicted.

The requirement's stated purpose survives, and arguably improves: "a section's conditional presence is decided in one place" becomes true of exactly one place rather than four copies of the same three lines. Its scenario also still passes — `render_section(header, [])` returns no lines, and the assembled board contains no trace of that section.

So this is a conflict of wording against an in-flight requirement, not of behavior. It exists only because the owner folded in a refactor the architect had recommended as a separate issue. It needs a decision, and the three ways out are:

1. **Drop the render-helper collapse from this change.** The conflict disappears entirely. The other three folded-in items are unaffected — none of them touches an `issue-46` requirement.
2. **Keep the collapse and edit `issue-46`'s own delta** to describe the shared helper. `issue-46` is un-archived, so its delta is still editable; but editing another in-flight change's artifact from inside this one is a new coupling between two changes that must then archive together.
3. **Keep the collapse and accept the wording tension**, on the ground that the requirement's purpose is preserved and its scenario still passes. The archived spec would then describe a decomposition the code implements by parameterization rather than by repetition.

### Not a conflict: unbounded categories

`issue-46`'s "Unbounded categories report as counts, never as rows" stays true exactly as written. It is about the ungroomed backlog and the epic list, both of which still report as summary counts. READY's withheld count is a different mechanism in a different place — one line inside the block, not a summary count — so this change adds a requirement beside it rather than modifying it.

Its scenario "Backlog size does not change board length" is likewise untouched. This change adds the matching invariance for the ready queue as a separate scenario under its own requirement.

### Archive ordering

Both deltas are pure ADDs of distinct requirements, so either archive order works. `issue-42`, `issue-46`, `issue-50` and `issue-53` are all currently queued for one bulk `/spec-flow:archive` pass, which is the case that will actually happen.
