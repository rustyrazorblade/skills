## Purpose

Aid human understanding of what's happening in a change — a worktree, a branch, or an issue —
presented as a walkthrough rather than a raw diff dump: a file tree, a code/diff/doc editor, and
an explanation pane, all in one self-contained HTML view. Deterministic and self-contained: no
model tokens spent on markup in the default mode, no server, opens over `file://`. Ships as the
`explain` skill in the standalone `review-tools` plugin — no dependency on any other plugin, and
generic enough to work on any project, including ones that can't or don't adopt spec-flow.
## Requirements
### Requirement: Deterministic manifest generation
The system SHALL generate a self-contained HTML view from a git diff, a GitHub issue, OpenSpec
docs, extra markdown/code files, or any combination, with zero model-authored markup in the
default mode.

#### Scenario: Diff produces one node per changed file
- **WHEN** `--diff` is passed with a base and head
- **THEN** the manifest contains one `kind: "diff"` node per changed file, each carrying that
  file's own raw unified-diff patch text

#### Scenario: Refuses to render an empty view
- **WHEN** none of `--issue`, `--diff`, `--change`, `--doc`, `--code`, or `--symbol` is passed
- **THEN** the generator exits non-zero instead of producing a manifest with no nodes

#### Scenario: Diff can be scoped to specific paths
- **WHEN** `--diff` is passed with one or more `--path` values
- **THEN** the diff is scoped to only those paths, excluding changes elsewhere in the repository

### Requirement: Generic scope aliases for worktree and branch
The system SHALL provide `--worktree` and `--branch <name>` as convenience aliases that resolve
to `--diff`'s own default base/head behavior, using only generic git-level information — no
issue-number inference, no assumption of any project's branch-naming or file-layout conventions —
so the aliases remain usable on any repository.

#### Scenario: Worktree alias
- **WHEN** `--worktree` is passed
- **THEN** the view is generated as if `--diff` were passed with no `--base`/`--head` override —
  merge-base with the default branch vs. the working tree

#### Scenario: Branch alias
- **WHEN** `--branch <name>` is passed without an explicit `--head`
- **THEN** the view is generated as if `--diff --head <name>` were passed

#### Scenario: Explicit --head takes precedence
- **WHEN** both `--branch <name>` and `--head` are passed
- **THEN** the explicit `--head` value is used, not the branch alias's

### Requirement: GitHub issue mode surfaces related work
The system SHALL, given `--issue N`, include that issue's full body and comment thread, plus,
one level out, every issue it is linked to via a native GitHub dependency or a bare `#N` mention.

#### Scenario: Primary issue includes its discussion
- **WHEN** `--issue N` is passed
- **THEN** the manifest includes a node for issue N containing its body and comment thread

#### Scenario: Related issue via native dependency
- **WHEN** issue N has a native `blocked_by` or `blocking` dependency on issue M
- **THEN** the manifest includes a lighter node for issue M under `related/`

#### Scenario: Related issue via mention
- **WHEN** issue N's body or comments contain a bare `#M` reference
- **THEN** the manifest includes a lighter node for issue M under `related/`, distinct from a
  native-dependency relation

### Requirement: Caller-supplied explanation of what the code does
The system SHALL accept a caller-supplied explanation of what a diff actually does, keyed by file
path, and SHALL apply it to any node whose path matches, taking priority over any other source of
explanation for that node. Explaining what code *does* requires understanding the diff; the
generator itself has none, so this content is always authored elsewhere (typically an LLM that has
already read the diff) and supplied as input, never invented mechanically.

#### Scenario: Supplied explanation is applied
- **WHEN** an explanation map entry's path matches a node's path
- **THEN** that node's explain field is set to the supplied text

#### Scenario: Supplied explanation overrides other sources
- **WHEN** a node has both a supplied explanation and commit-history context available
- **THEN** the supplied explanation is what's shown; the commit-history context is not

#### Scenario: Missing explanation-map file fails loudly
- **WHEN** an explanation map is requested from a file that doesn't exist
- **THEN** the generator exits non-zero rather than silently proceeding without it

### Requirement: Commit-history context as a fallback, not a default
The system SHALL support populating a diff node's explanation pane with commit-history context —
the full commit message(s) of whichever commit(s) last touched the changed lines, as of the diff
base — only when explicitly requested, and SHALL NOT enable it by default. Commit-history context
can only ever quote what someone wrote about a previous change to those lines; it is not an
explanation of the current diff, and must never be presented as the primary or default source of
explanation.

#### Scenario: Off by default
- **WHEN** a diff is generated without explicitly requesting commit-history context
- **THEN** diff nodes carry no explain field derived from commit history

#### Scenario: Modified lines show the full commit message, once requested
- **WHEN** commit-history context is explicitly requested, and a hunk changes lines that existed
  at the diff base
