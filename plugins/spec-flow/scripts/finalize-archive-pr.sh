#!/usr/bin/env bash
# Land an already-staged archive commit via its own small, self-merged PR — the one PR
# /spec-flow:finalize merges itself (see finalize/SKILL.md step 3 for why). Framework-agnostic:
# doesn't know or care which spec framework produced the changes in the worktree (OpenSpec today,
# possibly others later) — the caller runs that framework's own sync/archive commands first and
# supplies the PR body text; this script only handles the generic git/gh commit+push+PR+merge
# mechanics. Idempotent — safe to re-run after an interruption at any point up to the merge.
set -euo pipefail

usage() {
  echo "usage: finalize-archive-pr.sh <issue-number> <worktree-path> <pr-body>" >&2
  exit 2
}

issue="${1:-}"
worktree="${2:-}"
pr_body="${3:-}"
[[ -n "$issue" && -n "$worktree" && -n "$pr_body" ]] || usage
[[ "$issue" =~ ^[0-9]+$ ]] || usage
[[ -d "$worktree" ]] || { echo "finalize-archive-pr: '$worktree' is not a directory" >&2; exit 2; }

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "finalize-archive-pr: '$bin' is required but not on PATH." >&2
    exit 1
  }
done

main=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
if ! default_br=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name); then
  echo "finalize-archive-pr: couldn't resolve the repo's default branch ('gh repo view' failed)." >&2
  exit 1
fi
archive_br="archive/issue-${issue}"

# Commit whatever's staged in the worktree — idempotent: a re-run after this already happened
# (interrupted between commit and push/PR) finds a clean tree and skips straight to the PR check.
if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
  git -C "$worktree" add -A
  git -C "$worktree" commit -m "archive: issue-${issue}"
fi

existing_pr=$(gh pr list --head "$archive_br" --state open --json number --jq '.[0].number // empty')
if [[ -n "$existing_pr" ]]; then
  echo "finalize-archive-pr: archive PR #${existing_pr} already open for ${archive_br} — an earlier" >&2
  echo "run got this far and was interrupted before merging. Merging it rather than recreating" >&2
  echo "(a fresh push here would be rejected as non-fast-forward anyway)." >&2
elif git ls-remote --exit-code --heads origin "$archive_br" >/dev/null 2>&1; then
  # Narrower interruption: an earlier run pushed the branch but died before `gh pr create` — a
  # fresh push here would also be rejected non-fast-forward, so open the PR from what's already there.
  echo "finalize-archive-pr: ${archive_br} already exists on origin (earlier run pushed but didn't" >&2
  echo "open the PR) — creating the PR from it rather than re-pushing." >&2
  gh pr create --head "$archive_br" --base "$default_br" \
    --title "archive: issue-${issue}" \
    --body "$pr_body"
else
  git -C "$worktree" push origin "HEAD:$archive_br"
  gh pr create --head "$archive_br" --base "$default_br" \
    --title "archive: issue-${issue}" \
    --body "$pr_body"
fi

# The worktree's job is done once its content is on origin — true in all three branches above
# (an existing open PR, an already-pushed branch, or the fresh push just done). Remove it now,
# BEFORE attempting the merge: a blocked merge (pending checks, branch protection) exits non-zero
# below, and every retry re-running finalize would otherwise mint a fresh, never-cleaned-up TMPWT
# on top of the last one.
git -C "$main" worktree remove "$worktree"

if ! gh pr merge "$archive_br" --squash --delete-branch; then
  echo "finalize-archive-pr: archive PR for issue-${issue} is open but didn't merge automatically" >&2
  echo "(required checks still pending, or branch protection needs a review) — merge it yourself:" >&2
  echo "gh pr merge ${archive_br} --squash --delete-branch (or in GitHub), then re-run finalize." >&2
  exit 1
fi

echo "finalize-archive-pr: archived and merged for issue #${issue}"
