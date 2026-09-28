#!/usr/bin/env bash
# Behavioral test for close-on-merge.sh. Fakes `gh` on PATH, so it runs offline, and records every
# call, so each check can assert what the script asked GitHub to do and what it did not. Covers
# record (first run, repeat, M closed, M missing, M equal to N, a refused link, a loop through a
# chain), withdraw, the replay of record and withdrawn comments, a stranger's record, closes,
# close-merged, shell characters in titles, and the usage path. Exits non-zero if any assertion
# fails. macOS bash 3.2 compatible (no associative arrays, no mapfile). Touches nothing outside its
# own temp directory.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
com="$script_dir/close-on-merge.sh"

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

command -v jq >/dev/null 2>&1 || { echo "test-close-on-merge: 'jq' is required but not on PATH." >&2; exit 1; }

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fakes="$tmp_root/fakes"
st="$tmp_root/state"
mkdir -p "$fakes"

# The fake answers from files in $FAKE_STATE, per issue X:
#   issue_X.json     {"state","title","labels":[{"name"}]}; no file means the issue does not exist
#   links_X.json     X's native blocked_by list, as the REST API returns it
#   comments_X.json  X's comments, [{"user":{"login"},"body"}]
#   sticky_X         labels, one per line, that survive a removal
#   pr_P.json        {"state"} for PR P
#   viewer           the authenticated login
# A fail_<name> file makes that one call fail; fail_post holds GitHub's error text. Every call is
# appended to calls, and each posted comment to posted as "#X: <body>".
cat > "$fakes/gh" <<'GHEOF'
#!/bin/bash
st="$FAKE_STATE"
printf 'gh %s\n' "$*" >> "$st/calls"
method=GET jq_expr="" body_file="" issue_id="" remove="" prev=""
for a in "$@"; do
  case "$prev" in
    -X) method="$a" ;;
    --jq) jq_expr="$a" ;;
    --body-file) body_file="$a" ;;
    -F) issue_id="${a#issue_id=}" ;;
    --remove-label) remove="$a" ;;
  esac
  prev="$a"
done
emit() { if [ -n "$jq_expr" ]; then printf '%s' "$1" | jq -r "$jq_expr"; else printf '%s\n' "$1"; fi; }
failing() {
  if [ -e "$st/fail_$1" ]; then
    if [ -s "$st/fail_$1" ]; then cat "$st/fail_$1" >&2; else echo "gh: fake failure: $1" >&2; fi
    exit 1
  fi
}
need_issue() {
  if [ ! -e "$st/issue_$1.json" ]; then
    echo "GraphQL: Could not resolve to an issue or pull request with the number of $1." >&2
    exit 1
  fi
}
REPO="https://api.github.com/repos/me/this"
if [ "$1" = api ]; then
  path="$2"
  num=$(printf '%s' "$path" | sed -n 's#^repos/{owner}/{repo}/issues/\([0-9]*\).*#\1#p')
  case "$method $path" in
    "GET user")
      emit "{\"login\":\"$(cat "$st/viewer")\"}"
      ;;
    "GET repos/{owner}/{repo}")
      failing repo
      emit "{\"url\":\"$REPO\"}"
      ;;
    "GET repos/{owner}/{repo}/issues/"*/dependencies/blocked_by)
      failing "list_$num"
      failing list
      emit "$(cat "$st/links_$num.json" 2>/dev/null || echo '[]')"
      ;;
    "POST repos/{owner}/{repo}/issues/"*/dependencies/blocked_by)
      failing post
      b=$((issue_id - 1000))
      f="$st/links_$num.json"
      [ -e "$f" ] || echo '[]' > "$f"
      jq --argjson b "$b" --arg r "$REPO" '. + [{id: (1000 + $b), number: $b, repository_url: $r}]' "$f" > "$f.new"
      mv "$f.new" "$f"
      echo '{}'
      ;;
    "DELETE repos/{owner}/{repo}/issues/"*/dependencies/blocked_by/*)
      failing delete
      id="${path##*/}"
      f="$st/links_$num.json"
      jq --argjson id "$id" 'map(select(.id != $id))' "$f" > "$f.new"
      mv "$f.new" "$f"
      echo '{}'
      ;;
    "GET repos/{owner}/{repo}/issues/"*/comments)
      failing comments
      emit "$(cat "$st/comments_$num.json" 2>/dev/null || echo '[]')"
      ;;
    "GET repos/{owner}/{repo}/issues/"*)
      failing resolve
      emit "{\"id\":$((1000 + num))}"
      ;;
    *)
      echo "fake gh: unexpected api call: $*" >&2
      exit 1
      ;;
  esac
  exit 0
