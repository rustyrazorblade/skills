#!/usr/bin/env bash
# Structural + behavioral test for repo-config.sh and seed-config.sh. Builds throwaway git repos
# under a temp directory and fakes `gh` on PATH, so this runs offline, deterministically, and
# without ever contacting GitHub or opening a pull request — which is what makes seed-config's
# git/gh path testable at all. It exercises the branches a live run never reaches: hostile repo
# roots, every unusable-config state, and the seeding rollback when PR creation fails.
# Exits non-zero if any assertion fails. macOS bash 3.2 compatible (no associative arrays, no
# mapfile). Touches nothing outside its own temp directory.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_config="$script_dir/repo-config.sh"
seed_config="$script_dir/seed-config.sh"

pass_count=0
fail_count=0

pass() {
  echo "PASS: $1"
  pass_count=$((pass_count + 1))
}

fail() {
  echo "FAIL: $1"
  [[ -z "${2:-}" ]] || echo "      $2"
  fail_count=$((fail_count + 1))
}

# Assertion helpers take values rather than a bare `$?`, so a failure can report what it actually
# saw and no exit status can be clobbered between the test and the report.
expect_eq() { # desc expected actual
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

expect_contains() { # desc haystack needle
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected output to contain: $3" ;;
  esac
}

expect_not_contains() { # desc haystack needle
  case "$2" in
    *"$3"*) fail "$1" "expected output NOT to contain: $3" ;;
    *) pass "$1" ;;
  esac
}

command -v git >/dev/null 2>&1 || { echo "test-repo-config: 'git' is required but not on PATH." >&2; exit 1; }
# Resolved BEFORE any stub directory goes on PATH, so the git shim used by the push-interrupt case
# forwards to the real binary rather than recursing into itself.
real_git="$(command -v git)"

tmp_root="$(mktemp -d)"
# chmod first: one case makes a file unreadable, and rm -rf needs the parent traversable. The signal
# handlers exit rather than falling through, for the same reason seed-config.sh's do: bash resumes
# after an INT/TERM handler, so a bare handler would clean up and then carry on running tests
# against a deleted directory.
# Run-once, for the same reason seed-config.sh's cleanup is: the INT and TERM handlers below call it
# and then exit, and the EXIT trap would otherwise call it a second time on the way out.
harness_cleanup_done=''
harness_cleanup() {
  [[ -z "$harness_cleanup_done" ]] || return 0
  harness_cleanup_done='yes'
  chmod -R u+rwX "$tmp_root" 2>/dev/null
  rm -rf "$tmp_root"
}
trap harness_cleanup EXIT
trap 'harness_cleanup; exit 130' INT
trap 'harness_cleanup; exit 143' TERM

# A repo with no policy unless $2 is given. $1 names the directory, which is also how the hostile
# repo-root cases get their metacharacters. Echoes the repo path.
make_repo() {
  local name="$1" policy="${2:-}"
  local d="$tmp_root/repos/$name"
  mkdir -p "$d" || return 1
  git init -q "$d" 2>/dev/null || return 1
  git -C "$d" config user.email test@example.invalid
  git -C "$d" config user.name test
  if [[ -n "$policy" ]]; then
    mkdir -p "$d/spec-flow"
    printf '%s' "$policy" > "$d/spec-flow/TESTING.md"
  fi
  printf '%s' "$d"
}

run_code() { # dir script args... -> echoes exit code, discards output
  local dir="$1" script="$2"
  shift 2
  ( cd "$dir" && "$script" "$@" >/dev/null 2>&1 )
  echo $?
}

run_stdout() { # dir script args... -> echoes stdout only
  local dir="$1" script="$2"
  shift 2
  ( cd "$dir" && "$script" "$@" 2>/dev/null )
}

echo "=== repo-config.sh: exit codes and states ==="

d="$(make_repo configured 'This repo runs nothing locally.')"
expect_eq "a usable policy exits 0" 0 "$(run_code "$d" "$repo_config" check)"
expect_eq "a usable policy prints nothing on any stream" "" "$( cd "$d" && "$repo_config" check 2>&1 )"

