# Overrides and conflicts: issue 88

## Overrides existing behavior

This change modifies or removes baseline requirements in two capabilities: `owner-presentation` (from issue 82) and `idea-refinement` (from issue 77).  Each entry below names one baseline requirement, quotes its current text, and gives this change's text.  The deltas in `specs/owner-presentation/spec.md` and `specs/idea-refinement/spec.md` carry these as MODIFIED, REMOVED, and RENAMED sections.  Every other baseline requirement in the two capabilities stays unchanged.

### Override: owner-presentation, "The owner may override to a batch"

**Currently:** The owner MAY ask for a whole set at once.  When the owner does, the agent SHALL present the set together.  That override SHALL apply to that request only, and the agent SHALL NOT assume it for later presentations.

**This change:** Removed — no replacement.  Every question is its own message, and the owner is never offered a batch ("One question per message, with no exceptions").

**Owner answer:** Remove it.  "I don't ever want a fucking batch."

### Override: owner-presentation, "Decisions are presented one at a time by default"

**Currently:** When an agent has several findings or decisions for the owner, it SHALL present them one at a time by default and SHALL wait for an answer before presenting the next.  This rule governs interactive decision points, where the owner answers.

**This change:** Renamed to "One question per message, with no exceptions" and replaced.  An agent SHALL put at most one question to the owner in a message, live or written.  Anything that needs the owner's decision SHALL be its own message.  When an agent has several questions, it SHALL first list them all as bullets, for context, and then ask them one per message.  An agent MAY show a list of items only when nothing in it needs an answer.  No file in the plugin SHALL allow several questions in one message, and the owner SHALL NOT be offered a batch.