fi
x="$3"
case "$1 $2" in
  "issue view")
    failing "view_$x"
    need_issue "$x"
    emit "$(cat "$st/issue_$x.json")"
    ;;
  "issue comment")
    failing comment
    need_issue "$x"
    [ -n "$body_file" ] || { echo "fake gh: issue comment without --body-file: $*" >&2; exit 1; }
    f="$st/comments_$x.json"
    [ -e "$f" ] || echo '[]' > "$f"
    jq --rawfile b "$body_file" --arg u "$(cat "$st/viewer")" '. + [{user: {login: $u}, body: $b}]' "$f" > "$f.new"
    mv "$f.new" "$f"
    printf '#%s: %s\n' "$x" "$(cat "$body_file")" >> "$st/posted"
    ;;
  "issue close")
    failing close
    f="$st/issue_$x.json"
    jq '.state = "CLOSED"' "$f" > "$f.new"
    mv "$f.new" "$f"
    ;;
  "issue edit")
    failing remove_label
    f="$st/issue_$x.json"
    if ! grep -qxF -- "$remove" "$st/sticky_$x" 2>/dev/null; then
      jq --arg l "$remove" '.labels |= map(select(.name != $l))' "$f" > "$f.new"
      mv "$f.new" "$f"
    fi
    ;;
  "pr view")
    failing pr
    emit "$(cat "$st/pr_$x.json")"
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
  mkdir -p "$st" "$st/tmp"
  : > "$st/calls"
  : > "$st/posted"
  printf '%s' "me" > "$st/viewer"
}

set_st() { # key [value]
  printf '%s' "${2:-}" > "$st/$1"
}

issue() { # number state title [label...]
  local n="$1" state="$2" title="$3" labels
  shift 3
  labels=$(printf '%s\n' "$@" | jq -R 'select(length > 0) | {name: .}' | jq -s .)
  jq -n --arg s "$state" --arg t "$title" --argjson l "$labels" '{state: $s, title: $t, labels: $l}' > "$st/issue_$n.json"
}

link() { # issue blocker -- add "issue blocked by blocker" to the fake's links
  local f="$st/links_$1.json"
  [[ -e "$f" ]] || echo '[]' > "$f"
  jq --argjson b "$2" '. + [{id: (1000 + $b), number: $b, repository_url: "https://api.github.com/repos/me/this"}]' "$f" > "$f.new"
  mv "$f.new" "$f"
}

comment_as() { # issue login body -- a comment someone already posted
  local f="$st/comments_$1.json"
  [[ -e "$f" ]] || echo '[]' > "$f"
  jq --arg u "$2" --arg b "$3" '. + [{user: {login: $u}, body: $b}]' "$f" > "$f.new"
  mv "$f.new" "$f"
}

labels_of() { jq -r '[.labels[].name] | join(",")' "$st/issue_$1.json"; }
state_of() { jq -r '.state' "$st/issue_$1.json"; }
links_of() { jq -r '[.[].number] | join(",")' "$st/links_$1.json" 2>/dev/null; }
posted_on() { grep -c "^#$1: " "$st/posted" || true; }

rc=0 out="" err="" calls="" posted=""
run_com() {
  PATH="$fakes:$PATH" FAKE_STATE="$st" TMPDIR="$st/tmp" "$BASH" "$com" "$@" >"$st/stdout" 2>"$st/stderr"
  rc=$?
  out="$(cat "$st/stdout")"
  err="$(cat "$st/stderr")"
  calls="$(cat "$st/calls")"
  posted="$(cat "$st/posted")"
}
tmp_left() { find "$st/tmp" -mindepth 1 | wc -l | tr -d ' '; }

standard() {
  reset_state
  issue 971 OPEN "Rework the thing"
  issue 928 OPEN "Old duplicate of the thing" "status:ready" "P2"
}

# ---------------------------------------------------------------------------
# record <N> <M>
# ---------------------------------------------------------------------------
standard
run_com record 971 928
expect_eq "record, first run: exits 0" 0 "$rc"
expect_eq "record, first run: links 928 as blocked by 971" "971" "$(links_of 928)"
expect_contains "record, first run: the comment on 971 opens with the marker and names 928" "$posted" \
  "#971: 🔗 Closes on merge
