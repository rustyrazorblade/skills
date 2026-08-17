## Purpose

Render an IDE-style, single-page HTML view — a file tree, a code/diff/doc editor, and an
explanation pane — of a git diff, a GitHub issue plus everything linked to it, project docs, or
any combination, so a reviewer sees everything relevant to a decision in one place instead of
raw diff output or hopping between GitHub tabs. Deterministic and self-contained: no model tokens
spent on markup in the default mode, no server, opens over `file://`. Ships as the `explain` skill
in the standalone `review-tools` plugin — no dependency on any other plugin.

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
