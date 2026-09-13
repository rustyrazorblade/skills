# Design — issue 82: owner presentation contract

## Context

This change edits instruction prose only. There is no runtime, no data model, and no interface in
the usual sense. "Design" here means three things: where the contract text lives, how it binds every
owner-facing presenter, and how the contract avoids forbidding the deliberate batch presentations
that already exist.

The architect and design-critic both ran before the owner chose. design-critic found the first draft
could not meet its acceptance criteria as written. The decisions below resolve every blocker it
raised.

## Decisions

### Where the contract lives: central block plus in-place fixes

The contract is one canonical block in `docs/workflow.md`. Each owner-facing presenter also gets its
concrete emitting instruction fixed in place — the instruction that produces the finding text or the
option list — not just a pointer to the block.

design-critic showed that a pointer alone would not change behavior. The real violation lives in
concrete instructions. For example, `implement` tells the lead to write the residual findings list
straight from the lens JSON, whose fields include the identifier. A pointer at the top of the file
leaves that instruction standing. So each emitting site is edited to state findings in plain terms,
with the identifier as a trailing tag.

The central block prevents drift. The contract will otherwise be restated in seven files, and this
whole issue exists because a rule stated in one place did not bind another.

### The 0.46.0 sentence is reworded, not kept verbatim

The owner first asked to keep the 0.46.0 sentence verbatim. design-critic then showed the sentence
contradicts acceptance criterion 1: "never cite a spec section by its identifier" forbids the very
trailing tag the criterion allows. The owner chose to reword it. The new sentence forbids an
identifier as the subject or the sole referent, and allows it as an optional trailing tag. This
matches the contract and removes the contradiction.

### The batch carve-outs are enumerated, and groom is reconciled

The contract governs decisions, findings, and questions. It does not govern deliberate batch
presentations: status summaries (the board), read-only check batches (`setup` step 1), and
whole-artifact reviews (Seam 1's coverage tables, `implement`'s residual findings list in a PR body).
The contract names these so it cannot be read as forbidding them.

`groom` step 4 calls its bulk assumption confirm "the only exception to the one-question rule." Since
the contract now names several deliberate batches, that line is reworded to point at the contract's
list rather than claim to be the only one.

### Every owner-facing presenter is bound

Acceptance criterion 6 binds "every agent" that presents to the owner. The owner confirmed the intent
is consistency across all skills, not only the three demonstrated failure sites. So the contract
binds `issue-manager`, `implement`, `address`, `activate`, `groom`, `setup`, and `project-manager`.

The review subagents (`architect`, `product-manager`, `design-critic`, `reviewer`) are not bound.
They return structured output to a relayer; they never present to the owner. Binding them would
contradict the scope's carve-out that keeps the panel's JSON identifiers intact.

### Plain terms apply everywhere; one-at-a-time applies to live turns

design-critic noted that two bound files present through PR bodies and issue comments, which are
one-shot writes with no turn to wait for. So the contract splits its rules by presentation kind:

- **Plain terms, identifier as trailing tag, translate a relayed finding's words** — applies to every
  presentation, interactive or written into an artifact.
- **One decision at a time, wait for an answer before the next** — applies to interactive decision
  points, where the owner answers.

## Alternatives Considered

### Where the contract text lives

- **Central block plus in-place fixes at each site (chosen).** One canonical block for the wording
  and the reasoning, plus an edit to each concrete emitting instruction so behavior changes at the
  failure point. Cost: more surface to touch and one reference hop. Chosen because design-critic
  showed a pointer alone leaves the id-emitting instructions standing.
- **Restate the full rule at each site, no central block (rejected).** Matches how the repo already
  restates some behavioral rules. Rejected: it manufactures the duplication-drift this issue fights,
  across seven files.
- **Central block plus pointers only, no in-place edits (rejected, the architect's first draft).**
  Lowest effort. Rejected: design-critic judged it would not change behavior, because the emitting
  instructions would stand unchanged.

### The 0.46.0 sentence

- **Reword to allow a trailing tag (chosen).** Consistent with acceptance criterion 1. Cost: edits
  text the owner first asked to keep verbatim.
- **Keep verbatim as an absolute ban (rejected).** Would leave two different rules for two identifier
  kinds, with the same `C8` example on both sides.

### The batch carve-outs

- **Enumerate the carve-outs and reword groom's "only one" line (chosen).** Explicit and correct.
  Cost: touches `groom`, which the scope marked partly out of bounds.
- **Scope the contract narrowly and leave groom untouched (rejected).** Keeps the issue tight, but
  leaves groom's "the only one" claim stale.
- **Enumerate but leave groom untouched (rejected).** A known inconsistency between two documents.

### Reach beyond the three named files

- **Bind every owner-facing presenter (chosen).** The owner confirmed the goal is consistency across
  all skills. Cost: more files than the scope's list names.
- **Three named files plus activate only (rejected).** Leaves the central coordinator, the agent the
  owner talks to most, outside the rule.

## How this is verified

Prose has no unit test. "Tested" here means demonstrated and audited:

1. **A worked before/after example per acceptance criterion**, committed in this change under
   `verification.md`. Each pair shows a bad presentation and its compliant rewrite. This is the real
   proof the contract bites.
2. **A coverage checklist** mapping each acceptance criterion to the exact file and line that
   satisfies it, plus a scan confirming no bound file still tells an agent to present the owner a
   bare identifier as a referent.
3. **The review panel's spec lens** checks the committed prose against each scenario in this change.
