#!/usr/bin/env bash
# Behavioral test for spawn-issue-manager.sh. Fakes `gh`, `claude` and `sleep` on a PATH built from
# symlinks, so it runs offline and fast, and a case can take one required tool away. It pins every
# exit path (exit code and message) and the order of the pre-spawn checks, so a refactor of the
# script can prove it changed neither. Exits non-zero if any assertion fails. macOS bash 3.2
# compatible (no associative arrays, no mapfile). Touches nothing outside its own temp directory.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
spawn="$script_dir/spawn-issue-manager.sh"

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

for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "test-spawn-issue-manager: '$tool' is required but not on PATH." >&2; exit 1; }
done

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fakes="$tmp_root/fakes"
st="$tmp_root/state"
mkdir -p "$fakes" "$tmp_root/tmp" "$tmp_root/nogit"

# Every fake reads its answers from files in $FAKE_STATE and appends each call to $FAKE_STATE/calls,
# so a case sets up its world by writing files, and asserts on what the script asked for.
cat > "$fakes/gh" <<'GHEOF'
#!/bin/bash
st="$FAKE_STATE"
printf 'gh %s\n' "$*" >> "$st/calls"
get() { if [ -e "$st/$1" ]; then cat "$st/$1"; else printf '%s' "$2"; fi; }
fields="" jq_expr="" body_file=""
prev=""
for a in "$@"; do
  case "$prev" in
    --json) fields="$a" ;;
    --jq) jq_expr="$a" ;;
    --body-file) body_file="$a" ;;
  esac
  prev="$a"
done
# gh prints a --jq result compactly, one value per line, strings raw.
emit() { if [ -n "$jq_expr" ]; then printf '%s' "$1" | jq -rc "$jq_expr"; else printf '%s\n' "$1"; fi; }
case "$1 $2" in
  "issue view")
    if [ -e "$st/fail_view_$fields" ]; then echo "gh: fake failure for --json $fields" >&2; exit 1; fi
    emit "{\"title\":$(get title '"Fix the widget"'),\"subIssuesSummary\":{\"total\":$(get sub_total 0)},\"subIssues\":{\"nodes\":[{\"number\":7,\"state\":\"OPEN\",\"title\":\"Child one\"}]},\"labels\":$(get labels '[]'),\"assignees\":$(get assignees '[]')}"
    ;;
  "api user")
    [ -e "$st/fail_user" ] && exit 1
    emit "{\"login\":$(get login '"me"')}"
    ;;
  "issue edit")
    [ -e "$st/fail_edit" ] && exit 1
    exit 0
    ;;
  "issue comment")
    [ -e "$st/fail_comment" ] && exit 1
    cp "$body_file" "$st/comment_body"
    exit 0
    ;;
  *)
    echo "fake gh: unexpected call: $*" >&2
    exit 1
    ;;
esac
GHEOF

# `claude agents` answers from agents.json. A `respawn` or `--bg` swaps in the registry that
# follows it, when the case provides one. fail_agents_from N fails the Nth and every later
# `claude agents` call, which is how a case reaches a registry that goes away mid-run.
cat > "$fakes/claude" <<'CLEOF'
#!/bin/bash
st="$FAKE_STATE"
printf 'claude %s\n' "$*" >> "$st/calls"
case "$1" in
  agents)
    n=$(( $(cat "$st/agents_count" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$st/agents_count"
    [ -e "$st/fail_agents" ] && exit 1
    if [ -e "$st/fail_agents_from" ] && [ "$n" -ge "$(cat "$st/fail_agents_from")" ]; then exit 1; fi
    cat "$st/agents.json"
    ;;
  logs)
    [ -e "$st/logs_alive" ] && exit 0
    echo "job not found" >&2
    exit 1
    ;;
  respawn)
    [ -e "$st/agents_after_respawn.json" ] && cp "$st/agents_after_respawn.json" "$st/agents.json"
    exit 0
    ;;
  --bg)
    [ -e "$st/fail_bg" ] && exit 1
    [ -e "$st/agents_after_bg.json" ] && cp "$st/agents_after_bg.json" "$st/agents.json"
    exit 0
    ;;
  stop|rm)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
CLEOF

