#!/usr/bin/env bash
# Land a repo's first spec-flow policy file via one PR — the git/gh mechanics behind the seeding
# item in skills/setup/SKILL.md. The caller (that skill) has already proposed a policy to the owner
# and had it CONFIRMED, and has written the confirmed content to a file; this script only moves it
# onto a branch and opens a PR. It decides nothing about the content.
#
#   seed-config.sh <content-file>
#
# It never commits or pushes to the default branch, never merges, and never touches the owner's
# working tree or current branch: the commit is made in a throwaway detached worktree that is
# removed before the script returns.
#
# IT NEVER DELETES ANYTHING ON THE REMOTE. The script's one outward action is pushing its seed
# branch. If `gh pr create` then fails (a token without the PR scope, branch protection, a required
# template, a network blip) or the owner interrupts the run, the branch is LEFT on the remote and
# the script prints its name together with the two commands that resolve it: open the PR by hand, or
# delete the branch. The operator decides; this script does not.
#
# WHY IT IS DELIBERATELY DUMB — do not "improve" this by adding the rollback back.
#
# Automatic rollback was attempted four times and failed four different ways, each failure introduced
# by the fix for the previous one:
#   1. no rollback at all           -> every failed retry stranded another uniquely-named branch;
#   2. rollback on a trapped signal -> bash RESUMES after an INT handler, so it ran twice and printed
#                                      two contradictory messages, the second one false;
#   3. a run-once sentinel          -> an interrupt delivered mid-push landed before the flag was
#                                      set, so it did not run at all and the run exited silently;
#   4. gating on `git ls-remote`    -> that exits non-zero for BOTH "no such ref" AND "cannot reach
#                                      the remote", so an unreachable remote skipped the rollback
#                                      AND the message, silently.
#
# Every one of those came from keeping state that tried to mirror something outside this process.
# Reporting keeps no such state: it always prints, so it cannot be raced by a signal, fooled by a
# network failure, or desynchronised from the remote. A spurious recovery message costs the owner
# ten seconds; silence costs them a branch they never learn about. Seeding runs once per repo, so
# the accumulation risk that motivated the rollback is small, and it is the owner's explicit trade.
#
# If the policy file already exists on the remote default branch AND is usable, the repo already
# owns its policy: the script reports that, changes nothing, opens no PR, and exits 0. If it exists
# but is unusable, seeding cannot help and the script says so rather than adding a second copy.
#
# macOS bash 3.2 — no associative arrays, no `mapfile`, no `${var,,}`.
set -euo pipefail

# Named distinctly from repo-config.sh's own `usage`, which this script sources below and which
# would otherwise silently replace this one.
seed_usage() {
  echo "usage: seed-config.sh <content-file>" >&2
  echo "  <content-file>  a file holding the policy content the owner has already confirmed." >&2
  exit 2
}

