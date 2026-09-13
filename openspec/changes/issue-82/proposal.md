## Why

When an agent brings the owner findings or decisions, two failures repeat and compound each other.

First, agents name findings by internal identifiers. The review panel's lenses tag their findings
`C8`, `SEC-3`, `F1`, `OBS-1`. Those tags are internal to the panel's JSON contract. They mean
something to the lens that emitted them and to nothing else. Agents then relay them to the owner as
if they were shared words: "should I fix C8 and SEC-3 before Build?" The owner does not know what
those are. The same happens with `file:line` references, spec scenario titles, and task numbers used
as though the owner had them open.

Second, agents hand the owner several decisions at once. A single message carries four or five
choices, each with options. The owner cannot answer a batch. The owner must scroll back past detail
to find the one thing being asked.

Both happened in one session on issue 77: five findings, all named by lens code, none described.

The rule exists in two skills already (`groom` step 1, `activate` step 1) and in the owner's own
`CLAUDE.md`. It does not bind the path where it breaks: an agent relaying panel findings, or any
agent presenting a list of choices. This change makes the rule a single contract that binds every
owner-facing presenter in the plugin, so all skills present consistently.

## What Changes

- **A single presentation contract lands in `docs/workflow.md`.** It states four rules: plain terms
  before any identifier; one decision at a time by default; the owner may override to a batch; every
  option states its cost and marks the recommended one where one exists. It names the deliberate
  batch presentations it does not govern (status summaries, whole-artifact reviews).
- **Every owner-facing presenter is bound to the contract, and its concrete emitting instructions
  are fixed in place** — not merely pointed at the contract. The bound files are
  `agents/issue-manager.md`, `skills/implement/SKILL.md`, `skills/address/SKILL.md`,
  `skills/activate/SKILL.md`, `skills/groom/SKILL.md`, `skills/setup/SKILL.md`, and
  `agents/project-manager.md`.
- **The 0.46.0 sentence in `issue-manager.md` is reworded.** Today it reads "never cite a spec
  section by its identifier," which forbids even the trailing tag this contract allows. It is
  reworded to forbid an identifier only as the subject or the sole referent.
- **`groom`'s "the only exception" claim is reconciled.** `groom` step 4 calls its bulk assumption
  confirm "the only exception to the one-question rule." The contract now names several deliberate
  batch presentations, so that line is reworded to point at the contract's list instead of claiming
  to be the only one.
- **`activate` step 1 gains the missing half.** It states "one at a time" but omits the
  recommended-default half that `groom` states. The contract's "mark the recommended option where
  you have one" is added there.
- **The plain-terms rules apply to asynchronous artifacts too.** A finding written into a PR body or
  an issue comment must also be stated in plain terms, with the identifier as a trailing tag only.
  The "one at a time, wait for an answer" rule applies to interactive decision points, where the
  owner answers before the next.

## Scope

**In:** the presentation contract in `docs/workflow.md`; compliant edits to every owner-facing
presenter listed above; the reword of the 0.46.0 sentence; the reconcile of `groom`'s "only one"
line; the `activate` step 1 addition.

**Out:** the panel's JSON contract (lenses keep emitting identifiers); the agent-to-agent channel
(an identifier passed lead to fix agent is correct and stays); re-litigating the one-at-a-time rule
where it already works.
