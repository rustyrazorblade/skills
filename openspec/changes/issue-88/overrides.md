# Overrides and conflicts: issue 88

## Overrides existing behavior

None — this change only adds new requirements.

The current baseline in `openspec/specs/` holds `delivery-board`, `explain`, `repo-config`, `test-policy`, and `walkthrough`.  None of them specifies how an agent asks the owner a question, how an issue body is edited, or how an issue is closed on merge.  This change modifies none of them.

`owner-presentation` does not exist in the baseline yet.  Issue 82's change added it and is merged, but it is not archived.  This change therefore adds its requirements to `owner-presentation` as ADDED requirements, with names that differ from issue 82's.  Several of issue 82's requirements contradict this change; each one is an entry under **Conflicts** below.

## Conflicts with other in-flight changes

Open changes other than this one: `issue-77`, `issue-82`, `issue-86`.  All three are merged on `main` and wait only for archive.

### Dependency: issue 82's change must be archived before this one

This change extends `owner-presentation`, which only issue 82's un-archived change defines.  If issue 82 archives first, the requirements below that this change supersedes would stay in the baseline next to this change's requirements and contradict them.  Task 1.1 handles this: when `openspec/specs/owner-presentation/spec.md` exists at implementation time, this change's delta moves the superseded requirements to MODIFIED or REMOVED.  When both archive in one batch, issue 82 must archive first, and this change's delta must then carry those MODIFIED and REMOVED sections.

### Conflict: issue-82, owner-presentation, "The owner may override to a batch"

Issue 82 lets the owner ask for a whole set at once.  This change removes that rule: every question is its own message, and the owner is never offered a batch.  Incompatible: this change removes the requirement with no replacement.

### Conflict: issue-82, owner-presentation, "Decisions are presented one at a time by default"

Issue 82 makes one-at-a-time the default, with the batch override as the exception.  This change makes it absolute, adds the bullet list of upcoming questions first, and extends it to written questions.  Incompatible: this change replaces the requirement with "One question per message, with no exceptions".

### Conflict: issue-82, owner-presentation, "Options state their cost, and the recommended one is marked where one exists"

Issue 82 lets an agent withhold a recommendation when the choice is the owner's preference.  This change requires exactly one recommended option on every question, and each option's effect, pros, cons, and tradeoff.  Incompatible: this change replaces the requirement with "Each option states its effect, pros, cons, and tradeoff, and exactly one is recommended".

### Conflict: issue-82, owner-presentation, "Plain terms apply to written artifacts; one-at-a-time applies to live turns"

Issue 82 applies one-at-a-time only to live turns, and lets a written artifact carry several items.  This change applies one question per message to written questions too, and moves written questions to the issue thread, one per comment.  Incompatible: this change replaces the second half of the requirement.  The plain-terms half stays in force.

### Conflict: issue-82, owner-presentation, "Deliberate batch presentations are exempt"

Issue 82 exempts the board, `setup`'s check batch, the Seam 1 tables, the PR residual list, and `groom`'s bulk assumption confirm from one-at-a-time.  This change allows a list only when nothing in it needs an answer.  The board, the check results, the rendered spec, and the residual list stay allowed as information.  `groom`'s bulk confirm and the Seam 1 tables as a batch of questions are removed.  Incompatible: this change replaces the requirement.

### Conflict: issue-82, owner-presentation, "Every owner-facing presenter is bound"

Issue 82 binds seven presenters and says `architect` and `product-manager` are not bound, because they never present to the owner.  This change adds a requirement that those two follow the question format for any question they draft.  Incompatible in part: the list of bound agents grows.  The agent-to-agent channel stays unchanged.

### Conflict: issue-77, idea-refinement, "Assumptions are confirmed in one pass, split by provenance"

Issue 77 lets the owner confirm traceable assumptions in bulk, with one answer for the group.  This change asks about each assumption in its own message, each with a recommendation.  Incompatible: this change removes the bulk confirm.  The provenance split, the rule that an agent-authored assumption is never promoted without an explicit yes, and the assumptions section for unresolved items can stay.

### Conflict: issue-77, idea-refinement, "A round's questions reach the owner one at a time"

Issue 77 asks at most three questions per refinement round and relays them one at a time.  This change removes hard-coded question limits.  As written, this change removes only the five-question cap in `activate` step 1, and leaves the three-per-round size, because the loop runs as many rounds as the owner needs.  No actual conflict as written; recorded because the owner said there should be no hard-coded limit.

### Conflict: issue-86, blocked-dependency and delivery-board

Issue 86 makes the native `blocked_by` link the only record of an issue dependency, and the board reads it.  This change's `record` sets a native "M blocked by N" link, and `close-merged` calls `blocked-dependency.sh sweep` unchanged.  The board shows M as blocked by N while N is open, which is the intended effect.  The "make it block" option uses `blocked-dependency.sh add` unchanged.  No actual conflict: this change touches no requirement of issue 86.
