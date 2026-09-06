# walkthrough Specification

## Purpose
TBD - created by archiving change issue-42. Update Purpose after archive.
## Requirements
### Requirement: Manifest-driven, diagram-first presentation rendering
The system SHALL render a valid walkthrough manifest (a diagram plus an ordered, non-empty list of
steps) as one self-contained HTML presentation file, with the diagram appearing before all step
content and the steps rendered in the exact order given in the manifest.

#### Scenario: Valid manifest renders in order
- **WHEN** the generator is given a valid manifest containing a diagram and N ordered steps
- **THEN** it produces one HTML file containing the diagram before all step content, with the N
  steps appearing in the same order as the manifest

### Requirement: Fully self-contained output
The system SHALL produce output with no server dependency, no CDN reference, and no network call of
any kind, so the rendered file opens correctly via `file://` alone.

#### Scenario: No network references in rendered output
- **WHEN** the rendered HTML file is inspected
- **THEN** it contains no `http://`, `https://`, or `fetch(` reference anywhere in its content

### Requirement: Vertical scroll by default, with a runtime horizontal toggle
The system SHALL render the presentation with steps stacked in vertical-scroll layout by default,
and SHALL include a control in the rendered page that switches the layout to horizontal
slide-by-slide navigation and back, without requiring regeneration — a single generated artifact
SHALL serve both viewing modes.

#### Scenario: Default layout is vertical
- **WHEN** the presentation is opened
- **THEN** it defaults to vertical-scroll layout, with steps stacked top-to-bottom

#### Scenario: Toggle switches to horizontal and back
- **WHEN** the runtime toggle control is activated
- **THEN** the layout switches to horizontal slide-by-slide navigation without any regeneration,
  and activating it again returns to vertical layout — both modes are served by the same generated
  file

### Requirement: Horizontal-mode navigation chrome
The system SHALL provide a step counter, previous/next buttons, and keyboard left/right arrow
navigation for moving between steps while in horizontal mode.

#### Scenario: Nav chrome available in horizontal mode
- **WHEN** the presentation is in horizontal mode
- **THEN** a step counter, previous/next buttons, and keyboard arrow navigation are all available
  and functional for moving between steps

### Requirement: Code excerpts render with their source reference
The system SHALL render each step's one-or-more code excerpts together with their `file:line`
source reference inside that step.

#### Scenario: Excerpt and reference render together
- **WHEN** a step includes one or more code excerpts with `file:line` references
- **THEN** each excerpt's code and its source reference render inside that step

### Requirement: Content-agnostic across walkthrough kinds
The system SHALL use the same manifest schema and the same renderer regardless of what kind of
walkthrough the content represents (an explanation of how something works, a technical-debt
analysis, an areas-for-improvement review, general recommendations, or a performance analysis) —
only the agent-authored content differs; there is no separate code path per kind.

#### Scenario: Non-"how it works" walkthrough uses the same renderer
- **WHEN** a manifest represents a technical-debt, improvement, recommendation, or performance
  walkthrough rather than an explanation of how something works
- **THEN** the same manifest schema and renderer produce the output — no separate code path is
  invoked based on the kind of walkthrough

### Requirement: Optional per-step kind badge
The system SHALL render a small badge on a step when that step's manifest entry includes a `kind`
field, and SHALL render no badge when `kind` is omitted. Any string value SHALL be accepted for
`kind` — an unrecognized value SHALL still render (with a generic badge style), never causing
validation to fail.

#### Scenario: Kind present renders a badge
- **WHEN** a step includes an optional `kind` field
- **THEN** it renders as a small badge on that step

#### Scenario: Kind omitted renders no badge
- **WHEN** a step's `kind` field is omitted
- **THEN** no badge shows for that step

### Requirement: Loud failure on missing or empty manifest
The system SHALL fail with a non-zero exit and a clear error message when invoked with no manifest,
an unreadable manifest, or a manifest with no steps — never producing an empty presentation.

#### Scenario: No manifest fails loudly
- **WHEN** the generator is invoked with no manifest, an empty manifest, or a manifest with an
  empty step list
- **THEN** it fails with a non-zero exit and a clear error message, and produces no output file

### Requirement: Loud, specific failure on an invalid step or excerpt
The system SHALL fail generation, identifying the specific step (by its 1-based position and title,
if present) and, where applicable, the specific excerpt within it, when a manifest step or excerpt
is missing a required field.

#### Scenario: Step missing a required field
- **WHEN** a manifest step is missing a required field (`title`, `narration`, or a non-empty
  `excerpts` list)
- **THEN** generation fails with an error identifying which step is invalid

#### Scenario: Excerpt missing a required field
- **WHEN** an excerpt within a step is missing a required field (`path`, `startLine`, or `code`)
- **THEN** generation fails with an error identifying both the step and the excerpt within it

### Requirement: Diagram is mandatory
The system SHALL fail generation with a clear error when a manifest omits the diagram entirely, or
supplies a diagram with no `source` content.

#### Scenario: Missing diagram fails loudly
- **WHEN** the manifest omits the diagram entirely, or the diagram's `source` is empty
- **THEN** generation fails with a clear error rather than producing a diagram-less presentation

