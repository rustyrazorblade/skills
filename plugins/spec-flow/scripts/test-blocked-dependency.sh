#!/usr/bin/env bash
# Behavioral test for blocked-dependency.sh. Fakes `gh` on PATH, so it runs offline, and records
# every call, so each check can assert what the script asked GitHub to do and what it did not. One
# check per criterion of add, add-external, clear, clear-external, sweep and the usage path. Exits
# non-zero if any assertion fails. macOS bash 3.2 compatible (no associative arrays, no mapfile).
# Touches nothing outside its own temp directory.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
dep="$script_dir/blocked-dependency.sh"

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

command -v jq >/dev/null 2>&1 || { echo "test-blocked-dependency: 'jq' is required but not on PATH." >&2; exit 1; }

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fakes="$tmp_root/fakes"
st="$tmp_root/state"
mkdir -p "$fakes"

# The fake answers from files in $FAKE_STATE: links.json is issue N's native blocked_by list, as the
# REST API returns it; labels.json is its labels. A fail_<name> file makes that one call fail. Every
# call is appended to $FAKE_STATE/calls, one per line, and every comment body to comments.
cat > "$fakes/gh" <<'GHEOF'
#!/bin/bash
st="$FAKE_STATE"
printf 'gh %s\n' "$*" >> "$st/calls"
method=GET jq_expr="" body="" prev=""
for a in "$@"; do
  case "$prev" in
    -X) method="$a" ;;
    --jq) jq_expr="$a" ;;
    --body) body="$a" ;;
  esac
  prev="$a"
done
emit() { if [ -n "$jq_expr" ]; then printf '%s' "$1" | jq -r "$jq_expr"; else printf '%s\n' "$1"; fi; }
failing() {
  if [ -e "$st/fail_$1" ]; then
    echo "gh: fake failure: $1" >&2
    exit 1
  fi
}
REPO="https://api.github.com/repos/me/this"
if [ "$1" = api ]; then
  path="$2"
  case "$method $path" in
    "GET repos/{owner}/{repo}")
      failing repo
      emit "{\"url\":\"$REPO\"}"
      ;;
    "GET repos/{owner}/{repo}/issues/"*/dependencies/blocked_by)
      failing list
      emit "$(cat "$st/links.json" 2>/dev/null || echo '[]')"
      ;;
    "POST repos/{owner}/{repo}/issues/"*/dependencies/blocked_by)
      failing post
      echo '{}'
      ;;
    "DELETE repos/{owner}/{repo}/issues/"*/dependencies/blocked_by/*)
      failing delete
      echo '{}'
      ;;
    "GET repos/{owner}/{repo}/issues/"*)
      failing resolve
      emit "{\"id\":$((1000 + ${path##*/}))}"
      ;;
    *)
      echo "fake gh: unexpected api call: $*" >&2
      exit 1
      ;;
  esac
  exit 0
fi
case "$1 $2" in
  "issue edit")
    case "$*" in
      *--add-label*) failing add_label ;;
      *--remove-label*) failing remove_label ;;
    esac
    ;;
  "issue comment")
    failing comment
    printf '%s\n' "$body" >> "$st/comments"
    ;;
  "issue view")
    failing view
    emit "{\"labels\":$(cat "$st/labels.json" 2>/dev/null || echo '[]')}"
    ;;
  *)
    echo "fake gh: unexpected call: $*" >&2
    exit 1
    ;;
esac
GHEOF
chmod +x "$fakes/gh"

reset_state() {
  rm -rf "$st"
  mkdir -p "$st"
  : > "$st/calls"
  : > "$st/comments"
}

set_st() { # key [value]
  printf '%s' "${2:-}" > "$st/$1"
}

link() { # number [repo] -- one item of the REST blocked_by list; its id is the blocking issue's
  printf '{"id":%s,"number":%s,"repository_url":"https://api.github.com/repos/%s"}' \
    "$((1000 + $1))" "$1" "${2:-me/this}"
}