# The script polls with `sleep`; a no-op keeps the poll-exhaustion cases fast.
printf '#!/bin/bash\nexit 0\n' > "$fakes/sleep"
chmod +x "$fakes/gh" "$fakes/claude" "$fakes/sleep"

# A PATH directory holding only what the script needs. Any names given are left out, which is how a
# case reaches the missing-tool exit for one tool at a time.
make_bin() { # dir [tool-to-omit...]
  local dir="$1" tool omit skip
  shift
  mkdir -p "$dir"
  for tool in cat cp cut jq mkdir mktemp rm sed touch tr git gh claude sleep; do
    skip=""
    for omit in "$@"; do [[ "$tool" == "$omit" ]] && skip=yes; done
    [[ -n "$skip" ]] && continue
    if [[ -e "$fakes/$tool" ]]; then
      ln -s "$fakes/$tool" "$dir/$tool"
    else
      ln -s "$(command -v "$tool")" "$dir/$tool"
    fi
  done
}
make_bin "$tmp_root/bin"

repo="$tmp_root/repo"
git init -q "$repo"
root="$(git -C "$repo" rev-parse --show-toplevel)"
worktree="$root/.claude/worktrees/issue-42"

session() { # id name cwd state
  printf '{"id":"%s","name":"%s","cwd":"%s","state":"%s","startedAt":"2026-01-01T00:00:00Z"}' "$1" "$2" "$3" "$4"
}

reset_state() {
  rm -rf "$st"
  mkdir -p "$st"
  echo '[]' > "$st/agents.json"
  : > "$st/calls"
  run_bin="$tmp_root/bin"
  run_dir="$repo"
}

set_st() { # key [value]
  printf '%s' "${2:-}" > "$st/$1"
}

rc=0 out="" err="" calls=""
run_spawn() {
  (cd "$run_dir" && PATH="$run_bin" FAKE_STATE="$st" TMPDIR="$tmp_root/tmp" "$BASH" "$spawn" "$@" \
    >"$st/stdout" 2>"$st/stderr")
  rc=$?
  out="$(cat "$st/stdout")"
  err="$(cat "$st/stderr")"
  calls="$(cat "$st/calls")"
}

# A pre-spawn refusal must leave GitHub and the session registry exactly as it found them.
expect_no_mutation() { # desc
  if grep -qE '^(gh issue edit|gh issue comment|claude --bg|claude respawn|claude stop|claude rm)' "$st/calls"; then
    fail "$1" "mutating calls: $(grep -E '^(gh issue edit|gh issue comment|claude --bg|claude respawn|claude stop|claude rm)' "$st/calls" | tr '\n' ';')"
  else
    pass "$1"
  fi
}

# The line number of the first call matching a fixed string, or 0.
call_line() { # needle
  local n
  n="$(grep -nF -- "$1" "$st/calls" | head -1 | cut -d: -f1)"
  echo "${n:-0}"
}

usage_line="usage: spawn-issue-manager.sh <issue-number> [owner-instructions] [--backlog-overlap-file <path>]"
fresh_name="issue-manager-42-fix-the-widget"

# ---------------------------------------------------------------------------
# Argument parsing: every usage exit, and the not-readable shortlist exit.
# ---------------------------------------------------------------------------
for args in "none" "flag-no-value" "flag-empty" "flag-eq-empty" "unknown-flag" "three-positionals" "non-numeric"; do
  reset_state
  case "$args" in
    none) run_spawn ;;
    flag-no-value) run_spawn 42 --backlog-overlap-file ;;
    flag-empty) run_spawn 42 --backlog-overlap-file "" ;;
    flag-eq-empty) run_spawn 42 --backlog-overlap-file= ;;
    unknown-flag) run_spawn 42 --bogus ;;
    three-positionals) run_spawn 42 "first" "second" ;;
    non-numeric) run_spawn abc ;;
  esac
  expect_eq "usage ($args): exits 2" 2 "$rc"
  expect_eq "usage ($args): prints the usage line on stderr" "$usage_line" "$err"
  expect_eq "usage ($args): calls nothing" "" "$calls"
done

