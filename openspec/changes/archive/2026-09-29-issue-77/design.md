## Context

`groom` step 4 spawns `product-manager` once and treats the returned refinement as the issue-body
source. This change makes it a loop. The design work happened at the `activate` design stop, across
one `architect` consult, one skill-authoring research consult, and two adversarial `design-critic`
passes — the second because the owner's decisions produced a materially different design from the
one the first pass reviewed.

## Approach

`groom` drives a bounded interview loop; the agent never drives itself. Each round is a fresh
`product-manager` spawn whose entire input is the prompt: the raw idea verbatim, the refinement
record, and the previous round's refinement. `groom` owns the stop condition.

Three properties carry the anti-invention constraint:

1. **The prompt is the whole input.** Anything in a round's output not traceable to the idea or the
   record is visibly the agent's own.
2. **The readiness bar rejects unsourced concreteness.** A criterion testable only because it names
   a value with no antecedent in the record is a question, not a criterion.
3. **Promotion requires provenance.** At the closing pass, only items traceable to something the
   owner said are bulk-confirmable; agent-authored items need an individual yes.

## Alternatives Considered

### Where loop state lives

- **Chosen: fresh spawn per round, state in a file the prompt references.** The file is what makes
  "append-only" and "verbatim" true rather than aspirational.
- **Rejected: one persisting agent via `SendMessage`.** Cheaper — no repo re-reading — and it
  naturally avoids restating. But persistent-teammate machinery exists in exactly one place in this
  plugin, `implement`'s Team mode, gated on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` with an automatic
  fallback. `groom` has no such gate and no fallback path. Decisively: hidden agent context is
  invisible to `groom` and therefore to the owner, so "did this scope line come from the owner"
  stops being answerable by reading the prompt.
- **Rejected: state in `groom`'s conversation context.** `groom` runs in `project-manager`'s
  session, an agent built around keeping bulk material out of that context. On compaction the record
  becomes a summary and a later round receives paraphrased owner statements presented as verbatim —
  unobservable from outside, and it silently breaks the rule the whole design rests on.

### Convergence signal

- **Chosen: `groom` computes it.** Owner override of the architect's recommendation. The architect
  proposed a `STATUS: OPEN` / `STATUS: CONVERGED` trailer the agent emits and `groom` matches. The
  research consult found that no skill anywhere in `plugins/` lets a subagent decide when a loop
  ends, and `design-critic` found that every standing instruction on `product-manager` — "keep this
  short", "don't over-produce", plus a rule that a question must justify itself — points at
  declaring convergence in round 1. The observable result would be byte-identical to today.
- **Rejected: agent-declared with a floor** (`groom` refuses a round-1 convergence when any
  defaulted assumption remains). Cheaper; leaves the threshold inside the agent.
- **Rejected: `groom` judging convergence from prose.** The current failure mode restated.

### Provenance tags on scope lines

- **Chosen: none.** Owner override of the architect's recommendation. The architect proposed tagging
  every Scope line and criterion `[owner]` or `[proposed]`, stripped at draft time. `design-critic`
  found this converts a prohibition into a disclosure: the tag only means something if `[proposed]`
  lines may sit in Scope, which the existing placement rule forbids outright. The tag is also
  self-reported by the agent that would do the inventing, and stripping it left no acceptance step —
  colliding with `groom`'s own "Silence is not agreement."
- **Rejected: tags plus a per-line acceptance gate.** Closes the hole; adds a question per line to a
  change whose primary risk is owner fatigue.

### Runaway control

- **Chosen: no round cap.** Owner override of the architect's recommended cap of 3. The owner is
  present at every round, so a long loop is visible and one word ends it — unlike `implement`'s
  panel, which runs unattended and is capped by the repo's `WORKFLOWS.md`. A numeric cap can only
  stop the loop short of the readiness bar, which is the outcome this change exists to prevent.
  Termination rests on the bar, the owner's word, and the no-new-questions stop.
- **Rejected: cap 3, or a high cap of 5-6.** Predictable ceiling on owner time; can stop below the
  bar silently.

### Where the interview lives

- **Chosen: one loop at step 4; step 1 shrinks to launching it.** `design-critic` found step 1's
  existing rule — "Don't draft the issue until shape-defining ambiguity is actually resolved" —
  makes the new loop's trigger unreachable, and leaves two owner-facing interviews four steps apart
  with different bars and no stated relationship. Consolidating puts every question in the mouth of
  the agent that has read the code.