d="$(make_repo unconfigured)"
expect_eq "a missing policy exits 1, not 2" 1 "$(run_code "$d" "$repo_config" check)"
out="$(run_stdout "$d" "$repo_config" check)"
expect_contains "a missing policy says so, distinctly from an unusable one" "$out" "not there at all"
expect_contains "a missing policy points at the seeding command" "$out" "spec-flow:setup"

# Unusable is more than absent -- the three states the spec names, each distinguishable.
d="$(make_repo empty_policy '# a heading and nothing else

')"
expect_eq "a policy empty once blanks and comments are stripped exits 1" 1 "$(run_code "$d" "$repo_config" check)"
out="$(run_stdout "$d" "$repo_config" check)"
expect_contains "an empty policy names emptiness, not absence" "$out" "empty once blank and comment lines are stripped"
expect_contains "an empty policy steers AWAY from setup, which would call the repo configured" "$out" "Do NOT run /spec-flow:setup"

d="$(make_repo dir_policy)"
mkdir -p "$d/spec-flow/TESTING.md"
expect_contains "a directory where the policy should be is reported as such" \
  "$(run_stdout "$d" "$repo_config" check)" "not a regular file"

d="$(make_repo unreadable_policy 'unreadable')"
chmod 000 "$d/spec-flow/TESTING.md"
if [[ "$(id -u)" -eq 0 ]]; then
  echo "SKIP: unreadable-policy case (running as root, which can read anything)"
else
  expect_contains "an unreadable policy is reported as unreadable" \
    "$(run_stdout "$d" "$repo_config" check)" "not readable"
fi

# The gitignore diagnostic exists to prevent the mistake that would erase plugin source from git.
d="$(make_repo ignored_config)"
printf 'spec-flow/\n' > "$d/.gitignore"
out="$(run_stdout "$d" "$repo_config" check)"
expect_contains "a gitignored config directory is diagnosed, not merely reported missing" "$out" "matched by a gitignore rule"
expect_contains "the diagnostic names both directories literally, so it cannot contradict itself" "$out" "'spec-flow/' is the COMMITTED"

d="$(make_repo not_ignored)"
expect_not_contains "the gitignore diagnostic stays silent when nothing is ignored" \
  "$(run_stdout "$d" "$repo_config" check)" "matched by a gitignore rule"

echo ""
echo "=== repo-config.sh: environment errors (exit 2) ==="

nongit="$tmp_root/not-a-repo"
mkdir -p "$nongit"
expect_eq "outside a git repository exits 2, distinct from the unconfigured exit 1" 2 \
  "$(run_code "$nongit" "$repo_config" check)"

d="$(make_repo env_cases 'policy')"
for bad in "/absolute" "../traversal" "has space" "has\$dollar" "has\`tick" "has{brace}"; do
  code=$( cd "$d" && SPEC_FLOW_CONFIG_DIR="$bad" "$repo_config" check >/dev/null 2>&1; echo $? )
  expect_eq "SPEC_FLOW_CONFIG_DIR='$bad' is rejected with exit 2" 2 "$code"
done

expect_eq "no subcommand exits 2 via usage" 2 "$(run_code "$d" "$repo_config")"
expect_eq "an unknown subcommand exits 2 via usage" 2 "$(run_code "$d" "$repo_config" bogus)"
expect_eq "an extra argument exits 2 via usage" 2 "$(run_code "$d" "$repo_config" check extra)"

echo ""
echo "=== repo-config.sh: the emitted pointer ==="

d="$(make_repo pointer 'policy')"
line="$(run_stdout "$d" "$repo_config" instruction)"

expect_eq "the pointer is a single line" 0 "$(printf '%s' "$line" | wc -l | tr -d ' ')"

# Two different properties, deliberately not conflated.
#
# The WHOLE LINE is pasted into a JS template literal (implement.workflow.js) and into a JSON string
# value (implement/SKILL.md step 6), so it must carry no backtick, dollar, brace, double quote or
# backslash. Its prose legitimately contains ';', '(' and ')' — harmless in both of those, and the
# line is never executed as a shell command.
#
# The PATH inside it is the part that can end up in a shell command, so it carries the stricter
# shell-metacharacter guarantee. That is asserted by the hostile-repo-root cases below, against the
# emitter, rather than by scanning the prose here.
if printf '%s' "$line" | LC_ALL=C grep -q '[`$"\\{}]'; then
  fail "the pointer breaks no template literal or JSON string" \
    "found: $(printf '%s' "$line" | LC_ALL=C grep -o '[`$"\\{}]' | sort -u | tr -d '\n')"