reset_state
run_spawn 42 --backlog-overlap-file "$tmp_root/no-such-file"
expect_eq "unreadable shortlist: exits 2" 2 "$rc"
expect_eq "unreadable shortlist: names the file" \
  "spawn-issue-manager: --backlog-overlap-file '$tmp_root/no-such-file' is not readable" "$err"
expect_eq "unreadable shortlist: calls nothing" "" "$calls"

reset_state
run_spawn --backlog-overlap-file "$tmp_root/no-such-file"
expect_eq "order: a missing issue number is reported before an unreadable shortlist" "$usage_line" "$err"

reset_state
run_spawn abc --backlog-overlap-file "$tmp_root/no-such-file"
expect_eq "order: an unreadable shortlist is reported before a non-numeric issue number (exit)" 2 "$rc"
expect_contains "order: an unreadable shortlist is reported before a non-numeric issue number" "$err" "is not readable"

# ---------------------------------------------------------------------------
# Required tools, checked in the order claude, jq, gh, git, after argument checks.
# ---------------------------------------------------------------------------
for missing in claude jq gh git; do
  reset_state
  run_bin="$tmp_root/bin-no-$missing"
  make_bin "$run_bin" "$missing"
  run_spawn 42
  expect_eq "missing $missing: exits 1" 1 "$rc"
  expect_contains "missing $missing: names it" "$err" "spawn-issue-manager: '$missing' is required but not on PATH."
  expect_contains "missing $missing: names the manual fallback" "$err" "an agent can replicate"
  expect_no_mutation "missing $missing: changes nothing"
done

reset_state
run_bin="$tmp_root/bin-no-claude-jq"
make_bin "$run_bin" claude jq
run_spawn 42
expect_contains "order: claude is checked before jq" "$err" "'claude' is required"

reset_state
run_bin="$tmp_root/bin-no-jq-gh"
make_bin "$run_bin" jq gh
run_spawn 42
expect_contains "order: jq is checked before gh" "$err" "'jq' is required"

reset_state
run_bin="$tmp_root/bin-no-gh-git"
make_bin "$run_bin" gh git
run_spawn 42
expect_contains "order: gh is checked before git" "$err" "'gh' is required"

reset_state
run_bin="$tmp_root/bin-no-claude"
run_spawn abc
expect_eq "order: a non-numeric issue number is reported before a missing tool" 2 "$rc"

# ---------------------------------------------------------------------------
# The sub-issue check.
# ---------------------------------------------------------------------------
reset_state
set_st "fail_view_title,subIssuesSummary"
run_spawn 42
expect_eq "sub-issue view fails: exits 1" 1 "$rc"
expect_contains "sub-issue view fails: says so" "$err" "spawn-issue-manager: 'gh issue view' failed while checking #42 for sub-issues."
expect_contains "sub-issue view fails: relays gh's error" "$err" "gh said: gh: fake failure for --json title,subIssuesSummary"
expect_contains "sub-issue view fails: names the old-gh cause" "$err" "it's too old — upgrade gh."
expect_no_mutation "sub-issue view fails: changes nothing"

reset_state
set_st sub_total 2
run_spawn 42
expect_eq "parent issue: exits 1" 1 "$rc"
expect_contains "parent issue: refuses it" "$err" "spawn-issue-manager: #42 (\"Fix the widget\") has 2 sub-issue(s) — it's a"
expect_contains "parent issue: lists its sub-issues" "$err" "  #7 (OPEN) Child one"
expect_no_mutation "parent issue: changes nothing"

reset_state
run_bin="$tmp_root/bin-no-claude"
set_st sub_total 2
run_spawn 42
expect_contains "order: a missing tool is reported before a parent issue" "$err" "'claude' is required"

# ---------------------------------------------------------------------------
# The repo root, then the registry read.
# ---------------------------------------------------------------------------
reset_state
run_dir="$tmp_root/nogit"
run_spawn 42
expect_eq "outside a repo: exits 1" 1 "$rc"
expect_contains "outside a repo: says so" "$err" "spawn-issue-manager: couldn't resolve the repo root ('git rev-parse --show-toplevel' failed)."
expect_contains "outside a repo: says where to run it" "$err" "Run this from inside the target repo's primary checkout."
expect_no_mutation "outside a repo: changes nothing"

