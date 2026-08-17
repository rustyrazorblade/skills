## ADDED Requirements

### Requirement: OpenSpec files render as content, not a diff, in diff mode
The system SHALL render a changed, non-deleted file as a markdown content node instead of a diff
node, in `--diff` mode (including via the `--worktree`/`--branch` aliases), whenever that file's
path matches OpenSpec's own directory convention: `openspec/specs/**/*.md`,
`openspec/changes/*/specs/**/*.md`, `openspec/changes/*/proposal.md`,
`openspec/changes/*/design.md`, or `openspec/changes/*/tasks.md`. A **deleted** OpenSpec file
SHALL render as a diff node — there is no current content to show as markdown — and if the
matched file's content cannot be read at all (unexpected, since the diff itself reports it as
changed), the system SHALL fall back to a diff node rather than dropping the file from the
manifest. The system SHALL leave every other file entirely unaffected — rendered as a diff node
with its explanation pane exactly as before, including a brand-new non-OpenSpec file.

#### Scenario: OpenSpec path renders as content
- **WHEN** a changed, non-deleted file's path matches `openspec/specs/**/*.md` or one of the
  `openspec/changes/*/` document paths
- **THEN** the manifest contains a markdown node for that file using its current (head-side)
  content, not a diff node

#### Scenario: Deleted OpenSpec file stays a diff node
- **WHEN** a file matching an OpenSpec path pattern is deleted in the diff
- **THEN** the manifest contains a diff node for that file, exactly as it would without this
  feature

#### Scenario: Non-OpenSpec file is unaffected, even when brand-new
- **WHEN** a changed file's path does not match any OpenSpec path pattern
- **THEN** the manifest contains a diff node for that file, exactly as it would without this
  feature — including when the file is newly added

### Requirement: Delta-spec summary and category navigation
The system SHALL, for a rendered OpenSpec file whose content contains one or more of OpenSpec's
delta headers (`## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements`,
`## RENAMED Requirements`), include a summary line with the count of requirements in each present
category, and a jump link to each category's section. A rendered OpenSpec file with no delta
headers SHALL render as plain markdown with no summary or category navigation.

#### Scenario: Summary reflects actual counts
- **WHEN** a delta spec contains 2 requirements under `## ADDED Requirements` and 1 under
  `## MODIFIED Requirements`, and no `## REMOVED Requirements` or `## RENAMED Requirements` section
- **THEN** the rendered summary shows counts for ADDED and MODIFIED only, omitting REMOVED and
  RENAMED entirely

#### Scenario: Non-delta OpenSpec file has no summary
- **WHEN** a rendered OpenSpec file (e.g. `proposal.md`, or a baseline spec with no delta headers)
  contains none of the four delta headers
- **THEN** no summary line or category jump links are rendered for it

### Requirement: MODIFIED requirements show a comparison against the capability baseline
The system SHALL, for each requirement listed under a `## MODIFIED Requirements` section in a
delta spec located under `openspec/changes/<name>/specs/<capability>/`, attempt to locate the
same-titled requirement (matched on the exact `### Requirement: <title>` text) in that
capability's baseline spec at `openspec/specs/<capability>/spec.md`. When found, the system SHALL
include a "Currently:" block containing the baseline requirement's full text and a "This change:"
block containing the delta requirement's full text, both as prose, not a line-level diff. When the
baseline file does not exist, or no requirement in it matches the title, the system SHALL render
the `MODIFIED Requirements` section without a comparison for that requirement, and SHALL NOT fail
generation or render a broken or empty comparison block.

#### Scenario: Matching baseline requirement found
- **WHEN** a `MODIFIED Requirements` section's requirement title matches a requirement in the
  capability's baseline spec
- **THEN** the rendered section includes both the baseline text ("Currently:") and the new text
  ("This change:") for that requirement

#### Scenario: No matching baseline requirement
- **WHEN** a `MODIFIED Requirements` section's requirement title has no match in the capability's
  baseline spec, or the baseline spec file does not exist
- **THEN** the requirement still renders in full, without a comparison block, and generation does
  not fail

### Requirement: REMOVED and ADDED requirements render without a baseline lookup
The system SHALL render `## REMOVED Requirements` and `## ADDED Requirements` sections using their
existing color-coded rendering, without attempting a baseline comparison.

#### Scenario: ADDED requirement has no comparison
- **WHEN** a requirement is listed under `## ADDED Requirements`
- **THEN** it renders with its existing badge/color treatment and no "Currently:"/"This change:"
  comparison

#### Scenario: REMOVED requirement has no comparison
- **WHEN** a requirement is listed under `## REMOVED Requirements`
- **THEN** it renders with its existing badge/color treatment and no "Currently:"/"This change:"
  comparison

### Requirement: Delta-spec enrichment applies consistently regardless of entry point
The system SHALL apply the summary/category-navigation and MODIFIED-requirement baseline
comparison identically whether the delta spec was reached via `--diff`-mode path detection or via
`--change <dir>` mode, so the same file renders the same way in either mode.

#### Scenario: --change mode gets the same enrichment
- **WHEN** a delta spec is rendered via `--change <dir>` and contains a `## MODIFIED Requirements`
  section with a requirement matching the capability's baseline
- **THEN** the rendered output includes the same summary, category navigation, and
  "Currently:"/"This change:" comparison as if the same file had been reached via `--diff`-mode
  path detection
