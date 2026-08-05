---
name: finalize
description: Finalize a merged issue — sync the OpenSpec change's delta specs into the canonical specs and append the archive commit onto a shared queue branch, close the GitHub issue, and remove the issue's git worktree. Final stage of the flow delivery workflow (see docs/workflow.md). Runs once the FEATURE PR has merged — by the owner's squash-merge by default, or by `implement` itself if the `merge-on-green` label was set or this run's `.spec-flow/owner-instructions` said to auto-merge; this skill itself never merges that PR either way, and it never opens a PR of its own either — the queued archive commits land later, batched, via the owner-invoked `/spec-flow:archive`.
argument-hint: [issue number, with its PR already squash-merged]
---

# finalize — sync, archive, and clean up after merge

You are this issue's `issue-pm`, running as your own dedicated background session. The PR for
issue `#N` has **merged** — the owner's squash-merge in GitHub by default, or `implement`'s own
auto-merge if `merge-on-green` was set or this run's `.spec-flow/owner-instructions` said to (see
its SKILL.md step 5); either way, by the time this runs the merge has already happened. Sync and
archive the OpenSpec change,
close the issue, and tear down the worktree. **This skill itself never merges the feature PR** —
that already happened, by whichever path, before this skill starts — **and it never opens a PR of
its own either.** Step 3's archive commit is pure OpenSpec bookkeeping with no code and nothing to
review, but landing it via its own PR was still one PR per issue for zero review value — so it
appends onto a shared queue branch (`spec-flow/archive-queue`) instead, and the owner-invoked
`/spec-flow:archive` batches whatever's queued into one PR, on their own schedule (see **Archive
queue** in `docs/workflow.md`).

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
   If it isn't merged, stop — it hasn't happened yet, whether that's the owner's squash-merge in
   GitHub (default) or `implement`'s own auto-merge (only if this run was instructed to).

2. **Create a short-lived worktree from merged main.** Resolve the **main** checkout first —
   `git worktree list --porcelain`'s first entry — the owner's primary checkout, not a per-issue
   worktree; never switch branches or pull there. Do the archive in an isolated, detached-HEAD
   worktree instead, so finalize never touches whatever the owner has checked out or in progress:
   ```bash
   MAIN=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
   DEFAULT_BR=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   git -C "$MAIN" fetch origin
   git -C "$MAIN" worktree prune   # opportunistic: drops any prior run's TMPWT registration whose
                                    # temp dir the OS already cleaned up, before minting a new one
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
   that would land the archive commit somewhere other than the queue.

3. **Sync delta specs into canonical specs, then hand off the archive-queue mechanics to a
   script** (inside `<TMPWT>`, the literal path from step 2 — not a shell variable). A previous
   finalize run may already have gotten this far, in **either** of two ways — check both before
   regenerating anything, since `<TMPWT>` (cut from `origin/$DEFAULT_BR`) can only ever see the
   first:
   - **Already landed on `$DEFAULT_BR`** — `openspec/changes/archive/issue-<N>` already exists
     here (a `/spec-flow:archive` flush landed it since the interrupted run).
   - **Already queued, not yet flushed** — the archive commit is sitting on
     `spec-flow/archive-queue`, invisible from `<TMPWT>` since that branch was never merged into
     `$DEFAULT_BR` yet. Check for it explicitly:
     ```bash
     git -C <MAIN> fetch origin
     git -C <MAIN> log --oneline origin/spec-flow/archive-queue 2>/dev/null | grep -q "archive: issue-<N>$" && echo QUEUED
     ```
     (empty/no-match if the queue branch doesn't exist yet either — that's fine, means neither case
     applies.)

   Either case → remove the now-unneeded `<TMPWT>` and skip straight to step 4, nothing else to
   redo (step 2 creates `<TMPWT>` unconditionally before this check runs, so skipping without
   removing it would leave a registered-but-abandoned worktree behind on every re-run):
   ```bash
   git -C <MAIN> worktree remove <TMPWT>
   ```
   Otherwise, use the OpenSpec flow for change `issue-<N>` — OpenSpec is this repo's spec framework
   today; the script below doesn't know or care which one produced the change, it just commits and
   queues whatever's staged, so swapping frameworks later needs no change here:
   - `openspec-sync-specs` (or `/opsx:sync`) to fold the delta specs into `openspec/specs/`.
   - `openspec-archive-change` (or `/opsx:archive`) to move the change under
     `openspec/changes/archive/`.
   Then hand the generic git mechanics — commit, append onto the shared `spec-flow/archive-queue`
   branch (fetch/rebase/push, retrying if a concurrent finalize's append wins the race), clean up
   `<TMPWT>` — to the script, rather than reasoning through that by hand every time. **This does
   NOT open or merge a PR** — it only queues; **Invoke it from the issue worktree, not from inside
   `<TMPWT>`** — the script removes `<TMPWT>` on success, and a Bash call running from inside a
   directory that command just deleted is left in an undefined location for whatever runs next
   (step 4's `gh issue` calls in particular):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/finalize-queue-archive.sh <N> <TMPWT>
   ```
   The script exits non-zero only on a genuine conflict or persistent push contention (rare — see
   its own comments); either way, don't let that fall through to closing the issue anyway —
   re-running finalize retries cleanly, the commit isn't lost. **This issue's own progress (close +
   worktree removal, steps 4-5) does NOT wait on the queue actually landing on `main`** — queuing
   is enough; landing it is `/spec-flow:archive`'s job, on the owner's own schedule, not gated on
   any one issue finishing.

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
     --remove-label merge-on-green \
     2>/dev/null || true
   ```

5. **Remove your own worktree and branch — hand off to a script that only acts once verified
   safe.**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/finalize-remove-worktree.sh
   ```
   Run it from inside the worktree being removed — it resolves everything from where you're
   standing; no arguments. It removes the worktree only when HEAD is exactly a merged PR's tip, and
   only then applies the double `--force` a session-locked worktree needs — the full reasoning (why
   exact-SHA, why two forces) lives in the script's own comments; never bypass it with a hand-run
   `git worktree remove --force --force`. **Safe to re-run**: if already removed, it detects the
   main checkout and exits cleanly.

6. **Report.** Confirm: specs synced, change archived, worktree removed, issue closed. Suggest
   `/spec-flow:board` to see the rest of the pipeline.

## Rules

- **Never merge the feature PR.** Confirm the owner already did before finalizing (step 1).
- **Never open or merge a PR of your own, either.** Step 3 only appends the archive commit onto
  the shared `spec-flow/archive-queue` branch — landing it on `main` is `/spec-flow:archive`'s job
  (owner-invoked, batches everything queued), not something any single finalize run does itself.
- Only finalize a merged PR — finalizing an unmerged one would archive un-landed work.
- Leave `main` clean: finalize never pushes to it directly, and doesn't even land the archive
  itself — see above.
- **This is where `agent:active` finally comes off** — `activate` set it, every stage since kept
  it, this is the one place it's supposed to end. Don't skip step 4's label removal even on an
  otherwise-uneventful finalize.
- **Never remove a worktree by hand.** Step 5's script is the only sanctioned path — it checks
  before it forces.
- **Safe to re-run at any step.** Step 3 skips the archive if it's already there, and its script
  retries the queue-branch append cleanly if an earlier run was interrupted mid-attempt; step 4
  only closes/comments/relabels what isn't already done; step 5's script only removes what still
  exists.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