- 928: Old duplicate of the thing"
expect_contains "record, first run: the comment on 928 says when it closes" "$posted" \
  "#928: Closes when the PR for 971: Rework the thing merges."
link_at="$(grep -n 'dependencies/blocked_by -F' "$st/calls" | head -1 | cut -d: -f1)"
comment_at="$(grep -n 'gh issue comment' "$st/calls" | head -1 | cut -d: -f1)"
if [[ -n "$link_at" && -n "$comment_at" && "$link_at" -lt "$comment_at" ]]; then
  pass "record, first run: sets the link before any comment"
else
  fail "record, first run: sets the link before any comment" "link at '$link_at', comment at '$comment_at'"
fi
expect_not_contains "record, first run: never passes a title in argv" "$calls" "Rework the thing"
expect_eq "record, first run: leaves no temp file behind" 0 "$(tmp_left)"

run_com record 971 928
expect_eq "record, repeated: exits 0" 0 "$rc"
expect_eq "record, repeated: no second link" "971" "$(links_of 928)"
expect_eq "record, repeated: no second comment on 971" 1 "$(posted_on 971)"
expect_eq "record, repeated: no second comment on 928" 1 "$(posted_on 928)"

standard
issue 928 CLOSED "Old duplicate of the thing"
run_com record 971 928
expect_eq "record, M closed: exits non-zero" 1 "$rc"
expect_eq "record, M closed: sets no link" "" "$(links_of 928)"
expect_eq "record, M closed: posts nothing" "" "$posted"

standard
rm "$st/issue_928.json"
run_com record 971 928
expect_eq "record, M missing: exits non-zero" 1 "$rc"
expect_not_contains "record, M missing: sets no link" "$calls" "-X POST"
expect_eq "record, M missing: posts nothing" "" "$posted"

standard
run_com record 971 971
expect_eq "record, M equal to N: exits 2" 2 "$rc"
expect_eq "record, M equal to N: calls nothing" "" "$calls"

standard
set_st fail_post "gh: Validation Failed: circular dependency (HTTP 422)"
run_com record 971 928
expect_eq "record, GitHub refuses the link: exits non-zero" 1 "$rc"
expect_contains "record, GitHub refuses the link: prints GitHub's error" "$err" "circular dependency"
expect_eq "record, GitHub refuses the link: posts nothing" "" "$posted"

standard
link 971 928
run_com record 971 928
expect_eq "record, direct loop: exits non-zero" 1 "$rc"
expect_not_contains "record, direct loop: refuses before it sets the link" "$calls" "-X POST"
expect_eq "record, direct loop: posts nothing" "" "$posted"

standard
issue 500 OPEN "Middle of the chain"
link 971 500
link 500 928
run_com record 971 928
expect_eq "record, loop through a chain: exits non-zero" 1 "$rc"
expect_contains "record, loop through a chain: says why" "$err" "loop"
expect_not_contains "record, loop through a chain: refuses before it sets the link" "$calls" "-X POST"
expect_eq "record, loop through a chain: posts nothing" "" "$posted"

standard
link 971 500
link 500 971
run_com record 971 928
expect_eq "record, an unrelated cycle in N's chain: terminates and links" 0 "$rc"

standard
set_st fail_list_971
run_com record 971 928
expect_eq "record, N's chain unreadable: exits non-zero" 1 "$rc"
expect_not_contains "record, N's chain unreadable: sets no link" "$calls" "-X POST"
expect_eq "record, N's chain unreadable: posts nothing" "" "$posted"

standard
link 928 971
run_com record 971 928
expect_eq "record, link already there: exits 0" 0 "$rc"
expect_not_contains "record, link already there: creates no second link" "$calls" "-X POST"
expect_eq "record, link already there: still posts on 971" 1 "$(posted_on 971)"

# ---------------------------------------------------------------------------
# withdraw <N> <M>
# ---------------------------------------------------------------------------
standard
run_com record 971 928
run_com withdraw 971 928
expect_eq "withdraw: exits 0" 0 "$rc"
expect_contains "withdraw: posts the withdrawn marker on 971" "$posted" "#971: 🔗 Closes on merge: withdrawn 928"
expect_eq "withdraw: removes the link" "" "$(links_of 928)"
expect_contains "withdraw: tells 928 it no longer closes" "$posted" "#928: No longer closes with 971: Rework the thing."
run_com closes 971
expect_eq "withdraw: closes no longer prints Closes #928" "Closes #971" "$out"

