## ADDED Requirements

### Requirement: No hand-written command reference ships with the plugin

The easy-db-lab plugin SHALL NOT ship `plugins/easy-db-lab/references/commands.md`.  No skill or reference in the plugin SHALL point to it.  Agents SHALL learn commands, including `report upload`, from the binary.

#### Scenario: The file is gone

- **WHEN** the change lands
- **THEN** `plugins/easy-db-lab/references/commands.md` does not exist

#### Scenario: No reference to the file remains

- **WHEN** a reader searches the plugin for `commands.md`
- **THEN** no skill or reference file matches

#### Scenario: report upload is learned from the binary

- **WHEN** a skill needs the syntax of `report upload`
- **THEN** it reads it from `$EDB commands` at discovery

### Requirement: Discovery is help-first in every skill

The plan, run, and explore skills SHALL discover the command surface from the binary in this order: `$EDB help` (topic list), then `$EDB help <topic>` for each topic the work touches, then `$EDB commands` and `--help`.  When `$EDB help` errors with `Unmatched argument at index 0: 'help'`, the skill SHALL skip the topic guides and use `commands` and `--help`.

#### Scenario: Explore discovers help-first

- **WHEN** the explore skill starts
- **THEN** it runs `$EDB help`, reads `$EDB help <topic>` for the topics the session touches, and then runs `$EDB commands`
- **AND** Guidance Principle 1 states the same order

#### Scenario: Run and plan keep help-first discovery

- **WHEN** the run or plan skill starts discovery
- **THEN** it runs `$EDB help` and `$EDB help <topic>` before `$EDB commands`

#### Scenario: Binary predates the topic guides

- **WHEN** `$EDB help` errors with `Unmatched argument at index 0: 'help'`
- **THEN** the skill skips the topic guides and relies on `$EDB commands` and `--help`

### Requirement: Plan commands are verified against the binary

The run skill SHALL verify every command that comes from a plan against `$EDB commands`, the relevant `$EDB help <topic>`, and the command's `--help` before the first step that uses it.  The plan skill SHALL verify every command it writes the same way.  Neither skill SHALL verify against a hand-written reference.

#### Scenario: Run verifies a plan command

- **WHEN** the run skill is about to run a command that came from `docs/plan.md`
- **THEN** it checks the subcommand name and flags against the binary's `commands`, `help <topic>`, and `--help` output
- **AND** if the plan and the binary disagree, the binary wins and the plan gets corrected

#### Scenario: Plan verifies its commands

- **WHEN** the plan skill runs its Step 4 quality gate and Step 5 review
- **THEN** it checks each `$EDB` command against the binary's `commands`, `help <topic>`, and `--help` output, not against `references/commands.md`

### Requirement: A missing binary stops the skill

The plan, run, and explore skills SHALL stop when no easy-db-lab binary resolves, and SHALL report the paths searched.  They SHALL NOT write commands or plans from memory.  The run skill SHALL keep its ask-for-`--binary` question and SHALL stop only when the user has no path or the given path is not executable.  The plan and explore skills SHALL check with `command -v`; in an interactive session they SHALL ask for a path first; in an unattended session they SHALL NOT ask and SHALL stop with the paths searched.

#### Scenario: Interactive session with no binary found

- **WHEN** the plan, run, or explore skill runs interactively and no binary resolves
- **THEN** it asks the user for a binary path
- **AND** if the user has no path or the path is not executable, it stops and reports the paths searched

#### Scenario: Unattended session with no binary found

- **WHEN** the plan, run, or explore skill runs unattended and no binary resolves
- **THEN** it does not ask
- **AND** it stops and reports the paths searched

#### Scenario: Nothing is written from memory

- **WHEN** no binary resolves
- **THEN** the skill writes no plan step, command, or workspace file from memory

### Requirement: Explore resolves the binary through the cluster layout

The explore skill SHALL run `detect-cluster-layout.sh` first and use the wrapper or wrappers it finds as `$EDB`.  In a multi-DC workspace it SHALL use the list of DC wrappers.  With no workspace, it SHALL use `bin/easy-db-lab`, then `easy-db-lab` on `PATH`.  When none resolves, the missing-binary rule SHALL apply.

#### Scenario: Single-DC workspace

- **WHEN** the explore skill starts in a single-DC cluster workspace
- **THEN** it uses the `EDB` wrapper that `detect-cluster-layout.sh` reports

#### Scenario: Multi-DC workspace

- **WHEN** the explore skill starts in a multi-DC cluster workspace
- **THEN** it uses the per-DC wrappers that `detect-cluster-layout.sh` reports
- **AND** uploads and teardown go through every DC wrapper

#### Scenario: No workspace

- **WHEN** `detect-cluster-layout.sh` finds no wrapper
- **THEN** the skill tries `bin/easy-db-lab`, then `easy-db-lab` on `PATH`

### Requirement: Skills carry no stale command syntax

The run and explore skills and `references/environment.md` SHALL NOT contain commands that the current binary does not have.  A block that only repeats tool syntax SHALL become a pointer to the right `$EDB help <topic>`; the rest SHALL use current syntax.

#### Scenario: Explore observability block

- **WHEN** a reader opens `explore/SKILL.md` Observability
- **THEN** it contains no `logs backup`, `logs ls`, `metrics backup`, or `metrics ls`
- **AND** it points to `$EDB help observability`

#### Scenario: Run verify step

- **WHEN** a reader opens `run/SKILL.md` Execution Loop step 4
- **THEN** the Cassandra health check is `$EDB cassandra status` or `$EDB cassandra nt status`, not `cassandra nodetool`

#### Scenario: Environment reference

- **WHEN** a reader opens `references/environment.md`
- **THEN** it does not name `easy-db-lab metrics`
- **AND** it points to `help observability` for log and metric queries

#### Scenario: Explore provisioning lines

- **WHEN** a reader opens `explore/SKILL.md` Step 2
- **THEN** the `init` lines use `--db.count` and `--app.count`
- **AND** every invocation uses `$EDB`, not a bare `easy-db-lab`

#### Scenario: Explore teardown block

- **WHEN** a reader opens `explore/SKILL.md` Teardown
- **THEN** it contains no `--clickhouse.backup`
- **AND** the real teardown command is `$EDB down --auto-approve` after the upload gate
