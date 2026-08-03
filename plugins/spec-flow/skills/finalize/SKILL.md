---
name: finalize
description: Finalize a merged issue — sync the OpenSpec change's delta specs into the canonical specs and archive the change via its own small PR, close the GitHub issue, and remove the issue's git worktree. Final stage of the flow delivery workflow (see docs/workflow.md). Runs after the owner squash-merges the FEATURE PR in GitHub; never merges that one — the one PR this skill does merge itself is its own no-review archive-only bookkeeping PR (see step 3).
argument-hint: [issue number, with its PR already squash-merged]
---

# finalize — sync, archive, and clean up after merge

You are this issue's `issue-pm`, running as your own dedicated background session. The owner has
**squash-merged** the PR for issue `#N` in GitHub. Sync and archive the OpenSpec change, close the
issue, and tear down the worktree. **This skill never merges the feature PR** — that merge is the
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
   MAIN=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
   DEFAULT_BR=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   git -C "$MAIN" fetch origin
   TMPWT=$(mktemp -d)
   git -C "$MAIN" worktree add --detach "$TMPWT" "origin/$DEFAULT_BR"
   echo "TMPWT=$TMPWT"
   ```
   **Note the printed `$TMPWT` path — it's from `mktemp`, so unlike `$MAIN`/`$DEFAULT_BR` it can't
   be recomputed.** If step 3 runs as a separate Bash call (likely — OpenSpec's own commands sit
   between), that call won't have this shell's variables (only cwd survives across Bash calls, not
   variables) — so step 3 below uses `<TMPWT>` as a stand-in for the **literal path you just saw
   printed**, not the unset variable `$TMPWT`. Get this wrong and `git -C ""` doesn't error, it
   silently uses whatever the cwd happens to be — exactly the kind of silent wrong-tree operation
   this skill's one self-merge exception can't afford.

3. **Sync delta specs into canonical specs, then hand off the archive-and-PR mechanics to a
   script** (inside `<TMPWT>`, the literal path from step 2 — not a shell variable). If
   `openspec/changes/archive/issue-<N>` already exists here, a previous finalize run already got
   this far — remove the now-unneeded `<TMPWT>` and skip straight to step 4, nothing else to redo
   (step 2 creates `<TMPWT>` unconditionally before this check runs, so skipping without removing
   it would leave a registered-but-abandoned worktree behind on every re-run):
   ```bash
   git -C <MAIN> worktree remove <TMPWT>
   ```
   Otherwise, use the OpenSpec flow for change `issue-<N>` — OpenSpec is this repo's spec framework
   today; the script below doesn't know or care which one produced the change, it just archives
   and lands whatever's staged, so swapping frameworks later needs no change here:
   - `openspec-sync-specs` (or `/opsx:sync`) to fold the delta specs into `openspec/specs/`.
   - `openspec-archive-change` (or `/opsx:archive`) to move the change under
     `openspec/changes/archive/`.
   Then hand the generic git/gh mechanics — commit, open the archive PR (or reuse one from an
   earlier interrupted run), merge it, clean up `<TMPWT>` — to the script, rather than reasoning
   through the push-vs-reuse/non-fast-forward cases by hand every time:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/finalize-archive-pr.sh <N> <TMPWT> "OpenSpec sync + archive for issue #<N>, now that its PR is merged. No code changes — bookkeeping only."
   ```
   This is the **one** PR this skill merges itself — see the frontmatter note on why. The script
   exits non-zero if the PR doesn't merge automatically (required checks still pending, or branch
   protection needs a review) — don't let that fall through to closing the issue anyway: leaving
   the archive commit unmerged would strand `main` without it, the branch `/spec-flow:activate`
   cuts every new worktree from. **Re-running after any interruption between the commit and the
   merge is safe** — the script handles reusing an already-open PR, a pushed-but-PR-less branch, or
   a fully fresh push, whichever the previous run got to.

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

5. **Remove your own worktree and branch — hand off to a script that only acts once verified
   safe.**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/finalize-remove-worktree.sh
   ```
   Run this from inside the worktree being removed — it resolves everything (which worktree, which
   branch, whether it's safe) from wherever you're standing, same as the rest of this session's own
   git/gh calls; it takes no arguments. It only reaches for the double-force once HEAD is **exactly
   a merged PR's tip** — not just "some PR for this branch merged at some point" (a merged-PR-exists
   check alone can't tell a fully-landed branch from one with extra local commits on top of an old
   merge, or from a branch reused for a second, still-open PR after its first one merged — see the
   script's own comments). Claude Code locks a worktree while its session is running, so removing
   your own always needs `--force` twice (confirmed by test: single `--force` only overrides
   *uncommitted changes*, not a *lock* — two separate gates) — the script never reaches for that
   without its safety check passing first. **Safe to re-run**: if an earlier run already removed
   the worktree, the script detects it's standing in the main checkout and exits cleanly.

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
  a real safety mechanism as an obstacle instead of a signal. Step 5's script enforces this itself
  — always go through it rather than running `git worktree remove --force --force` by hand.
- **Safe to re-run at any step.** Step 3 skips the archive if it's already there (and its script
  handles reusing an in-progress PR/branch from an earlier interrupted run); step 4 only
  closes/comments/relabels what isn't already done; step 5's script only removes what still exists.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
