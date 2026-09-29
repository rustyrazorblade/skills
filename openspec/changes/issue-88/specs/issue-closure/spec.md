## ADDED Requirements

### Requirement: `record` links the issues, then comments on both
`close-on-merge.sh record <N> <M>` SHALL check that both are numbers, that M differs from N, and that M is open.  It SHALL first set the native "M blocked by N" link; an existing link counts as present.  If GitHub refuses the link, a loop included, it SHALL post nothing, print GitHub's error, and exit non-zero.  It SHALL then post on N a comment whose first line is `🔗 Closes on merge` and whose next line is `- <M>: <title>`, and post on M the comment "Closes when the PR for <N>: <title> merges."  It SHALL skip either comment when it is already there.

#### Scenario: A first record
- **WHEN** `record 971 928` runs and 928 is open
- **THEN** 928 is linked as blocked by 971, 971 gets a `🔗 Closes on merge` comment naming `928: <title>`, and 928 gets the comment "Closes when the PR for 971: <title> merges."

#### Scenario: A repeated record
- **WHEN** `record 971 928` runs a second time
- **THEN** no second link and no second comment is created on either issue, and it exits 0

#### Scenario: M is closed or missing
- **WHEN** `record 971 928` runs and 928 is closed or does not exist
- **THEN** it posts nothing, sets no link, and exits non-zero

#### Scenario: M equals N
- **WHEN** `record 971 971` runs
- **THEN** it prints usage and exits 2

#### Scenario: GitHub refuses the link
- **WHEN** GitHub refuses the "928 blocked by 971" link, for example because 971 is already blocked by 928
- **THEN** it posts no comment on either issue, prints GitHub's error, and exits non-zero

#### Scenario: GitHub accepts a loop
- **WHEN** implementation finds that GitHub accepts a `blocked_by` loop, and 971's `blocked_by` chain reaches 928
- **THEN** `record 971 928` refuses before it sets the link, posts nothing, and exits non-zero

### Requirement: `withdraw` undoes a record
`close-on-merge.sh withdraw <N> <M>` SHALL post on N a comment whose first line is `🔗 Closes on merge: withdrawn <M>`, remove the native "M blocked by N" link, and post on M "No longer closes with <N>: <title>."

#### Scenario: The owner changes their mind
- **WHEN** `withdraw 971 928` runs after `record 971 928`
- **THEN** 971 gets the withdrawn comment, the link is gone, 928 gets the "No longer closes" comment, and `closes 971` no longer prints `Closes #928`

### Requirement: The record is the set of close-on-merge comments on issue N
The active records SHALL be computed by replaying, in order, every comment on N whose first line starts with `🔗 Closes on merge` and whose author is the authenticated `gh` user: a record comment adds M, a withdrawal comment removes it.  The record SHALL NOT live in N's body.

#### Scenario: A record then a withdrawal then a record
- **WHEN** N has, in order, a record for 928, a withdrawal of 928, and a record for 930
- **THEN** the active records are 930 only

#### Scenario: A stranger's comment
- **WHEN** another GitHub user posts a `🔗 Closes on merge` comment on N
- **THEN** that comment does not add a record

### Requirement: `closes` prints the closing lines
`close-on-merge.sh closes <N>` SHALL print `Closes #<N>`, then one `Closes #<M>` line per active record, in record order, and exit 0.  When it cannot read N's comments, it SHALL exit non-zero and print nothing to stdout.

#### Scenario: Two records
- **WHEN** N 971 has active records for 928 and 930
- **THEN** `closes 971` prints `Closes #971`, `Closes #928`, and `Closes #930`, one per line

#### Scenario: No records
- **WHEN** N has no active records
- **THEN** `closes` prints only `Closes #<N>`

#### Scenario: The comments cannot be read
- **WHEN** `gh` fails to list N's comments
- **THEN** `closes` exits non-zero and prints nothing to stdout

### Requirement: Every PR-body write carries the closing lines
Every write of a PR body in `implement` SHALL start with the output of `close-on-merge.sh closes <N>`.  This covers the draft PR in step 2b, the docs path in step 4c, the failure path's residual-findings write, the rewrite at ready in step 5, and the tech-debt draft PR in `implement.workflow.js`.  When `closes` fails, the stage SHALL stop and tell the owner, and SHALL NOT write the body.

#### Scenario: The owner picked close
- **WHEN** the owner picked "close 928 when this PR merges" for issue 971, and `implement` opens the draft PR
- **THEN** the PR body contains `Closes #928` alongside `Closes #971`

#### Scenario: The owner picked fold-in
- **WHEN** the owner picked "fold 928's scope into this issue"
- **THEN** the PR body contains `Closes #928` alongside `Closes #971`

#### Scenario: A later session opens the PR
- **WHEN** the owner answered in `activate`, and `implement` opens the PR in a different session
- **THEN** the PR body still contains `Closes #928`, because the record is on the issue

#### Scenario: implement marks the PR ready
- **WHEN** `implement` rewrites the PR body at step 5
- **THEN** `Closes #928` is still in it

#### Scenario: The docs and tech-debt paths
- **WHEN** `implement` opens or rewrites the PR on the docs path or the tech-debt path
- **THEN** the body starts with the output of `closes <N>`

