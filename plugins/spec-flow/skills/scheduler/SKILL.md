---
name: scheduler
description: Keep the delivery pipeline saturated — a project-manager loop that pulls the highest-priority ready issue and spawns an issue-manager to drive it, up to a concurrency cap. Both owner seams stay the owner's; the issue-manager holds at both by default, honors the merge-on-green label, and the scheduler reports every schedule and stall to the owner. Use when the owner wants issues flowing continuously with minimal per-issue dispatch. Part of the flow delivery workflow (see docs/workflow.md).
---

# scheduler — keep issues flowing

You are the central `project-manager`, running a scheduling loop. You keep work moving so
the owner does not dispatch each issue by hand. You pull ready issues by priority, spawn one
`issue-manager` per issue, and report. Each `issue-manager` claims its own issue as its first
step; you never pre-claim. You coordinate; you never implement.

The owner grooms and enriches issues in parallel with you. As they mark issues
`status:ready`, you pick them up. You control throughput; the owner controls the feed.

## How it ticks (session-driven, not a daemon)

You run inside the owner's session, the same as every flow skill. A "tick" is one cycle of
the Steps below. The owner drives ticks one of two ways:

- **Manually** — the owner re-invokes `/spec-flow:scheduler` when they want you to fill slots.
- **On an interval** — the owner wraps you in `/loop` (for example, `/loop 10m /spec-flow:scheduler`).

`10m` is the intended cadence. Each tick runs `board.py`, which makes several `gh` calls, and an
issue-manager takes far longer than a minute to reach a seam. A sub-minute interval mostly re-reads
the same state and risks `gh` rate limits; it never breaks correctness (the concurrency cap and the
spawn guard hold at any cadence), but it wastes calls. Match the interval to how fast the board
actually changes.

You are NOT a resident daemon. Work pauses when the session closes, exactly as
`docs/workflow.md` describes ("session-driven, not cron"). You do not need to survive a
restart on your own: you derive all state from labels, PRs, and live sessions through
`board.py`, so a fresh tick reconstructs the world and resumes cleanly. Keep no local
state file.

## Decisions this skill encodes

- **Feed** = `status:ready`. The owner marks issues ready; you pull them. No extra gate.
- **Order** = strict priority. Highest `P0 > P1 > P2 > P3` first. Ties break by lowest number.
- **Concurrency** = at most 3 issue-managers in flight.
- **Seam handling** = both seams stay the owner's. The issue-manager holds at both by
  default — exactly as if the owner dispatched the issue. The scheduler mandates no
  auto-advance for any class of issue; the owner opts individual issues into auto-approval
  through labels (see Rules and the Future-extension section).
- **Merge** = honor the `merge-on-green` label; otherwise the issue-manager holds for the owner.
- **Collisions** = no footprint lanes. The owner's manual merge is rebased by the owner; the
  `merge-on-green` auto-merge path is not rebased today, so it carries a real gap at concurrency
  (see Rules).

## Steps (one tick)

1. **Read the board.** Run the board script; it owns every `gh`/`git`/`claude` call and the
   whole join — in-flight issues (`agent:active` + live sessions), CI rollups, `blocked`
   state, `needs-attention`, and the priority-sorted `status:ready` queue:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/board.py --ready-limit 100
   ```
   Pass `--ready-limit 100`. The board renders only the top 5 `📋 READY` rows by default, so if
   the 5 highest-priority ready issues are all `blocked`, the default view would hide every
   unblocked candidate behind them and the scheduler would stall with slots free. A high limit
   shows the whole queue, so step 3 always sees an unblocked candidate if one exists.

   The IN FLIGHT bucket counts every issue past `status:ready`, whether or not a live session
   backs it — so a crashed issue-manager still counts. Do not compute free slots yet; run the
   recovery pass (step 2) first, so a dead session does not hold a slot forever.

2. **Recover stalled or dead-claimed issues.** Read the board's liveness markers on the IN
   FLIGHT rows. Two markers mean the issue is in flight but nothing is driving it:
   - `🔴 STALLED — no agent:active label` — the claim was dropped; nothing owns it.
   - `🟡 claimed — agent:active set, no session on this machine` — claimed, but no live local
     session (a crashed local session, or one on another machine).

   For each such row, re-run the spawn script and trust its exit code — do not decide the
   cause yourself:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/spawn-issue-manager.sh <N>
   ```
   The script self-heals: a crashed local session respawns; a session live on another machine
   makes it refuse (exit non-zero), which is correct — do not duplicate it. Record each outcome
   for the digest: recovered, or left for the owner (still stalled, or running elsewhere).

3. **Compute free slots, then pick the next candidate.** Free slots = 3 − in-flight, counted
   from the IN FLIGHT bucket after recovery. If there are no free slots, skip to the report.
   Otherwise, from the board's `status:ready` queue, in strict-priority order, take the
   highest-priority issue that is NOT already claimed (`agent:active`) and NOT `blocked`.
   `status:ready` is the whole gate; the owner sets it in `groom` only after the readiness bar
   is met, so it already implies scope and acceptance criteria. Check the `blocked` marker
   yourself, on each candidate row: the board renders a `🔒 BLOCKED` marker on a blocked row,
   but it does not drop an unclaimed blocked issue from the `📋 READY` bucket, so a blocked row
   can still appear as a candidate. Skip any row that carries the marker. Fill one free slot
   per candidate, up to the free-slot count.