reset_state
run_dir="$tmp_root/nogit"
set_st sub_total 2
run_spawn 42
expect_contains "order: a parent issue is reported before a missing repo root" "$err" "has 2 sub-issue(s)"

reset_state
set_st fail_agents
run_spawn 42
expect_eq "registry read fails: exits 1" 1 "$rc"
expect_eq "registry read fails: says so" \
  "spawn-issue-manager: 'claude agents --json --all' failed — can't check for an existing session." "$err"
expect_no_mutation "registry read fails: changes nothing"

reset_state
run_dir="$tmp_root/nogit"
set_st fail_agents
run_spawn 42
expect_contains "order: a missing repo root is reported before a failed registry read" "$err" "couldn't resolve the repo root"

# ---------------------------------------------------------------------------
# A live session already exists.
# ---------------------------------------------------------------------------
reset_state
echo "[$(session s1 issue-manager-42-old-title "$worktree" working)]" > "$st/agents.json"
set_st logs_alive
run_spawn 42
expect_eq "live session: exits 1" 1 "$rc"
expect_contains "live session: reports it by its registered name" "$err" \
  "already running: issue-manager-42-old-title s1 (attach: claude agents — select s1)"
expect_contains "live session: names the stale-record escape" "$err" "'claude rm s1' and re-run this script."
expect_no_mutation "live session: changes nothing"

reset_state
echo "[$(session s1 issue-manager-42-old-title "$worktree" blocked)]" > "$st/agents.json"
set_st logs_alive
run_spawn 42 "merge on green"
expect_eq "live session with instructions: exits 1" 1 "$rc"
expect_contains "live session with instructions: posts them" "$err" \
  "spawn-issue-manager: posted owner instructions to #42 — issue-manager-42-old-title reads them at its next seam check."
expect_eq "live session with instructions: the comment carries the marker and the text" \
  "$(printf '🤖 Owner instructions\n\nmerge on green')" "$(cat "$st/comment_body")"
expect_not_contains "live session with instructions: spawns nothing" "$calls" "claude --bg"

reset_state
echo "[$(session s1 issue-manager-42-old-title "$worktree" working)]" > "$st/agents.json"
set_st logs_alive
set_st fail_comment
run_spawn 42 "merge on green"
expect_eq "live session, comment fails: exits 1" 1 "$rc"
expect_contains "live session, comment fails: says so" "$err" "spawn-issue-manager: couldn't post owner instructions to #42. The session is unaffected;"
expect_contains "live session, comment fails: still reports the live session" "$err" "already running: issue-manager-42-old-title s1"

# A live session whose `state` is live but whose process is gone falls through to the respawn path.
reset_state
echo "[$(session s1 issue-manager-42-old-title "$root" working)]" > "$st/agents.json"
echo "[$(session s1 issue-manager-42-old-title "$worktree" working)]" > "$st/agents_after_respawn.json"
run_spawn 42
expect_eq "stale live state: exits 0 after respawning" 0 "$rc"
expect_contains "stale live state: says the entry is stale" "$err" \
  "spawn-issue-manager: issue-manager-42-old-title (s1) shows state=working in the registry, but"
expect_contains "stale live state: respawns" "$calls" "claude respawn s1"

# ---------------------------------------------------------------------------
# The respawn path: a past session for this issue in this repo.
# ---------------------------------------------------------------------------
respawn_world() { # state
  reset_state
  echo "[$(session s1 issue-manager-42-old-title "$root" "$1")]" > "$st/agents.json"
  echo "[$(session s1 issue-manager-42-old-title "$worktree" working)]" > "$st/agents_after_respawn.json"
}

respawn_world stopped
set_st labels '[{"name":"agent:active"}]'
set_st assignees '[{"login":"alice"}]'
run_spawn 42
expect_eq "respawn, claimed by someone else: exits 1" 1 "$rc"
expect_contains "respawn, claimed by someone else: names them" "$err" \
  "already active: issue #42 carries agent:active, assigned to alice (not you) —"
expect_no_mutation "respawn, claimed by someone else: changes nothing"

respawn_world stopped
set_st labels '[{"name":"agent:active"}]'
set_st assignees '[{"login":"alice"},{"login":"me"}]'
run_spawn 42
expect_eq "respawn, claimed by me among others: respawns" 0 "$rc"