content_file="${1:-}"
[[ -n "$content_file" && $# -eq 1 ]] || seed_usage

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "seed-config: '$bin' is required but not on PATH." >&2
    exit 2
  }
done

# Repo root, config directory, and the policy file's name all come from repo-config.sh, which owns
# that resolution. Sourcing it keeps exactly one copy of the rules.
#
# source-path=SCRIPTDIR, not a relative path: shellcheck resolves a relative `source=` against its
# own working directory, so `shellcheck -x` on this file passed only when run from inside this
# directory. SCRIPTDIR resolves against the script's location, so the gate spec-flow/CI.md
# prescribes is clean from any working directory.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=repo-config.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/repo-config.sh"

[[ -f "$content_file" && -r "$content_file" ]] || {
  echo "seed-config: '$content_file' is not a readable file." >&2
  exit 2
}
config_usable "$content_file" || {
  echo "seed-config: '$content_file' is empty once blank and comment lines are stripped. Seeding" >&2
  echo "an empty policy would leave the repo failing its own check. Nothing written." >&2
  exit 2
}

root=$(resolve_repo_root)
config_dir=$(resolve_config_dir)
rel_path="${config_dir}/${POLICY_FILE}"

work_dir=$(mktemp -d)
work_tree="${work_dir}/seed"
branch=''
pushed=''
remote='origin'
default_br=''
cleanup_done=''

# Unwind BOTH sides of the operation. `pushed` is set the moment the branch reaches the remote and
# cleared the moment a PR exists to hold it, so this deletes the ref on exactly one path: pushed,
# but no PR. `-C "$root"`, not the worktree, because the worktree is already gone by the time this
# runs. Errors are swallowed so a failed rollback cannot mask the failure that triggered it — but
# never silently: both outcomes are reported.
#
# RUNS AT MOST ONCE. Bash runs an INT or TERM handler and then RESUMES the script, so without the
# sentinel an interrupt between the push and `pushed=''` would run this, delete the ref and report
# success, then let the script carry on, fail, and run this AGAIN from the EXIT trap with `pushed`
# still set — reporting that the branch is still on the remote when it is not, and handing the
# owner two recovery commands that both fail. `pushed` is also cleared after a successful delete,
# so the state and the message can never disagree.
cleanup() {
  [[ -z "$cleanup_done" ]] || return 0
  cleanup_done='yes'

  # REPORT; never delete, and never ask the remote anything.
  #
  # `pushed` is local-only and deliberately pessimistic: it is set BEFORE the push and means "we got
  # as far as trying", so an interrupt at any moment during the push still reaches this. It is not a
  # model of the remote's state — nothing here has one, which is the entire point. This block cannot
  # be wrong about the network, cannot be raced by a signal, and has no branch that stays quiet.
  if [[ -n "$pushed" && -n "$branch" ]]; then
    echo "seed-config: no pull request was opened for the branch this run pushed." >&2
    echo "  branch: ${branch}  (on ${remote})" >&2
    echo "It holds one commit adding ${rel_path}. Nothing was committed or pushed to" >&2
    echo "${default_br:-the default branch}, and nothing was merged." >&2
    echo "Either open the pull request yourself:" >&2
    echo "  gh pr create --head ${branch} --base ${default_br}" >&2
    echo "or delete the branch:" >&2
    echo "  git push ${remote} --delete ${branch}" >&2
    echo "(If the push did not finish, that branch is not there and the delete is a harmless no-op.)" >&2
  fi
  if [[ -e "$work_tree" ]]; then
    if ! git -C "$root" worktree remove --force "$work_tree" >/dev/null 2>&1; then
      echo "seed-config: could not remove the temporary worktree at ${work_tree}. Run" >&2
      echo "'git worktree prune' in ${root} to clear the stale entry." >&2
    fi
  fi
  rm -rf "$work_dir"
}

# The signal handlers EXIT rather than falling through. A bare `trap cleanup INT` would clean up and
# then resume — carrying on to push a branch or open a PR the owner has just interrupted, and, on an
# early interrupt, running git against a work tree cleanup had already deleted (reported as "failed
# while committing", which is not what happened). 130 and 143 are the conventional
# 128+signal statuses for SIGINT and SIGTERM.
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# One error mechanism, not two. Rather than wrapping every git and gh call in its own `if !`, the
# ERR trap names the step in progress and exits 2, so every unguarded command failure carries the
# same `seed-config:` prefix and the same exit code as the hand-written guards. Without it the
# script would exit with git's or gh's raw status and stderr, which setup/SKILL.md would then relay
# to the owner with nothing tying it to seeding.
step='starting up'
on_error() {
  echo "seed-config: failed while ${step}." >&2
  echo "Nothing was committed or pushed to ${default_br:-the default branch}, and nothing was merged." >&2
  exit 2
}
trap on_error ERR

step="resolving the repo's default branch"
if ! default_br=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name); then
  echo "seed-config: couldn't resolve the repo's default branch ('gh repo view' failed)." >&2
  exit 2
fi
[[ -n "$default_br" ]] || {
  echo "seed-config: 'gh repo view' returned an empty default branch name." >&2
  exit 2
}

# Resolve the remote ONCE and drive the fetch, the base ref, and the push from it. `gh` resolves its
# own base repo, so hardcoding `origin` for the git half lets the two disagree: in a clone whose
# GitHub remote is named something else, the fetch fails outright, and in a multi-remote clone the
# branch could land somewhere `gh pr create` is not looking.
step="resolving which git remote holds this repo"
if ! remote=$(git -C "$root" config --get "branch.${default_br}.remote" 2>/dev/null) || [[ -z "$remote" ]]; then
  if git -C "$root" remote get-url origin >/dev/null 2>&1; then
    remote='origin'
  else
    remote=$(git -C "$root" remote | head -n 1)
    [[ -n "$remote" ]] || {
      echo "seed-config: this repo has no git remote configured, so there is nowhere to push a" >&2
      echo "seed branch. Add one and run seeding again." >&2
      exit 2
    }
  fi
fi
# Everything below passes $default_br to git as a ref. A value beginning with a dash would be read
# as an option instead; refuse rather than fail confusingly halfway through.
case "$default_br" in
  -*)
    echo "seed-config: the default branch name '${default_br}' begins with a dash, which git would" >&2
    echo "read as an option rather than a branch. Refusing rather than guessing." >&2
    exit 2
    ;;