- **Rejected: keep both with a hard division** (step 1 shape, step 4 detail, no re-asking). Less
  rewriting; the shape/detail boundary blurs in practice and the owner still sits through two
  interviews.
- **Rejected: move the loop into step 1 and keep `product-manager` a single spawn at the end.**
  `design-critic` raised this as the simplest option — `groom`'s own session already holds the
  conversation, dissolving the record plumbing entirely. Rejected because the questions would come
  from an agent that has not read the code, which is most of what makes a question worth asking
  here, and `product-manager` would get one shot at the end. That is today's behaviour with more
  owner questions in front of it.

### Owner technical direction

- **Chosen: a verbatim `## Technical direction` section, passed to `architect` by `activate`.**
  Reuses the mechanism `activate` already has for `type:tech-debt`'s `## Direction`.
- **Rejected: capture now, wire the hand-off in a later issue.** Stays strictly inside the issue's
  boundary; ships a section no downstream agent reads.
- **Rejected: put the notes in Scope as constraints.** Reaches `architect` today with no `activate`
  change, but architecture and performance notes are not scope, and it muddies the one section the
  whole pipeline keys off.

### Exit behaviour

- **Chosen: a closing pass, with its assumptions split by provenance.** The owner asked for bulk
  confirmation; `design-critic` found that bulk-confirming a list and promoting all of it into
  Acceptance criteria launders agent-authored scope into owner-traceable lines, at the moment the
  owner is least attentive — and that promotion grants the stronger status to the weaker signal,
  since a skipped item stays visibly hedged while a skimmed one becomes indistinguishable from
  something the owner wrote. The split keeps the bulk affordance and closes the route.
- **Rejected: no closing pass.** The owner's last answers never reach the agent, and `groom` would
  fold them in itself — `groom` authoring scope lines is what the traceability rule exists to stop.
- **Rejected: bulk confirmation that never promotes.** Safest, but with the general hand-off
  deferred, assumptions reach no downstream agent, so confirming them would achieve little.

## Domain Facts

From the skill-authoring research consult, verified against the tree:

- **No skill in `plugins/` lets a subagent decide when a loop ends.** The one real multi-round loop,
  `implement`'s review/fix panel, has the caller recompute the verdict:
  `missingLenses.length === 0 && reviews.every(r => r.approve) && mustFix.length === 0`.
- **A declining agent must justify the decline.** A lens returning `approve:false` with no
  blocker/major finding gets a finding synthesized *for* it (`unexplained-non-approval`), so its
  non-approval flows through the same pipeline as a real one. A silent agent is never counted as an
  approval.
- **Plain subagents cannot be resumed.** Each round is a new agent with no memory beyond what the
  caller re-supplies — stated in `implement`'s docs-fast-path, which respawns fresh with the answer
  plus the original prompt.
- **Convergence state held inside an agent does not survive respawn.** The refactor circuit breaker
  is the worked example: a fresh agent's in-run counter resets, so the script must not run a fix
  round after a trip.
- **The repo's standing answer to loop bounding is a repo-owned numeric cap plus a defined failure
  state, never a model-owned one** — but every such loop runs unattended, which this one does not.
- **`architect`, `design-critic` and spec generation all receive only the issue's scope and
  acceptance criteria**; the review panel reads the spec, not the issue. Notes/context reaches no
  downstream agent, which is why `## Technical direction` needs an explicit hand-off.

## Risks & impact

- **Owner fatigue is the primary risk.** Three mitigations are load-bearing: the per-round question
  cap of three, the requirement that a question name what it would change, and round-1 convergence
  being an explicitly normal outcome for a small idea.
- **The readiness bar is applied by an LLM, not a parser.** Applied loosely it lets a vague criterion
  through; applied strictly it can chase detail that belongs to the architect. Scoping bar item (c)
  to *behavioural* assumptions is what gives it a reachable fixed point.
- **The no-new-questions stop depends on recognizing a paraphrase.** Recording each answer with the
  question it answered is what makes that tractable; it is still judgment, not string matching.
- **Cost and latency.** Grooming becomes several subagent rounds instead of one, each re-reading some
  of the repo.
- **`activate` is touched.** One narrow addition, but it puts this change on a file owned by another
  part of the pipeline.
