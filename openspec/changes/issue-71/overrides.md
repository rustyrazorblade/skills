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

So this was a conflict of wording against an in-flight requirement, not of behavior. It existed only because the owner folded in a refactor the architect had recommended as a separate issue.

**Resolved: the owner chose to reword `issue-46`'s requirement.** This change edits `openspec/changes/issue-46/specs/delivery-board/spec.md`, renaming the requirement to "`render_board()` delegates every section to a render function" and restating it so that sections whose rendering differs only by header MAY share one parameterized helper. The presence decision must still live in a render function; that is what the requirement was always protecting. A second scenario was added for the shared-helper case. `openspec validate issue-46 --type change --strict` passes after the edit.

The two rejected options, for the record:

- **Drop the render-helper collapse from this change.** Rejected. The conflict would disappear, but so would work the owner explicitly asked for.
- **Keep the collapse and leave `issue-46` as written.** Rejected. The archived spec would describe a decomposition the code implements by parameterization, so the spec would simply be wrong on that sentence.

**Consequence of the chosen option: the two changes are now coupled.** `issue-71` carries an edit to `issue-46`'s delta, so `issue-46` must not be archived from a tree that lacks this branch. Both are already queued for the same bulk `/spec-flow:archive` pass, which satisfies this; archiving `issue-46` alone, before this branch merges, would archive the old wording and re-open the conflict.

### Not a conflict: unbounded categories

`issue-46`'s "Unbounded categories report as counts, never as rows" stays true exactly as written. It is about the ungroomed backlog and the epic list, both of which still report as summary counts. READY's withheld count is a different mechanism in a different place — one line inside the block, not a summary count — so this change adds a requirement beside it rather than modifying it.

Its scenario "Backlog size does not change board length" is likewise untouched. This change adds the matching invariance for the ready queue as a separate scenario under its own requirement.

### Archive ordering

Both deltas are pure ADDs of distinct requirements, so either archive order works. `issue-42`, `issue-46`, `issue-50` and `issue-53` are all currently queued for one bulk `/spec-flow:archive` pass, which is the case that will actually happen.
