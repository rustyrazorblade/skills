#!/usr/bin/env bash
# Flush spec-flow's shared archive queue (spec-flow/archive-queue — see finalize/SKILL.md step 3
# and scripts/finalize-queue-archive.sh) into one batch PR against the default branch, and merge
# it. Owner-invoked via /spec-flow:archive — session-driven, not cron, matching this plugin's own
# philosophy (docs/workflow.md, Substrate section) — the owner runs this when they want the queue
# landed, not on any automatic schedule. Idempotent: safe to re-run if an earlier attempt opened
# the PR but didn't merge (required checks pending, branch protection needing a review, etc).
# No worktree needed — this reads origin via fetch + rev-list, but never checks out a working tree
# of the queue branch.
set -euo pipefail

queue_br="spec-flow/archive-queue"

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "archive-flush: '$bin' is required but not on PATH." >&2
    exit 1
  }
done

if ! git ls-remote --exit-code --heads origin "$queue_br" >/dev/null 2>&1; then
  echo "archive-flush: nothing queued — ${queue_br} doesn't exist on origin. Nothing to do." >&2
  exit 0
fi

if ! default_br=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name); then
  echo "archive-flush: couldn't resolve the repo's default branch ('gh repo view' failed)." >&2
  exit 1
fi

# Fetch both refs before counting — rev-list reads LOCAL remote-tracking refs, and ls-remote above
# (a raw network query, not a local ref update) doesn't populate or refresh them.
git fetch origin "$default_br" "$queue_br" >/dev/null 2>&1 || true

# Purely for the PR title/report below except the zero-count guard just after — if it can't be
# counted for any reason, fall back to a vague-but-honest label rather than failing the flush.
ahead=$(git rev-list --count "origin/${default_br}..origin/${queue_br}" 2>/dev/null) || ahead=""

if [[ "$ahead" == "0" ]]; then
  echo "archive-flush: ${queue_br} exists but has nothing new to merge — already flushed, or the" >&2
  echo "branch just wasn't cleaned up after an earlier merge. Nothing to do." >&2
  exit 0
fi
[[ -n "$ahead" ]] || ahead="some"

existing_pr=$(gh pr list --head "$queue_br" --state open --json number --jq '.[0].number // empty')
if [[ -z "$existing_pr" ]]; then
  gh pr create --head "$queue_br" --base "$default_br" \
    --title "archive: batch (${ahead} issue(s))" \
    --body "Batched OpenSpec sync + archive for ${ahead} finalized issue(s), queued since the last flush. No code changes — bookkeeping only."
else
  echo "archive-flush: batch PR #${existing_pr} already open — an earlier flush got this far and" >&2
  echo "was interrupted before merging. Merging it rather than recreating." >&2
fi

if ! gh pr merge "$queue_br" --squash --delete-branch; then
  echo "archive-flush: the batch archive PR is open but didn't merge automatically (required" >&2
  echo "checks still pending, or branch protection needs a review) — merge it yourself, or just" >&2
  echo "re-run this script once it's mergeable." >&2
  exit 1
fi

echo "archive-flush: merged and flushed (${ahead} issue(s)); ${queue_br} deleted — the next"
echo "finalize starts a fresh queue from ${default_br}."
