---
name: finalize
description: Finalize a merged issue — sync the OpenSpec change's delta specs into the canonical specs, archive the change, remove its git worktree, and close the GitHub issue. Final stage of the flow delivery workflow (see docs/workflow.md). Runs after the owner squash-merges the PR in GitHub; it never merges.
argument-hint: [issue number, with its PR already squash-merged]
---

# finalize — sync, archive, and clean up after merge

You are the PM/lead in the main session. The owner has **squash-merged** the PR for issue
`#N` in GitHub. Sync and archive the OpenSpec change, tear down the worktree, and close the
issue. **This skill never merges** — the merge is the owner's action in GitHub.

Input: an issue number `#N`. Worktree `.claude/worktrees/issue-<N>-<slug>`, branch
`issue-<N>-<slug>`, OpenSpec change `<slug>`. If `<slug>` isn't already known from context,
recover it with `git worktree list | grep "issue-<N>-"` or
`gh pr list --search "head:issue-<N>-" --json headRefName`.

## Steps

1. **Verify the PR is merged** (precondition — do not merge it yourself):
   ```bash
   gh pr list --head issue-<N>-<slug> --state merged --json number,mergedAt
   ```
   If it isn't merged, stop and tell the owner the merge is theirs to do in GitHub.

2. **Update local main** so the archive operates on merged content. `<repo-root>` is the
   owner's primary checkout, not a worktree — switching branches there is disruptive if it's
   mid-work, so confirm it's clean first:
   ```bash
   git -C <repo-root> status --porcelain   # must be empty; if not, stop and ask the owner
   git -C <repo-root> checkout main
   git -C <repo-root> pull origin main
   ```

3. **Sync delta specs into canonical specs, then archive the change.** Use the OpenSpec flow
   for change `<slug>`:
   - `openspec-sync-specs` (or `/opsx:sync`) to fold the delta specs into `openspec/specs/`.
   - `openspec-archive-change` (or `/opsx:archive`) to move the change under
     `openspec/changes/archive/`.
   Commit the archive on `main` (this is the one place finalize commits to main, mirroring how
   prior changes were archived) and push it:
   ```bash
   git -C <repo-root> push origin main
   ```
   Leaving the archive commit local would strand it out of sync with `origin/main` — the branch
   `/spec-flow:activate` cuts every new worktree from. If the repo prefers the owner push it
   themselves, surface the commit for them instead, but say so explicitly.

4. **Remove the worktree and branch:**
   ```bash
   git -C <repo-root> worktree remove ".claude/worktrees/issue-<N>-<slug>"
   git -C <repo-root> branch -D "issue-<N>-<slug>"        # local — -D, not -d: a squash-merge
                                                           # commit is never an ancestor of the
                                                           # branch tip, so -d always refuses here
   git -C <repo-root> push origin --delete "issue-<N>-<slug>"   # remote (optional; squash-merge may have removed it)
   ```

5. **Close the issue** (a PR with `Closes #N` usually auto-closes on merge — confirm, and
   close explicitly if still open). Remove the lifecycle label:
   ```bash
   gh issue view <N> --json state,closed
   gh issue close <N> 2>/dev/null || true
   gh issue edit <N> --remove-label status:in-review --remove-label status:addressing 2>/dev/null || true
   ```

6. **Report.** Confirm: specs synced, change archived, worktree removed, issue closed. Suggest
   `/spec-flow:board` to see the rest of the pipeline.

## Rules

- Never merge a PR. Confirm the owner already did before finalizing.
- Only finalize a merged PR — finalizing an unmerged one would archive un-landed work.
- Leave `main` clean: the only commit finalize makes to main is the OpenSpec archive, matching
  the repo's existing archive convention.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
