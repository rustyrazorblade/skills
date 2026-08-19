## ADDED Requirements

### Requirement: Standalone repo-wide structural audit
The system SHALL run a full repo-wide structural-debt audit (three parallel SOLID/duplication/
structure lens agents, merge/dedupe/rank to a top-10 list, one-at-a-time owner-confirmed filing)
whenever `review-tools` is installed, whether or not `spec-flow` is also installed.

#### Scenario: review-tools installed alone
- **WHEN** a repo has only the `review-tools` plugin installed (no `spec-flow`)
- **THEN** `/tech-debt` is available and runs the full repo-wide structural audit, unchanged in
  mechanism from its previous spec-flow-hosted behavior

### Requirement: Skill instructions carry no dependency on another plugin
The tech-debt skill's own instructions SHALL describe its execution shape (foreground, standalone,
no worktree, no issue coupling, no code edits) without naming or depending on any other plugin's
agents, skills, or vocabulary.

#### Scenario: Read in isolation
- **WHEN** the moved skill's instructions are read on their own, with no other plugin installed
- **THEN** every instruction is followable without needing to know what spec-flow, project-manager,
  groom, board, or archive are

### Requirement: Single, non-duplicated home for the skill
The system SHALL have exactly one copy of the tech-debt skill in the repository, located under
`review-tools`.

#### Scenario: No duplicate remains
- **WHEN** the repository is inspected after this change lands
- **THEN** `plugins/spec-flow/skills/tech-debt/` does not exist, and
  `plugins/review-tools/skills/tech-debt/SKILL.md` is the sole copy

### Requirement: spec-flow's own references point at the moved skill
spec-flow's own files SHALL reference the moved skill by its new command name and location, not a
spec-flow-owned copy.

#### Scenario: Both plugins installed
- **WHEN** both `spec-flow` and `review-tools` are installed
- **THEN** spec-flow's `project-manager` cadence recommendation and `docs/workflow.md` reference the
  review-tools-hosted `/tech-debt` skill, and no spec-flow file references a spec-flow-owned
  tech-debt skill location

### Requirement: Cadence recommendation degrades gracefully without an explicit availability probe
`project-manager`'s tech-debt review cadence recommendation SHALL be worded conditionally on the
agent's own runtime awareness of its available skills, rather than backed by an explicit
plugin-detection command — so it neither errors nor references a missing skill when `review-tools`
isn't installed.

#### Scenario: spec-flow installed without review-tools
- **WHEN** `spec-flow` is installed without `review-tools`, and the tech-debt review cadence is due
- **THEN** `project-manager` states plainly that the periodic-audit feature needs `review-tools`
  installed, without erroring or referencing a missing skill file

#### Scenario: spec-flow and review-tools both installed
- **WHEN** both are installed and the cadence is due
- **THEN** `project-manager` recommends running `/tech-debt` normally, by name

### Requirement: Command renamed, no alias
The moved skill SHALL be invoked as `/tech-debt` (or `/review-tools:tech-debt`, namespaced) once
this change lands; `/spec-flow:tech-debt` SHALL no longer resolve, and no compatibility alias is
provided.

#### Scenario: Old command no longer resolves
- **WHEN** `/spec-flow:tech-debt` is invoked after this change
- **THEN** it does not resolve to any skill; the audit is only reachable via `/tech-debt` or
  `/review-tools:tech-debt`
