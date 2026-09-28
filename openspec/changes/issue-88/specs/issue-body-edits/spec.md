## ADDED Requirements

### Requirement: The issue body changes only for requirement changes
A stage SHALL change an existing issue body only for a requirement change: the `activate` step 1 scope rewrite, and fold-in.  Any other information SHALL be posted as a comment.  `docs/workflow.md` SHALL state: "No stage edits an existing issue body by hand; it uses issue-body.sh.  Creating a new issue is not an edit."

#### Scenario: A reader checks the rule
- **WHEN** a reader opens `docs/workflow.md`
- **THEN** it holds the rule word for word

#### Scenario: A reader searches for hand edits
- **WHEN** a reader searches the plugin for `gh issue edit` with `--body` or `--body-file` on an existing issue
- **THEN** only `scripts/issue-body.sh` writes an issue body

#### Scenario: The owner changes the scope in activate step 1
- **WHEN** an answer in `activate` step 1 changes the scope
- **THEN** the agent writes the new scope with `issue-body.sh replace <N> "Scope" <file>`, not with `gh issue edit --body`

#### Scenario: groom creates an issue
- **WHEN** `groom` creates a new issue with `gh issue create --body-file`
- **THEN** that is allowed, because creating an issue is not an edit

### Requirement: The tech-debt adjacent-behavior list is a comment
`activate` step 5's tech-debt branch SHALL post the adjacent-behavior list as an issue comment whose first line is `🧭 Adjacent specified behavior`.  It SHALL NOT append it to the body.  Every reader of the list (`skills/implement/SKILL.md`, `implement.workflow.js`, `activate` step 7, and `docs/workflow.md`) SHALL use the newest such comment, and SHALL fall back to a `## Adjacent specified behavior (must be preserved)` body section when no comment exists.

#### Scenario: A tech-debt issue is activated
- **WHEN** `activate` step 5 runs for a `type:tech-debt` issue
- **THEN** the list is posted as a `🧭 Adjacent specified behavior` comment, and the body is unchanged

#### Scenario: The review panel reads the list
- **WHEN** `implement` runs on a tech-debt issue with that comment
- **THEN** the implementer and the review panel are told to read the newest `🧭 Adjacent specified behavior` comment

#### Scenario: An issue activated before this change
- **WHEN** a tech-debt issue has the old body section and no comment
- **THEN** the readers use the body section

### Requirement: `issue-body.sh` edits one named section
`scripts/issue-body.sh` SHALL provide `get <N> <heading>`, `replace <N> <heading> <file>`, and `append <N> <heading> <file>`.  Each SHALL act on the one section headed `## <heading>`.  `get` SHALL print the section's content and exit 1 when the section is absent.  `replace` SHALL replace the section's content.  `append` SHALL add the file's lines to the end of the section.  No other section SHALL change.

#### Scenario: Replacing the scope
- **WHEN** `replace 88 "Scope" <file>` runs
- **THEN** only the `## Scope` section's content changes

#### Scenario: Appending criteria
- **WHEN** `append 88 "Acceptance criteria" <file>` runs
- **THEN** the file's lines follow the section's existing lines, and nothing else changes

### Requirement: A missing target section is an error that changes nothing
When the body has no `## <heading>` section outside a fence, `replace` and `append` SHALL exit non-zero with an error that names the missing section and the issue, and SHALL NOT write the body.  They SHALL NOT add the section.  The calling stage SHALL stop and tell the owner which section is missing.

#### Scenario: append on an absent section
- **WHEN** `append 88 "Assumptions" <file>` runs and the body has no `## Assumptions` section
- **THEN** the script exits non-zero, the error names `## Assumptions` and issue 88, and no `gh issue edit` call is made

#### Scenario: replace on an absent section
- **WHEN** `replace 88 "Scope" <file>` runs and the body has no `## Scope` section
- **THEN** the script exits non-zero, the error names `## Scope` and issue 88, and the body is unchanged

#### Scenario: The only match is inside a code fence
- **WHEN** `replace 88 "Scope" <file>` runs and the body's only `## Scope` line is inside a fenced block
- **THEN** the section counts as absent, the script exits non-zero naming `## Scope`, and the body is unchanged

### Requirement: Section parsing is fence-aware and refuses a duplicate heading
A line that starts with `## ` SHALL count as a heading only outside a ```` ``` ```` or `~~~` fence.  A section SHALL run from its heading to the next heading outside a fence, or to the end of the body.  A duplicate target heading SHALL be an error that names the issue and the heading and changes nothing.  A content file that holds a `## ` heading outside a fence SHALL be an error that changes nothing.

#### Scenario: A heading inside a code fence
- **WHEN** the body holds a fenced block with a `## Scope` line in it, and a real `## Scope` heading elsewhere
- **THEN** `replace` edits only the real section, and the fenced block is unchanged

#### Scenario: A duplicate heading
- **WHEN** the body has two `## Scope` headings outside fences
- **THEN** `replace 88 "Scope" <file>` exits non-zero, names issue 88 and the heading, and does not write

#### Scenario: Content with its own heading
- **WHEN** the content file holds a `## Notes` line outside a fence
- **THEN** the script exits non-zero and does not write

### Requirement: A pre-check re-reads the body when it moved
The script SHALL read the body and the GraphQL `lastEditedAt` together.  Just before it writes, it SHALL read `lastEditedAt` again.  When it moved, it SHALL re-read the body and re-apply its one-section change to the new body.

#### Scenario: The owner edits while the agent drafts
- **WHEN** `lastEditedAt` moved between the read and the pre-write check
- **THEN** the script re-reads the body and applies its change to the new body, so the owner's edit is kept

### Requirement: A post-check stops on a lost edit
After the write, the script SHALL read `userContentEdits` and the body.  When any edit other than its own landed between its read and its write, it SHALL print each lost version's timestamp and editor and exit non-zero.  It SHALL NOT retry in that case.  The calling stage SHALL stop and tell the owner that the old text is recoverable from GitHub's edit history.

#### Scenario: An edit lands inside the window
- **WHEN** another edit lands after the pre-write check and before the write
- **THEN** the script prints that edit's timestamp and editor, exits non-zero, and does not write again

#### Scenario: No other edit
- **WHEN** only the script's own edit landed
- **THEN** the post-check passes

### Requirement: The script confirms its section landed
When no other edit landed, the script SHALL confirm that its section holds the new content and that every other section is still present.  When the confirm fails, it SHALL retry the write once, and then exit non-zero.

#### Scenario: The section did not land
- **WHEN** the read-back body does not hold the new section content
- **THEN** the script writes once more, and exits non-zero if the read-back still fails

### Requirement: `issue-body.sh` is safe with hostile text and tested with a fake gh
The script SHALL run on bash 3.2 and use `gh` only.  It SHALL write every body through a `mktemp` file under `$TMPDIR` and `gh issue edit --body-file`, never through argv, and remove its temp files on exit.  `scripts/test-issue-body.sh` SHALL put a fake `gh` on `PATH`, record every call, and check each requirement above, including a fenced heading, a duplicate heading, a moved `lastEditedAt`, and a lost edit.  Bad arguments SHALL print usage and exit 2.

#### Scenario: A body with shell characters
- **WHEN** the body or the content file holds `$(...)` and backticks
- **THEN** they reach GitHub unchanged, and nothing is executed

#### Scenario: The test runs offline
- **WHEN** `scripts/test-issue-body.sh` runs on macOS bash 3.2 with no network
- **THEN** it exits 0 only when every check passes