else
  pass "the pointer breaks no template literal or JSON string"
fi

expect_contains "the pointer names the resolved policy path" "$line" "spec-flow/TESTING.md"
expect_contains "the pointer bounds the policy file's authority to naming commands" "$line" \
  "cannot authorize any action your GUARDRAILS forbid"

# SPEC_FLOW_CONFIG_DIR relocation must actually move where the policy is read from.
d="$(make_repo relocated)"
mkdir -p "$d/config/spec-flow-cfg"
printf 'relocated policy\n' > "$d/config/spec-flow-cfg/TESTING.md"
code=$( cd "$d" && SPEC_FLOW_CONFIG_DIR=config/spec-flow-cfg "$repo_config" check >/dev/null 2>&1; echo $? )
expect_eq "SPEC_FLOW_CONFIG_DIR relocates where the policy is read from" 0 "$code"

relocated_line=$( cd "$d" && SPEC_FLOW_CONFIG_DIR=config/spec-flow-cfg/ "$repo_config" instruction 2>/dev/null )
expect_contains "a trailing slash on SPEC_FLOW_CONFIG_DIR is trimmed, not doubled" \
  "$relocated_line" "config/spec-flow-cfg/TESTING.md"

echo ""
echo "=== repo-config.sh: hostile repo roots (both subcommands must agree) ==="

# The repo root comes from git, not from the character-validated env var, so it is the one part of
# the composed path this script does not choose.
#
# The accept list is as important as the reject list, and is why this section exists in this shape:
# an earlier, wider deny-list refused `Dropbox (Personal)` and `R&D`, which are directory names
# macOS users have by default, and the harness locked that in rather than catching it. Only the five
# characters that actually break a consumer are refused; a space is allowed, which is precisely why
# every consumer must quote the path and why `( ) & ; | * ?` cannot hurt it.
for pair in "plain:accept" "my projects:accept" "Dropbox (Personal):accept" "R&D:accept" "semi;colon:accept" "pipe|char:accept" "star*glob:accept" "has\"quote:reject" "has'quote:reject" "has\$dollar:reject" "has\`tick:reject" "has\\\\slash:reject"; do
  name="${pair%:*}"
  want="${pair##*:}"
  if ! d="$(make_repo "$name" 'policy' 2>/dev/null)"; then
    echo "SKIP: repo root '$name' (this filesystem will not create it)"
    continue
  fi
  c="$(run_code "$d" "$repo_config" check)"
  i="$(run_code "$d" "$repo_config" instruction)"
  if [[ "$want" == "accept" ]]; then
    expect_eq "repo root '$name' accepted by check" 0 "$c"
    expect_eq "repo root '$name' accepted by instruction" 0 "$i"
  else
    expect_eq "repo root '$name' refused by check" 2 "$c"
    expect_eq "repo root '$name' refused by instruction (the two must agree)" 2 "$i"
  fi
done

# A newline in the repo root is the single most damaging character — it would split the one-line
# pointer, and the second line would land in every agent prompt as an instruction. The control-char
# guard is a separate branch of path_rejection_reason from the metacharacter list, and it went
# untested through two rounds, which matters more now that the metacharacter list is narrow.
echo ""
echo "=== repo-config.sh: control characters in the repo root ==="

for ctrl_case in "newline:\\n" "tab:\\t" "carriage-return:\\r" "vertical-tab:\\v"; do
  ctrl_name="${ctrl_case%%:*}"
  ctrl_esc="${ctrl_case##*:}"
  # shellcheck disable=SC2059  # the escape IS the payload under test, not a format-string mistake
  ctrl_dir="$(printf "ctrl-${ctrl_esc}-dir")"
  if ! d="$(make_repo "$ctrl_dir" 'policy' 2>/dev/null)"; then
    echo "SKIP: repo root containing a $ctrl_name (this filesystem will not create it)"
    continue
  fi
  expect_eq "a repo root containing a $ctrl_name is refused by check" 2 "$(run_code "$d" "$repo_config" check)"
  expect_eq "a repo root containing a $ctrl_name is refused by instruction" 2 "$(run_code "$d" "$repo_config" instruction)"