- **THEN** the node's explain field contains the full commit message (not just the one-line
  summary) of the commit(s) that last touched those lines, with author/commit-id shown as
  secondary metadata, not the primary content

#### Scenario: New file gets an explicit reason, not silence
- **WHEN** commit-history context is explicitly requested, and a diff node is for a brand-new file
- **THEN** its explain field states there is no prior history to show, rather than being absent

#### Scenario: Pure addition gets an explicit reason
- **WHEN** commit-history context is explicitly requested, and a hunk adds lines without touching
  any existing old-side lines
- **THEN** the node's explain field states there is nothing to blame, rather than being absent

### Requirement: PR review comment overlay
The system SHALL, given `--pr N` alongside `--diff`, overlay that pull request's file/line-anchored
GitHub review comments onto the diff nodes they were left on.

#### Scenario: Comment anchored inside the diff attaches to its row
- **WHEN** a review comment's file and line fall within the current diff's range
- **THEN** the comment is attached to that diff node, keyed by line and side, for the viewer to
  render at the corresponding row

#### Scenario: Comment outside the diff is never dropped
- **WHEN** a review comment's file or line falls outside the current diff's range
- **THEN** the comment is surfaced in its own node instead of being silently omitted

#### Scenario: Ignored without a diff
- **WHEN** `--pr N` is passed without `--diff`
- **THEN** the generator warns and proceeds without attempting to overlay comments

### Requirement: Blast-radius symbol search
The system SHALL, given `--symbol NAME`, produce a deterministic, language-agnostic list of every
reference to that name across tracked files in the working tree.

#### Scenario: Symbol found
- **WHEN** `--symbol NAME` matches one or more locations
- **THEN** the manifest includes a node listing each match's file and line

#### Scenario: Symbol not found still produces a node
- **WHEN** `--symbol NAME` matches nothing
- **THEN** the manifest includes a node explicitly stating no references were found, rather than
  omitting the symbol entirely

### Requirement: Delta-spec sections are visually distinct
The system SHALL render OpenSpec's `ADDED`/`MODIFIED`/`REMOVED`/`RENAMED` Requirements sections
with distinct color coding in the viewer, and classify each markdown node's file-tree badge by
the highest-severity section it contains.

#### Scenario: Section coloring
- **WHEN** a rendered markdown document contains a `## MODIFIED Requirements` heading
- **THEN** that section's content is wrapped in a distinctly colored, labeled block in the viewer

#### Scenario: Badge priority on mixed files
- **WHEN** a single document contains more than one of ADDED/MODIFIED/REMOVED/RENAMED sections
- **THEN** its file-tree badge reflects the highest-severity section present, in the order
  REMOVED, MODIFIED, RENAMED, ADDED

### Requirement: Two-panel file tree
The viewer SHALL separate code-oriented nodes (diff and code kinds) from document-oriented nodes
(markdown kind) into two independently-scrolling tree panels, hiding either panel when it has no
nodes to show.

#### Scenario: Both kinds present
- **WHEN** the manifest contains both diff/code nodes and markdown nodes
- **THEN** the viewer shows a Code panel and a Documents panel, each listing only its own nodes

#### Scenario: One kind absent
- **WHEN** the manifest contains no diff/code nodes
- **THEN** the Code panel is hidden entirely and the Documents panel takes the full sidebar height

### Requirement: Self-contained output
The system SHALL produce a single HTML file with no external network dependencies, opening
correctly when loaded directly from the filesystem.

#### Scenario: No external references
- **WHEN** a view is generated
- **THEN** the output file contains no `http://`, `https://`, or `fetch(` substrings, and the
  `<!--MANIFEST-->` injection marker is fully replaced

### Requirement: Display constraint for non-interactive callers
The system SHALL never assume a display is available; it SHALL always print the output file's
absolute path and an `open <path>` command, and SHALL only attempt to open a browser when
explicitly requested.

#### Scenario: Path always printed
- **WHEN** generation succeeds, regardless of `--open`
- **THEN** the generator prints the absolute output path followed by an `open <path>` line

#### Scenario: Browser only opens on request
- **WHEN** `--open` is not passed
- **THEN** no browser-opening attempt is made

### Requirement: Curated authoring mode
The system SHALL support a hand-authored mode, bootstrapped separately from the deterministic
generator, for narratives worth curating rather than generating.

#### Scenario: Bootstrap produces an editable skeleton
- **WHEN** the curated bootstrap script is run against a target directory
- **THEN** it copies the viewer shell and writes a skeleton manifest file loaded via an external
  script tag, without modifying the viewer shell itself

### Requirement: Stable section anchors
The viewer SHALL assign every rendered heading a stable, unique, slugified id, so a specific
requirement or scenario can be referenced precisely without any comment/annotation channel back
to the generator.

#### Scenario: Unique ids on repeated headings
- **WHEN** a rendered document contains two headings with identical text
- **THEN** the second heading's id is deduplicated with a numeric suffix rather than colliding
  with the first

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

