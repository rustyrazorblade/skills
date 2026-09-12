## ADDED Requirements

### Requirement: A finding is stated in plain terms before any identifier
An agent presenting a finding to the owner SHALL state what is wrong in plain terms first. An
internal identifier (a review-panel finding tag, a spec section, a task number) MAY appear only as a
trailing tag. The identifier SHALL NOT be the subject of the sentence, and SHALL NOT be the only
referent. When an agent relays a finding it did not author, it SHALL translate the author's words
and SHALL NOT adopt the author's vocabulary unchanged.

#### Scenario: Relaying a review-panel finding
- **WHEN** an agent relays a lens finding tagged `SEC-3` to the owner
- **THEN** it states the problem in plain terms, for example "the auth token is written to the log in
  plaintext"
- **AND** the tag `SEC-3` appears only as a trailing tag, never as "should I fix SEC-3?"

#### Scenario: The 0.46.0 spec-identifier sentence
- **WHEN** an agent refers to a spec section while presenting to the owner
- **THEN** it states what the section requires in plain terms
- **AND** it MAY add the section identifier as a trailing tag, rather than being forbidden every
  identifier

### Requirement: A cited location is described, not just named
When an agent cites a file, a line, a spec scenario, or a task number to the owner, it SHALL say what
is there. The agent SHALL NOT assume the owner has the file or the artifact open.

#### Scenario: Citing a file and line
- **WHEN** an agent points the owner at `reviewer.md:120`
- **THEN** it says what that line instructs or contains, not the location alone

### Requirement: Decisions are presented one at a time by default
When an agent has several findings or decisions for the owner, it SHALL present them one at a time by
default and SHALL wait for an answer before presenting the next. This rule governs interactive
decision points, where the owner answers.

#### Scenario: Several findings after a review round
- **WHEN** a review round returns five findings that need the owner's decision
- **THEN** the agent presents the first, waits for the owner's answer, then presents the next
- **AND** it does not present all five in one message

### Requirement: The owner may override to a batch
The owner MAY ask for a whole set at once. When the owner does, the agent SHALL present the set
together. That override SHALL apply to that request only, and the agent SHALL NOT assume it for later
presentations.

#### Scenario: The owner asks for the whole set
- **WHEN** the owner says "give me all the findings at once"
- **THEN** the agent presents them together for that request
- **AND** the agent returns to one-at-a-time for the next set, without being told again

### Requirement: Options state their cost, and the recommended one is marked where one exists
When an agent lists options for a decision, each option SHALL state what it costs as well as what it
does. The agent SHALL mark the recommended option where it has a recommendation. Where the decision
is deliberately the owner's and the agent withholds a recommendation, it SHALL present the options
unmarked and SHALL say the choice is the owner's.

#### Scenario: Options with a recommendation
- **WHEN** an agent lists three design options
- **THEN** each option states its cost and its effect
- **AND** the recommended option is marked

#### Scenario: A decision the agent must not steer
- **WHEN** an agent presents the tech-debt escalation options, which it must not choose for the owner
- **THEN** it presents the options unmarked and says the choice is the owner's

### Requirement: Plain terms apply to written artifacts; one-at-a-time applies to live turns
The plain-terms rules SHALL apply to every presentation, whether interactive or written into an
artifact such as a PR body or an issue comment. The one-at-a-time rule and its wait SHALL apply to
interactive decision points, not to a one-shot written artifact.

#### Scenario: A finding written into a PR body
- **WHEN** an agent writes residual findings into a PR body
- **THEN** each finding is stated in plain terms with the identifier as a trailing tag
- **AND** the agent is not required to split the list across separate writes and wait between them

### Requirement: Deliberate batch presentations are exempt
The contract SHALL name the deliberate batch presentations it does not govern: status summaries such
as the board, read-only check batches, and whole-artifact reviews such as Seam 1 coverage tables and
a residual findings list. An agent presenting one of these SHALL NOT be forced to split it into one
item at a time.

#### Scenario: The board renders many items
- **WHEN** the board renders the state of many issues at once
- **THEN** the contract does not require the board to present one issue at a time

#### Scenario: groom's bulk assumption confirm
- **WHEN** `groom` step 4 presents its bulk assumption confirm
- **THEN** the wording points at the contract's list of exempt batches
- **AND** it does not claim to be the only exception to the one-question rule

### Requirement: Every owner-facing presenter is bound
Every agent or skill that presents findings, options, or questions to the owner SHALL follow this
contract. The bound presenters are `issue-manager`, `implement`, `address`, `activate`, `groom`,
`setup`, and `project-manager`. A review subagent that returns structured output to a relayer, and
never presents to the owner, is not bound.

#### Scenario: The central coordinator presents a decision
- **WHEN** `project-manager` asks the owner which issue to start next
- **THEN** it follows the contract, the same as any other bound presenter

#### Scenario: A review subagent returns findings to its lead
- **WHEN** a lens returns findings tagged with identifiers to its lead agent
- **THEN** the identifiers are correct on that agent-to-agent channel and are not changed by this
  contract
