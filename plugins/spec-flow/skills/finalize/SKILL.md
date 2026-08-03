---
name: finalize
description: Finalize a merged issue — close the GitHub issue, sync the OpenSpec change's delta specs into the canonical specs, archive the change via its own small PR, and remove the issue's git worktree. Final stage of the flow delivery workflow (see docs/workflow.md). Runs after the owner squash-merges the FEATURE PR in GitHub; never merges that one — the one PR this skill does merge itself is its own no-review archive-only bookkeeping PR (see step 3).
argument-hint: [issue number, with its PR already squash-merged]
---

# finalize — sync, archive, and clean up after merge

You are this issue's `issue-pm`, running as your own dedicated background session. The owner has
**squash-merged** the PR for issue `#N` in GitHub. Close the issue, sync and archive the OpenSpec
change, and tear down the worktree. **This skill never merges the feature PR** — that merge is the
owner's action in GitHub, always. The one exception, scoped narrowly: step 3's archive commit lands
via its own tiny PR that this skill opens *and* merges itself, because it's pure OpenSpec
bookkeeping with no code and nothing to review — not a carve-out for anything else.

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
   DEFAULT_BR=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   git -C "$MAIN" fetch origin
   TMPWT=$(mktemp -d)
   git -C "$MAIN" worktree add --detach "$TMPWT" "origin/$DEFAULT_BR"
   ```

3. **Sync delta specs into canonical specs, then archive the change** (inside `$TMPWT`). If
   `openspec/changes/archive/issue-<N>` already exists here, a previous finalize run already got
   this far — skip straight to step 4, nothing to redo. Otherwise, use the OpenSpec flow for
   change `issue-<N>`:
   - `openspec-sync-specs` (or `/opsx:sync`) to fold the delta specs into `openspec/specs/`.
   - `openspec-archive-change` (or `/opsx:archive`) to move the change under
     `openspec/changes/archive/`.
   Commit the archive, then land it on `main` **through a PR, not a direct push** — this repo's
   own rule against pushing straight to `main` applies to finalize too, and a repo with branch
   protection (the configuration `/spec-flow:adopt-tiering` tells owners to set up) would simply
   reject a direct push outright:
   ```bash
   git -C "$TMPWT" add -A
   git -C "$TMPWT" commit -m "archive: issue-<N>"
   ARCHIVE_BR="archive/issue-<N>"
   git -C "$TMPWT" push origin "HEAD:$ARCHIVE_BR"
   gh pr create --head "$ARCHIVE_BR" --base "$DEFAULT_BR" \
     --title "archive: issue-<N>" \
     --body "OpenSpec sync + archive for issue #<N>, now that its PR is merged. No code changes — bookkeeping only."
   if ! gh pr merge "$ARCHIVE_BR" --squash --delete-branch; then
     echo "archive PR for issue-<N> is open but didn't merge automatically (required checks still" >&2
     echo "pending, or branch protection needs a review) — merge it yourself: gh pr merge" >&2
     echo "$ARCHIVE_BR --squash --delete-branch (or in GitHub), then re-run finalize." >&2
     exit 1
   fi
   git -C "$MAIN" worktree remove "$TMPWT"
   ```
   This is the **one** PR this skill merges itself — see the frontmatter note on why. Don't let the
   archive PR merge silently fail and fall through to closing the issue anyway: leaving the archive
   commit unmerged would strand `main` without it — the branch `/spec-flow:activate` cuts every new
   worktree from.

4. **Close the issue** (a PR with `Closes #N` usually auto-closes on merge — check `state`/`closed`
   from the `gh issue view` below first, and only close/comment/relabel what isn't already done —
   this step is safe to re-run, but don't post a second "🎉" comment or re-attempt a close that
   already happened). Remove the lifecycle and coordination labels — closing doesn't drop them on
   its own, and a stray `agent:active` on a closed issue would misread as still live. **Do this
   before step 5, not after** — `gh issue` commands have no `-C`/path override, they infer the repo
   from wherever you're standing, and step 5 is about to remove that:
   ```bash
   STATE=$(gh issue view <N> --json state,closed)
   if [[ "$(jq -r .closed <<<"$STATE")" != "true" ]]; then
     gh issue comment <N> --body "🎉 Merged, archived, and closed."
     gh issue close <N> 2>/dev/null || true
   fi
   gh issue edit <N> --remove-label status:in-review --remove-label status:addressing \
     --remove-label status:in-progress --remove-label agent:active --remove-label blocked \
     2>/dev/null || true
   ```

5. **Remove your own worktree and branch — only once verified safe, then a genuine double-force.**
   Resolve them from where you're standing — you never assumed a name for either. Claude Code locks
   a worktree while its session is running, so removing your own always needs `--force` twice
   (confirmed by test: single `--force` only overrides *uncommitted changes*, not a *lock* — those
   are two separate gates). **Never reach for the double-force without checking first** — it would
   just as happily discard real, unrecoverable work as it overrides the lock. "Safe" here means
   HEAD is already fully landed in the default branch — check that directly rather than comparing
   against the branch's own upstream, which GitHub may have already deleted itself (many repos
   auto-delete a branch on merge) and would otherwise make this check fail closed on the *normal*,
   successful case instead of the risky one. Re-resolve `$MAIN`/`$DEFAULT_BR` here rather than
   assuming they carried over from step 2 — a fresh Bash call doesn't inherit another one's shell
   variables, only its working directory:
   ```bash
   MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
   DEFAULT_BR=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   BR=$(git rev-parse --abbrev-ref HEAD)
   WT=$(git rev-parse --show-toplevel)
   DIRTY=$(git -C "$WT" status --porcelain)
   if [[ -n "$DIRTY" ]] || ! git -C "$WT" merge-base --is-ancestor HEAD "origin/$DEFAULT_BR"; then
     echo "worktree has uncommitted changes, or HEAD isn't reachable from origin/$DEFAULT_BR yet — not removing. Resolve it, then re-run finalize." >&2
     exit 1
   fi
   cd "$MAIN"    # off the worktree BEFORE removing it, so nothing below runs from a deleted cwd
   git -C "$MAIN" worktree remove --force --force "$WT"
   git -C "$MAIN" branch -D "$BR"                          # local — -D, not -d: a squash-merge
                                                             # commit is never an ancestor of the
                                                             # branch tip, so -d always refuses here
   git -C "$MAIN" push origin --delete "$BR" 2>/dev/null || true   # remote — often already gone if
                                                                     # the repo auto-deletes on merge
   ```

6. **Report.** Confirm: specs synced, change archived, worktree removed, issue closed. Suggest
   `/spec-flow:board` to see the rest of the pipeline.

## Rules

- **Never merge the feature PR.** Confirm the owner already did before finalizing (step 1). The
  archive-only PR in step 3 is the sole, narrow exception — see the frontmatter and step 3 for why;
  it never extends to anything else.
- Only finalize a merged PR — finalizing an unmerged one would archive un-landed work.
- Leave `main` clean: the only change finalize lands on `main` is the OpenSpec archive, via its own
  PR, matching the repo's existing archive convention — never a direct push.
- **This is where `agent:active` finally comes off** — `activate` set it, every stage since kept
  it, this is the one place it's supposed to end. Don't skip step 4's label removal even on an
  otherwise-uneventful finalize.
- **Never double-force a worktree removal without checking it's safe first.** The lock override
  and the uncommitted-changes override are two different gates; skipping the check means treating
  a real safety mechanism as an obstacle instead of a signal.
- **Safe to re-run at any step.** Step 3 skips the archive if it's already there; step 4 only
  closes/comments/relabels what isn't already done; step 5 only removes what still exists.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