esac

# Ask the remote default branch, not the working tree: a local file on some other branch is not the
# repo owning its policy. And ask whether the committed blob is USABLE, not merely whether it
# exists — otherwise a committed-but-empty policy makes `check` say "no usable configuration, run
# setup" while this script says "already owns its policy", and the operator loops forever.
step="fetching ${remote}/${default_br}"
git -C "$root" fetch --quiet "$remote" "$default_br"

step="reading ${rel_path} from ${remote}/${default_br}"
committed_probe="${work_dir}/committed-policy"
if git -C "$root" cat-file -e "${remote}/${default_br}:${rel_path}" 2>/dev/null; then
  git -C "$root" cat-file -p "${remote}/${default_br}:${rel_path}" >"$committed_probe" 2>/dev/null
  probe_state=0
  config_state "$committed_probe" || probe_state=$?
  if [[ "$probe_state" -eq 0 ]]; then
    echo "seed-config: this repo already owns its policy — '${rel_path}' is on ${remote}/${default_br}."
    echo "Nothing changed, no branch created, no PR opened."
    exit 0
  fi
  # Exit 1 carries its message on STDOUT, matching repo-config.sh's convention and what the relaying
  # callers are written against — a caller capturing stdout alone must not relay an empty string.
  echo "seed-config: '${rel_path}' is already committed on ${remote}/${default_br}. Checking it: it is"
  echo "$(state_reason "$probe_state")."
  echo
  echo "Seeding cannot help — a second copy is not what is wrong. Edit the committed file so it"
  echo "states this repo's policy, or delete it from ${remote}/${default_br} and run this again."
  echo "Nothing was changed and no PR was opened."
  exit 1
fi

branch="spec-flow/seed-config-$(date +%Y%m%d%H%M%S)-$$"

# Detached, so no local branch is created and there is nothing left to clean up afterwards; the
# commit reaches the remote by the same `HEAD:refs/heads/...` push archive-batch-pr.sh uses.
step="creating a temporary worktree from ${remote}/${default_br}"
git -C "$root" worktree add --quiet --detach "$work_tree" "${remote}/${default_br}"

step="writing ${rel_path} in the temporary worktree"
mkdir -p "$(dirname "${work_tree}/${rel_path}")"
cat "$content_file" >"${work_tree}/${rel_path}"

step="committing ${rel_path}"
git -C "$work_tree" add -- "$rel_path"
if [[ -z "$(git -C "$work_tree" status --porcelain -- "$rel_path")" ]]; then
  echo "seed-config: '${rel_path}' is unchanged from ${remote}/${default_br}. Nothing to commit."
  exit 1
fi
git -C "$work_tree" commit --quiet -m "spec-flow: this repo states its own test and CI policy

Adds ${rel_path}, the policy spec-flow reads at the start of every run. spec-flow
ships no default and falls back to nothing, so this file is what the pipeline
obeys. Every line of it is this repo's to change."

step="pushing ${branch} to ${remote}"
# Set BEFORE the push, not after. Bash defers a signal handler until the running foreground command
# returns, so an interrupt delivered while the push is in flight runs cleanup at the point where the
# ref is already on the remote — and if this line came after the push, `pushed` would still be empty
# there, cleanup would skip the rollback, and the run would end silently leaving an orphan behind.
# The flag therefore means "we may have pushed", and cleanup asks the remote what is actually true.
pushed='yes'
git -C "$work_tree" push --quiet "$remote" "HEAD:refs/heads/${branch}"

echo "seed-config: pushed branch ${branch} to ${remote}, holding one commit that adds ${rel_path}."

step="opening the pull request"
pr_url=$(gh pr create --head "$branch" --base "$default_br" \
  --title "spec-flow: this repo states its own test and CI policy" \
  --body "Adds \`${rel_path}\`, this repo's own test and CI policy.

spec-flow reads this file at the start of every run. It ships no default and falls back to nothing,
so this file is the only thing the pipeline obeys — and every line of it is yours to change,
including the local/CI split itself.

Seeded by \`/spec-flow:setup\` from a proposal you confirmed. Nothing here was written without your
say-so. Review it as you would any other PR; nothing merges it for you.")

# A PR now holds the branch, so the transaction is complete and the rollback is off. Anything that
# fails past this point must leave the branch alone — it is no longer this script's to unwind.
pushed=''

echo "seed-config: opened ${pr_url}"
echo "Branch ${branch} holds ${rel_path}. Nothing was committed or pushed to ${default_br}, and"
echo "nothing was merged. The check keeps failing until this PR lands on ${default_br} and the"
echo "branch you are working on carries it."
