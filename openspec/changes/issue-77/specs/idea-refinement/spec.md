## ADDED Requirements

### Requirement: `groom` refines an idea over multiple rounds

`groom` SHALL run `product-manager` as a loop. Each round SHALL spawn a fresh agent whose prompt
carries the owner's raw idea verbatim, the refinement record, and the previous round's refinement.
`groom` SHALL NOT depend on a persisting agent or on the experimental agent-teams gate.

#### Scenario: An idea with unresolved detail runs more than one round
- **WHEN** round 1 returns a refinement whose acceptance criteria are not all testable as written
- **THEN** `groom` runs a further round rather than drafting the issue

#### Scenario: A later round receives what came before
- **WHEN** `groom` spawns round 2
- **THEN** the prompt contains the raw idea verbatim, the refinement record, and round 1's full refinement

#### Scenario: A small idea converges in one round
- **WHEN** round 1 returns a refinement that already meets the readiness bar
- **THEN** `groom` proceeds to draft the issue without a second round

### Requirement: `groom` decides when the loop ends, not `product-manager`

`groom` SHALL judge each refinement against the readiness bar and decide whether to run another
round. `groom` SHALL NOT treat the agent's own claim of completeness as the stop condition. The bar
is met when every acceptance criterion is testable as written, unhappy paths are covered, and no
behavioural assumption is left for a downstream agent to guess at.

#### Scenario: The agent claims completeness but the bar is unmet
- **WHEN** a round returns a refinement asking no questions, and one acceptance criterion is not testable as written
- **THEN** `groom` runs another round

#### Scenario: An unsourced specific value does not satisfy the bar
- **WHEN** a refinement contains a criterion rejecting requests over a stated size, and the record contains no antecedent for that size
- **THEN** `groom` treats that criterion as not ready and the value becomes a question for the next round

#### Scenario: Design assumptions do not hold the loop open
- **WHEN** the only unresolved assumptions concern data models, interfaces, algorithms or libraries
- **THEN** the bar is met, because those belong to `architect` at the design stop

### Requirement: A round's questions reach the owner one at a time

`groom` SHALL relay a round's questions to the owner one at a time, at most three per round, each
with a stated recommended default the owner can accept in one word. `groom` SHALL NOT present a
round's questions as a batch.

#### Scenario: A round asks three questions
- **WHEN** a round returns three questions
- **THEN** the owner is asked the first, and the second only after answering the first

#### Scenario: A round produces more candidate questions than the cap
- **WHEN** a round would ask five questions
- **THEN** at most three reach the owner in that round, and the rest are available to a later round

#### Scenario: A question arrives without a recommended default
- **WHEN** a round returns a question with no stated default
- **THEN** `groom` does not relay it as-is, and the round is treated as not having asked it

### Requirement: The refinement record is durable, and represents edits as well as answers

`groom` SHALL maintain the refinement record as a file it appends to and each round's spawn reads,
not as conversation context. Each entry SHALL pair an answer with the question it answered. The
record SHALL represent an owner's hand edit or deletion as an explicit entry. Where two entries
contradict, the later SHALL win.

#### Scenario: The record survives a compacted conversation
- **WHEN** `groom`'s session is compacted between rounds
- **THEN** the next round's spawn still receives the owner's statements verbatim

#### Scenario: The owner deletes a criterion without comment
- **WHEN** the owner removes an acceptance criterion from a refinement and says nothing
- **THEN** the record carries an entry recording the deletion, and the next round does not re-add that criterion

#### Scenario: A later answer contradicts an earlier one
- **WHEN** the owner asks for a CLI flag in round 2 and removes the criterion mentioning it in round 4
- **THEN** the later entry governs and no later round re-proposes the flag

#### Scenario: A bare answer retains its question
- **WHEN** a round records an answer that is meaningless on its own, such as a bare refusal
- **THEN** the record also carries the question it answered, so a later round can resolve the referent

### Requirement: The owner's hand edits are binding input to the next round

`groom` SHALL carry the owner's edited version of a refinement into the next round's prompt, not the
agent's. An edit SHALL be recorded the same way an answer is.

#### Scenario: The owner rewrites a scope line
- **WHEN** the owner edits a scope line in round 2's refinement and round 3 is spawned
- **THEN** round 3's prompt carries the owner's wording, not the agent's

### Requirement: The owner may state technical direction; `product-manager` may not

`groom` SHALL accept owner-stated technical direction — architecture, performance characteristics,
implementation guidelines, constraints — at any round, and SHALL record it verbatim.
`product-manager` SHALL NOT rewrite it into behavioural criteria, and SHALL NOT drop it for being
design. It SHALL appear in the created issue under a technical direction section. `product-manager`'s
own prohibition on specifying design SHALL continue to bind the agent and SHALL NOT bind the owner.

#### Scenario: The owner states a constraint mid-loop
- **WHEN** the owner states a performance constraint during round 2
- **THEN** it is recorded verbatim and appears in the created issue under the technical direction section

