---
name: archive
description: Flush spec-flow's shared archive queue (spec-flow/archive-queue) into one batch PR against the default branch and merge it. Every /spec-flow:finalize appends its issue's OpenSpec archive commit onto that queue instead of opening its own PR — this is what actually lands the queue on main. Owner-invoked, session-driven, never polled or scheduled — run it whenever you want the queue landed. Part of the flow delivery workflow (see docs/workflow.md).
---

# archive — batch-flush the queued OpenSpec archives

You are the central `project-manager` (this isn't tied to any one issue, so it's yours to run, the
same way `board`/`groom`/`adopt-tiering` are — no `issue-pm` involved). Every finalized issue's
OpenSpec archive commit sits queued on `spec-flow/archive-queue` until this runs; nothing lands on
the default branch until you flush it. There's no automatic schedule — this plugin is
session-driven, not cron (see **Substrate and constraints** in `docs/workflow.md`), so "periodic"
means "whenever you decide to," not a timer.

## Steps

1. **Check whether anything's actually queued** before running the script — cheap, and lets you
   tell the owner "nothing to flush" without even attempting a PR:
   ```bash
   git ls-remote --exit-code --heads origin spec-flow/archive-queue
   ```
   Exit code non-zero → nothing queued (every finalized issue since the last flush already got
   landed, or nothing has finalized yet). Say so and stop; nothing else to do.

2. **Flush it:**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/archive-flush.sh
   ```
   Opens (or reuses, if an earlier flush was interrupted before merging) one PR from
   `spec-flow/archive-queue` into the default branch, titled with how many issues' archives it
   bundles, and merges it — squash, so the batch lands as one clean commit on `main` regardless of
   how many issues fed into it. Deletes the queue branch on success; the next `/spec-flow:finalize`
   recreates it fresh from `main`.

3. **Report.** If the script succeeded, tell the owner how many issues' archives just landed. If it
   exited non-zero (required checks still pending, or branch protection needs a review on this
   repo), relay its message verbatim — the PR is still open, re-run this skill (or merge it
   yourself in GitHub) once it clears.

## Rules

- **Never invent a schedule.** Don't suggest running this "every night" or wire it to anything
  automatic — the owner decides when, that's the whole point of it being session-driven. `board`
  can surface that N issues are queued so the owner *notices*; it never triggers this on its own.
- **This never touches the feature PR mechanics.** It only ever operates on
  `spec-flow/archive-queue` → default branch — a completely separate, code-free bookkeeping lane
  from the issues' own feature branches and PRs.
- If the queue branch doesn't exist, that's not an error — it means nothing's been finalized since
  the last flush (or ever). Say so plainly rather than treating it as a failure.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
