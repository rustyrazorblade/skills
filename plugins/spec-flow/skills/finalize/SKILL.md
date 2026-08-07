---
name: finalize
description: Finalize a merged issue — close the GitHub issue, remove its lifecycle/coordination labels, and remove the issue's git worktree. Final stage of the flow delivery workflow (see docs/workflow.md). Runs once the FEATURE PR has merged — by the owner's squash-merge by default, or by `implement` itself if the `merge-on-green` label was set or this run's `.spec-flow/owner-instructions` said to auto-merge. Does NOT touch the OpenSpec archive — that's `project-manager`'s job, done in bulk across several issues at once via `/spec-flow:archive`, once enough have piled up. This skill never merges the feature PR and never opens a PR of its own.
argument-hint: [issue number, with its PR already squash-merged]
---

# finalize — close out an issue after merge

You are this issue's `issue-pm`, running as your own dedicated background session. The PR for
issue `#N` has **merged** — the owner's squash-merge in GitHub by default, or `implement`'s own
auto-merge if `merge-on-green` was set or this run's `.spec-flow/owner-instructions` said to (see
its SKILL.md step 5); either way, by the time this runs the merge has already happened. Close the
issue and tear down your worktree — that's the whole job. **This skill itself never merges the
feature PR** — that already happened, by whichever path, before this skill starts — **and it never
touches the OpenSpec archive either.** When this issue committed an `openspec/changes/issue-<N>`
change (every issue except a content-only `type:docs` one, or any `type:tech-debt` one — see **Docs
fast path** and **Tech-debt fast path** in `docs/workflow.md`, neither of which generates one), it
already landed on the default branch as part of the merge; syncing it into canonical specs and
moving it under `openspec/changes/archive/` is
`project-manager`'s job, batched across however many issues have piled up since the last pass (see
**Bulk spec archiving** in `docs/workflow.md`) — not something any single issue's finalize waits on
or does itself.

Input: an issue number `#N`. You're already running inside this issue's worktree — Claude Code's
own background-session isolation put you there, on whatever branch it assigned, so resolve the
branch with `git rev-parse --abbrev-ref HEAD` rather than assuming a name.

## Steps

1. **Verify the PR is merged** (precondition — do not merge it yourself):
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   gh pr list --head "$BR" --state merged --json number,mergedAt
   ```
   If it isn't merged, stop — it hasn't happened yet, whether that's the owner's squash-merge in
   GitHub (default) or `implement`'s own auto-merge (only if this run was instructed to).

2. **Close the issue** (a PR with `Closes #N` usually auto-closes on merge — check `state`/`closed`
   first, and only close/comment/relabel what isn't already done; this step is safe to re-run, but
   don't post a second "🎉" comment or re-attempt a close that already happened). Remove the
   lifecycle and coordination labels — closing doesn't drop them on its own, and a stray
   `agent:active` on a closed issue would misread as still live. **Do this before step 3, not
   after** — `gh issue` commands have no `-C`/path override, they infer the repo from wherever
   you're standing, and step 3 is about to remove that:
   ```bash
   STATE=$(gh issue view <N> --json state,closed)
   if [[ "$(jq -r .closed <<<"$STATE")" != "true" ]]; then
     # A content-only type:docs issue, or any type:tech-debt issue, committed no
     # openspec/changes/issue-<N> at all (see Docs fast path / Tech-debt fast path in
     # docs/workflow.md) — nothing for a later archive batch to pick up, so say so accurately
     # instead of promising an archive that will never happen.
     if [[ -d "openspec/changes/issue-<N>" ]]; then
       gh issue comment <N> --body "🎉 Merged and closed. Its spec will be archived in a later batch — see /spec-flow:board."
     else
       gh issue comment <N> --body "🎉 Merged and closed."
     fi
     gh issue close <N> 2>/dev/null || true
   fi
   gh issue edit <N> --remove-label status:in-review --remove-label status:addressing \
     --remove-label status:in-progress --remove-label agent:active --remove-label blocked \
     --remove-label merge-on-green \
     2>/dev/null || true
   ```

3. **Remove your own worktree and branch — hand off to a script that only acts once verified
   safe.** **Before running it, note whether this issue had an OpenSpec change** —
   `[[ -d "openspec/changes/issue-<N>" ]]` — for step 4's report; the worktree (and anywhere you
   could still run that check) is gone once this script finishes:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/finalize-remove-worktree.sh
   ```
   Run it from inside the worktree being removed — it resolves everything from where you're
   standing; no arguments. It removes the worktree only when HEAD is exactly a merged PR's tip, and
   only then applies the double `--force` a session-locked worktree needs — the full reasoning (why
   exact-SHA, why two forces) lives in the script's own comments; never bypass it with a hand-run
   `git worktree remove --force --force`. **Safe to re-run**: if already removed, it detects the
   main checkout and exits cleanly.

4. **Report.** Confirm: issue closed, worktree removed. If step 3's check found
   `openspec/changes/issue-<N>`, note it's still sitting on the default branch, unarchived, until
   `project-manager` runs a bulk archive
   pass — this is expected, not something to wait on here. A content-only `type:docs` issue, or any
   `type:tech-debt` issue, has none — nothing pending for either. Suggest `/spec-flow:board` to see
   the rest of the pipeline.

## Rules

- **Never merge the feature PR.** Confirm the owner already did before finalizing (step 1).
- **Never touch the OpenSpec archive.** No `openspec-sync-specs`, no `openspec-archive-change`, no
  worktree cut from the default branch for this purpose — that's entirely `project-manager`'s job,
  batched. Don't wait for it, don't attempt it yourself even if you notice the change is still
  sitting unarchived.
- **Never open or merge a PR of your own.** Nothing in this skill produces a PR at all anymore.
- Only finalize a merged PR — finalizing an unmerged one would close an issue before its work
  actually landed.
- **This is where `agent:active` finally comes off** — `activate` set it, every stage since kept
  it, this is the one place it's supposed to end. Don't skip step 2's label removal even on an
  otherwise-uneventful finalize.
- **Never remove a worktree by hand.** Step 3's script is the only sanctioned path — it checks
  before it forces.
- **Safe to re-run at any step.** Step 2 only closes/comments/relabels what isn't already done;
  step 3's script only removes what still exists.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
