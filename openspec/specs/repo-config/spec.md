# repo-config Specification

## Purpose
TBD - created by archiving change issue-50. Update Purpose after archive.
## Requirements
### Requirement: The consuming repo owns its configuration, and the plugin never supplies a default

spec-flow SHALL read its per-repo configuration from a file in the consuming repo. The plugin SHALL ship a template for seeding that file, and the template SHALL NOT be read at runtime, quoted into any prompt, or substituted when the repo's file is absent. There SHALL be no fallback.

#### Scenario: The repo's file is the only runtime source

- **WHEN** any part of the pipeline needs the repo's test/CI policy
- **THEN** it reads the repo's own configuration file
- **AND** no shipped template, built-in default, or previously-cached copy is consulted

#### Scenario: A missing file stops the pipeline rather than degrading it

- **WHEN** the repo's configuration file is absent
- **THEN** the pipeline stops
- **AND** no run proceeds on an assumed or inferred policy

### Requirement: Configuration location resolves from the repository root, relocatable by environment

The configuration directory SHALL default to `spec-flow/` at the repository root, and SHALL be overridable by the `SPEC_FLOW_CONFIG_DIR` environment variable. The repository root SHALL be resolved with `git rev-parse --show-toplevel`, which returns the worktree root, so an issue worktree reads the policy its own branch carries.

#### Scenario: Default location

- **WHEN** `SPEC_FLOW_CONFIG_DIR` is unset
- **THEN** the policy is read from `spec-flow/TESTING.md` at the repository root

#### Scenario: Relocated by environment

- **WHEN** `SPEC_FLOW_CONFIG_DIR` is set to a repo-relative path in the consuming repo's `.claude/settings.json`
- **THEN** the policy is read from `<that dir>/TESTING.md`, resolved against the repository root

#### Scenario: An absolute override is rejected

- **WHEN** `SPEC_FLOW_CONFIG_DIR` is set to a value beginning with `/`
- **THEN** the check exits with an environment error naming the value
- **AND** the message states that a checked-in absolute path is wrong on every other clone

#### Scenario: A traversing or unsafe override is rejected

- **WHEN** `SPEC_FLOW_CONFIG_DIR` contains `..`, or any character outside letters, digits, `.`, `_`, `-`, and `/`
- **THEN** the check exits with an environment error naming the offending value
- **AND** no path is constructed from it

#### Scenario: Run outside a git repository

- **WHEN** the check runs somewhere that is not inside a git repository
- **THEN** it exits with an environment error distinct from the missing-config error
- **AND** no offer to create a configuration file is made

#### Scenario: A repository root that cannot be described safely is refused