#### Scenario: `closes` fails
- **WHEN** `close-on-merge.sh closes <N>` exits non-zero during a PR-body write
- **THEN** `implement` does not write the body and tells the owner

### Requirement: `implement.workflow.js` requires `alsoCloses`
`implement.workflow.js` SHALL require an `alsoCloses` argument: an array of positive integers, empty allowed, none equal to `issue`.  It SHALL throw when the argument is missing or malformed.  The tech-debt draft PR body it asks for SHALL start with `Closes #<issue>` and one `Closes #<M>` line per entry.  `skills/implement/SKILL.md` SHALL pass it on every path.

#### Scenario: The argument is missing
- **WHEN** the workflow runs without `alsoCloses`
- **THEN** it throws before any phase starts

#### Scenario: An entry is not an integer
- **WHEN** `alsoCloses` is `["928"]` or `[0]`
- **THEN** it throws

#### Scenario: An empty list
- **WHEN** `alsoCloses` is `[]`
- **THEN** the run proceeds, and the tech-debt PR body holds only `Closes #<issue>` as its closing line

### Requirement: Leave open and block add no closing line
When the owner picks "leave it open" or "make it block" for M, the PR body SHALL NOT contain `Closes #M`, and no close-on-merge comment SHALL be posted on M.  The existing blocking path MAY still post its own blocking comment on M.

#### Scenario: The owner picked block
- **WHEN** the owner picked "make 928 block this issue" and `implement` writes the PR body
- **THEN** the body has no `Closes #928`, and 928 has no close-on-merge comment

### Requirement: `close-merged` closes and cleans recorded issues only for a merged PR
`close-on-merge.sh close-merged <N> <PR>` SHALL read the PR's state.  For any state but `MERGED` it SHALL exit non-zero and close nothing.  For each active record M, it SHALL close M with a comment naming N and the PR when M is open, and SHALL NOT reopen M when M is already closed.  For each M, open or closed, it SHALL remove `status:*`, `needs-attention`, `blocked`, and `merge-on-green`, run `blocked-dependency.sh sweep <M>`, and read M's labels back.  It SHALL report `agent:active` on M and SHALL NOT remove it.  A label from the removal list that survives SHALL make it exit non-zero, naming the issue and the label.

#### Scenario: GitHub left M open
- **WHEN** the PR merged and 928 is still open
- **THEN** `close-merged` closes 928 with a comment, removes its lifecycle labels, and sweeps its links

#### Scenario: M is already closed
- **WHEN** the PR merged and 928 is already closed
- **THEN** nothing fails, 928 is not reopened, and its lifecycle labels are still removed

#### Scenario: The PR closed without merging
- **WHEN** the PR was closed without merging
- **THEN** `close-merged` exits non-zero, and 928 stays open

#### Scenario: M carries agent:active
- **WHEN** 928 carries `agent:active`
- **THEN** `close-merged` reports it and leaves the label in place

#### Scenario: A label survives
- **WHEN** `status:ready` is still on 928 after the removal
- **THEN** `close-merged` exits non-zero and names 928 and `status:ready`

### Requirement: `finalize` closes what GitHub left open
`finalize` step 2 SHALL run `close-on-merge.sh close-merged <N> <PR>` after it closes N and before step 3 removes the worktree.  On failure it SHALL retry once.  If the retry fails, it SHALL stop before step 3, keep the worktree, and tell the owner which recorded issue is still open and which labels remain.

#### Scenario: The PR merges and GitHub closes nothing extra
- **WHEN** the PR for 971 merges and GitHub leaves 928 open
- **THEN** `finalize` closes 928, and the owner closes nothing by hand

#### Scenario: close-merged fails twice
- **WHEN** `close-merged` fails, and fails again on the retry
- **THEN** `finalize` stops before removing the worktree and tells the owner which issue is open and which labels remain

### Requirement: The scripts are bash 3.2 and tested with a fake gh
`close-on-merge.sh` SHALL run on bash 3.2, use `gh` only, and write every title through a `mktemp` file under `$TMPDIR` and `--body-file`, removing its temp files on exit.  `scripts/test-close-on-merge.sh` SHALL put a fake `gh` on `PATH`, record every call, and check each requirement above, in the pattern of `scripts/test-blocked-dependency.sh`.  Bad arguments SHALL print usage and exit 2.

#### Scenario: The test runs offline
- **WHEN** `scripts/test-close-on-merge.sh` runs on macOS bash 3.2 with no network
- **THEN** it exercises every subcommand against the fake `gh` and exits 0 only when every check passes

#### Scenario: A title with shell characters
- **WHEN** M's title contains `$(rm -rf ~)` and a backtick
- **THEN** the title reaches the comment text unchanged, and nothing is executed

### Requirement: The Naming section warns about the shared search
`docs/workflow.md`'s Naming section SHALL say, in one sentence, that a PR that also carries `Closes #M` is found by a search for issue M's PR too.  No PR lookup SHALL change.

#### Scenario: A reader checks Naming
- **WHEN** a reader opens the Naming section
- **THEN** it holds the sentence about `Closes #M`, and the `Closes #N in:body` lookups are unchanged
