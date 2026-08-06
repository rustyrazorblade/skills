#!/usr/bin/env bash
# Land a batch of OpenSpec archive changes via one PR — the generic git/gh mechanics for
# /spec-flow:archive's worker (agents/archive-batch.md). The caller (that agent) has already run
# OpenSpec's own sync/archive commands for every issue in the batch inside the given worktree,
# leaving the result UNCOMMITTED, and supplies the PR title/body; this script does the commit
# itself, then handles push + PR + merge + worktree cleanup — the caller should not commit first.
# Unlike the old per-issue queue mechanism this replaces, there is no concurrent
# writer to coordinate with — this is a single pass by a single session — so there's no retry-on-
# rejected-push loop and no reason to reuse a branch across runs: every invocation gets its own
# fresh, uniquely-named branch. If this script is interrupted before merging, don't re-run it
# against the same worktree — re-run /spec-flow:archive instead, which recomputes the buildup
# fresh from the default branch (anything already merged by a prior partial run no longer shows up
# as pending) and starts clean.
set -euo pipefail

usage() {
  echo "usage: archive-batch-pr.sh <worktree-path> <pr-title> <pr-body>" >&2
  exit 2
}

worktree="${1:-}"
pr_title="${2:-}"
pr_body="${3:-}"
[[ -n "$worktree" && -n "$pr_title" && -n "$pr_body" ]] || usage
[[ -d "$worktree" ]] || { echo "archive-batch-pr: '$worktree' is not a directory" >&2; exit 2; }

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "archive-batch-pr: '$bin' is required but not on PATH." >&2
    exit 1
  }
done

main=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
if ! default_br=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name); then
  echo "archive-batch-pr: couldn't resolve the repo's default branch ('gh repo view' failed)." >&2
  exit 1
fi
batch_br="archive/batch-$(date +%Y%m%d%H%M%S)-$$"

if [[ -z "$(git -C "$worktree" status --porcelain)" ]]; then
  echo "archive-batch-pr: nothing changed in '$worktree' — the caller should have run OpenSpec's" >&2
  echo "sync/archive commands (leaving the result UNCOMMITTED) before invoking this script, which" >&2
  echo "does the commit itself. Nothing to do." >&2
  exit 1
fi
git -C "$worktree" add -A
git -C "$worktree" commit -m "$pr_title"

git -C "$worktree" push origin "HEAD:refs/heads/${batch_br}"
pr_url=$(gh pr create --head "$batch_br" --base "$default_br" --title "$pr_title" --body "$pr_body")

# Worktree's job is done once its content is on origin — remove it now, BEFORE attempting the
# merge: a blocked merge (pending checks, branch protection) exits non-zero below, and leaving the
# worktree around after that would just be clutter (nothing re-runs against it — see the header).
git -C "$main" worktree remove "$worktree"

if ! gh pr merge "$batch_br" --squash --delete-branch; then
  echo "archive-batch-pr: batch PR is open (${pr_url}) but didn't merge automatically (required" >&2
  echo "checks still pending, or branch protection needs a review) — merge it yourself:" >&2
  echo "gh pr merge ${batch_br} --squash --delete-branch (or in GitHub)." >&2
  exit 1
fi

echo "archive-batch-pr: merged ${pr_url}"
