# Overrides and conflicts for `issue-50`

## Overrides existing behavior

None — this change only adds new requirements.

Its delta specs contain no `## MODIFIED Requirements` and no `## REMOVED Requirements` sections. The baseline (`openspec/specs/`) holds exactly one capability, `explain/`, whose requirements this change does not touch.

**Worth stating plainly, though the spec baseline does not capture it:** this change *is* breaking for consuming repos at the code level. `tests_ran`'s enum changes from `full | unit | degraded | none` to `policy | partial | degraded | none`, and every repo using spec-flow stops at its next `implement` until it owns a `spec-flow/TESTING.md`. Neither behavior was ever written into a committed OpenSpec requirement, so there is nothing here to mark MODIFIED — but the absence of a MODIFIED section should not be read as "nothing existing changes." See `proposal.md`'s **BREAKING** markers and `design.md` D6.

## Conflicts with other in-flight changes

None found.

Two other change directories are open on this branch's base:

- `issue-42` — touches capability `walkthrough`. This change touches `repo-config` and `test-policy`. No shared capability, no shared requirement.
- `openspec-aware-explain-view` — touches capability `explain`. Again disjoint from both of this change's capabilities.

Neither modifies a requirement this change modifies, and neither asserts anything incompatible with it.

**One non-conflicting adjacency to note.** `openspec-aware-explain-view` concerns the explain view that `activate` renders at Seam 1. This change alters what `implement` and the review lenses report (`tests_ran`, `tests_detail`), not what the explain view renders, so the two do not collide. If both land, the explain view will simply show the new field names wherever it surfaces review output — no coordination needed.
