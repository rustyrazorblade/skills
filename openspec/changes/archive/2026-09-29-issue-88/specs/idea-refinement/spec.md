## MODIFIED Requirements

### Requirement: A round's questions reach the owner one at a time

`groom` SHALL relay a round's questions to the owner one at a time, each with a stated recommended default the owner can accept in one word.  `groom` SHALL NOT present a round's questions as a batch.  `product-manager` SHALL return every question a round cannot settle from the refinement record or the repo, ranked by how much the answer changes the work, each with a recommended default.  It SHALL NOT hold a question back to meet a per-round size.  `groom` SHALL relay every question the round returns, one per message, after listing them all as bullets.  It SHALL NOT drop or defer a question because of how many the round returned.  A question that arrives without a recommended default SHALL NOT be relayed.

#### Scenario: A round asks three questions
- **WHEN** a round returns three questions
- **THEN** the owner is asked the first, and the second only after answering the first

#### Scenario: A question arrives without a recommended default
- **WHEN** a round returns a question with no stated default
- **THEN** `groom` does not relay it as-is, and the round is treated as not having asked it

#### Scenario: A round returns five questions
- **WHEN** a `product-manager` round returns five questions, each with a recommended default
- **THEN** `groom` lists all five as bullets, then asks each one in its own message, in the ranked order, and asks the next only after the owner answers

#### Scenario: A round has more open items than three
- **WHEN** a round finds six open items it cannot settle from the record or the repo
- **THEN** it returns all six as questions, and none is moved to a later round or turned into an assumption because of a per-round size

#### Scenario: A question without a default in a large round
- **WHEN** a round returns four questions and one has no recommended default
- **THEN** `groom` relays the other three, and records the fourth as dropped

### Requirement: Assumptions are confirmed one at a time, split by provenance

`groom` SHALL split the closing pass's assumptions into items traceable to something the owner said and items the owner never raised.  `groom` SHALL list all of them as bullets, then ask about each assumption in its own message, each with a recommendation.  It SHALL NOT confirm assumptions in bulk.  A traceable item, once confirmed, SHALL be promoted into Scope or Acceptance criteria as an ordinary line.  An item the owner never raised SHALL require an explicit yes or no, and SHALL NOT be promoted without an explicit yes.  Items left unresolved SHALL appear in the created issue under a dedicated assumptions section.

#### Scenario: The closing pass returns five assumptions
- **WHEN** the closing pass returns five assumptions, three traceable to the owner and two not
- **THEN** `groom` lists all five as bullets, then asks about each one in its own message, each with a recommended answer

#### Scenario: A traceable assumption is confirmed
- **WHEN** the owner answers yes to the question about a traceable assumption
- **THEN** that item becomes an ordinary Scope or Acceptance criteria line

#### Scenario: An agent-authored assumption cannot ride along
- **WHEN** the closing pass lists an unhappy-path behaviour the owner never raised, and the owner confirms every traceable item
- **THEN** that item is not promoted until the owner answers yes to its own question

#### Scenario: An unresolved assumption is recorded, not dropped
- **WHEN** the owner declines to resolve an assumption
- **THEN** it appears in the created issue under its own assumptions section, not in Scope or Acceptance criteria

## RENAMED Requirements

- FROM: `### Requirement: Assumptions are confirmed in one pass, split by provenance`
- TO: `### Requirement: Assumptions are confirmed one at a time, split by provenance`