done

# Containment. Every usability test (-f, -r, and the read itself) follows symlinks, so without a
# physical-path check a committed symlink redirects the read to a file outside the repo — which
# every panel agent then loads into context. Symlinks are committable, so the branch under review
# controls this; it is an exfiltration channel, not a repo owner's own choice.
echo ""
echo "=== repo-config.sh: the policy must physically live inside the repo ==="

outside_dir="$tmp_root/outside"
mkdir -p "$outside_dir/cfg"
printf 'pretend secret\n' > "$outside_dir/secret.txt"
printf 'pretend secret policy\n' > "$outside_dir/cfg/TESTING.md"

d="$(make_repo symlinked_policy_file)"
mkdir -p "$d/spec-flow"
ln -s "$outside_dir/secret.txt" "$d/spec-flow/TESTING.md"
expect_eq "a policy file symlinked outside the repo is refused by check" 2 "$(run_code "$d" "$repo_config" check)"
expect_eq "a policy file symlinked outside the repo is refused by instruction" 2 "$(run_code "$d" "$repo_config" instruction)"

d="$(make_repo symlinked_config_dir)"
ln -s "$outside_dir/cfg" "$d/spec-flow"
expect_eq "a config directory symlinked outside the repo is refused by check" 2 "$(run_code "$d" "$repo_config" check)"
expect_eq "a config directory symlinked outside the repo is refused by instruction" 2 "$(run_code "$d" "$repo_config" instruction)"

# Refused even pointing inward: there is no legitimate use, and allowing it would mean trusting the
# link target to stay put.
d="$(make_repo symlinked_policy_inward)"
mkdir -p "$d/real" "$d/spec-flow"
printf 'a real policy line\n' > "$d/real/TESTING.md"
ln -s "$d/real/TESTING.md" "$d/spec-flow/TESTING.md"
expect_eq "a symlinked policy file is refused even when it points inside the repo" 2 \
  "$(run_code "$d" "$repo_config" check)"

# The containment check must not turn an unconfigured repo into an environment error: a missing
# directory is exit 1 with the seeding message, not exit 2.
d="$(make_repo unconfigured_still_exit_1)"
expect_eq "an unconfigured repo still reports missing (1), not an environment error (2)" 1 \
  "$(run_code "$d" "$repo_config" check)"

echo ""
echo "=== repo-config.sh: exactly one policy filename resolves ==="

# The rename from CI.md to TESTING.md is a clean break, by the owner's ruling: no alias, no
# fallback, no did-you-mean. A repo carrying only the previous name is unconfigured and stops the
# pipeline, exactly as one that never had a policy does. Asserted here because "we did not add a
# fallback" is otherwise invisible — nothing else fails if someone adds one later.
d="$(make_repo previous_filename_only)"
mkdir -p "$d/spec-flow"
printf 'a policy under the previous name\n' > "$d/spec-flow/CI.md"
expect_eq "a repo holding only the previous CI.md is unconfigured" 1 \
  "$(run_code "$d" "$repo_config" check)"
previous_name_out="$(run_stdout "$d" "$repo_config" check)"
# The remedy paragraph's assertions below match sentences, not lines. The message is echoed one
# wrapped line at a time, so a needle spanning a wrap breaks whenever the prose re-flows — twice
# already, on edits that changed no meaning. Matching against a whitespace-collapsed copy pins what
# the operator reads instead of where the line happens to end. The absence checks keep using the
# raw text: collapsing must never be what makes a forbidden string disappear.
previous_name_flat="$(printf '%s' "$previous_name_out" | tr '\n' ' ' | tr -s ' ')"
expect_contains "the previous filename is reported missing, not accepted as a substitute" \
  "$previous_name_out" "TESTING.md"