respawn_world stopped
set_st fail_view_labels
run_spawn 42
expect_eq "respawn, label read fails: fails open and respawns" 0 "$rc"

respawn_world "done"
run_spawn 42
expect_eq "respawn: exits 0" 0 "$rc"
expect_eq "respawn: prints the session line on stdout" \
  "issue-manager-42-old-title s1 (\"Fix the widget\") — attach: claude agents — select s1" "$out"
expect_contains "respawn: says it is resuming" "$err" \
  "resuming: issue-manager-42-old-title was done — respawning s1 in its existing worktree"
expect_contains "respawn: sets agent:active" "$calls" "gh issue edit 42 --add-label agent:active"
expect_not_contains "respawn: never starts a fresh session" "$calls" "claude --bg"

respawn_world stopped
set_st fail_edit
run_spawn 42
expect_eq "respawn, label set fails: still exits 0" 0 "$rc"
expect_contains "respawn, label set fails: warns" "$err" \
  "spawn-issue-manager: warning — couldn't set agent:active on #42 after respawn"

respawn_world stopped
printf -- '- 7: Some title — overlaps\n' > "$tmp_root/shortlist"
run_spawn 42 "auto-approve seam 1" --backlog-overlap-file "$tmp_root/shortlist"
expect_eq "respawn with instructions and shortlist: exits 0" 0 "$rc"
expect_contains "respawn with instructions: posts them" "$err" \
  "spawn-issue-manager: posted owner instructions to #42 — issue-manager-42-old-title (s1) reads them fresh at its next seam check."
expect_eq "respawn with shortlist: writes it into the worktree under an issue header" \
  "$(printf 'issue: 42\n- 7: Some title — overlaps')" "$(cat "$worktree/.spec-flow/backlog-overlap")"
expect_contains "respawn with shortlist: says so" "$err" \
  "spawn-issue-manager: updated .spec-flow/backlog-overlap for issue-manager-42-old-title (s1)."
rm -rf "$root/.claude"

respawn_world stopped
set_st fail_agents_from 2
run_spawn 42
expect_eq "respawn, registry never answers: exits 1" 1 "$rc"
expect_contains "respawn, registry never answers: says nothing was changed" "$err" \
  "failed on every attempt, so its working directory could not be confirmed. Nothing was"
expect_not_contains "respawn, registry never answers: does not stop the session" "$calls" "claude stop"
expect_not_contains "respawn, registry never answers: leaves the label" "$calls" "gh issue edit"

respawn_world stopped
rm -f "$st/agents_after_respawn.json"
run_spawn 42
expect_eq "respawn lands in the primary checkout: exits 1" 1 "$rc"
expect_contains "respawn lands in the primary checkout: says so" "$err" \
  "spawn-issue-manager: respawned issue-manager-42-old-title (s1) landed in '$root',"
expect_contains "respawn lands in the primary checkout: stops the session" "$calls" "claude stop s1"
expect_contains "respawn lands in the primary checkout: removes the record" "$calls" "claude rm s1"
expect_contains "respawn lands in the primary checkout: clears the label" "$calls" "gh issue edit 42 --remove-label agent:active"

respawn_world stopped
echo "[$(session s1 issue-manager-42-old-title "$worktree" failed)]" > "$st/agents_after_respawn.json"
run_spawn 42
expect_eq "respawned session is failed: exits 1" 1 "$rc"
expect_contains "respawned session is failed: says so" "$err" \
  "spawn-issue-manager: issue-manager-42-old-title (s1) is failed — check 'claude logs s1'"
expect_contains "respawned session is failed: clears the label" "$calls" "gh issue edit 42 --remove-label agent:active"

respawn_world stopped
set_st fail_agents_from 3
run_spawn 42
expect_eq "respawn, final state unreadable: exits 0" 0 "$rc"
expect_contains "respawn, final state unreadable: warns" "$err" \
  "spawn-issue-manager: warning — couldn't confirm final state ('claude agents --json --all' failed); issue-manager-42-old-title (s1) is running regardless."

