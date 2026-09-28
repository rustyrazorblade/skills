#!/usr/bin/env bash
# Behavioral test for issue-body.sh. Fakes `gh` on PATH, so it runs offline, and records every call,
# so each check can assert what the script asked GitHub to do and what it did not. One check per
# requirement: get, replace and append; a missing section; fence-aware parsing; a duplicate heading;
# content with its own heading; the lastEditedAt pre-check; the userContentEdits post-check; the
# confirm and its one retry; shell characters; and the usage path. Exits non-zero if any assertion
# fails. macOS bash 3.2 compatible (no associative arrays, no mapfile). Touches nothing outside its
# own temp directory.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
ib="$script_dir/issue-body.sh"

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

command -v jq >/dev/null 2>&1 || { echo "test-issue-body: 'jq' is required but not on PATH." >&2; exit 1; }

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fakes="$tmp_root/fakes"
st="$tmp_root/state"
mkdir -p "$fakes"

# The fake answers every `gh api graphql` call with one JSON document built from files in
# $FAKE_STATE, then applies the caller's --jq to it, as gh does:
#   body         the issue body, raw
#   last_edited  GraphQL lastEditedAt; empty means null (never edited)
#   created      createdAt
#   viewer       the authenticated login
#   edits        userContentEdits, one "<editedAt> <login>" per line
# Hooks simulate other writers. Before it answers graphql call K, the fake applies pre_gql_K.body
# (a new body), pre_gql_K.ts (a new lastEditedAt) and pre_gql_K.edit (lines added to edits). Before
# it applies body edit K, it adds pre_edit_K.edit to edits: an edit that landed in the window and
# that this write then overwrites. drop_edit_K makes edit K not land at all. A missing_issue file
# makes the issue not exist. Every call is appended to calls, and each written body to written_K.
cat > "$fakes/gh" <<'GHEOF'
#!/bin/bash
st="$FAKE_STATE"
printf 'gh %s\n' "$*" >> "$st/calls"
jq_expr="" body_file="" prev=""
for a in "$@"; do
  case "$prev" in
    --jq) jq_expr="$a" ;;
    --body-file) body_file="$a" ;;
  esac
  prev="$a"