# No did-you-mean either, which is the owner's ruling and not implied by the exit code: a check
# that exited 1 while naming the file it found would still pass the two assertions above.
# "TESTING.md" does not contain "CI.md", so this cannot false-positive on the line above.
expect_not_contains "the previous filename gets no did-you-mean" "$previous_name_out" "CI.md"
# The assertion above reads stdout alone, deliberately: check's contract puts the whole message
# there, and a combined-stream read would stop proving it. So prove the absence on both streams
# too, as a second assertion rather than a changed one — a did-you-mean smuggled onto stderr is
# still a did-you-mean.
expect_not_contains "no did-you-mean reaches stderr either" \
  "$( cd "$d" && "$repo_config" check 2>&1 )" "CI.md"
# Naming nothing is not the same as helping nobody. A repo that used spec-flow under the previous
# filename lands here, and which remedy fits depends on what its own default branch holds — which
# this script cannot see. The message raises that, and routes on it, without naming a filename or
# inspecting the tree.
expect_contains "an existing consumer is warned the remedy depends on their default branch" \
  "$previous_name_out" "the policy filename this version"
# The rebase-does-not-help clause is conditional on what the reader's own default branch carries,
# and both sub-cases are pinned. At upgrade time a branch cut before its default branch was renamed
# satisfies the guard above but wants the rebase remedy: for it, renaming here writes a divergent
# second policy and buys an add/add conflict. An unconditional "rebasing does not help" would send
# that reader past its own fix, so the condition is the assertion, not decoration on it.
# Both needles carry the consequent, not just the condition: a regression that kept the conditions
# and swapped which remedy each one routes to would satisfy a condition-only check. The first also
# carries the negative clause, because without it the two conditions overlap — a default branch
# mid-rename carries both filenames, matches both, and would take the rename verdict, which is the
# add/add conflict this split exists to prevent.
expect_contains "the rename remedy is conditional on the reader's own default branch" \
  "$previous_name_flat" "and not the path named above, rebasing does not help; rename"
expect_contains "and the already-renamed default branch is sent to the rebase remedy instead" \
  "$previous_name_flat" "already carries the path named above, the rebase remedy below is yours"
# The remedy points at the expected path, which the "Missing or unusable" block already printed,
# so the operator never has to leave the terminal to act on it.
expect_contains "and is pointed at the path already printed rather than to a second policy file" \
  "$previous_name_flat" "policy file to the path named above rather than seeding a second one"
# And nothing sends them out of the terminal instead. This repo publishes no release notes: no
# CHANGELOG, no releases file, no tags. Asserted for the same reason as the no-did-you-mean checks
# above — re-adding a dead-end pointer beside the working one breaks nothing else.
expect_not_contains "and is not sent anywhere outside the terminal" \
  "$previous_name_out" "release notes"

echo ""
echo "=== seed-config.sh: argument and content handling ==="

d="$(make_repo seed_args 'policy')"
expect_eq "seed-config with no argument exits 2" 2 "$(run_code "$d" "$seed_config")"
expect_contains "seed-config's usage is its own, unshadowed by the sourced repo-config.sh" \
  "$( cd "$d" && "$seed_config" 2>&1 >/dev/null )" "usage: seed-config.sh"

printf '# comment only\n\n' > "$tmp_root/empty-policy.md"
expect_eq "seeding refuses content empty once stripped, rather than seeding a failing policy" 2 \
  "$(run_code "$d" "$seed_config" "$tmp_root/empty-policy.md")"
expect_eq "seeding refuses a content file that does not exist" 2 \
  "$(run_code "$d" "$seed_config" "$tmp_root/does-not-exist.md")"

echo ""
echo "=== seed-config.sh: the full git/gh path, offline ==="

