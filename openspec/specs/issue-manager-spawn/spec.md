# issue-manager-spawn Specification

## Purpose
TBD - created by archiving change issue-86. Update Purpose after archive.
## Requirements
### Requirement: `project-manager` confirms with the owner before spawning for a blocked issue

Before `project-manager` spawns an `issue-manager` for an issue, it SHALL look for that issue in the
board's Blocked section. When the issue is there, `project-manager` SHALL show the owner that issue's
lines from the Blocked section, as data, and SHALL spawn only after the owner confirms.
`project-manager` SHALL get the blocker list from the board and SHALL NOT re-derive "blocked" from
`gh` output itself. `spawn-issue-manager.sh` SHALL NOT gain a blocked check.

#### Scenario: A blocked issue, owner confirms
- **WHEN** the owner asks `project-manager` to spawn an `issue-manager` for an issue that has an OPEN
  native blocker or the `blocked` label
- **THEN** `project-manager` shows the owner that issue's lines from the board's Blocked section,
  as data, and asks whether to spawn
- **AND** the `issue-manager` spawns only after the owner confirms

#### Scenario: A blocked issue, owner declines
- **WHEN** the owner does not confirm the spawn of a blocked issue
- **THEN** no `issue-manager` spawns and no label changes

#### Scenario: An issue that is not blocked
- **WHEN** the owner asks `project-manager` to spawn an `issue-manager` for an issue absent from the
  board's Blocked section
- **THEN** the spawn works as it does today, with no extra question

#### Scenario: The blocker list comes from the board
- **WHEN** a reader follows `agents/project-manager.md`'s pre-spawn check
- **THEN** it reads the issue's lines from the board's Blocked section, and does not tell the agent
  to query `gh` for blockers or labels itself

### Requirement: `spawn-issue-manager.sh` is split into parts with one preflight function, without behavior change

`scripts/spawn-issue-manager.sh` SHALL be split into clearly named parts, with every pre-spawn check
in one preflight function. Every existing exit path, its exit code and message, and the order of
the pre-spawn checks SHALL stay the same.

#### Scenario: The preflight function holds every pre-spawn check
- **WHEN** a reader opens `spawn-issue-manager.sh` after the refactor
- **THEN** every pre-spawn check lives in one preflight function, called before any mutation

#### Scenario: Exit paths are unchanged
- **WHEN** the script hits any exit path it had before the refactor
- **THEN** it exits with the same code and prints the same message as before

#### Scenario: Check order is unchanged
- **WHEN** several pre-spawn checks would fail at once
- **THEN** the same check fails first as before the refactor

### Requirement: A script test pins the spawn script's behavior across the refactor

`scripts/test-spawn-issue-manager.sh` SHALL run on bash 3.2 with a fake `gh` and a fake `claude` on
PATH, SHALL check each existing exit path of `spawn-issue-manager.sh` and the order of its pre-spawn
checks, and SHALL pass both against the script before the refactor and after it.

#### Scenario: The test passes on the current script
- **WHEN** `test-spawn-issue-manager.sh` runs against the script as it is before the refactor
- **THEN** every check passes and it exits 0

#### Scenario: The test passes after the refactor
- **WHEN** `test-spawn-issue-manager.sh` runs against the refactored script
- **THEN** every check passes and it exits 0

#### Scenario: A reordered check is caught
- **WHEN** two pre-spawn checks are swapped in the script
- **THEN** `test-spawn-issue-manager.sh` fails

