#!/usr/bin/env bash
# Commit a staged OpenSpec archive change and append it onto the shared queue branch
# (spec-flow/archive-queue) — NOT its own PR. finalize used to open+merge one small PR per issue
# purely for this bookkeeping (see git history, scripts/finalize-archive-pr.sh, now retired) — one
# PR per issue for zero review value. Every finalize now appends its archive commit onto one
# shared branch instead; /spec-flow:archive periodically flushes the whole queue as a single batch
# PR (scripts/archive-flush.sh). Framework-agnostic, same as before: the caller runs OpenSpec's own
# sync/archive commands first and hands this script a worktree with the result staged/committed.
set -euo pipefail

usage() {
  echo "usage: finalize-queue-archive.sh <issue-number> <worktree-path>" >&2
  exit 2
}

issue="${1:-}"
worktree="${2:-}"
[[ -n "$issue" && -n "$worktree" ]] || usage
[[ "$issue" =~ ^[0-9]+$ ]] || usage
[[ -d "$worktree" ]] || { echo "finalize-queue-archive: '$worktree' is not a directory" >&2; exit 2; }

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "finalize-queue-archive: '$bin' is required but not on PATH." >&2
    exit 1
  }
done

main=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
if ! default_br=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name); then
  echo "finalize-queue-archive: couldn't resolve the repo's default branch ('gh repo view' failed)." >&2
  exit 1
fi
queue_br="spec-flow/archive-queue"

# Commit whatever's staged — idempotent: a re-run after this already happened (interrupted between
# commit and the append below) finds a clean tree and just re-attempts the append.
if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
  git -C "$worktree" add -A
  git -C "$worktree" commit -m "archive: issue-${issue}"
fi
commit=$(git -C "$worktree" rev-parse HEAD)

# Append onto the queue branch's current tip (or the default branch, if nothing's queued yet) —
# fetch, rebase, push; retry if another finalize's append wins the race in between. Every attempt
# resets back to the pristine single-commit state first and rebases fresh from there, rather than
# chaining rebases on top of a possibly-already-rebased HEAD — simpler to reason about and avoids
# rebase recomputing the wrong diff on a second pass. Bounded, not infinite: genuine, persistent
# contention (or a real conflict) should surface rather than spin quietly.
attempts=0
while :; do
  attempts=$((attempts + 1))
  git -C "$worktree" reset --hard "$commit" >/dev/null
  git -C "$main" fetch origin >/dev/null 2>&1 || true
  # Local remote-tracking ref check, not a second network round-trip — the fetch above just
  # updated it. A worktree shares its parent repo's refs/object store (only HEAD/index are
  # per-worktree), so this is visible from "$worktree" too without fetching there separately.
  if git -C "$main" rev-parse --verify -q "refs/remotes/origin/${queue_br}" >/dev/null; then
    base="origin/${queue_br}"
  else
    base="origin/${default_br}"
  fi
  if ! git -C "$worktree" rebase "$base" >/dev/null 2>&1; then
    git -C "$worktree" rebase --abort 2>/dev/null || true
    echo "finalize-queue-archive: rebasing onto ${base} hit a real conflict, not just contention —" >&2
    echo "retrying wouldn't help. Resolve by hand: rebase issue-${issue}'s archive commit (${commit})" >&2
    echo "onto ${base} in a scratch worktree and push the result to ${queue_br}, then re-run finalize." >&2
    exit 1
  fi
  # Fully qualify the destination — "HEAD:${queue_br}" alone fails to CREATE a new remote branch
  # from a detached HEAD (confirmed by test: git can't infer the dst refname in that case, "you
  # must fully qualify the ref"), which is exactly the common case here — the queue branch doesn't
  # exist yet on the very first finalize, and again after every /spec-flow:archive flush deletes
  # it. Fully qualifying works whether the branch already exists (fast-forward update) or not
  # (fresh creation) — no need to branch behavior on which case this is.
  push_err=$(git -C "$worktree" push origin "HEAD:refs/heads/${queue_br}" 2>&1) && break
  if [[ $attempts -ge 5 ]]; then
    echo "finalize-queue-archive: couldn't append to ${queue_br} after ${attempts} attempts." >&2
    echo "Last error: ${push_err}" >&2
    echo "If that looks like real contention (rejected, non-fast-forward), re-run finalize to" >&2
    echo "retry — the archive commit isn't lost, it's still sitting in this worktree. If it looks" >&2
    echo "like something else (permissions, network), that won't resolve on its own; fix it first." >&2
    exit 1
  fi
done

git -C "$main" worktree remove "$worktree" 2>/dev/null || true
echo "finalize-queue-archive: issue #${issue}'s archive commit appended to ${queue_br} — a future" >&2
echo "/spec-flow:archive run batches it into ${default_br}." >&2