rc=0 err="" calls="" comments=""
run_dep() {
  PATH="$fakes:$PATH" FAKE_STATE="$st" "$BASH" "$dep" "$@" >/dev/null 2>"$st/stderr"
  rc=$?
  err="$(cat "$st/stderr")"
  calls="$(cat "$st/calls")"
  comments="$(cat "$st/comments")"
}

# ---------------------------------------------------------------------------
# add <N> <M> <reason>: a native link and a comment, never the label.
# ---------------------------------------------------------------------------
reset_state
run_dep add 12 77 "needs the API"
expect_eq "add, new link: exits 0" 0 "$rc"
expect_contains "add, new link: creates the native link to #77's id" "$calls" \
  "gh api repos/{owner}/{repo}/issues/12/dependencies/blocked_by -F issue_id=1077 -X POST"
expect_eq "add, new link: posts the ⛔ Blocked on comment" "⛔ Blocked on #77 — needs the API" "$comments"
expect_not_contains "add, new link: never adds the blocked label" "$calls" "--add-label"

reset_state
echo "[$(link 77)]" > "$st/links.json"
run_dep add 12 77 "a newer reason"
expect_eq "add, existing link: exits 0" 0 "$rc"
expect_not_contains "add, existing link: creates no second link" "$calls" "-X POST"
expect_eq "add, existing link: still posts the comment" "⛔ Blocked on #77 — a newer reason" "$comments"
expect_not_contains "add, existing link: never adds the blocked label" "$calls" "--add-label"

reset_state
echo "[$(link 77 other/repo)]" > "$st/links.json"
run_dep add 12 77 "needs the API"
expect_eq "add, a same-numbered link in another repo: exits 0" 0 "$rc"
expect_contains "add, a same-numbered link in another repo: still links this repo's #77" "$calls" "-F issue_id=1077 -X POST"

reset_state
set_st fail_post
run_dep add 12 77 "needs the API"
expect_eq "add, link fails: exits 1" 1 "$rc"
expect_contains "add, link fails: says nothing was applied" "$err" "nothing was applied"
expect_eq "add, link fails: posts no comment" "" "$comments"
expect_not_contains "add, link fails: never adds the blocked label" "$calls" "--add-label"

reset_state
set_st fail_resolve
run_dep add 12 77 "needs the API"
expect_eq "add, blocker unresolvable: exits 1" 1 "$rc"
expect_contains "add, blocker unresolvable: says nothing was applied" "$err" "nothing was applied"
expect_not_contains "add, blocker unresolvable: creates no link" "$calls" "-X POST"
expect_eq "add, blocker unresolvable: posts no comment" "" "$comments"

reset_state
set_st fail_list
run_dep add 12 77 "needs the API"
expect_eq "add, links unreadable: exits 1" 1 "$rc"
expect_contains "add, links unreadable: says nothing was applied" "$err" "nothing was applied"
expect_not_contains "add, links unreadable: creates no link" "$calls" "-X POST"

reset_state
set_st fail_comment
run_dep add 12 77 "needs the API"
expect_eq "add, comment fails: exits 1" 1 "$rc"
expect_contains "add, comment fails: says the link is in place" "$err" "link is in place"
expect_contains "add, comment fails: says the comment was not posted" "$err" "comment was not posted"
expect_not_contains "add, comment fails: never adds the blocked label" "$calls" "--add-label"

# ---------------------------------------------------------------------------
# add-external <N> <reason>: the label and a `Blocked by:` comment.
# ---------------------------------------------------------------------------
reset_state
run_dep add-external 12 "waiting on vendor contract"
expect_eq "add-external: exits 0" 0 "$rc"
expect_contains "add-external: adds the blocked label" "$calls" "gh issue edit 12 --add-label blocked"
expect_eq "add-external: posts the Blocked by comment" "Blocked by: waiting on vendor contract" "$comments"
label_at="$(grep -n -- '--add-label blocked' "$st/calls" | head -1 | cut -d: -f1)"
comment_at="$(grep -n 'gh issue comment' "$st/calls" | head -1 | cut -d: -f1)"
if [[ -n "$label_at" && -n "$comment_at" && "$label_at" -lt "$comment_at" ]]; then
  pass "add-external: labels first, then comments"