run_com record 971 928
expect_eq "record after withdraw: exits 0" 0 "$rc"
expect_eq "record after withdraw: posts a new record on 971" 3 "$(posted_on 971)"
expect_eq "record after withdraw: posts a new note on 928" 3 "$(posted_on 928)"
run_com closes 971
expect_eq "record after withdraw: closes prints it again" "Closes #971
Closes #928" "$out"

standard
run_com withdraw 971 928
expect_eq "withdraw, nothing recorded: exits 0" 0 "$rc"
expect_eq "withdraw, nothing recorded: posts nothing" "" "$posted"

# ---------------------------------------------------------------------------
# The record: replay order, and only the gh user's comments count.
# ---------------------------------------------------------------------------
standard
comment_as 971 me "$(printf '🔗 Closes on merge\n- 928: Old duplicate of the thing')"
comment_as 971 me "🔗 Closes on merge: withdrawn 928"
comment_as 971 me "$(printf '🔗 Closes on merge\n- 930: Another one')"
run_com closes 971
expect_eq "replay: record, withdraw, record leaves only the last" "Closes #971
Closes #930" "$out"

standard
comment_as 971 me "$(printf '🔗 Closes on merge\r\n- 928: CRLF from the web editor')"
run_com closes 971
expect_eq "replay: a CRLF record still counts" "Closes #971
Closes #928" "$out"

standard
comment_as 971 stranger "$(printf '🔗 Closes on merge\n- 928: Old duplicate of the thing')"
run_com closes 971
expect_eq "replay: a stranger's record comment does not count" "Closes #971" "$out"

# ---------------------------------------------------------------------------
# closes <N>
# ---------------------------------------------------------------------------
standard
run_com closes 971
expect_eq "closes, no records: exits 0" 0 "$rc"
expect_eq "closes, no records: prints only Closes #N" "Closes #971" "$out"

standard
run_com record 971 928
run_com closes 971
expect_eq "closes, one record" "Closes #971
Closes #928" "$out"

standard
issue 930 OPEN "Another one"
run_com record 971 928
run_com record 971 930
run_com closes 971
expect_eq "closes, two records: one line each, in record order" "Closes #971
Closes #928
Closes #930" "$out"

standard
run_com record 971 928
set_st fail_comments
run_com closes 971
expect_eq "closes, comments unreadable: exits non-zero" 1 "$rc"
expect_eq "closes, comments unreadable: prints nothing to stdout" "" "$out"

# ---------------------------------------------------------------------------
# close-merged <N> <PR>
# ---------------------------------------------------------------------------
merged_setup() {
  standard
  run_com record 971 928
  : > "$st/calls"
  : > "$st/posted"
  echo '{"state":"MERGED"}' > "$st/pr_42.json"
}

merged_setup
issue 928 OPEN "Old duplicate of the thing" "status:ready" "needs-attention" "blocked" "merge-on-green" "P2"
run_com close-merged 971 42
expect_eq "close-merged, M open: exits 0" 0 "$rc"
expect_eq "close-merged, M open: closes 928" "CLOSED" "$(state_of 928)"
expect_contains "close-merged, M open: the comment names 971 and the PR" "$posted" "#928: "
expect_contains "close-merged, M open: the comment names the PR" "$(grep '^#928: ' "$st/posted")" "#42"
expect_contains "close-merged, M open: the comment names 971" "$(grep '^#928: ' "$st/posted")" "971: Rework the thing"
expect_eq "close-merged, M open: removes every lifecycle label, keeps priority" "P2" "$(labels_of 928)"
expect_eq "close-merged, M open: sweeps 928's native links" "" "$(links_of 928)"
expect_eq "close-merged, M open: leaves no temp file behind" 0 "$(tmp_left)"

merged_setup
issue 928 CLOSED "Old duplicate of the thing" "status:in-progress" "P2"
run_com close-merged 971 42
expect_eq "close-merged, M closed: exits 0" 0 "$rc"
expect_eq "close-merged, M closed: does not reopen it" "CLOSED" "$(state_of 928)"
expect_not_contains "close-merged, M closed: makes no close call" "$calls" "gh issue close"
expect_eq "close-merged, M closed: still removes its lifecycle labels" "P2" "$(labels_of 928)"