- **WHEN** the repository root contains a control character, or one of the characters that terminate or interpolate into a string literal (backtick, `$`, `"`, `'`, `\`)
- **THEN** both subcommands exit with an environment error naming the offending class of character
- **AND** the refusal is the same for `check` and for `instruction`, so the two never disagree about whether a repository can be described

#### Scenario: An ordinary repository root is never refused for its punctuation

- **WHEN** the repository root contains a space, parentheses, an ampersand, or other ordinary path punctuation — `Dropbox (Personal)` and `R&D` are the common cases
- **THEN** the check passes and the pointer is emitted normally
- **AND** the repository is not required to be moved or re-cloned

#### Scenario: The policy must physically live inside the repository

- **WHEN** the policy file is a symbolic link, or the configuration directory resolves through a link to a location outside the repository
- **THEN** both subcommands exit with an environment error
- **AND** no path outside the repository is emitted or read
- **AND** this is a check on the resolved path only; the policy's content is still never inspected

### Requirement: A single script owns the check and all of its messaging

One script SHALL own configuration resolution, validation, and every message about it. Its name SHALL describe the class of repo configuration it governs rather than any single file it checks, so that later configuration files are added without renaming it. No caller SHALL restate, paraphrase, or supplement its output.

#### Scenario: Everything present costs nothing

- **WHEN** every required configuration file is present and usable
- **THEN** the script exits 0
- **AND** prints nothing on any stream

#### Scenario: Something missing produces the complete message

- **WHEN** a required configuration file is missing or unusable
- **THEN** the script exits non-zero
- **AND** prints each missing path, what it is for, and the command that creates it
- **AND** the message is complete enough that a caller relaying it verbatim needs to add nothing

#### Scenario: A missing file inside a stale worktree names the rebase

- **WHEN** the configuration file is missing in a worktree whose branch predates the file landing on the default branch
- **THEN** the message names rebasing onto the default branch as the fix

#### Scenario: The environment error is distinguishable from the missing-config error

- **WHEN** the failure is an environment or usage error rather than an unconfigured repo
- **THEN** the exit code differs from the missing-config exit code
- **AND** a caller can tell "this repo needs configuring" apart from "this environment is broken"

#### Scenario: Unusable is more than absent

- **WHEN** the configured path exists but is a directory, is unreadable, or is empty once whitespace and comment lines are stripped
- **THEN** the check treats it as unusable and fails as though it were missing

#### Scenario: The check never inspects policy content

- **WHEN** the configuration file is present, readable, and non-empty
- **THEN** the check passes
- **AND** it makes no assessment of whether the policy answers any particular question, names any particular command, or takes any particular shape

### Requirement: Callers run the check before working and stop on failure

Every entry point that acts on a repo SHALL run the check before doing work, and SHALL stop on failure, relaying the script's output unchanged. No caller SHALL carry its own prose rules about the configuration file, and none SHALL read, quote, or substitute the plugin's shipped template.

#### Scenario: A skill stops before doing any work

- **WHEN** `implement` or `sync-ci` starts and the check exits non-zero
- **THEN** the skill stops before performing any work
- **AND** relays the script's output
- **AND** adds no rules, explanation, or fallback of its own

#### Scenario: The coordinator offers to fix it

- **WHEN** `project-manager` starts a session and the check reports an unconfigured repo
- **THEN** it offers seeding

#### Scenario: The seeding offer belongs to the coordinator alone

- **WHEN** the check reports an unconfigured repo to `issue-pm`, `archive-batch`, or any skill
- **THEN** that caller stops and relays the message
- **AND** does not offer seeding

### Requirement: Seeding proposes, confirms with the owner, and lands through the repo's normal review flow

Seeding SHALL propose a concrete policy for the repo, confirm it with the owner before writing anything, then create a branch, write the file, and open a pull request. It SHALL NOT commit or push to the default branch, and SHALL NOT merge.

#### Scenario: Seeding an unconfigured repo

- **WHEN** seeding runs in a repo with no policy file and the owner confirms the proposed policy
- **THEN** it creates a branch, writes the configuration file, and opens a pull request
- **AND** makes zero commits and zero pushes to the default branch

#### Scenario: The owner is asked before anything is written

- **WHEN** seeding has determined what it believes this repo's policy should be
- **THEN** it presents that proposal to the owner and waits
- **AND** writes nothing until the owner confirms or amends it

#### Scenario: A proposal is offered whether or not the stack is recognized

- **WHEN** seeding cannot confidently recognize the repo's test stack
- **THEN** it still presents a concrete proposal, stating plainly what it was unable to determine and what it inferred
- **AND** relies on the owner's confirmation rather than writing an unconfirmed guess

#### Scenario: A repo that already owns its policy is left alone

- **WHEN** the policy file already exists on the default branch
- **THEN** seeding makes no change, opens no pull request
- **AND** reports that the repo already owns its policy

#### Scenario: The default branch is discovered, never assumed

- **WHEN** seeding needs the default branch
- **THEN** it queries the repository for it rather than assuming a particular name

### Requirement: The seeded file reads as the repo's own editable choice

The configuration file SHALL be self-describing: it SHALL state that the repo owns it, that spec-flow reads it and ships no default, and that the policy itself — including the local/CI split — is the owner's to change.

#### Scenario: The owner reads the file

- **WHEN** the owner opens the seeded configuration file
- **THEN** it states that they own it and that spec-flow never overrides it
- **AND** it is evident which parts are safe to edit
- **AND** the policy reads as this repo's choice rather than as spec-flow's requirement

### Requirement: The committed config directory is distinguishable from the gitignored state directory

`spec-flow/` (committed configuration) and `.spec-flow/` (gitignored per-branch runtime state) differ by one character at the same level. The documentation SHALL distinguish them explicitly, and the pipeline SHALL diagnose the confusion rather than failing opaquely.

#### Scenario: The config directory is committed

- **WHEN** a repo adds `spec-flow/` to its tree
- **THEN** it is committed
- **AND** it is not matched by the existing `.spec-flow/` gitignore entry

#### Scenario: An ignored config directory is diagnosed, not merely reported missing

- **WHEN** the configuration file is missing and the configured directory is matched by a gitignore rule
- **THEN** the check names that as the likely cause

#### Scenario: The documentation distinguishes the two directories

- **WHEN** the owner reads the workflow documentation or the setup guidance
- **THEN** it states which directory is committed configuration and which is gitignored runtime state
- **AND** warns against adding the undotted `spec-flow/` to a gitignore file

### Requirement: This repository ships its own policy in this change

`skills` is itself a consuming repo, so the no-fallback rule applies to it on merge. Its policy file SHALL land in this change rather than a follow-up, and SHALL state this repo's actual gate.

#### Scenario: The repo is configured on merge

- **WHEN** this change merges
- **THEN** `spec-flow/TESTING.md` already exists in this repository
- **AND** the check passes here immediately, with no window in which this repo's own pipeline refuses

#### Scenario: The policy states what is actually true here

- **WHEN** an agent reads this repository's policy file
- **THEN** it states this repository's actual test tooling and that it has no test-running CI
- **AND** names what does gate merge here
- **AND** does not name a test command this repo does not run

### Requirement: The plugin ships exactly one seeding template, and nothing reads it at runtime

The plugin SHALL ship a seeding template at a single documented path inside the plugin. Policy
resolution SHALL be anchored at the consuming repo's root, so that a template contained in the
plugin lies outside the tree any resolution searches and no configuration resolution can reach it.
The template SHALL be read only during seeding, with the owner present, and SHALL NOT be read at
runtime, quoted into any prompt, or substituted when the repo's file is absent.

#### Scenario: The template ships and is discoverable at one path

- **WHEN** the plugin is installed
- **THEN** the seeding template is present at a single documented path inside the plugin
- **AND** searching the installed plugin for that path finds it

#### Scenario: The template cannot be reached by configuration resolution

- **WHEN** any part of the pipeline resolves the repo's policy file
- **THEN** the resolved path is anchored at the consuming repo's root, and the plugin's own root
  takes no part in it
- **AND** the template is contained in the plugin, outside the tree that resolution searches, so no
  resolved path can name it whatever it is called
- **AND** reaching the template would require a literal path written by hand rather than any
  resolution the pipeline performs

#### Scenario: A missing repo policy still stops the pipeline

- **WHEN** the repo's configuration file is absent and the plugin's template is present
- **THEN** the check still exits non-zero and the pipeline still stops
- **AND** the template is not read, not quoted into any prompt, and not substituted for the missing
  file

### Requirement: The template states the policy spec-flow previously hardcoded, and names the conditions under which it applies

The shipped template SHALL state, in full, the test and CI policy spec-flow hardcoded before the
policy moved into the consuming repo. Its header SHALL name the conditions a repo must meet for
that policy to apply, and SHALL direct a repo failing any of them to write its policy from what the
repo actually does. The header SHALL carry a boundary marker separating the seeding notes from the
policy text.

#### Scenario: A repo adopting the previous policy reproduces it from the template

- **WHEN** a repo whose shape is the previously hardcoded split adopts that policy
- **THEN** the template supplies the wording, and the resulting file states that split
- **AND** the requirement that such a repo behaves exactly as before has a concrete referent to
  compare against

#### Scenario: The header disqualifies a repo that does not match

- **WHEN** a reader opens the template
- **THEN** the header names the conditions under which the policy applies
- **AND** states that a repo failing any of them should write its policy from what the repo does
- **AND** states that nothing reads this file at runtime

#### Scenario: Seeding notes never reach the repo's file

- **WHEN** seeding writes a repo's policy file using the template's wording
- **THEN** the written file contains neither the seeding notes above the boundary marker nor any
  reference to the template
- **AND** the file reads as the repo's own choice

### Requirement: Seeding reads the repo before it reads the template

Seeding SHALL determine the repo's actual test and CI shape from the repo itself before consulting
the template. It SHALL open the template only where it has already determined that the repo's shape
is the previously hardcoded split, and SHALL NOT open it for any other shape. Seeding SHALL
continue to propose a concrete policy and SHALL continue to write nothing until the owner confirms.

#### Scenario: A repo that does not match never sees the template

- **WHEN** seeding runs in a repo whose shape is not the previously hardcoded split
- **THEN** it proposes a policy written from what the repo actually does
- **AND** the template is not opened

#### Scenario: A repo with no test suite is still first-class

- **WHEN** seeding runs in a repo with no automated test suite and no test-running CI
- **THEN** it proposes that as the policy, plainly
- **AND** it does not propose a tiered split, and does not open the template

#### Scenario: The owner still confirms before anything is written

- **WHEN** seeding proposes a policy, whether or not the template supplied its wording
- **THEN** the full proposed file is shown to the owner
- **AND** nothing is written until the owner confirms or amends it

### Requirement: The template's existence and its non-fallback status are both documented

The plugin's own documentation SHALL state that a seeding template ships and SHALL state that
nothing reads it at runtime. Neither statement SHALL be written in a way that implies the template
is a runtime default. The workflow document SHALL state the test and CI policy in one authoritative
place, with its other mentions pointing at that place rather than restating it.

#### Scenario: A reader learns both facts together

- **WHEN** a reader opens the plugin's workflow documentation or its README at the section
  describing the repo-owned policy
- **THEN** the template's existence is stated
- **AND** its non-fallback status is stated alongside it
- **AND** neither implies the pipeline falls back to it

#### Scenario: The policy is stated once, not three times

- **WHEN** a reader follows any mention of the test and CI policy in the plugin's workflow document
- **THEN** one section of that document states the policy authoritatively
- **AND** every other mention in it points at that section rather than restating it

#### Scenario: The references directory says who reads each file

- **WHEN** a contributor browses the plugin's references directory
- **THEN** an index names each file and the consumer that reads it
- **AND** the template's entry states that it is read only during seeding, never at runtime

### Requirement: The policy file is named for what it governs, and the template is named for what it becomes

The repo-owned policy file SHALL be named `TESTING.md`. A shipped template whose destination is a
single named file SHALL be named for that filename with a `.template` suffix, so a reader can
identify the pair without opening either file. The plugin SHALL resolve exactly one policy
filename, with no alias and no acceptance of a previous name.

#### Scenario: One filename resolves, and only one

- **WHEN** any part of the pipeline resolves the repo's policy file
- **THEN** it resolves `TESTING.md` under the repo's configuration directory
- **AND** no previous filename is tried, accepted, or read as a substitute

#### Scenario: A repo carrying only the previous filename is unconfigured

- **WHEN** the check runs in a repo that holds the previous `CI.md` but no `TESTING.md`
- **THEN** the check reports the policy file is missing and exits non-zero
- **AND** the pipeline stops, exactly as it does for a repo that never had a policy at all

#### Scenario: The template's name names its destination

- **WHEN** a contributor lists the plugin's references directory
- **THEN** the seeding template's filename is its destination filename followed by `.template`
- **AND** the pair it belongs to is identifiable without opening the file

### Requirement: This repository's own policy states what it actually runs

The policy file in this repository SHALL describe the test tooling this repository actually has.
Where an executable test harness exists, the local gate SHALL name it and SHALL state when it must
run. The policy SHALL NOT instruct an agent that no test runner exists while one does.

#### Scenario: The harnesses are named in the local gate

- **WHEN** an agent reads this repository's policy before changing a file that a harness covers,
  wherever in the repository that file sits
- **THEN** the local gate names every harness in the repository and what each one covers
- **AND** states that the covering harness must exit zero

#### Scenario: Compliance still means running only what applies

- **WHEN** a change triggers none of the local gate's clauses
- **THEN** running nothing is full compliance with the policy
- **AND** the policy says so plainly

#### Scenario: CI remains outside the test gate

- **WHEN** a reader asks what CI enforces in this repository
- **THEN** the policy states CI is not a test gate here
- **AND** states that nothing produces a test-failure artifact to sync back

