## ADDED Requirements

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
