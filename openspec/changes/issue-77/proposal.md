## Why

`groom` spawns `product-manager` once. One pass over a rough idea produces a refinement shaped by
whatever the agent could infer in a single reading, and the issue it creates carries only that
depth. Everything the agent could not settle becomes a guess made later — by `architect` at the
design stop, by `tdd-developer` while implementing, by the review panel deciding whether the result
matches. Each of those guesses is made without the owner in the room.

The owner's stated direction for this repo (`CLAUDE.md`, "Spec-Flow Project Direction") is to front-
load that work: one conversation, deep enough that the agents afterwards have the detail to get it
right, then mark the issue ready and let them run. A single refinement pass cannot reach that depth,
because the questions worth asking only become visible after the first answers land.

Two constraints landed on `main` at `bca5297` — `product-manager` must never invent a requirement,
and every line in a groomed issue must trace back to the owner. More rounds mean more opportunities
to violate both, so the loop has to make invention harder rather than merely more frequent.

## What Changes

- **`groom` step 4 becomes an iterative loop.** Each round spawns a fresh `product-manager` with the
  raw idea, the refinement record, and the previous round's refinement. No persisting agent, so no
  dependency on the experimental agent-teams gate that `groom` does not have today.
- **`groom` decides when the loop ends, not the agent.** No other loop in this plugin lets a
  subagent decide its own termination; `implement`'s panel recomputes the stop condition rather than
  trusting a lens's verdict. The bar is downstream readiness: every acceptance criterion testable as
  written, unhappy paths covered, no behavioural assumption left for a downstream agent to guess at.
- **A criterion made testable by an unsourced specific value is not ready.** It becomes the next
  round's question. Without this the readiness bar would reward inlining values the owner never
  gave, which is the anti-invention rule's exact failure mode.
- **`groom` step 1 shrinks** to what is needed to launch round 1. The deep interview moves into the
  loop, where the asking agent has read the code. Today's step 1 resolves shape ambiguity before
  step 4 runs, which would leave the loop with nothing to ask and the owner in two interviews.
- **The refinement record is a file** `groom` appends to and each round's spawn reads. `groom` runs
  in `project-manager`'s session; a record held in conversation context degrades to a paraphrase on
  compaction, and a later round would receive softened owner constraints while still reporting the
  anti-invention rule satisfied.
- **The record represents edits and deletions, not only utterances**, and pairs each answer with the
  question it answered. Later entries win over earlier contradicting ones.
- **The owner may state technical direction at any round** — architecture, performance, constraints,
  implementation guidelines. It is recorded verbatim under `## Technical direction`, never rewritten
  into behavioural criteria, and `activate` passes it to `architect` verbatim. `product-manager`'s
  "stay out of design" rule binds the agent, not the owner.
- **Ending the loop runs a closing pass** that asks nothing and converts what is still open into
  stated assumptions. `groom` presents them in one screen, split by provenance: items traceable to
  something the owner said are bulk-confirmable and promote into Scope or Acceptance criteria; items
  the owner never raised each need an explicit yes or no, so an invented line cannot ride along on a
  bulk yes.
- **`groom` step 7 uses `--body-file`.** A drafted body containing `` `file:line` `` is currently
  interpolated into a double-quoted shell string, where backticks are command substitution. This
  change makes bodies longer and more code-dense.
- **`agents/project-manager.md`, `README.md` and `docs/workflow.md` stop describing grooming as a
  single pass.** `project-manager.md` is the agent that runs `groom`; a stale instruction there is a
  competing spec, not documentation drift.

## Scope

Grooming only. The architect loop at `activate`, the spec audit gate, and widening the `activate`
hand-off in general are each separate work. The one narrow `activate` change here is passing
`## Technical direction` to `architect`, without which that section would reach nobody.
