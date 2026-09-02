---
name: board
description: Report status across all in-flight delivery pipelines — every issue by lifecycle label with its priority, stage, live issue-manager session, and PR state — and highlight what's next, what's blocked on the owner, and what's stalled. Use when the owner asks 'where do things stand' or 'what should I work on'. Part of the flow delivery workflow (see docs/workflow.md).
---

# board — status across all in-flight pipelines

You are the central `project-manager`. Give the owner one view of the whole pipeline, derived from
GitHub labels (including liveness and blocking, not just lifecycle) + PR state, cross-checked
against this machine's local sessions where they happen to match. Read-only; you don't change
anything.

## Steps

**Run the board script — it owns every `gh`/`git`/`claude` call and the entire join.** No raw
GitHub JSON belongs in your context for this skill; the script fetches issues, PRs (correlated
via `closingIssuesReferences`, not branch-name guessing), CI rollups, local `claude agents`
sessions, and the OpenSpec archive-pending count, joins all of it, and prints the finished board
text — bucketed (BLOCKED ON YOU / IN FLIGHT / READY), priority-sorted, with "next up",
stalled/blocked/needs-attention, and counts for the unbounded categories (ungroomed backlog,
epics) already computed:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/board.py
```
Print its stdout directly to the owner — **this IS the board, not raw material to reformat or
re-derive.** Pass `--user <login>` only if the owner explicitly wants it scoped to someone other
than the authenticated `gh` user; the default (the authenticated user) is almost always right.

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
- Every issue/PR in your own added commentary (step 2) is written as `<number>: <title>` —
  `85: Field identity in the sync path`, never a bare `85`. Put each one on its own line, prefixed
  with `-`, even when there is only one; never run several together inline in a sentence.
  (Workflow convention; see `docs/workflow.md`.) The script's own aligned bucket rows are the
  documented exception — print them as-is, never reformat them into this shape.

## Extending the board

The classification rules (what counts as "blocked on you", "stalled", "claimed", the "next up"
ladder, epic exclusion, PR/CI correlation) live in `scripts/board.py` itself, not here. That file
is the single authority: each rule is stated in a comment beside the code implementing it. This
page covers invocation and output only, and deliberately does not restate any rule — read the
script before changing behavior. If a rule needs to change,
change the script and re-run `scripts/test-board.sh` (fakes `gh`/`git`/`claude` on `PATH`, so it's
deterministic and doesn't touch real GitHub state) before trusting the new output.