# A fake `gh` makes the whole push/PR path exercisable with no network and no GitHub account.
# GH_STUB_MODE=fail simulates PR creation failing AFTER the push, the case that used to strand a
# branch on the remote.
fake_bin_dir="$tmp_root/bin"
mkdir -p "$fake_bin_dir"
# The stub LOGS its full argv, not just the first two words. Matching on "$1 $2" alone and
# discarding the rest means a regression that swapped --head and --base, hardcoded 'main', or
# dropped --head entirely would leave every assertion green.
#
# GH_STUB_MODE=fail simulates PR creation failing AFTER the push. GH_STUB_MODE=interrupt reproduces
# an owner pressing Ctrl-C in that same window, by signalling the seed-config process that invoked
# this stub.
cat > "$fake_bin_dir/gh" <<'GHEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_STUB_LOG:-/dev/null}"
case "$1 $2" in
  "repo view") echo "trunk" ;;
  "pr create")
    case "${GH_STUB_MODE:-ok}" in
      fail)
        echo "gh: pull request creation failed (stubbed)" >&2
        exit 1
        ;;
      interrupt)
        # Interrupt the seed-config run mid-PR-creation, the window where the branch is already
        # pushed but `pushed` has not yet been cleared.
        kill -INT "$PPID" 2>/dev/null
        sleep 2
        exit 1
        ;;
    esac
    echo "https://example.invalid/pr/1"
    ;;
  *) echo "gh stub: unhandled invocation: $*" >&2; exit 1 ;;
esac
GHEOF
chmod +x "$fake_bin_dir/gh"
PATH="$fake_bin_dir:$PATH"
export PATH

# A bare repo standing in for the remote, plus a clone. $2 names the remote, so the non-origin
# case is covered too. Echoes the clone path.
make_remote_pair() { # policy remote_name tag
  local policy="$1" remote_name="$2" tag="$3"
  local bare="$tmp_root/remotes/$tag.git"
  local work="$tmp_root/clones/$tag"
  rm -rf "$bare" "$work"
  mkdir -p "$(dirname "$bare")" "$(dirname "$work")"
  git init -q --bare "$bare"
  git -C "$bare" symbolic-ref HEAD refs/heads/trunk
  git init -q -b trunk "$work"
  git -C "$work" config user.email test@example.invalid
  git -C "$work" config user.name test
  echo readme > "$work/README.md"
  if [[ -n "$policy" ]]; then
    mkdir -p "$work/spec-flow"
    printf '%s' "$policy" > "$work/spec-flow/TESTING.md"
  fi
  git -C "$work" add -A >/dev/null
  git -C "$work" commit -qm initial
  git -C "$work" remote add "$remote_name" "$bare"
  git -C "$work" push -q "$remote_name" trunk
  printf '%s' "$work"
}

seed_branch_count() {
  git -C "$1" for-each-ref --format='%(refname:short)' refs/heads | grep -c '^spec-flow/'
}

printf 'This repo runs nothing locally.\n' > "$tmp_root/policy.md"

work="$(make_remote_pair "" origin happy)"
bare="$tmp_root/remotes/happy.git"
trunk_before="$(git -C "$bare" rev-parse trunk)"
GH_STUB_LOG="$tmp_root/gh-happy.log"
export GH_STUB_LOG
expect_eq "seeding a clean repo succeeds" 0 "$(run_code "$work" "$seed_config" "$tmp_root/policy.md")"

# Assert what gh was actually CALLED with, not merely that it was called.
gh_log="$(cat "$tmp_root/gh-happy.log" 2>/dev/null)"
pr_create_line="$(grep '^pr create' "$tmp_root/gh-happy.log" 2>/dev/null)"
expect_contains "gh repo view is asked for the default branch, never assumed" "$gh_log" "repo view --json defaultBranchRef"
expect_contains "gh pr create targets the discovered default branch as --base" "$pr_create_line" "--base trunk"
expect_contains "gh pr create passes the seed branch as --head" "$pr_create_line" "--head spec-flow/seed-config-"
expect_not_contains "gh pr create never hardcodes 'main' as the base" "$pr_create_line" "--base main"
expect_eq "seeding never moves the default branch" "$trunk_before" "$(git -C "$bare" rev-parse trunk)"
expect_eq "seeding leaves exactly one seed branch when a PR holds it" 1 "$(seed_branch_count "$bare")"
expect_eq "seeding never switches the owner's working branch" "trunk" "$(git -C "$work" rev-parse --abbrev-ref HEAD)"
expect_eq "seeding leaves no temporary worktree registered" 1 "$(git -C "$work" worktree list | wc -l | tr -d ' ')"