# The lookup: the legacy prefix matches; a longer number, another repo, and a null name do not.
reset_state
echo "[$(session s9 issue-pm-42-legacy "$root" stopped)]" > "$st/agents.json"
echo "[$(session s9 issue-pm-42-legacy "$worktree" working)]" > "$st/agents_after_respawn.json"
run_spawn 42
expect_contains "lookup: a legacy issue-pm- session is respawned" "$calls" "claude respawn s9"

reset_state
echo "[{\"id\":\"sx\",\"name\":null,\"cwd\":null,\"state\":\"working\",\"startedAt\":\"2026-01-01T00:00:00Z\"},$(session s8 issue-manager-420-other "$root" stopped),$(session s7 issue-manager-42-elsewhere /somewhere/else stopped)]" > "$st/agents.json"
echo "[$(session s2 "$fresh_name" "$worktree" working)]" > "$st/agents_after_bg.json"
run_spawn 42
expect_eq "lookup: a null entry, issue 420, and another repo's issue 42 leave a fresh spawn" 0 "$rc"
expect_not_contains "lookup: nothing unrelated is respawned" "$calls" "claude respawn"

# ---------------------------------------------------------------------------
# The fresh-spawn path: no past session for this issue in this repo.
# ---------------------------------------------------------------------------
fresh_world() {
  reset_state
  echo "[$(session s2 "$fresh_name" "$worktree" working)]" > "$st/agents_after_bg.json"
}

fresh_world
set_st fail_view_labels
run_spawn 42
expect_eq "fresh, label read fails: exits 1" 1 "$rc"
expect_contains "fresh, label read fails: says so" "$err" \
  "spawn-issue-manager: 'gh issue view' failed — can't verify whether #42 is already"
expect_no_mutation "fresh, label read fails: changes nothing"

fresh_world
set_st labels '[{"name":"agent:active"}]'
set_st assignees '[{"login":"alice"}]'
run_spawn 42
expect_eq "fresh, already active: exits 1" 1 "$rc"
expect_contains "fresh, already active: names the assignee" "$err" \
  "already active: issue #42 carries agent:active (assignee: alice) — an issue-manager may be running on another machine"
expect_no_mutation "fresh, already active: changes nothing"

fresh_world
set_st fail_user
run_spawn 42
expect_eq "fresh, identity unknown: exits 1" 1 "$rc"
expect_contains "fresh, identity unknown: says so" "$err" \
  "spawn-issue-manager: couldn't verify your GitHub identity ('gh api user' failed) — check"
expect_no_mutation "fresh, identity unknown: changes nothing"

fresh_world
set_st fail_view_assignees
run_spawn 42
expect_eq "fresh, assignees unknown: exits 1" 1 "$rc"
expect_contains "fresh, assignees unknown: says so" "$err" \
  "spawn-issue-manager: couldn't check #42's assignees ('gh issue view' failed) — check"
expect_no_mutation "fresh, assignees unknown: changes nothing"

fresh_world
set_st assignees '[{"login":"alice"}]'
run_spawn 42
expect_eq "fresh, assigned to someone else: exits 1" 1 "$rc"
expect_eq "fresh, assigned to someone else: says so" \
  "issue #42 is already assigned to alice (not you) — not spawning; that's their claim." "$err"
expect_no_mutation "fresh, assigned to someone else: changes nothing"

fresh_world
set_st labels '[{"name":"agent:active"}]'
set_st fail_user
run_spawn 42
expect_contains "order: agent:active is reported before an unknown identity" "$err" "already active: issue #42"

fresh_world
set_st fail_user
set_st fail_view_assignees
run_spawn 42
expect_contains "order: an unknown identity is reported before unknown assignees" "$err" "couldn't verify your GitHub identity"

fresh_world
set_st fail_bg
run_spawn 42
expect_eq "fresh, launch fails: exits 1" 1 "$rc"
expect_eq "fresh, launch fails: says so" \
  "spawn-issue-manager: 'claude --bg' itself failed to launch $fresh_name" "$err"
add_at="$(call_line "gh issue edit 42 --add-label agent:active")"
remove_at="$(call_line "gh issue edit 42 --remove-label agent:active")"
if [[ "$add_at" -gt 0 && "$remove_at" -gt "$add_at" ]]; then
  pass "fresh, launch fails: sets the label, then rolls it back"
else
  fail "fresh, launch fails: sets the label, then rolls it back" "add at $add_at, remove at $remove_at"
