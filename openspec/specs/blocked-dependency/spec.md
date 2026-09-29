# blocked-dependency Specification

## Purpose
TBD - created by archiving change issue-86. Update Purpose after archive.
## Requirements
### Requirement: `add` records an issue-to-issue dependency as a native link only

`blocked-dependency.sh add <N> <M> <reason>` SHALL create a native `blocked_by` link from issue N to
issue M and post the comment `⛔ Blocked on #M — <reason>` on N. It SHALL NOT add the `blocked`
label. A link from N to M that already exists SHALL count as present.

#### Scenario: A new dependency
- **WHEN** `add <N> <M> <reason>` runs and N has no link to M
- **THEN** N gets a native `blocked_by` link to M and a `⛔ Blocked on #M — <reason>` comment
- **AND** N does not get the `blocked` label, and the script exits 0

#### Scenario: The link already exists
- **WHEN** `add <N> <M> <reason>` runs and N already has a native link to M
- **THEN** the script counts the link as present, creates no second link, posts the comment, and
  exits 0

#### Scenario: The link cannot be created
- **WHEN** `add` cannot create the native link
- **THEN** it exits non-zero and says what was applied and what was not

#### Scenario: The comment fails after the link lands
- **WHEN** the native link exists but the comment cannot be posted
- **THEN** `add` exits non-zero and says the link is in place and the comment was not posted

### Requirement: `add-external` records a blocker that is not an issue

`blocked-dependency.sh add-external <N> <reason>` SHALL add the `blocked` label to issue N and post
the comment `Blocked by: <reason>` on N.

#### Scenario: An external blocker is recorded
- **WHEN** `add-external <N> <reason>` runs
- **THEN** N gets the `blocked` label and a `Blocked by: <reason>` comment
- **AND** the board shows `⛔ Blocked by: <reason>` for N

#### Scenario: A second external reason
- **WHEN** `add-external` runs again on an issue that already has the label, with a new reason
- **THEN** the board shows the newer reason, because the last `Blocked by:` comment wins

#### Scenario: A partial failure
- **WHEN** the label is added but the comment cannot be posted, or the label cannot be added
- **THEN** `add-external` exits non-zero and names what was applied and what was not

### Requirement: `clear` removes a wrong issue-to-issue link in this repo

`blocked-dependency.sh clear <N> <M>` SHALL remove the native `blocked_by` link from issue N to issue
M in this repo and post a short comment on N that the dependency on #M was removed. The comment
SHALL NOT say that M landed. `clear` SHALL NOT change the `blocked` label. A link to an issue in
another repo is out of `clear`'s reach and is removed by hand.

#### Scenario: An existing link is removed
- **WHEN** `clear <N> <M>` runs and N has a native link to issue M in this repo
- **THEN** the native link from N to M is gone
- **AND** a short comment on N says the dependency on #M was removed
- **AND** the comment does not say that M landed
- **AND** the `blocked` label on N does not change

#### Scenario: No such link
- **WHEN** `clear <N> <M>` runs and N has no link to issue M in this repo
- **THEN** it exits 0 and posts no comment

#### Scenario: A same-numbered issue in another repo
- **WHEN** N's only native link is to issue number M in another repo
- **THEN** `clear <N> <M>` leaves that link in place, exits 0, and posts no comment

#### Scenario: The link cannot be deleted
- **WHEN** `clear <N> <M>` finds the link but the delete fails
- **THEN** it exits non-zero, says the link is still there, and posts no comment

### Requirement: `clear-external` removes the label for a blocker that is not an issue

`blocked-dependency.sh clear-external <N>` SHALL remove the `blocked` label from issue N, matched
exactly by name, and post a `✅ Unblocked` comment.

#### Scenario: A labeled issue
- **WHEN** `clear-external <N>` runs on an issue with the `blocked` label
- **THEN** the label is removed and a `✅ Unblocked` comment is posted

#### Scenario: No label
- **WHEN** `clear-external <N>` runs on an issue with no `blocked` label, including one whose labels
  only contain `blocked` as a substring
- **THEN** it exits 0 and posts no comment

#### Scenario: The label cannot be removed
- **WHEN** `clear-external <N>` cannot remove the label
- **THEN** it exits non-zero and says the board will keep showing the issue as blocked

### Requirement: `sweep` is unchanged

`blocked-dependency.sh sweep <N>` SHALL behave exactly as it did before this change.

