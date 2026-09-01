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

# -C "$worktree": without it this describes whatever repo the CALLER happens to be standing in,
# while $worktree is an explicit argument. The common path (invoked from MAIN) works either way;
# from anywhere else the later `worktree remove` would target a different repo's worktree list.
main=$(git -C "$worktree" worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
# Every gh call below must resolve the SAME repo git does. gh reads the repo from cwd, so without
# this it would read the caller's repo while git -C targets the worktree's -- opening the PR in the
# wrong place. Resolved once, then passed explicitly with --repo.
if ! repo=$(git -C "$worktree" remote get-url origin 2>/dev/null); then
  echo "archive-batch-pr: couldn't resolve the worktree's origin remote." >&2
  exit 1
fi
repo=${repo%.git}
repo=${repo##*[:/]github.com/}
repo=${repo##*:}
if ! default_br=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name); then
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

if ! git -C "$worktree" push origin "HEAD:refs/heads/${batch_br}"; then
  echo "archive-batch-pr: couldn't push '${batch_br}' to origin. The archive commit is made in" >&2
  echo "'${worktree}' but nothing is on the remote; the worktree is left in place so you can" >&2
  echo "retry the push from it." >&2
  exit 1
fi

if ! pr_url=$(gh pr create --repo "$repo" --head "$batch_br" --base "$default_br" --title "$pr_title" --body "$pr_body"); then
  # set -e would have exited here with gh's raw status and no mention of the branch it just
  # pushed -- leaving a stranded remote branch nobody is told about, and no recovery command.
  echo "archive-batch-pr: pushed '${batch_br}' to origin, but 'gh pr create' failed." >&2
  echo "The branch is on the remote with the archive commit on it; nothing was lost. Open the PR" >&2
  echo "yourself, or delete the branch to start over:" >&2
  # Write the body to a file rather than inlining it: it is multi-line, and a title containing a
  # double quote would otherwise produce an unpastable command. --body-file keeps the per-issue
  # citation list the caller composed, which an inline retry silently dropped.
  body_file=$(mktemp "${TMPDIR:-/tmp}/archive-batch-body.XXXXXX")
  printf '%s\n' "$pr_body" > "$body_file"
  echo "  gh pr create --head ${batch_br} --base ${default_br} \\" >&2
  echo "    --title \"\$(cat <<'EOF'" >&2
  echo "${pr_title}" >&2
  echo "EOF" >&2
  echo "    )\" --body-file ${body_file}" >&2
  echo "or delete the branch to start over:" >&2
  echo "  git push origin --delete ${batch_br}" >&2
  exit 1
fi

# Worktree's job is done once its content is on origin — remove it now, BEFORE attempting the
# merge: a blocked merge (pending checks, branch protection) exits non-zero below, and leaving the
# worktree around after that would just be clutter (nothing re-runs against it — see the header).
# --force twice: Claude Code locks a worktree while its session runs, and lock and dirtiness are
# separate gates (see finalize-remove-worktree.sh, which documents this from testing). Failure here
# must NOT abort: the PR already exists, and dying now would leave it open, unmerged and unreported.
if ! git -C "$main" worktree remove --force --force "$worktree" 2>/dev/null; then
  echo "archive-batch-pr: note — couldn't remove the temporary worktree '${worktree}'." >&2
  echo "Harmless; nothing re-runs against it. Remove it later with:" >&2
  echo "  git -C ${main} worktree remove --force --force ${worktree}" >&2
fi

if ! gh pr merge --repo "$repo" "$batch_br" --squash --delete-branch; then
  echo "archive-batch-pr: batch PR is open (${pr_url}) but didn't merge automatically (required" >&2
  echo "checks still pending, or branch protection needs a review) — merge it yourself:" >&2
  echo "gh pr merge ${batch_br} --squash --delete-branch (or in GitHub)." >&2
  exit 1
fi

echo "archive-batch-pr: merged ${pr_url}"
