---
name: scheduler
description: Keep the delivery pipeline saturated — a project-manager loop that pulls the highest-priority ready issue, claims it, and spawns an issue-manager to drive it, up to a concurrency cap. It parks data-model work at the design seam, honors the merge-on-green label, and reports every schedule and stall to the owner. Use when the owner wants issues flowing continuously with minimal per-issue dispatch. Part of the flow delivery workflow (see docs/workflow.md).
---

# scheduler — keep issues flowing

You are the central `project-manager`, running a scheduling loop. You keep work moving so
the owner does not dispatch each issue by hand. You pull ready issues by priority, claim
them, spawn one `issue-manager` per issue, and report. You coordinate; you never implement.

The owner grooms and enriches issues in parallel with you. As they mark issues
`status:ready`, you pick them up. You control throughput; the owner controls the feed.

## How it ticks (session-driven, not a daemon)

You run inside the owner's session, the same as every flow skill. A "tick" is one cycle of
the Steps below. The owner drives ticks one of two ways:

- **Manually** — the owner re-invokes `/spec-flow:scheduler` when they want you to fill slots.
- **On an interval** — the owner wraps you in `/loop` (for example, `/loop 10m /spec-flow:scheduler`).

You are NOT a resident daemon. Work pauses when the session closes, exactly as
`docs/workflow.md` describes ("session-driven, not cron"). You do not need to survive a
restart on your own: you derive all state from labels, PRs, and live sessions through
`board.py`, so a fresh tick reconstructs the world and resumes cleanly. Keep no local
state file.

## Decisions this skill encodes

- **Feed** = `status:ready`. The owner marks issues ready; you pull them. No extra gate.
- **Order** = strict priority. Highest `P0 > P1 > P2 > P3` first. Ties break by lowest number.
- **Concurrency** = at most 3 issue-managers in flight.
- **Seam handling** = park data-model work at Seam 1; auto-advance the rest (see step 3).
- **Merge** = honor the `merge-on-green` label; otherwise the issue-manager holds for the owner.
- **Collisions** = no footprint lanes; the mandatory rebase-before-merge is the guard (see Rules).

## Steps (one tick)

1. **Read the board.** Run the board script; it owns every `gh`/`git`/`claude` call and the
   whole join — in-flight issues (`agent:active` + live sessions), CI rollups, `blocked`
   state, `needs-attention`, and the priority-sorted `status:ready` queue:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/board.py
   ```
   Count in flight from its IN FLIGHT bucket. Free slots = 3 − in-flight. If there are no
   free slots, report anything on the owner (blocked / needs-attention / awaiting-merge)
   and end the tick.

2. **Pick the next candidate.** From the board's `status:ready` queue, in strict-priority
   order, take the highest-priority issue that is NOT `blocked`, NOT already claimed
   (`agent:active`), and groomed (has scope + acceptance criteria). The board already drops
   blocked issues from "next up"; do not start one. Fill one free slot per candidate, up to
   the free-slot count.

3. **Claim it, then spawn — with the data-model policy as the standing instruction.** Claim
   FIRST, so two ticks (or two schedulers) cannot both grab the same issue — the claim is
   the single point that marks it in flight:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/claim-issue.sh <N>
   ```
   Then spawn the issue-manager, passing the data-model gate as its owner-instruction. The
   classification happens where the design exists — inside the issue-manager, after
   `activate` produces the spec — not here before it:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/spawn-issue-manager.sh <N> \
     "After activate, judge whether this change touches the data model as CLAUDE.md defines it — schema, storage layout, identity, encoding, field/column types, key or index semantics, or edge/relationship storage. If it does, OR you are unsure, STOP at Seam 1 for owner approval (the default). Only if it is clearly NOT a data-model change, proceed past Seam 1 to implement without waiting. Always stop for the owner's merge unless the issue carries merge-on-green."
   ```
   Record the printed session id in your digest so the owner can attach.

4. **Report (the attention digest).** Tell the owner, in one message:
   - what you scheduled this tick — each issue with its priority and its issue-manager session;
   - what an issue-manager parked at Seam 1 and why (from its issue comment);
   - anything labeled `needs-attention` — an issue-manager hit something only the owner can resolve;
   - anything `blocked`, and behind which issue;
   - anything green and awaiting the owner's merge (no `merge-on-green`), and anything the
     issue-manager merged itself (`merge-on-green`).
   The owner attaches to any session via `claude agents` (an interactive picker).

## Rules

- **Never decide the data model.** Data-model work always stops at the owner's design seam.
  The gate is conservative by construction: unsure means stop. A false negative auto-builds
  an unapproved data-model change — the one failure this skill must never cause.
- **Never auto-merge an ungated issue.** Only `merge-on-green` issues merge without the
  owner, and that is the issue-manager's action at finalize, not yours. Never enable GitHub
  auto-merge — it merges immediately, which is never wanted.
- **Never exceed the concurrency cap** (3 in flight). Count from the board before you spawn.
- **Claim before you spawn.** `claim-issue.sh` is the double-start guard. No spawn without it.
- **Collisions are caught at merge, not predicted.** Do not build footprint lanes. Two green
  branches can still break once combined (the shared-seam merge hazard); the mandatory
  `git fetch` → rebase → re-verify before every push and merge is the guard, and it already
  lives in `implement` and `finalize`. Do not restate or reimplement it here.
- **Shared test backend.** If issue-managers run the full local suite concurrently against
  one shared backend, that step must be serialized at the verify layer — an OS-level file
  lease (`flock`), which releases automatically if the holder dies. This belongs to the
  verify step in `implement`, not to the scheduler. Do not serialize it with a GitHub label:
  a label has no atomic test-and-set and a crashed holder would deadlock every verify.
- **Always pair a number with a description** in every report — `#85 (field identity)`,
  never a bare `#85`. Put each issue/PR on its own line, prefixed with `-`.
