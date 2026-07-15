---
name: board
description: Report status across all in-flight delivery pipelines — every issue by lifecycle label with its priority, stage, worktree, and PR state — and highlight what's next and what's blocked on the owner. Use when the owner asks 'where do things stand' or 'what should I work on'. Part of the flow delivery workflow (see docs/workflow.md).
---

# board — status across all in-flight pipelines

You are the PM/lead in the main session. Give the owner one view of the whole pipeline,
derived from GitHub labels + PR state + worktrees. Read-only; you don't change anything.

## Steps

1. **Gather issues by lifecycle:**
   ```bash
   gh issue list --state open --json number,title,labels,url --limit 100
   ```
   Bucket by the `status:*` label; read the `P?` label as priority. Issues carrying **no
   `status:*` label** are the raw backlog — not yet groomed, so no `P?` either. Keep them
   separate; they're the fallback when nothing labeled is actionable.

2. **Gather PR state** for branches `issue-*`:
   ```bash
   gh pr list --state open --json number,headRefName,title,reviewDecision,url --limit 100
   ```

   Then **gather CI state for each open `issue-*` PR** — an `in-review` PR is only actionable
   by the owner once CI is green; while CI runs there is nothing for them to do:
   ```bash
   gh pr checks <PR> --json name,state,bucket   # per PR; bucket ∈ pass/fail/pending/skipping
   ```
   Roll the checks into one CI status per PR: **green** (all required checks pass), **running**
   (any required check still pending/queued), or **failing** (any required check failed). Treat
   `skipping` (e.g. deploy-pages off a PR) as not-required.

3. **Gather worktrees:**
   ```bash
   git worktree list
   ```

4. **Render a board** grouped by stage, priority-sorted within each group. An `in-review` PR
   goes under **BLOCKED ON YOU only when its CI is green**; while CI is running it goes under
   **IN FLIGHT** with its CI state, because the owner has nothing to act on yet:

   ```
   ## Delivery board

   ⛳ BLOCKED ON YOU
     spec-review   #N P1  <title>                  → review spec in worktree, then /spec-flow:implement <N>
     in-review     #M P0  <title>  PR #P  ✅ CI     → review in GitHub: <url>

   🔧 IN FLIGHT (agents / CI)
     in-review     #M P1  <title>  PR #P  ⏳ CI     (awaiting CI — not on you yet)
     in-review     #M P1  <title>  PR #P  ❌ CI     (CI failing — /spec-flow:sync-ci)
     in-progress   #K P2  <title>                  (worktree present)
     addressing    #J P1  <title>  PR #Q           (resolving your comments)

   📋 READY
     ready         #L P0  <title>                  → /spec-flow:activate <L>   ← next up

   📥 BACKLOG (ungroomed)
     (no labels)   #H     <title>                  → /spec-flow:groom <H>

   (worktrees: 3 active · open PRs: 2)
   ```

5. **Call out the two things that matter most:**
   - **Next up** — ranked by **distance to landed**, not just priority label, walking this ladder
     until something applies: (1) a `status:in-review` PR **whose CI is green** — one merge away
     from shipping, and `/spec-flow:finalize` can't run until it merges; (2) the highest-priority
     `status:ready` issue to activate; (3) if nothing is `status:ready` either, the highest-value
     **BACKLOG** issue to groom — and if it looks too large to spec and land as one unit, say so
     and suggest splitting it into smaller issues instead. **Keep the train moving** — landing
     what's already close beats starting something new, and starting something small beats
     reporting a stall.
   - **Blocked on you** — your seams: anything in `status:spec-review` (approve the spec) and any
     `status:in-review` PR **whose CI is green** (review/merge in GitHub). An `in-review` PR with
     CI still **running** is NOT blocked on you — surface it under IN FLIGHT as awaiting CI, and a
     PR with **failing** CI as needing `/spec-flow:sync-ci` (pull the failures into the branch's
     flagged set, then re-run the fix loop), not as your action.

## Rules

- Read-only. Never change labels, push, or merge from this skill.
- **Always pair a number with a description.** Every issue/PR number you render carries a brief
  `(description)` — `#85 (field identity)`, `PR #97 (test-rigor agent)` — never a bare `#85`. The
  owner does not track raw numbers. (Workflow convention; see docs/workflow.md.)
- Sort within each group by priority (`P0` first).
- If a `status:*` label and the PR state disagree (e.g. labeled in-review but PR merged),
  flag the drift so the owner can run `/spec-flow:finalize`.