merged_setup
issue 928 OPEN "Old duplicate of the thing" "status:ready" "agent:active"
run_com close-merged 971 42
expect_eq "close-merged, agent:active: exits 0" 0 "$rc"
expect_contains "close-merged, agent:active: reports it" "$out$err" "agent:active"
expect_eq "close-merged, agent:active: leaves it in place" "agent:active" "$(labels_of 928)"
expect_not_contains "close-merged, agent:active: never removes it" "$calls" "--remove-label agent:active"

merged_setup
issue 928 OPEN "Old duplicate of the thing" "status:ready"
printf 'status:ready\n' > "$st/sticky_928"
run_com close-merged 971 42
expect_eq "close-merged, a label survives: exits non-zero" 1 "$rc"
expect_contains "close-merged, a label survives: names the issue" "$err" "928"
expect_contains "close-merged, a label survives: names the label" "$err" "status:ready"

merged_setup
echo '{"state":"CLOSED"}' > "$st/pr_42.json"
run_com close-merged 971 42
expect_eq "close-merged, PR not merged: exits non-zero" 1 "$rc"
expect_eq "close-merged, PR not merged: 928 stays open" "OPEN" "$(state_of 928)"
expect_not_contains "close-merged, PR not merged: closes nothing" "$calls" "gh issue close"
expect_eq "close-merged, PR not merged: posts nothing" "" "$posted"

merged_setup
set_st fail_close
run_com close-merged 971 42
expect_eq "close-merged, the close fails: exits non-zero" 1 "$rc"
expect_contains "close-merged, the close fails: says 928 is still open" "$err" "928"

merged_setup
set_st fail_comments
run_com close-merged 971 42
expect_eq "close-merged, the record unreadable: exits non-zero" 1 "$rc"
expect_eq "close-merged, the record unreadable: 928 stays open" "OPEN" "$(state_of 928)"

standard
echo '{"state":"MERGED"}' > "$st/pr_42.json"
run_com close-merged 971 42
expect_eq "close-merged, no records: exits 0" 0 "$rc"
expect_not_contains "close-merged, no records: closes nothing" "$calls" "gh issue close"

# ---------------------------------------------------------------------------
# Titles with shell characters reach the comments unchanged, and nothing runs.
# ---------------------------------------------------------------------------
reset_state
# shellcheck disable=SC2016 # the text is literal on purpose: it must never run
issue 971 OPEN 'N $(touch '"$st"'/pwned-n) `touch '"$st"'/pwned-n2`'
# shellcheck disable=SC2016
issue 928 OPEN 'M $(rm -rf ~) and $(touch '"$st"'/pwned-m) `touch '"$st"'/pwned-m2`'
echo '{"state":"MERGED"}' > "$st/pr_42.json"
run_com record 971 928
expect_eq "shell characters, record: exits 0" 0 "$rc"
expect_contains "shell characters: M's title is unchanged in the record" "$posted" "- 928: M \$(rm -rf ~) and"
expect_contains "shell characters: N's title is unchanged on M" "$posted" "\`touch $st/pwned-n2\`"
run_com close-merged 971 42
expect_eq "shell characters, close-merged: exits 0" 0 "$rc"
expect_eq "shell characters: nothing ran" "" "$(find "$st" -name 'pwned*' | head -1)"
expect_not_contains "shell characters: no title in argv" "$calls" "rm -rf"

# ---------------------------------------------------------------------------
# Usage: every bad-argument path lists all four subcommands and exits 2, calling nothing.
# ---------------------------------------------------------------------------
usage_case() { # desc args...
  local desc="$1" sub
  shift
  reset_state
  run_com "$@"
  expect_eq "usage ($desc): exits 2" 2 "$rc"
  for sub in "record " "withdraw " "closes " "close-merged "; do
    expect_contains "usage ($desc): lists $sub" "$err" "close-on-merge.sh $sub"
  done
  expect_eq "usage ($desc): calls nothing" "" "$calls"
}

usage_case "no subcommand"
usage_case "unknown subcommand" frobnicate 971
usage_case "record, no M" record 971
usage_case "record, non-numeric M" record 971 nine
usage_case "record, M equal to N" record 971 971
usage_case "withdraw, M equal to N" withdraw 971 971
usage_case "withdraw, non-numeric N" withdraw n 928
usage_case "closes, no N" closes
usage_case "closes, extra argument" closes 971 928
usage_case "close-merged, no PR" close-merged 971
usage_case "close-merged, non-numeric PR" close-merged 971 pr

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
