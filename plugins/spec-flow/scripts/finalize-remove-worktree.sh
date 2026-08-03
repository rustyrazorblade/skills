#!/usr/bin/env bash
# Safely remove THIS session's own issue worktree and branch, once verified the current HEAD is
# exactly a merged PR's tip — never on uncommitted work or a branch with unmerged/extra commits.
# Run from inside the worktree being removed; it resolves everything from cwd, same as the rest of
# this session's own git/gh calls. See finalize/SKILL.md step 5 for the full reasoning.
set -euo pipefail

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "finalize-remove-worktree: '$bin' is required but not on PATH." >&2
    exit 1
  }
done

main=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
wt=$(git rev-parse --show-toplevel)

if [[ "$wt" == "$main" ]]; then
  echo "finalize-remove-worktree: already standing in the main checkout — this issue's worktree was already removed by an earlier finalize run. Nothing to do."
  exit 0
fi

br=$(git rev-parse --abbrev-ref HEAD)
dirty=$(git -C "$wt" status --porcelain)
current_sha=$(git -C "$wt" rev-parse HEAD)

# "Safe" means the current branch tip IS a merged PR's tip — not just that SOME PR for this branch
# merged at some point. A merged-PR-exists check alone can't tell a fully-landed branch from one
# with extra local commits on top of an old merge (a checkpoint push racing the owner's merge, or a
# final commit that got made but never pushed), or a branch reused for a second, still-open PR
# after its first one merged — all three would pass "a merged PR exists" and then get destroyed by
# the double-force below. Comparing exact SHAs closes all three, and stays squash-safe (unlike
# `git merge-base --is-ancestor`, which — confirmed by test — a squashed branch tip is NEVER an
# ancestor of, even on the fully successful path; the same fact is why `branch -D` below needs
# `-D`, not `-d`).
safe=false
if [[ -z "$dirty" ]]; then
  merged_pr=$(gh pr list --head "$br" --state merged --json number --jq '.[0].number // empty')
  if [[ -n "$merged_pr" ]]; then
    merged_sha=$(gh pr view "$merged_pr" --json headRefOid --jq .headRefOid 2>/dev/null) || true
    [[ -n "$merged_sha" && "$merged_sha" == "$current_sha" ]] && safe=true
  fi
fi

if [[ "$safe" != true ]]; then
  echo "finalize-remove-worktree: worktree has uncommitted changes, or HEAD doesn't match a merged" >&2
  echo "PR's tip for ${br} (extra commits after merge, or a newer unmerged PR reusing this branch)" >&2
  echo "— not removing. Resolve it, then re-run finalize." >&2
  exit 1
fi

# Claude Code locks a worktree while its session is running, so removing your own always needs
# --force twice (confirmed by test: single --force only overrides uncommitted changes, not a lock
# — two separate gates). Never reach this without the safety check above having passed first.
cd "$main"    # off the worktree BEFORE removing it, so nothing below runs from a deleted cwd
git -C "$main" worktree remove --force --force "$wt"
git -C "$main" branch -D "$br"                          # local — -D, not -d: a squash-merge
                                                          # commit is never an ancestor of the
                                                          # branch tip, so -d always refuses here
git -C "$main" push origin --delete "$br" 2>/dev/null || true   # remote — often already gone if
                                                                  # the repo auto-deletes on merge
echo "finalize-remove-worktree: removed worktree and branch ${br}"
