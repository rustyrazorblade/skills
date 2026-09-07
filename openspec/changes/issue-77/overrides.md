# Overrides and conflicts

## Overrides existing behavior

None — this change only adds new requirements. Its delta spec contains a single `## ADDED
Requirements` section and no `## MODIFIED` or `## REMOVED` section.

`idea-refinement` is a new capability. Grooming has no committed spec today: `openspec/specs/` holds
`delivery-board`, `explain`, `repo-config`, `test-policy` and `walkthrough`, and the only mention of
grooming anywhere in them is in `delivery-board/spec.md`, which specifies how the board *renders*
the ungroomed backlog and what it recommends — not how an idea is refined. Nothing there is changed
or contradicted by this change.

Worth stating plainly, because it is behaviour that changes without a spec to modify: `groom`'s step
1 gate ("Don't draft the issue until shape-defining ambiguity is actually resolved") is removed, and
`groom` step 7 stops interpolating the issue body into a shell string. Both are real behaviour
changes to an unspecified surface, not spec overrides.

## Conflicts with other in-flight changes

None found. `openspec/changes/` contains no other open change directory.