# The script never deletes a remote ref. When a push happened and no PR was obtained, it REPORTS:
# the branch name and both recovery commands. These assertions therefore check what the operator is
# TOLD, not what the remote ends up holding — the branch is expected to survive, and removing it is
# the operator's call. Automatic rollback was tried four times and broke four different ways; see
# seed-config.sh's header for the list and why the behaviour is now deliberately stateless.
#
# Helper so every "did it tell the operator" assertion checks the same three things: the branch
# name, the command that opens the PR, and the command that deletes the branch.
# Matches the recovery block's OWN labelled line, `  branch: <name>  (on <remote>)`, not the bare
# branch name: the earlier push-success line also prints the name, so a bare-name assertion passes
# even when the recovery report is missing entirely. Verified by silencing the report and watching
# this assertion stay green while its siblings went red.
expect_reports_recovery() { # label output branch
  expect_contains "$1: names the branch in the recovery report" "$2" "branch: $3"
  expect_contains "$1: gives the open-the-PR command" "$2" "gh pr create --head $3"
  expect_contains "$1: gives the delete-the-branch command" "$2" "--delete $3"
}

work="$(make_remote_pair "" origin reports)"
bare="$tmp_root/remotes/reports.git"
trunk_before="$(git -C "$bare" rev-parse trunk)"
fail_out="$( cd "$work" && GH_STUB_MODE=fail "$seed_config" "$tmp_root/policy.md" 2>&1 >/dev/null )"
code=$( cd "$work" && GH_STUB_MODE=fail "$seed_config" "$tmp_root/policy.md" >/dev/null 2>&1; echo $? )
expect_eq "a failed PR creation exits 2 with seed-config's own code, not gh's raw status" 2 "$code"
expect_eq "a failed PR creation still never moves the default branch" "$trunk_before" "$(git -C "$bare" rev-parse trunk)"
failed_branch="$(git -C "$bare" for-each-ref --format='%(refname:short)' refs/heads | grep '^spec-flow/' | head -n 1)"
expect_reports_recovery "a failed PR creation" "$fail_out" "$failed_branch"
expect_not_contains "a failed PR creation never claims to have deleted anything" "$fail_out" "deleted"

# Ctrl-C in the window between the push and the PR. Bash runs an INT handler and then RESUMES, so
# without the run-once sentinel and the exiting handlers this fired twice with contradictory output.
# The branch now survives by design; what must hold is that the operator is told about it.
work="$(make_remote_pair "" origin interrupted)"
bare="$tmp_root/remotes/interrupted.git"
trunk_before="$(git -C "$bare" rev-parse trunk)"
interrupt_out="$( cd "$work" && GH_STUB_MODE=interrupt "$seed_config" "$tmp_root/policy.md" 2>&1 )"
int_branch="$(git -C "$bare" for-each-ref --format='%(refname:short)' refs/heads | grep '^spec-flow/' | head -n 1)"
expect_eq "an interrupt still never moves the default branch" "$trunk_before" "$(git -C "$bare" rev-parse trunk)"
expect_reports_recovery "an interrupt during PR creation" "$interrupt_out" "$int_branch"
expect_eq "an interrupt leaves no temporary worktree registered" 1 "$(git -C "$work" worktree list | wc -l | tr -d ' ')"

# The other interrupt window, one line earlier: a signal delivered while `git push` is IN FLIGHT.
# Bash defers the handler until the command returns, so it lands after the ref is on the remote.
# This is the window where the run once exited completely silently, leaving a branch nobody was told
# about — the failure reporting exists to prevent. The git shim does the real push and then signals,
# which is the ordering that makes this reachable.
push_int_bin="$tmp_root/bin-push-interrupt"
mkdir -p "$push_int_bin"
cat > "$push_int_bin/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    HEAD:refs/heads/spec-flow/*)
      "$real_git" "\$@"
      rc=\$?
      kill -INT "\$PPID" 2>/dev/null
      sleep 1
      exit \$rc
      ;;
  esac
done
exec "$real_git" "\$@"
STUB
chmod +x "$push_int_bin/git"