done
bump() { # counter-name -> prints the new value
  local n
  n=$(( $(cat "$st/$1" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$st/$1"
  echo "$n"
}
if [ "$1 $2" = "api graphql" ]; then
  k=$(bump gql_count)
  [ -e "$st/pre_gql_$k.body" ] && cp "$st/pre_gql_$k.body" "$st/body"
  [ -e "$st/pre_gql_$k.ts" ] && cp "$st/pre_gql_$k.ts" "$st/last_edited"
  [ -e "$st/pre_gql_$k.edit" ] && cat "$st/pre_gql_$k.edit" >> "$st/edits"
  if [ -e "$st/missing_issue" ]; then
    echo "gh: Could not resolve to an Issue" >&2
    exit 1
  fi
  doc=$(jq -n --rawfile body "$st/body" --rawfile le "$st/last_edited" --rawfile ca "$st/created" \
    --rawfile v "$st/viewer" --rawfile edits "$st/edits" '
    {data: {viewer: {login: $v}, repository: {issue: {
      body: $body,
      lastEditedAt: (if $le == "" then null else $le end),
      createdAt: $ca,
      userContentEdits: {nodes: [$edits | split("\n")[] | select(length > 0) | split(" ")
                                 | {editedAt: .[0], editor: {login: .[1]}}]}}}}}')
  if [ -n "$jq_expr" ]; then printf '%s' "$doc" | jq -r "$jq_expr"; else printf '%s\n' "$doc"; fi
  exit $?
fi
case "$1 $2" in
  "issue edit")
    k=$(bump edit_count)
    [ -n "$body_file" ] || { echo "fake gh: issue edit without --body-file: $*" >&2; exit 1; }
    cp "$body_file" "$st/written_$k"
    [ -e "$st/pre_edit_$k.edit" ] && cat "$st/pre_edit_$k.edit" >> "$st/edits"
    [ -e "$st/drop_edit_$k" ] && exit 0
    cp "$body_file" "$st/body"
    ts="2026-06-01T00:00:0${k}Z"
    printf '%s' "$ts" > "$st/last_edited"
    printf '%s %s\n' "$ts" "$(cat "$st/viewer")" >> "$st/edits"
    ;;
  *)
    echo "fake gh: unexpected call: $*" >&2
    exit 1
    ;;
esac
GHEOF
chmod +x "$fakes/gh"

reset_state() { # body-text
  rm -rf "$st"
  mkdir -p "$st" "$st/tmp"
  : > "$st/calls"
  printf '%s' "$1" > "$st/body"
  printf '%s' "2026-02-01T00:00:00Z" > "$st/last_edited"
  printf '%s' "2026-01-01T00:00:00Z" > "$st/created"
  printf '%s' "me" > "$st/viewer"
  printf '%s\n' "2026-01-01T00:00:00Z me" "2026-02-01T00:00:00Z me" > "$st/edits"
}

set_st() { # key [value]
  printf '%s' "${2:-}" > "$st/$1"
}

content() { # text -> path of a content file holding it
  printf '%s\n' "$1" > "$st/content"
  echo "$st/content"
}

rc=0 out="" err="" calls=""
run_ib() {
  PATH="$fakes:$PATH" FAKE_STATE="$st" TMPDIR="$st/tmp" "$BASH" "$ib" "$@" >"$st/stdout" 2>"$st/stderr"
  rc=$?
  out="$(cat "$st/stdout")"
  err="$(cat "$st/stderr")"
  calls="$(cat "$st/calls")"
}

edit_calls() { grep -c '^gh issue edit' "$st/calls" || true; }
written() { cat "$st/written_$1" 2>/dev/null; }
tmp_left() { find "$st/tmp" -mindepth 1 | wc -l | tr -d ' '; }

BODY='## Problem

Something is wrong.

## Scope

- in: the thing
- out: the other thing

## Acceptance criteria

- WHEN a THEN b
- WHEN c THEN d

## Notes

See above.'

# ---------------------------------------------------------------------------
# get <N> <heading>
# ---------------------------------------------------------------------------
reset_state "$BODY"
run_ib get 88 "Scope"
expect_eq "get, present: exits 0" 0 "$rc"
expect_eq "get, present: prints only the section's content" "- in: the thing
- out: the other thing" "$out"
expect_eq "get: makes no edit" 0 "$(edit_calls)"

reset_state "$BODY"
run_ib get 88 "Assumptions"
expect_eq "get, absent: exits 1" 1 "$rc"
expect_eq "get, absent: prints nothing" "" "$out"
expect_contains "get, absent: names the section" "$err" "## Assumptions"

reset_state "$BODY"
set_st missing_issue
run_ib get 88 "Scope"
expect_eq "get, no such issue: exits 1" 1 "$rc"

# ---------------------------------------------------------------------------
# replace and append on a present section.
# ---------------------------------------------------------------------------
reset_state "$BODY"
run_ib replace 88 "Scope" "$(content '- in: only the new thing')"
expect_eq "replace: exits 0" 0 "$rc"
expect_eq "replace: writes once" 1 "$(edit_calls)"
expect_eq "replace: only the Scope section changes" '## Problem

Something is wrong.

## Scope

- in: only the new thing

## Acceptance criteria

- WHEN a THEN b
- WHEN c THEN d

## Notes

See above.' "$(written 1)"
expect_contains "replace: writes through --body-file" "$calls" "gh issue edit 88 --body-file"
expect_not_contains "replace: never passes the body in argv" "$calls" "--body "
expect_eq "replace: leaves no temp file behind" 0 "$(tmp_left)"

reset_state "$BODY"
run_ib append 88 "Acceptance criteria" "$(content '- WHEN e THEN f')"
expect_eq "append: exits 0" 0 "$rc"
expect_eq "append: the new lines follow the section's lines, nothing else changes" '## Problem

Something is wrong.

## Scope

- in: the thing
- out: the other thing

## Acceptance criteria

- WHEN a THEN b
- WHEN c THEN d
- WHEN e THEN f

## Notes

See above.' "$(written 1)"
expect_eq "append: leaves no temp file behind" 0 "$(tmp_left)"

reset_state "$BODY"
run_ib append 88 "Notes" "$(content 'More notes.')"
expect_eq "append, last section: exits 0" 0 "$rc"
expect_eq "append, last section: appends at the end" '## Problem

Something is wrong.

## Scope

- in: the thing
- out: the other thing

## Acceptance criteria

- WHEN a THEN b
- WHEN c THEN d

## Notes

See above.
More notes.' "$(written 1)"

# ---------------------------------------------------------------------------
# A missing section: an error that names it and the issue, and no write.
# ---------------------------------------------------------------------------
reset_state "$BODY"
run_ib append 88 "Assumptions" "$(content '- assume x')"
expect_eq "append, absent: exits non-zero" 1 "$rc"
expect_contains "append, absent: the error names the section" "$err" "## Assumptions"
expect_contains "append, absent: the error names the issue" "$err" "88"
expect_eq "append, absent: makes no gh issue edit call" 0 "$(edit_calls)"
expect_eq "append, absent: leaves no temp file behind" 0 "$(tmp_left)"

NOSCOPE='## Problem

Something is wrong.'
reset_state "$NOSCOPE"
run_ib replace 88 "Scope" "$(content '- in: x')"
expect_eq "replace, absent: exits non-zero" 1 "$rc"
expect_contains "replace, absent: the error names the section" "$err" "## Scope"
expect_contains "replace, absent: the error names the issue" "$err" "88"
expect_eq "replace, absent: makes no gh issue edit call" 0 "$(edit_calls)"
expect_eq "replace, absent: the body is unchanged" "$NOSCOPE" "$(cat "$st/body")"

# ---------------------------------------------------------------------------
# Fence-aware parsing.
# ---------------------------------------------------------------------------
FENCED_ONLY='## Problem

```
## Scope
not a heading
```'
reset_state "$FENCED_ONLY"
run_ib replace 88 "Scope" "$(content '- in: x')"
expect_eq "replace, only match inside a fence: exits non-zero" 1 "$rc"
expect_contains "replace, only match inside a fence: names the section" "$err" "## Scope"
expect_eq "replace, only match inside a fence: makes no edit" 0 "$(edit_calls)"

BACKTICK='## Problem

Example:

```markdown
## Scope
fenced text
```

## Scope

real scope

## Notes

n'
reset_state "$BACKTICK"
run_ib replace 88 "Scope" "$(content 'new scope')"
expect_eq "replace, heading in a backtick fence: exits 0" 0 "$rc"
expect_eq "replace, heading in a backtick fence: edits only the real section" '## Problem

Example:

```markdown
## Scope
fenced text
```

## Scope

new scope

## Notes

n' "$(written 1)"

# A `## ` line inside a fence within the target section does not end the section.
TILDE='## Scope

~~~
## Not a heading
~~~
tail of scope

## Notes

n'
reset_state "$TILDE"
run_ib get 88 "Scope"
expect_eq "get, a ## line inside a ~~~ fence stays in the section" '~~~
## Not a heading
~~~
tail of scope' "$out"
run_ib replace 88 "Scope" "$(content 'replaced')"
expect_eq "replace, a ## line inside a ~~~ fence is replaced with its section" '## Scope

replaced

## Notes

n' "$(written 1)"

INNER_BACKTICK='## Scope

````
```
## Still fenced
```
````

## Notes

n'
reset_state "$INNER_BACKTICK"
run_ib get 88 "Notes"
expect_eq "get, a longer fence is closed only by a fence as long" "n" "$out"
run_ib get 88 "Still fenced"
expect_eq "get, a heading inside a nested fence is not a heading" 1 "$rc"

# ---------------------------------------------------------------------------
# A duplicate target heading, and content with its own heading.
# ---------------------------------------------------------------------------
DUP='## Scope

one

## Scope

two'
reset_state "$DUP"
run_ib replace 88 "Scope" "$(content 'x')"
expect_eq "replace, duplicate heading: exits non-zero" 1 "$rc"
expect_contains "replace, duplicate heading: names the issue" "$err" "88"
expect_contains "replace, duplicate heading: names the heading" "$err" "## Scope"
expect_eq "replace, duplicate heading: makes no edit" 0 "$(edit_calls)"

reset_state "$BODY"
run_ib append 88 "Scope" "$(content '- in: more
## Notes
oops')"
expect_eq "append, content with a ## heading: exits non-zero" 1 "$rc"
expect_contains "append, content with a ## heading: says why" "$err" "## Notes"
expect_eq "append, content with a ## heading: makes no edit" 0 "$(edit_calls)"

reset_state "$BODY"
run_ib append 88 "Scope" "$(content '```
## fenced in the content
```')"
expect_eq "append, content with a ## line inside a fence: exits 0" 0 "$rc"
expect_eq "append, content with a ## line inside a fence: writes once" 1 "$(edit_calls)"

# ---------------------------------------------------------------------------
# CRLF bodies, as the web editor writes them: headings still match.
# ---------------------------------------------------------------------------
CRLF="$(printf '## Scope\r\n\r\nold\r\n\r\n## Notes\r\n\r\nn')"
reset_state "$CRLF"
run_ib get 88 "Scope"
expect_eq "get, CRLF body: finds the section" "old" "$out"

# ---------------------------------------------------------------------------
# The lastEditedAt pre-check: the owner edits while the agent drafts.
# ---------------------------------------------------------------------------
OWNER_EDIT='## Problem

Something is wrong, and the owner added this line.

## Scope

- in: the thing
- out: the other thing

## Acceptance criteria

- WHEN a THEN b
- WHEN c THEN d

## Notes

See above.'
reset_state "$BODY"
printf '%s' "$OWNER_EDIT" > "$st/pre_gql_2.body"
set_st pre_gql_2.ts "2026-03-01T00:00:00Z"
printf '%s\n' "2026-03-01T00:00:00Z owner" > "$st/pre_gql_2.edit"
run_ib replace 88 "Scope" "$(content '- in: only the new thing')"
expect_eq "moved lastEditedAt: exits 0" 0 "$rc"
expect_eq "moved lastEditedAt: writes once" 1 "$(edit_calls)"
expect_contains "moved lastEditedAt: keeps the owner's edit" "$(written 1)" "the owner added this line"
expect_contains "moved lastEditedAt: applies its own change to the new body" "$(written 1)" "only the new thing"
expect_not_contains "moved lastEditedAt: drops the old scope" "$(written 1)" "the other thing"

# ---------------------------------------------------------------------------
# The userContentEdits post-check: an edit that lands inside the window is lost.
# ---------------------------------------------------------------------------
reset_state "$BODY"
printf '%s\n' "2026-05-01T00:00:00Z alice" > "$st/pre_edit_1.edit"
run_ib replace 88 "Scope" "$(content '- in: only the new thing')"
expect_eq "lost edit: exits non-zero" 1 "$rc"
expect_contains "lost edit: prints the lost version's timestamp" "$err" "2026-05-01T00:00:00Z"
expect_contains "lost edit: prints the lost version's editor" "$err" "alice"
expect_eq "lost edit: does not write again" 1 "$(edit_calls)"
expect_eq "lost edit: leaves no temp file behind" 0 "$(tmp_left)"

reset_state "$BODY"
set_st last_edited ""
printf '%s\n' "2026-01-01T00:00:00Z me" > "$st/edits"
run_ib replace 88 "Scope" "$(content '- in: only the new thing')"
expect_eq "never edited before: the original version is not a lost edit" 0 "$rc"

# ---------------------------------------------------------------------------
# The confirm: a write that does not land is retried once.
# ---------------------------------------------------------------------------
reset_state "$BODY"
set_st drop_edit_1
run_ib replace 88 "Scope" "$(content '- in: only the new thing')"
expect_eq "failed confirm, retry lands: exits 0" 0 "$rc"
expect_eq "failed confirm, retry lands: writes twice" 2 "$(edit_calls)"
expect_contains "failed confirm, retry lands: the body holds the new content" "$(cat "$st/body")" "only the new thing"

reset_state "$BODY"
set_st last_edited ""
set_st edits ""
set_st drop_edit_1
run_ib replace 88 "Scope" "$(content '- in: only the new thing')"
expect_eq "no edit history at all, retry lands: exits 0" 0 "$rc"
expect_eq "no edit history at all, retry lands: writes twice" 2 "$(edit_calls)"

reset_state "$BODY"
set_st drop_edit_1
set_st drop_edit_2
run_ib replace 88 "Scope" "$(content '- in: only the new thing')"
expect_eq "failed confirm twice: exits non-zero" 1 "$rc"
expect_eq "failed confirm twice: writes exactly twice" 2 "$(edit_calls)"
expect_contains "failed confirm twice: names the section" "$err" "## Scope"
expect_eq "failed confirm twice: leaves no temp file behind" 0 "$(tmp_left)"

# ---------------------------------------------------------------------------
# Shell characters in the body and the content reach GitHub unchanged.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # the text is literal on purpose: it must never run
HOSTILE_BODY='## Scope

$(touch '"$st"'/pwned-body) and `touch '"$st"'/pwned-body2`

## Notes

n'
# shellcheck disable=SC2016
HOSTILE_CONTENT='- $(touch '"$st"'/pwned-content) and `touch '"$st"'/pwned-content2`'
reset_state "$HOSTILE_BODY"
run_ib append 88 "Scope" "$(content "$HOSTILE_CONTENT")"
expect_eq "shell characters: exits 0" 0 "$rc"
expect_contains "shell characters: the body's text is unchanged" "$(written 1)" "\$(touch $st/pwned-body)"
expect_contains "shell characters: the content's text is unchanged" "$(written 1)" "\`touch $st/pwned-content2\`"
expect_eq "shell characters: nothing ran" "" "$(find "$st" -name 'pwned*' | head -1)"

# ---------------------------------------------------------------------------
# An unchanged body is not written.
# ---------------------------------------------------------------------------
reset_state "$BODY"
run_ib replace 88 "Scope" "$(content '- in: the thing
- out: the other thing')"
expect_eq "no change: exits 0" 0 "$rc"
expect_eq "no change: makes no edit" 0 "$(edit_calls)"

# ---------------------------------------------------------------------------
# Usage: every bad-argument path lists all three subcommands and exits 2, calling nothing.
# ---------------------------------------------------------------------------
usage_case() { # desc args...
  local desc="$1" sub
  shift
  reset_state "$BODY"
  run_ib "$@"
  expect_eq "usage ($desc): exits 2" 2 "$rc"
  for sub in "get " "replace " "append "; do
    expect_contains "usage ($desc): lists $sub" "$err" "issue-body.sh $sub"
  done
  expect_eq "usage ($desc): calls nothing" "" "$calls"
}

usage_case "no subcommand"
usage_case "unknown subcommand" frobnicate 88 "Scope"
usage_case "get, no heading" get 88
usage_case "get, non-numeric issue" get eighty "Scope"
usage_case "get, empty heading" get 88 ""
usage_case "get, heading with its own ##" get 88 "## Scope"
usage_case "replace, no file" replace 88 "Scope"
usage_case "replace, missing file" replace 88 "Scope" "$tmp_root/no-such-file"
printf 'x\n' > "$tmp_root/some-content"
usage_case "append, non-numeric issue" append eighty "Scope" "$tmp_root/some-content"
usage_case "append, extra argument" append 88 "Scope" "$tmp_root/some-content" extra

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
