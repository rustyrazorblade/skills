# test-policy Specification

## Purpose
TBD - created by archiving change issue-50. Update Purpose after archive.
## Requirements
### Requirement: Agents receive a pointer to the repo's policy, never policy text

Every prompt that instructs an agent to run tests SHALL carry a pointer directing it to read the repo's policy file and follow it, and SHALL NOT carry test commands, tier names, or any statement of what runs where. The pointer SHALL name a resolved absolute path, so the agent receives a path rather than a rule to evaluate.

#### Scenario: The instruction is derived from the repo's file

- **WHEN** the repo's policy file exists and `implement` runs
- **THEN** the test instruction every teammate receives directs them to that file
- **AND** the instruction names its absolute resolved path

#### Scenario: No plugin default can leak into a prompt

- **WHEN** any teammate prompt is composed
- **THEN** the plugin's own former default commands appear nowhere in it
- **AND** a command appears in the run only because the repo's policy file named it

#### Scenario: The policy is obeyed as written, whichever way it points

- **WHEN** the repo's policy says the full suite runs locally and CI is the merge gate only
- **THEN** teammates are instructed to run the full suite locally
- **AND** no instruction to avoid running the full suite locally is emitted anywhere in the run, including the draft pull request body and the final report

#### Scenario: A repo with no test suite is a valid policy, not a degraded one

- **WHEN** the repo's policy states that the repo has no automated test suite and that CI is not a test gate
- **THEN** agents follow that policy without attempting to discover, infer, or invent a test command
- **AND** the run is not treated as broken, incomplete, or degraded on that basis

#### Scenario: The pointer carries no missing-file handling

- **WHEN** the pointer instruction is composed
- **THEN** it contains no conditional or fallback for the policy file being absent
- **AND** the check that guarantees the file's presence has already run before any agent is spawned

### Requirement: One generated pointer serves every mode and every caller

The pointer line SHALL be generated in exactly one place and consumed everywhere, so that no two callers can hold divergent copies of it. A consumer that cannot generate it SHALL receive it as a required input and SHALL fail loudly if it is absent, rather than falling back to a literal of its own.

#### Scenario: Both implement modes use the same line

- **WHEN** `implement` runs in either `team` or `workflow` mode
- **THEN** both paths use the same pointer, generated from the same source
- **AND** neither path contains a copy of the instruction that could drift from the other

#### Scenario: A consumer that cannot read the repo refuses rather than defaulting

- **WHEN** the workflow-mode script is invoked without the pointer it requires
- **THEN** it stops with an error naming the missing input and where it comes from
- **AND** it does not substitute a default instruction of its own

#### Scenario: Other callers reuse the same generated line

- **WHEN** `address` prompts its fix agent to run tests
- **THEN** it uses the same generated pointer
- **AND** restates no tier, command, or policy of its own

#### Scenario: The generated line is safe to embed

- **WHEN** the pointer is passed into a consumer that embeds it in a string literal
- **THEN** the line contains no character that could terminate or interpolate into that literal
- **AND** the guarantee comes from validating the path that composes it, not from escaping at the point of use

### Requirement: Agents report what they ran against the repo's policy, not against a fixed tier

The review contract SHALL express test execution relative to the repo's policy rather than naming a tier the repo may not use, and SHALL carry the exact commands run so the claim is checkable.

#### Scenario: Reporting compliance with the policy

- **WHEN** a reviewer reports which tests ran
- **THEN** the report expresses whether the repo's policy was satisfied
- **AND** does not assert a fixed tier unconditionally

#### Scenario: The exact commands are named

- **WHEN** a reviewer reports test execution
- **THEN** it names the exact commands it ran
- **AND** that detail is what the pull request body and final report quote

#### Scenario: Running nothing can be full compliance

- **WHEN** the repo's policy names nothing to run locally and the agent runs nothing
- **THEN** it reports full compliance with the policy
- **AND** does not report the run as degraded or as having skipped tests

#### Scenario: A policy command that cannot run is distinguishable from one that was not attempted

- **WHEN** the policy's command exists but fails to run because a tool or dependency is missing
- **THEN** the report distinguishes that from having run the policy successfully and from having run nothing
- **AND** the detail names what failed

#### Scenario: Static agent definitions carry no tier

- **WHEN** an agent definition file is read
- **THEN** it contains no assertion about which tier runs locally
- **AND** it defers to the pointer supplied in its prompt

#### Scenario: A report assembled without a review reports that it does not know

- **WHEN** a run summary must state test execution but no review round produced one — the refactor breaker tripped, the spec lens never reported, or no round completed
- **THEN** the summary states that the outcome is unknown rather than asserting compliance or asserting that nothing ran
- **AND** the accompanying detail names why no result exists

### Requirement: CI-dependent mechanism yields to the repo's policy

Pipeline machinery that presumes CI runs tests SHALL consult the repo's policy first and SHALL exit cleanly, reporting why, when the policy says CI is not a test gate.

#### Scenario: Syncing CI failures where CI is not a test gate

- **WHEN** `sync-ci` runs in a repo whose policy states CI is not a test gate
- **THEN** it reports that this repo's policy defines no CI test gate and exits cleanly
- **AND** does not fail searching for a test-failure artifact the repo never produces

#### Scenario: Syncing CI failures where CI is a test gate

- **WHEN** `sync-ci` runs in a repo whose policy states CI runs tests
- **THEN** it proceeds with its existing behavior unchanged

### Requirement: A repo matching the shipped template behaves exactly as before

Adopting this change SHALL NOT alter pipeline behavior for a repo whose policy states the split spec-flow previously hardcoded.

#### Scenario: No behavior change for a previously-tiered repo

- **WHEN** a repo's policy file states the fast tier locally and the full suite in CI, matching the previously hardcoded policy
- **THEN** pipeline behavior is identical to that before this change
- **AND** the only difference for that repo is that the file is now required to exist