#### Scenario: Sweep on a closed issue
- **WHEN** `sweep <N>` runs
- **THEN** it removes every native `blocked_by` link on N and the `blocked` label, posts no comment,
  and makes the same `gh` calls as before this change

### Requirement: Bad arguments print usage and exit 2

Every subcommand SHALL, when given missing or non-numeric issue numbers, print a usage message that
lists all five subcommands (`add`, `add-external`, `clear`, `clear-external`, `sweep`) and exit 2.
An unknown subcommand SHALL do the same.

#### Scenario: A missing issue number
- **WHEN** any subcommand runs without its required issue numbers
- **THEN** it prints usage listing all five subcommands and exits 2

#### Scenario: A non-numeric issue number
- **WHEN** any subcommand gets a non-numeric issue number
- **THEN** it prints usage listing all five subcommands and exits 2

### Requirement: A script test covers every subcommand criterion

`scripts/test-blocked-dependency.sh` SHALL run on bash 3.2 with a fake `gh` on PATH that records
each call, and SHALL have a passing check for each criterion of `add`, `add-external`, `clear`,
`clear-external`, `sweep`, and the usage path.

#### Scenario: The test runs on macOS bash
- **WHEN** `test-blocked-dependency.sh` runs under bash 3.2
- **THEN** every check passes and it exits 0

#### Scenario: A regression is caught
- **WHEN** `add` is changed to add the `blocked` label
- **THEN** `test-blocked-dependency.sh` fails

### Requirement: Docs, skills and agents describe the label as only for blockers that are not issues

The `blocked` label description in `bin/bootstrap-labels.sh` SHALL be
`Blocked by something that is not an issue`. `skills/setup/SKILL.md`, `skills/activate/SKILL.md`,
`skills/finalize/SKILL.md`, `agents/issue-manager.md`, `agents/project-manager.md`,
`docs/workflow.md` and `README.md` SHALL describe the label as only for blockers that are not
issues, and SHALL describe an issue-to-issue dependency as a native link only. None of them SHALL
tell an agent to set `blocked` for a dependency on another issue, or require an agent to call
`clear` when a blocker lands.

#### Scenario: The label description
- **WHEN** `bin/bootstrap-labels.sh` creates or updates the `blocked` label
- **THEN** its description is `Blocked by something that is not an issue`

#### Scenario: No listed file sets the label for an issue dependency
- **WHEN** a reader searches the listed files for how to record a dependency on another issue
- **THEN** each describes a native link via `add`, and none tells an agent to set `blocked`

#### Scenario: No listed file requires `clear` when a blocker lands
- **WHEN** a reader searches the listed files for what to do when a blocking issue closes
- **THEN** none requires an agent to call `clear`

### Requirement: The docs state the rule for a wait on a person

`docs/workflow.md` and `agents/issue-manager.md` SHALL state that `add-external` is for a third
party that no owner action can unblock, and `needs-attention` is for anything the owner must act
on. Neither file SHALL define `blocked` as "a hard dependency on another issue."

#### Scenario: A wait on a third party
- **WHEN** a reader looks up how to record a wait on a person in `docs/workflow.md` or
  `agents/issue-manager.md`
- **THEN** the file says `add-external` is for a third party no owner action can unblock, and
  `needs-attention` is for anything the owner must act on

#### Scenario: The old definition is gone
- **WHEN** a reader searches `docs/workflow.md` and `agents/issue-manager.md` for the definition of
  `blocked`
- **THEN** neither defines it as "a hard dependency on another issue"

### Requirement: `activate` and `issue-manager` route external blockers to `add-external`

Both documents SHALL say that an external blocker, found by the architect or confirmed by the owner,
uses `add-external`: `skills/activate/SKILL.md` step 4, and the `agents/issue-manager.md` section on
a hard dependency found outside `activate`. The "auto mode never skips past" rule in
`skills/activate/SKILL.md` SHALL apply to both kinds of blocker.

#### Scenario: An external blocker at activate
- **WHEN** a reader follows `skills/activate/SKILL.md` step 4 for a blocker that is not an issue
- **THEN** it says to use `add-external`

#### Scenario: An external blocker found later
- **WHEN** a reader follows the `agents/issue-manager.md` section on a hard dependency found outside
  `activate`, for a blocker that is not an issue
- **THEN** it says to use `add-external`

#### Scenario: Auto mode meets either kind of blocker
- **WHEN** `activate` runs in auto mode and finds either an issue-to-issue dependency or an external
  blocker
- **THEN** the "auto mode never skips past" rule applies to it