#### Scenario: The agent tries to restate direction as behaviour
- **WHEN** a round returns owner technical direction reworded as an acceptance criterion
- **THEN** `groom` does not accept the rewording, and the direction remains verbatim

#### Scenario: `activate` hands technical direction to `architect`
- **WHEN** `activate` spawns `architect` for an issue carrying a technical direction section
- **THEN** that section is included verbatim in the architect's prompt alongside the scope and acceptance criteria

#### Scenario: An issue without technical direction is unaffected
- **WHEN** `activate` spawns `architect` for an issue with no technical direction section
- **THEN** the architect's prompt carries scope and acceptance criteria as before, with no empty section

### Requirement: The loop terminates

The loop SHALL end when the readiness bar is met, when the owner ends it, or when every question a
round would ask is already answered in the record.

#### Scenario: The owner ends the loop
- **WHEN** the owner says to stop at any round
- **THEN** `groom` asks no further questions and runs the closing pass

#### Scenario: A round produces nothing new
- **WHEN** every question a round would ask is already answered in the record
- **THEN** the loop ends, because a further round has the same inputs

### Requirement: The closing pass converts open items into stated assumptions

When the loop ends other than by meeting the readiness bar, `groom` SHALL run one closing round that
carries the owner's last answers, asks nothing, and converts everything still open into explicitly
stated assumptions.

#### Scenario: The closing pass asks nothing
- **WHEN** the closing round runs
- **THEN** it returns a refinement and stated assumptions, and no questions

#### Scenario: The owner's final answers reach the agent
- **WHEN** the owner answers a question and then immediately ends the loop
- **THEN** the closing round's prompt contains that final answer

### Requirement: Assumptions are confirmed in one pass, split by provenance

`groom` SHALL present the closing pass's assumptions together, in one pass, split into items
traceable to something the owner said and items the owner never raised. Traceable items SHALL be
confirmable in bulk and, once confirmed, promoted into Scope or Acceptance criteria as ordinary
lines. Items the owner never raised SHALL each require an explicit yes or no, and SHALL NOT be
promoted by a bulk confirmation. Items left unresolved SHALL appear in the created issue under a
dedicated assumptions section.

#### Scenario: A traceable assumption is bulk-confirmed
- **WHEN** the owner confirms the traceable group in one answer
- **THEN** each of its items becomes an ordinary Scope or Acceptance criteria line

#### Scenario: An agent-authored assumption cannot ride along
- **WHEN** the closing pass lists an unhappy-path behaviour the owner never raised, and the owner bulk-confirms the traceable group
- **THEN** that item is not promoted, and the owner is asked about it explicitly

#### Scenario: An unresolved assumption is recorded, not dropped
- **WHEN** the owner declines to resolve an assumption
- **THEN** it appears in the created issue under its own assumptions section, not in Scope or Acceptance criteria

### Requirement: `product-manager` never authors Scope or Acceptance criteria the owner did not raise

Across every round, `product-manager` SHALL place anything the owner did not raise under open
questions, never into Scope or Acceptance criteria as settled fact. Running more rounds SHALL NOT
relax this.

#### Scenario: A repo finding suggests unrequested scope
- **WHEN** a round's repo reading suggests a configuration path the owner never mentioned
- **THEN** it appears as an open question, not as a scope line

#### Scenario: Invention does not accumulate across rounds
- **WHEN** the loop runs four rounds
- **THEN** no Scope or Acceptance criteria line exists that has no antecedent in the record or an explicit owner confirmation

### Requirement: `groom` creates the issue without drafted text reaching a parser that can act on it

`groom` SHALL pass the drafted issue title and body to GitHub by file, and SHALL NOT interpolate
either into a shell argument. Where the request payload is structured, `groom` SHALL build it by
machine from the title and body files, so that escaping is correct by construction; it SHALL NOT
require an agent to escape the payload by hand.

#### Scenario: A body citing related code
- **WHEN** the drafted body cites related code in backticks
- **THEN** the issue is created with that text intact and no shell command substitution occurs

#### Scenario: A body containing a quote character
- **WHEN** the drafted body contains a `"` character, or a line that resembles a payload field
- **THEN** it is carried as text, and no additional field reaches the create-issue request

#### Scenario: A multi-line body
- **WHEN** the drafted body spans multiple lines and its sections are `##` headings
- **THEN** the created issue carries those headings each at the start of a line

### Requirement: The agent that runs `groom` is instructed to run it as a loop

`agents/project-manager.md` SHALL describe grooming as an iterative refinement loop. It SHALL NOT
instruct a single spawn followed by an owner-edit loop.

#### Scenario: The driving agent's instructions match the skill
- **WHEN** `project-manager` reads its own front-of-pipeline delegation guidance
- **THEN** it describes the loop, and nothing there directs a single `product-manager` spawn
