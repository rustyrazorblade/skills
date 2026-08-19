## Context

Issue #45. `explain` was already extracted from spec-flow into standalone `review-tools` for the
same reason this issue gives for `tech-debt`: the skill's actual mechanism has no spec-flow
dependency, only its location did. An `architect` design consult ran during `/spec-flow:activate
45` (no domain-expert agent was consulted — not applicable to a plugin-relocation change in this
repo). The owner then made three decisions at the design-choice stop, two of which explicitly
override the architect's own recommendation.

## Goals / Non-Goals

**Goals:**
- Relocate the skill verbatim in mechanism; generalize only the prose that assumes spec-flow's
  presence.
- Update all six spec-flow files that reference the skill by its old command name/location.
- Make `project-manager`'s cadence recommendation degrade gracefully when `review-tools` isn't
  installed (issue AC #3), without introducing a new hardcoded cross-plugin dependency.
- No duplicate copy of the skill remains anywhere in the repo.

**Non-Goals:**
- No change to the audit's own SOLID/duplication/structure lens logic.
- No change to `architect`'s separate, smaller "nearby structural debt" in-context flag during
  `activate` — whether it should delegate to the moved skill is a separate, undecided question.
- No shared plugin-detection helper script factored out of the existing `EXPLAIN_ROOT`-style
  call sites (architect flagged this as worth a future issue; explicitly not bundled here).
- No true dynamic/pluggable discovery mechanism that would let an arbitrary third-party plugin's
  own "tech-debt-shaped" skill be picked up automatically — considered and explicitly deferred by
  the owner as real new design work beyond this issue's relocation charter.

## Alternatives Considered

**Decision 1 — how much the moved `SKILL.md` itself should say about spec-flow's fast-path
integration (the `## Direction` section, `type:tech-debt` label, etc.).**

*Architect recommended:* one short integration paragraph near the top, mirroring how `explain`'s
own `SKILL.md` mentions `SPEC_FLOW_SEAM_VIEW` — enough to signpost *why* `## Direction` is a
required, distinct section, without depending on spec-flow being present.

*Owner decision: no mention at all.* **Explicit override of the architect's recommendation.** The
moved skill reads as though spec-flow doesn't exist — genuinely standalone, not just
standalone-with-a-footnote. The "why" for `## Direction`'s strictness is left entirely to whichever
consuming pipeline needs it; spec-flow's own `docs/workflow.md` already explains it from its side,
and a review-tools-only reader who never files a `type:tech-debt`-shaped issue for a downstream
consumer doesn't need that context to use the skill correctly.

**Decision 2 — the plugin-detection mechanism for `project-manager`'s cadence recommendation.**

*Architect recommended:* reuse the existing `claude plugin list --json | jq '...
startswith("review-tools@")...'` snippet already inlined at three call sites (`activate`,
`implement`, `setup`) for `explain`'s own `EXPLAIN_ROOT` detection — Option A of "inline at each
call site" vs. "factor into a shared script," recommending inline as consistent with current
precedent.

*Owner pushed back on the premise itself*, not just the code-location choice: asked why an explicit
detection command was needed at all, then asked whether the check could be more loosely coupled —
generic enough that a different tool could satisfy the same recommendation without spec-flow
hardcoding a dependency on `review-tools` by plugin id.

*Explored and explicitly deferred:* a true pluggable-discovery mechanism — scanning
`claude plugin list --json` for *any* enabled plugin exposing a skill matching a documented
"tech-debt" naming convention, so a different plugin's own audit skill would be picked up with no
code change to `project-manager.md`. The owner agreed this is real new design work (defining and
documenting a discovery convention) beyond what a relocation issue should take on, and deferred it.

*Owner's actual decision: no explicit detection command of any kind.* `project-manager`'s cadence
recommendation is reworded as conditional prose — "if you have a tech-debt audit skill installed,
it's about due" — trusting the agent's own runtime awareness of which skills are actually available
to it (visible in its own skill listing) rather than shelling out to probe for a specific plugin id.
This is a **deliberate departure** from the `EXPLAIN_ROOT` precedent used elsewhere in spec-flow,
made with full awareness of that precedent, not from missing it — consistent with this repo's
existing preference for keeping swappable external tooling agent-driven and parameterized rather
than hardcoded (the same principle already applied to OpenSpec itself as a swappable backend).

**Decision 3 — command rename.**

Following the plugin's own directory/skill-name convention (matching `explain`/`walkthrough`), the
moved skill's command becomes `/tech-debt` (bare) / `/review-tools:tech-debt` (namespaced). Not
really an open choice — it follows automatically from the move — but the owner confirmed explicitly
since it's a breaking rename for anyone with muscle memory or scripts referencing
`/spec-flow:tech-debt`. No alias kept.

## Domain Facts

Not applicable — no domain-expert agent was consulted for this change (a plugin-relocation change
within this repo's own tooling, not a domain-specific question).

## Risks / Trade-offs

- **[Risk] The filed-issue `## Direction` section is a hard mechanical dependency, not decorative
  prose** — spec-flow's `activate` fast-path and `reviewer`'s tech-debt-mode gate on that heading
  being present verbatim in a filed issue. **[Mitigation]** the moved skill's step 6 (issue-filing
  template) is carried over unchanged in structure; only the surrounding provenance prose (which
  pipeline consumes it) is generalized away, never the `## Direction` heading itself or its
  requirement to be a distinct section.
- **[Risk] Removing the explicit `EXPLAIN_ROOT`-style detection check means `project-manager` can
  no longer be certain, at the moment it speaks, whether `review-tools` is actually installed** —
  it relies on its own runtime skill-availability awareness instead. **[Mitigation]** this is an
  accepted trade-off, not an oversight: the alternative (a hardcoded `review-tools@` id check) is
  exactly the tight coupling the owner wants to avoid, and an agent's own skill listing is itself a
  reliable, already-existing signal — no separate probe duplicates what the agent already knows.
- **[Risk] Breaking rename** (`/spec-flow:tech-debt` stops resolving) **→ [Mitigation]** none
  needed beyond the owner's explicit confirmation — this repo has one owner/operator, not a wide
  external user base with muscle-memory scripts to break.