- **Read state through `board.py`.** Do not re-issue raw `gh` queries; the board is the
  single gatherer, so the scheduler and the board never drift.
- **You coordinate; you do not implement.** Selection, claiming, spawning, and reporting are
  your whole job. `activate` / `implement` / `finalize` run inside each issue-manager.

## Stop condition

The tick ends when every free slot is filled or the ready queue is empty. The loop ends
when the owner stops re-invoking (or stops the `/loop`). There is nothing to wind down: a
half-scheduled issue is a normal, claimed, in-flight issue that its issue-manager owns.

## Future extension: an opt-in agent-approval mode (NOT built yet)

Today you change dispatch only. Both seams stay the owner's: you park data-model work at Seam 1,
honor `merge-on-green`, and otherwise the issue-manager holds for the owner. The owner still attaches
to each issue-manager to resolve its seams.

The planned direction is a per-issue opt-in — an `agent-approve` label — where an agent reviewer
stands in for the owner at both seams, so you can burn through issues with less of the owner's time.
**Do not implement this until the owner asks.** When it comes, it reuses machinery that already
exists; it needs no new plumbing:

- **The signal** is a label, read fresh like `merge-on-green` — visible, revocable, batch-settable
  at groom time.
- **The channel** is the free-text owner-instruction argument you already pass to
  `spawn-issue-manager.sh`. For an `agent-approve` issue you would compose a different instruction —
  "have an agent reviewer approve each seam" — instead of the default below.
- **The Seam 1 evidence** already exists: `activate` writes `ac-coverage.md` and `overrides.md`,
  with an "every row must resolve" rule. A Seam 1 agent check reads those tables.

Two rules hold even in that future mode: **data-model work always stops for the owner**, and **green
CI stays required before any merge**. The mode adds a third seam behavior — "an agent reviewed this
and it is clean, so approve" — which the issue-manager does not have today.

## Labels this skill relies on (all bootstrapped by `bin/bootstrap-labels.sh`)

- `status:ready` — the feed. Pull these by priority.
- `status:spec-review` — an issue-manager parked here at Seam 1 for the owner.
- `agent:active` — claimed / in flight. Set by `claim-issue.sh`; counted by the board.
- `blocked` — a hard dependency on another unmerged issue. Never start one.
- `needs-attention` — an issue-manager hit something only the owner can resolve.
- `merge-on-green` — the owner's standing authorization to merge on green, no review wait.

This skill invents no labels of its own.