work="$(make_remote_pair "" origin push_interrupted)"
bare="$tmp_root/remotes/push_interrupted.git"
trunk_before="$(git -C "$bare" rev-parse trunk)"
push_int_out="$( cd "$work" && PATH="$push_int_bin:$PATH" "$seed_config" "$tmp_root/policy.md" 2>&1 )"
push_int_branch="$(git -C "$bare" for-each-ref --format='%(refname:short)' refs/heads | grep '^spec-flow/' | head -n 1)"
expect_eq "an interrupt DURING the push still never moves the default branch" \
  "$trunk_before" "$(git -C "$bare" rev-parse trunk)"
expect_reports_recovery "an interrupt during the push" "$push_int_out" "$push_int_branch"

# The case that ended automatic rollback: the push succeeds, then the remote becomes unreachable.
# `git ls-remote --exit-code` returns non-zero for BOTH "no such ref" and "cannot reach the remote",
# so gating the rollback on it skipped the recovery message entirely and the run went silent. With
# nothing asking the remote anything, the operator is told regardless. The git shim breaks the
# remote by rewriting its URL right after the push, so every later git call against it fails.
unreachable_bin="$tmp_root/bin-unreachable"
mkdir -p "$unreachable_bin"
cat > "$unreachable_bin/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    HEAD:refs/heads/spec-flow/*)
      "$real_git" "\$@"
      rc=\$?
      # Point the remote at a path that does not exist, so anything asking it from here fails.
      "$real_git" -C "\$(pwd)" remote set-url origin /nonexistent/unreachable.git 2>/dev/null
      exit \$rc
      ;;
  esac
done
exec "$real_git" "\$@"
STUB
chmod +x "$unreachable_bin/git"

work="$(make_remote_pair "" origin unreachable)"
bare="$tmp_root/remotes/unreachable.git"
trunk_before="$(git -C "$bare" rev-parse trunk)"
unreachable_out="$( cd "$work" && PATH="$unreachable_bin:$PATH" GH_STUB_MODE=fail "$seed_config" "$tmp_root/policy.md" 2>&1 >/dev/null )"
unreachable_branch="$(git -C "$bare" for-each-ref --format='%(refname:short)' refs/heads | grep '^spec-flow/' | head -n 1)"
expect_eq "an unreachable remote still never moves the default branch" \
  "$trunk_before" "$(git -C "$bare" rev-parse trunk)"
expect_reports_recovery "a remote unreachable after the push" "$unreachable_out" "$unreachable_branch"

# gh resolves its own repo; git must not assume the remote is called origin.
work="$(make_remote_pair "" upstream nonorigin)"
bare="$tmp_root/remotes/nonorigin.git"
expect_eq "seeding works when the remote is not named 'origin'" 0 \
  "$(run_code "$work" "$seed_config" "$tmp_root/policy.md")"
expect_eq "seeding pushes via the resolved remote, not a hardcoded 'origin'" 1 "$(seed_branch_count "$bare")"

work="$(make_remote_pair "an existing policy line" origin already)"
expect_eq "a repo that already owns a usable policy is left alone, exit 0" 0 \
  "$(run_code "$work" "$seed_config" "$tmp_root/policy.md")"
expect_eq "a repo that already owns its policy gets no branch and no PR" 0 \
  "$(seed_branch_count "$tmp_root/remotes/already.git")"

# The dead loop: check rejects the committed file, so seeding must not claim it is fine.
work="$(make_remote_pair '# heading only

' origin committed_empty)"
expect_eq "a committed but unusable policy exits 1 rather than claiming the repo is configured" 1 \
  "$(run_code "$work" "$seed_config" "$tmp_root/policy.md")"
out="$(run_stdout "$work" "$seed_config" "$tmp_root/policy.md")"
expect_contains "seed-config's exit-1 message goes to stdout, where relaying callers read it" \
  "$out" "already committed"

# Clean up here rather than leaving it to the EXIT trap alone, so the temp tree is gone before the
# summary is printed and a caller reading the last line knows nothing is still on disk. The trap
# stays as the safety net for every path that does not reach this point.
harness_cleanup

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