4. **Spawn — with the default seam policy. Do not pre-claim.** Spawn the issue-manager with no
   owner-instruction, so its default applies: it holds for the owner at both seams, exactly as
   if the owner dispatched the issue by hand. The scheduler adds no seam instruction of its
   own; it does not mandate auto-advance for any class of issue.
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/spawn-issue-manager.sh <N>
   ```
   Do NOT run `claim-issue.sh` first. The spawned issue-manager claims the issue as its own
   first step, inside `activate`. A pre-claim sets `agent:active`, which the spawn script reads
   as someone else's claim and refuses — so a pre-claim breaks the spawn. The spawn script is
   itself the double-start guard (see Rules). The issue-manager reads `merge-on-green` itself at
   finalize, so the scheduler passes no merge instruction either. If the owner opts an issue
   into auto-approval through a label, pass that as the owner-instruction instead (see the
   Future-extension section). Record the printed session id in your digest so the owner can
   attach.

5. **Report (the attention digest).** Tell the owner, in one message:
   - what you scheduled this tick — each issue with its priority and its issue-manager session;
   - what you recovered this tick, and anything still stalled or `🟡 claimed` that you could not
     recover (running elsewhere, or needing the owner) — so the owner learns why a slot is held;
   - what an issue-manager parked at Seam 1 and why (from its issue comment);
   - anything labeled `needs-attention` — an issue-manager hit something only the owner can resolve;
   - anything `blocked`, and behind which issue;
   - anything green and awaiting the owner's merge (no `merge-on-green`), and anything the
     issue-manager merged itself (`merge-on-green`).
   The owner attaches to any session via `claude agents` (an interactive picker).

## Rules

- **Never auto-advance any seam.** The scheduler spawns with the default; every issue holds
  at both seams for the owner. Data-model work is safe by that same default, so the scheduler
  needs no data-model classification of its own. Auto-approval is only ever a per-issue,
  owner-set opt-in (see the Future-extension section); even then, data-model work always stops
  for the owner and green CI stays required before any merge.
- **Never auto-merge an ungated issue.** Only `merge-on-green` issues merge without the
  owner, and that is the issue-manager's action at finalize, not yours. Never enable GitHub
  auto-merge — it merges immediately, which is never wanted.
- **Never exceed the concurrency cap** (3 in flight). Count the IN FLIGHT bucket after the
  recovery pass, before you spawn anything new.
- **Never pre-claim.** Do not run `claim-issue.sh` before `spawn-issue-manager.sh`. A pre-claim
  sets `agent:active`, which the spawn script reads back as an existing claim and refuses — so a
  pre-claim breaks every fresh spawn. `spawn-issue-manager.sh` is itself the double-start guard:
  its local-session lookup stops a same-machine double-spawn, and its `agent:active` check stops
  a cross-machine one. The spawned issue-manager claims the issue as its own first step, inside
  `activate` (which is where `claim-issue.sh` belongs).
- **Collisions are caught at merge, not predicted.** Do not build footprint lanes. Two green
  branches can still break once combined (the shared-seam merge hazard). On the owner's default
  path the owner rebases before their own squash-merge, which catches it (the rebase + squash
  merge convention in `docs/workflow.md`). The `merge-on-green` auto-merge path in `implement` does NOT rebase and
  re-verify before it merges today — it goes straight from a green required-checks watch to the
  squash-merge. So running the scheduler with `merge-on-green` at concurrency can merge a stale
  branch and break the default branch. This is a real gap this churn mode surfaces, not a guard
  already in place. Closing it — a `git fetch` → rebase → re-verify step before the auto-merge —
  is follow-up work in `implement`, not the scheduler. Until it lands, prefer the owner's manual
  merge for concurrent work.
- **Shared test backend (note for future work, not yet built).** If issue-managers run the full
  local suite concurrently against one shared backend, that step needs serialization at the
  verify layer — an OS-level file lease (`flock`), which releases automatically if the holder
  dies. No such serialization exists in `implement` today; this is a design note, not a guard in
  place. It belongs in `implement`'s verify step when built, not in the scheduler. Do not
  serialize it with a GitHub label: a label has no atomic test-and-set, and a crashed holder
  would deadlock every verify.
- **Always pair a number with a description** in every report — `#85 (field identity)`,
  never a bare `#85`. Put each issue/PR on its own line, prefixed with `-`.
- **Read state through `board.py`.** Do not re-issue raw `gh` queries; the board is the
  single gatherer, so the scheduler and the board never drift.
- **You coordinate; you do not implement.** Selection, recovery, spawning, and reporting are
  your whole job. Claiming, `activate`, `implement`, and `finalize` all run inside each
  issue-manager.

## Stop condition

The tick ends when every free slot is filled or the ready queue is empty. The loop ends
when the owner stops re-invoking (or stops the `/loop`). There is nothing to wind down. A
spawned issue is a normal, in-flight issue that its issue-manager owns. If a spawn died before
its issue-manager claimed and started, the next tick's recovery pass (step 2) re-drives it, or
reports it for the owner.

## Future extension: an opt-in agent-approval mode (NOT built yet)

Today you change dispatch only. Both seams stay the owner's: the issue-manager holds at both by
default — data-model work included — and honors `merge-on-green` at finalize. The owner still
attaches to each issue-manager to resolve its seams.

The planned direction is a per-issue opt-in — an `agent-approve` label — where an agent reviewer
stands in for the owner at both seams, so you can burn through issues with less of the owner's time.
**Do not implement this until the owner asks.** When it comes, it reuses machinery that already
exists; it needs no new plumbing:

- **The signal** is a label, read fresh like `merge-on-green` — visible, revocable, batch-settable
  at groom time.
- **The channel** is the free-text owner-instruction argument you already pass to
  `spawn-issue-manager.sh`. For an `agent-approve` issue you would compose a seam instruction —
  "have an agent reviewer approve each seam" — instead of spawning with no instruction, as step 4
  does today.
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