**Owner answer:** Replace it.  Already decided at the design stop (Q10, and "Remove all exceptions" in the issue's Technical direction).

### Override: owner-presentation, "Options state their cost, and the recommended one is marked where one exists"

**Currently:** When an agent lists options for a decision, each option SHALL state what it costs as well as what it does.  The agent SHALL mark the recommended option where it has a recommendation.  Where the decision is deliberately the owner's and the agent withholds a recommendation, it SHALL present the options unmarked and SHALL say the choice is the owner's.

**This change:** Renamed to "Each option states its effect, pros, cons, and tradeoff, and exactly one is recommended" and replaced.  When a question lists options, each option SHALL state its concrete effect, its pros, its cons, and the tradeoff the choice makes.  Exactly one option SHALL be marked as recommended.  The contract SHALL NOT allow an agent to withhold a recommendation.

**Owner answer:** Replace it.  Already decided at the design stop (Q12, and the pros/cons/tradeoff direction in the issue).

### Override: owner-presentation, "Plain terms apply to written artifacts; one-at-a-time applies to live turns"

**Currently:** The plain-terms rules SHALL apply to every presentation, whether interactive or written into an artifact such as a PR body or an issue comment.  The one-at-a-time rule and its wait SHALL apply to interactive decision points, not to a one-shot written artifact.

**This change:** Renamed to "Plain terms and one question per message apply to live and written presentations".  The plain-terms half stays as written.  The one-question-per-message rule SHALL apply to written questions as well as to live turns: a written question is posted on the issue thread, one question per comment.  A written list that needs no answer, such as a residual findings list in a PR body, is information and is not split.

**Owner answer:** Replace the one-at-a-time half.  Already decided at the design stop (C5).

### Override: owner-presentation, "Deliberate batch presentations are exempt"

**Currently:** The contract SHALL name the deliberate batch presentations it does not govern: status summaries such as the board, read-only check batches, and whole-artifact reviews such as Seam 1 coverage tables and a residual findings list.  An agent presenting one of these SHALL NOT be forced to split it into one item at a time.  Its scenarios include `groom`'s bulk assumption confirm as one of the exempt batches.

**This change:** Removed — no replacement.  A list is allowed only when nothing in it needs an answer ("One question per message, with no exceptions").  The board, the check results, the rendered spec, and the residual list stay allowed as information.  `groom`'s bulk confirm and the Seam 1 tables as a batch of questions are gone.

**Owner answer:** Replace it.  Already decided at the design stop (Q10).

### Override: owner-presentation, "Every owner-facing presenter is bound"

**Currently:** Every agent or skill that presents findings, options, or questions to the owner SHALL follow this contract.  The bound presenters are `issue-manager`, `implement`, `address`, `activate`, `groom`, `setup`, and `project-manager`.  A review subagent that returns structured output to a relayer, and never presents to the owner, is not bound.

**This change:** The list of bound agents grows.  `product-manager` and `architect` SHALL follow the question format for any question or list of options they draft for the owner, even though a relayer presents it.  A review subagent that returns structured output to a relayer, and never drafts a question for the owner, is not bound.  The agent-to-agent channel stays unchanged.

**Owner answer:** Accept.  In the issue's scope ("Sub-agents").

### Override: idea-refinement, "Assumptions are confirmed in one pass, split by provenance"

**Currently:** `groom` SHALL present the closing pass's assumptions together, in one pass, split into items traceable to something the owner said and items the owner never raised.  Traceable items SHALL be confirmable in bulk and, once confirmed, promoted into Scope or Acceptance criteria as ordinary lines.  Items the owner never raised SHALL each require an explicit yes or no, and SHALL NOT be promoted by a bulk confirmation.  Items left unresolved SHALL appear in the created issue under a dedicated assumptions section.

**This change:** Renamed to "Assumptions are confirmed one at a time, split by provenance".  `groom` SHALL split the closing pass's assumptions into items traceable to something the owner said and items the owner never raised.  `groom` SHALL list all of them as bullets, then ask about each assumption in its own message, each with a recommendation.  It SHALL NOT confirm assumptions in bulk.  A traceable item, once confirmed, SHALL be promoted into Scope or Acceptance criteria as an ordinary line.  An item the owner never raised SHALL require an explicit yes or no, and SHALL NOT be promoted without an explicit yes.  Items left unresolved SHALL appear in the created issue under a dedicated assumptions section.  The provenance split, the explicit-yes rule, and the assumptions section stay; only the bulk confirm is gone.

**Owner answer:** Remove the bulk confirm.  In the issue's scope and acceptance criteria.

### Override: idea-refinement, "A round's questions reach the owner one at a time"

**Currently:** `groom` SHALL relay a round's questions to the owner one at a time, at most three per round, each with a stated recommended default the owner can accept in one word.  `groom` SHALL NOT present a round's questions as a batch.  Its scenarios include "A round produces more candidate questions than the cap": at most three reach the owner in a round, and the rest wait for a later round.

**This change:** The "at most three per round" clause and the "more candidate questions than the cap" scenario are gone.  `product-manager` SHALL return every question a round cannot settle from the refinement record or the repo, ranked by how much the answer changes the work, each with a recommended default.  It SHALL NOT hold a question back to meet a per-round size.  `groom` SHALL relay every question the round returns, one per message, after listing them all as bullets.  It SHALL NOT drop or defer a question because of how many the round returned.  The one-at-a-time relay, and the rule that a question without a recommended default is not relayed, stay.

As first written, this change removed only the five-question cap in `activate` step 1, and left the three-per-round size, because the loop runs as many rounds as the owner needs.  The owner's answer below replaced issue 77's per-round size too, because the owner said there should be no hard-coded limit.

**Owner answer:** Remove the three-per-round limit too.  This is now a real conflict: this change replaces issue 77's per-round size.

## Conflicts with other in-flight changes

Open changes other than this one: none.  Issues 77, 82, and 86 are archived.

### Dependency: issue 82's and issue 77's changes are archived; the dependency is satisfied

This change extends `owner-presentation`, from issue 82, and replaces two `idea-refinement` requirements, from issue 77.  Both changes are archived (commit f7d263b, PR 94), so both capabilities are in the baseline.  Task 1.1 rewrote this change's deltas against that baseline: each requirement this change supersedes is now a MODIFIED, REMOVED, or RENAMED entry, listed under **Overrides existing behavior** above.  No contradicting requirement stays in the baseline after this change archives.

### Conflict: issue-86, blocked-dependency and delivery-board

Issue 86 makes the native `blocked_by` link the only record of an issue dependency, and the board reads it.  This change's `record` sets a native "M blocked by N" link, and `close-merged` calls `blocked-dependency.sh sweep` unchanged.  The board shows M as blocked by N while N is open, which is the intended effect.  The "make it block" option uses `blocked-dependency.sh add` unchanged.  No actual conflict: this change touches no requirement of issue 86.
