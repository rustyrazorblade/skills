---
name: finalize
description: Finalize a merged issue — sync the OpenSpec change's delta specs into the canonical specs, archive the change, remove its git worktree, and close the GitHub issue. Final stage of the flow delivery workflow (see docs/workflow.md). Runs after the owner squash-merges the PR in GitHub; it never merges.
argument-hint: [issue number, with its PR already squash-merged]
---

# finalize — sync, archive, and clean up after merge

You are this issue's `issue-pm`, running as your own dedicated background session. The owner has
**squash-merged** the PR for issue `#N` in GitHub. Sync and archive the OpenSpec change, tear down
the worktree, and close the issue. **This skill never merges** — the merge is the owner's action
in GitHub.

Input: an issue number `#N`, OpenSpec change `issue-<N>` — deterministic, from `activate`. You're
already running inside this issue's worktree — Claude Code's own background-session isolation put
you there, on whatever branch it assigned, so resolve the branch with
`git rev-parse --abbrev-ref HEAD` rather than assuming a name. If `openspec/changes/issue-<N>`
isn't there, list `openspec/changes/` (excluding `archive/`) — one change per issue, so whatever's
there is it — and orient yourself in it before proceeding: it may predate this naming, or be
mid-flight from an interrupted `activate`/`implement` pass.

## Steps

1. **Verify the PR is merged** (precondition — do not merge it yourself):
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   gh pr list --head "$BR" --state merged --json number,mergedAt
   ```
   If it isn't merged, stop and tell the owner the merge is theirs to do in GitHub.

2. **Create a short-lived worktree from merged main.** Resolve the **main** checkout first —
   `git worktree list --porcelain`'s first entry — the owner's primary checkout, not a per-issue
   worktree; never switch branches or pull there. Do the archive in an isolated, detached-HEAD
   worktree instead, so finalize never touches whatever the owner has checked out or in progress:
   ```bash
   MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
   git -C "$MAIN" fetch origin
   TMPWT=$(mktemp -d)
   git -C "$MAIN" worktree add --detach "$TMPWT" origin/main
   ```

3. **Sync delta specs into canonical specs, then archive the change** (inside `$TMPWT`). Use the
   OpenSpec flow for change `issue-<N>`:
   - `openspec-sync-specs` (or `/opsx:sync`) to fold the delta specs into `openspec/specs/`.
   - `openspec-archive-change` (or `/opsx:archive`) to move the change under
     `openspec/changes/archive/`.
   Commit the archive (this is the one place finalize commits to `main`, mirroring how prior
   changes were archived) and push it straight to `main`, then remove the temp worktree:
   ```bash
   git -C "$TMPWT" add -A
   git -C "$TMPWT" commit -m "archive: issue-<N>"
   git -C "$TMPWT" push origin HEAD:main
   git -C "$MAIN" worktree remove "$TMPWT"
   ```
   Leaving the archive commit unpushed would strand `origin/main` without it — the branch
   `/spec-flow:activate` cuts every new worktree from. If the repo prefers the owner push it
   themselves, stop before the push and surface the commit for them instead, but say so
   explicitly.

4. **Remove your own worktree and branch.** Resolve them from where you're standing — you never
   assumed a name for either — and remove them from `$MAIN` (a worktree can't remove itself while
   something's sitting in it):
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   WT=$(git rev-parse --show-toplevel)
   git -C "$MAIN" worktree remove "$WT"
   git -C "$MAIN" branch -D "$BR"                  # local — -D, not -d: a squash-merge commit is
                                                    # never an ancestor of the branch tip, so -d
                                                    # always refuses here
   git -C "$MAIN" push origin --delete "$BR"       # remote (optional; squash-merge may have removed it)
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
