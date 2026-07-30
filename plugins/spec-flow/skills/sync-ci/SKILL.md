---
name: sync-ci
description: Pull the branch's latest CI test failures into the issue's local flagged set — download the spec-flow-failures artifact from the most recent CI run and append the failing test ids to .spec-flow/flagged-tests in the worktree, so the local loop runs them for the rest of the branch. Part of the flow delivery workflow (see docs/workflow.md, "Test tiering"). Owner-invoked when CI reports red; never polls.
argument-hint: [issue number, or its PR number]
---

# sync-ci — pull CI failures into the local flagged set

You are the PM/lead for this issue — typically that issue's `issue-pm` subagent, or the central
coordinator if invoked directly. CI ran the full suite on issue `#N`'s branch and
something failed. Pull those failures into the branch's **flagged set** so the fast local loop
(`/spec-flow:implement`'s gate and your own runs) guards them for the rest of the branch. This is
owner-invoked — run it when you see CI go red — there is **no polling**.

Input: an issue number `#N` (or its PR number). Worktree `.claude/worktrees/issue-<N>-<slug>`,
branch `issue-<N>-<slug>`. If `<slug>` isn't already known from context, recover it with
`git worktree list | grep "issue-<N>-"` or `gh pr list --search "head:issue-<N>-" --json headRefName`.
See **Test tiering (unit / integration)** in `docs/workflow.md` for the
model: the unit tier runs locally every cycle; a CI-caught test is added here and run locally until
the branch merges, then evaporates.

## Steps

1. **Resolve the branch and its latest CI run.**
   ```bash
   BR=issue-<N>-<slug>
   # Most recent completed run for this branch:
   gh run list --branch "$BR" --json databaseId,status,conclusion,workflowName,createdAt \
     --limit 10
   ```
   Pick the most recent **completed** run whose `conclusion` is `failure`. If the latest run is
   still in progress, say so and stop — don't act on a half-finished run. If the latest completed
   run is green, there's nothing to sync: say so and stop.

2. **Download the failures artifact.** The consuming repo's CI uploads failing test ids as an
   artifact named `spec-flow-failures` (the CI contract — see `references/ci/`). Fetch it:
   ```bash
   TMP=$(mktemp -d)
   gh run download <run-id> -n spec-flow-failures -D "$TMP" 2>/dev/null \
     || { echo "no spec-flow-failures artifact on this run"; }
   ```
   If the run failed but produced **no** `spec-flow-failures` artifact, the failure wasn't a test
   failure (e.g. a build/lint break, or CI isn't wired to the contract yet). Report that plainly —
   there's nothing to add to the flagged set — and point the owner at `references/ci/` if CI needs
   wiring. Do not invent entries.

3. **Ensure `.spec-flow/` is gitignored** (idempotent, one-time; the flagged set must never commit):
   ```bash
   cd <worktree>
   grep -qxF '.spec-flow/' .gitignore 2>/dev/null \
     || { printf '\n# spec-flow local flagged tests (never commit)\n.spec-flow/\n' >> .gitignore; \
          git add .gitignore && git commit -m "chore: gitignore .spec-flow/ (flagged tests)"; }
   ```

4. **Append the failing ids to the flagged set** (dedup; keep what's already there — the set
   accumulates across the branch's life). Diff the incoming ids against what's already flagged
   *before* merging, so step 5 can tell the owner which are new vs. repeat failures — an id
   failing again after a fix round is either still broken or flaky, worth calling out rather than
   folding silently into the merge:
   ```bash
   mkdir -p <worktree>/.spec-flow
   FLAG=<worktree>/.spec-flow/flagged-tests
   touch "$FLAG"
   INCOMING=$(cat "$TMP"/* 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | sort -u)
   NEW=$(comm -23 <(echo "$INCOMING") <(sort -u "$FLAG"))
   REPEAT=$(comm -12 <(echo "$INCOMING") <(sort -u "$FLAG"))
   # Merge new ids in, preserving existing, dropping blanks/duplicates:
   cat "$FLAG" "$TMP"/* 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' \
     | sort -u > "$FLAG.new" && mv "$FLAG.new" "$FLAG"
   ```
   Each line is a runner-selectable test id in the same form CI emitted (a JUnit `Class.method`, a
   nextest `test(=path)` / test path). The local gate expands these alongside the unit-tier command.

5. **Report.** Tell the owner which test ids are newly flagged (`$NEW`) and which are repeat
   failures already in the set (`$REPEAT` — still broken or flaky, call it out explicitly), plus
   the total now in the flagged set, and that the next local run — `/spec-flow:implement`'s gate
   or a manual run — will include them. Then the loop is: fix on the branch (tests stay green
   locally including the flagged ones), push, CI re-runs the full suite; when it's green and the
   owner merges, the flagged set evaporates with the worktree at `/spec-flow:finalize`.

## Rules

- **Owner-invoked, never polls.** Run it when CI reports red; there is no watch loop.
- **Never fabricate entries.** Only ids that came from the `spec-flow-failures` artifact go in. A
  failed run with no artifact means "not a test failure" or "CI not wired" — report, don't invent.
- **The flagged set is local and gitignored** — it never commits and never leaves the branch.
- **Additive + idempotent.** Re-running after another red CI run merges new ids without dropping the
  ones already being guarded; running when CI is green is a no-op.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
