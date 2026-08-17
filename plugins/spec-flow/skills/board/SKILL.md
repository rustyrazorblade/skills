---
name: board
description: Report status across all in-flight delivery pipelines — every issue by lifecycle label with its priority, stage, live issue-pm session, and PR state — and highlight what's next, what's blocked on the owner, and what's stalled. Use when the owner asks 'where do things stand' or 'what should I work on'. Part of the flow delivery workflow (see docs/workflow.md).
---

# board — status across all in-flight pipelines

You are the central `project-manager`. Give the owner one view of the whole pipeline, derived from
GitHub labels (including liveness and blocking, not just lifecycle) + PR state, cross-checked
against this machine's local sessions where they happen to match. Read-only; you don't change
anything.

## Steps

1. **Run the board script — it owns every `gh`/`git`/`claude` call and the entire join.** No raw
   GitHub JSON belongs in your context for this skill; the script fetches issues, PRs (correlated
   via `closingIssuesReferences`, not branch-name guessing), CI rollups, local `claude agents`
   sessions, and the OpenSpec archive-pending count, joins all of it, and prints the finished board
   text — bucketed (BLOCKED ON YOU / IN FLIGHT / READY / BACKLOG / EPICS), priority-sorted, with
   "next up" and stalled/blocked/needs-attention already computed:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/board.py
   ```
   Print its stdout directly to the owner — **this IS the board, not raw material to reformat or
   re-derive.** Pass `--user <login>` only if the owner explicitly wants it scoped to someone other
   than the authenticated `gh` user; the default (the authenticated user) is almost always right.

2. **Add the one judgment call the script can't make.** If its "Next up" line picked a BACKLOG
   issue to groom (nothing higher up the ladder was available), look at that issue and say in one
   line whether it looks too large to spec and land as one unit — suggest splitting it into smaller
   issues if so. This is genuine judgment (reading the issue's substance), not something
   mechanical; everything else in the render already reflects the rules below.

## Rules

- Read-only. Never change labels, push, or merge from this skill.
- **Don't re-derive the board from raw `gh`/`git` calls yourself.** This skill's entire point is
  that `board.py` already does the gathering, joining, classification, and formatting — hand-
  rolling any part of that in your own context (a `gh issue list` call, a Python one-liner to sort
  by priority, etc.) defeats it and burns far more context than printing the script's own output.
  If the render is missing something you need, that's a reason to extend the script (see its own
  docstring/rules below), not to patch around it inline.
- **If the script fails** (e.g. `gh`/`git` not on PATH, a real API error), relay its stderr
  verbatim and stop — don't silently fall back to querying GitHub yourself to paper over it.
- Every issue/PR number in your own added commentary (step 2) still carries a brief
  `(description)` — `#85 (field identity)`, never a bare `#85`. (Workflow convention; see
  `docs/workflow.md`.)

## Extending the board

The classification rules (what counts as "blocked on you", "stalled", the "next up" ladder,
epic exclusion, PR/CI correlation) live in `scripts/board.py` itself, not here — read its
docstring and the comments near each rule before changing behavior. If a rule needs to change,
change the script and re-run `scripts/test-board.sh` (fakes `gh`/`git`/`claude` on `PATH`, so it's
deterministic and doesn't touch real GitHub state) before trusting the new output.