else
  fail "add-external: labels first, then comments" "label at '$label_at', comment at '$comment_at'"
fi
expect_not_contains "add-external: creates no native link" "$calls" "dependencies"

reset_state
run_dep add-external 12 "waiting on vendor contract"
run_dep add-external 12 "waiting on legal review"
expect_eq "add-external, a second reason: exits 0" 0 "$rc"
expect_eq "add-external, a second reason: posts it after the first, so it is the newest" \
  "$(printf 'Blocked by: waiting on vendor contract\nBlocked by: waiting on legal review')" "$comments"

reset_state
set_st fail_comment
run_dep add-external 12 "waiting on vendor contract"
expect_eq "add-external, comment fails: exits 1" 1 "$rc"
expect_contains "add-external, comment fails: says the label was applied" "$err" "label is on #12"
expect_contains "add-external, comment fails: says the comment was not" "$err" "comment was not posted"

reset_state
set_st fail_add_label
run_dep add-external 12 "waiting on vendor contract"
expect_eq "add-external, label fails: exits 1" 1 "$rc"
expect_contains "add-external, label fails: says nothing was applied" "$err" "nothing was applied"
expect_eq "add-external, label fails: posts no comment" "" "$comments"

# ---------------------------------------------------------------------------
# clear <N> <M>: removes a wrong issue-to-issue link in this repo. Never touches the label.
# ---------------------------------------------------------------------------
reset_state
echo "[$(link 77),$(link 88)]" > "$st/links.json"
run_dep clear 12 77
expect_eq "clear, link present: exits 0" 0 "$rc"
expect_contains "clear, link present: deletes the link to #77" "$calls" \
  "gh api repos/{owner}/{repo}/issues/12/dependencies/blocked_by/1077 -X DELETE"
expect_not_contains "clear, link present: leaves the link to #88" "$calls" "blocked_by/1088"
expect_contains "clear, link present: comments that the dependency on #77 was removed" "$comments" "#77"
expect_contains "clear, link present: the comment says removed" "$comments" "removed"
expect_not_contains "clear, link present: the comment does not say #77 landed" "$comments" "landed"
expect_not_contains "clear, link present: leaves the label alone" "$calls" "--remove-label"
expect_not_contains "clear, link present: adds no label" "$calls" "--add-label"

reset_state
run_dep clear 12 77
expect_eq "clear, no link: exits 0" 0 "$rc"
expect_eq "clear, no link: posts no comment" "" "$comments"
expect_not_contains "clear, no link: deletes nothing" "$calls" "-X DELETE"

reset_state
echo "[$(link 77 other/repo)]" > "$st/links.json"
run_dep clear 12 77
expect_eq "clear, same number in another repo: exits 0" 0 "$rc"
expect_not_contains "clear, same number in another repo: leaves that link in place" "$calls" "-X DELETE"
expect_eq "clear, same number in another repo: posts no comment" "" "$comments"

reset_state
echo "[$(link 77)]" > "$st/links.json"
set_st fail_delete
run_dep clear 12 77
expect_eq "clear, delete fails: exits 1" 1 "$rc"
expect_contains "clear, delete fails: says the link is still there" "$err" "still there"
expect_eq "clear, delete fails: posts no comment" "" "$comments"

reset_state
set_st fail_list
run_dep clear 12 77
expect_eq "clear, links unreadable: exits 1" 1 "$rc"
expect_contains "clear, links unreadable: says the link is still there" "$err" "still there"
expect_eq "clear, links unreadable: posts no comment" "" "$comments"

# ---------------------------------------------------------------------------
# clear-external <N>: removes the label, matched exactly, and posts ✅ Unblocked.
# ---------------------------------------------------------------------------
reset_state
echo '[{"name":"P1"},{"name":"blocked"}]' > "$st/labels.json"
run_dep clear-external 12
expect_eq "clear-external, labeled: exits 0" 0 "$rc"
expect_contains "clear-external, labeled: removes the label" "$calls" "gh issue edit 12 --remove-label blocked"
expect_eq "clear-external, labeled: posts ✅ Unblocked" "✅ Unblocked" "$comments"
expect_not_contains "clear-external, labeled: touches no native link" "$calls" "dependencies"

