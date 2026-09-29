# Overrides and conflicts — issue 82

## Overrides existing behavior

None — this change only adds a new capability, `owner-presentation`. It modifies no existing baseline
requirement in `openspec/specs/`.

Note: the change edits instruction prose in several plugin files, including one sentence added in
release 0.46.0. That is an edit to instruction text, not an override of a committed spec requirement.
No baseline spec covers the presentation contract today.

## Conflicts with other in-flight changes

`issue-77` is the only other open change. It modifies the `idea-refinement` capability (groom's
refinement loop). This change adds the `owner-presentation` capability and does not touch
`idea-refinement`. No actual conflict.

`issue-77` and this change both edit `skills/groom/SKILL.md`, but different parts: `issue-77` reworks
step 4's refinement loop; this change rewords step 4's "the only exception" sentence. If `issue-77`
merges first, confirm that sentence still exists before rewording it; the edit is small and
independent either way.