fi

fresh_world
rm -f "$st/agents_after_bg.json"
run_spawn 42
expect_eq "fresh, session never registers: exits 1" 1 "$rc"
expect_contains "fresh, session never registers: says so" "$err" \
  "spawn-issue-manager: launched $fresh_name, but it did not appear in 'claude agents --json --all'"
expect_not_contains "fresh, session never registers: leaves the label set" "$calls" "--remove-label"

fresh_world
run_spawn 42
expect_eq "fresh: exits 0" 0 "$rc"
expect_eq "fresh: prints the session line on stdout" \
  "$fresh_name s2 (\"Fix the widget\") — attach: claude agents — select s2" "$out"
expect_eq "fresh: prints nothing on stderr" "" "$err"
add_at="$(call_line "gh issue edit 42 --add-label agent:active")"
bg_at="$(call_line "claude --bg")"
if [[ "$add_at" -gt 0 && "$bg_at" -gt "$add_at" ]]; then
  pass "fresh: sets agent:active before launching"
else
  fail "fresh: sets agent:active before launching" "add at $add_at, --bg at $bg_at"
fi
expect_contains "fresh: launches the issue-manager agent under the slugged name" "$calls" \
  "claude --bg --agent spec-flow:issue-manager --name $fresh_name --permission-mode auto"
expect_contains "fresh: the prompt isolates into the issue's worktree first" "$calls" \
  "call the EnterWorktree tool with name: \"issue-42\""
expect_contains "fresh: with no instructions, the prompt keeps the default stops" "$calls" \
  "Stop at both owner approval points, exactly as your agent instructions describe."

fresh_world
run_spawn 42 "auto-approve seam 1"
expect_eq "fresh with instructions: exits 0" 0 "$rc"
expect_eq "fresh with instructions: posts them as a marked comment" \
  "$(printf '🤖 Owner instructions\n\nauto-approve seam 1')" "$(cat "$st/comment_body")"
expect_contains "fresh with instructions: the prompt carries them" "$calls" \
  "where they're silent on a given point, the default (stop and wait) still applies: \"auto-approve seam 1\""

fresh_world
printf -- '- 7: Some title — overlaps\n' > "$tmp_root/shortlist"
run_spawn 42 --backlog-overlap-file "$tmp_root/shortlist"
expect_eq "fresh with shortlist: exits 0" 0 "$rc"
overlap_tmp="$(find "$tmp_root/tmp" -name 'spec-flow-overlap-42.*' | head -1)"
expect_eq "fresh with shortlist: restamps it into a temp file under an issue header" \
  "$(printf 'issue: 42\n- 7: Some title — overlaps')" "$(cat "$overlap_tmp" 2>/dev/null)"
expect_contains "fresh with shortlist: the prompt names the temp file, not its contents" "$calls" \
  "copy the file at $overlap_tmp to .spec-flow/backlog-overlap"
expect_not_contains "fresh with shortlist: the prompt never carries the shortlist text" "$calls" "Some title"
rm -f "$tmp_root"/tmp/spec-flow-overlap-42.*

fresh_world
printf -- '- 7: Some title — overlaps\n' > "$tmp_root/shortlist"
echo "[$(session s2 "$fresh_name" "$worktree" failed)]" > "$st/agents_after_bg.json"
run_spawn 42 --backlog-overlap-file "$tmp_root/shortlist"
expect_eq "fresh session is failed: exits 1" 1 "$rc"
expect_contains "fresh session is failed: says so" "$err" \
  "spawn-issue-manager: $fresh_name (s2) is failed — check 'claude logs s2'"
expect_contains "fresh session is failed: clears the label" "$calls" "gh issue edit 42 --remove-label agent:active"
expect_eq "fresh session is failed: removes the shortlist temp file" "" \
  "$(find "$tmp_root/tmp" -name 'spec-flow-overlap-42.*')"

fresh_world
set_st fail_agents_from 3
run_spawn 42
expect_eq "fresh, final state unreadable: exits 0" 0 "$rc"
expect_contains "fresh, final state unreadable: warns" "$err" \
  "spawn-issue-manager: warning — couldn't confirm final state ('claude agents --json --all' failed); $fresh_name (s2) is running regardless."

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