reset_state
echo '[{"name":"P1"}]' > "$st/labels.json"
run_dep clear-external 12
expect_eq "clear-external, unlabeled: exits 0" 0 "$rc"
expect_not_contains "clear-external, unlabeled: removes nothing" "$calls" "--remove-label"
expect_eq "clear-external, unlabeled: posts no comment" "" "$comments"

reset_state
echo '[{"name":"not-blocked"},{"name":"blocked-upstream"}]' > "$st/labels.json"
run_dep clear-external 12
expect_eq "clear-external, substring-only labels: exits 0" 0 "$rc"
expect_not_contains "clear-external, substring-only labels: removes nothing" "$calls" "--remove-label"
expect_eq "clear-external, substring-only labels: posts no comment" "" "$comments"

reset_state
echo '[{"name":"blocked"}]' > "$st/labels.json"
set_st fail_remove_label
run_dep clear-external 12
expect_eq "clear-external, removal fails: exits 1" 1 "$rc"
expect_contains "clear-external, removal fails: says the board will keep showing it blocked" "$err" \
  "board will keep showing"
expect_eq "clear-external, removal fails: posts no comment" "" "$comments"

# ---------------------------------------------------------------------------
# sweep <N>: unchanged -- the same gh calls as before this change.
# ---------------------------------------------------------------------------
reset_state
echo "[$(link 77),$(link 88 other/repo)]" > "$st/links.json"
run_dep sweep 12
expect_eq "sweep: exits 0" 0 "$rc"
expect_eq "sweep: lists every link, deletes each, and removes the label, in that order" \
  "gh api repos/{owner}/{repo}/issues/12/dependencies/blocked_by --jq .[].id
gh api repos/{owner}/{repo}/issues/12/dependencies/blocked_by/1077 -X DELETE
gh api repos/{owner}/{repo}/issues/12/dependencies/blocked_by/1088 -X DELETE
gh issue edit 12 --remove-label blocked" "$calls"
expect_eq "sweep: posts no comment" "" "$comments"

reset_state
set_st fail_list
run_dep sweep 12
expect_eq "sweep, links unreadable: still exits 0" 0 "$rc"
expect_contains "sweep, links unreadable: warns" "$err" "couldn't list native blocked_by links on #12"
expect_contains "sweep, links unreadable: still removes the label" "$calls" "gh issue edit 12 --remove-label blocked"

# ---------------------------------------------------------------------------
# Usage: every bad-argument path lists all five subcommands and exits 2, calling nothing.
# ---------------------------------------------------------------------------
usage_case() { # desc args...
  local desc="$1" sub
  shift
  reset_state
  run_dep "$@"
  expect_eq "usage ($desc): exits 2" 2 "$rc"
  for sub in "add " "add-external " "clear " "clear-external " "sweep "; do
    expect_contains "usage ($desc): lists $sub" "$err" "blocked-dependency.sh $sub"
  done
  expect_eq "usage ($desc): calls nothing" "" "$calls"
}

usage_case "no subcommand"
usage_case "unknown subcommand" frobnicate 12
usage_case "add, no reason" add 12 77
usage_case "add, no blocker" add 12
usage_case "add, non-numeric issue" add twelve 77 "reason"
usage_case "add, non-numeric blocker" add 12 seventy "reason"
usage_case "add-external, no reason" add-external 12
usage_case "add-external, non-numeric issue" add-external twelve "reason"
usage_case "clear, no blocker" clear 12
usage_case "clear, non-numeric blocker" clear 12 seventy
usage_case "clear-external, no issue" clear-external
usage_case "clear-external, non-numeric issue" clear-external twelve
usage_case "sweep, no issue" sweep
usage_case "sweep, non-numeric issue" sweep twelve

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
