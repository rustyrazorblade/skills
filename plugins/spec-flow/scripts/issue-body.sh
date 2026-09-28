#!/usr/bin/env bash
# Read or edit ONE `## ` section of an existing issue's body. Every stage that changes an existing
# issue body goes through this script; creating a new issue is not an edit, and needs nothing here.
# The body changes only for a requirement change; any other information is a comment.
#
# Subcommands:
#   get     <issue> <heading>          print the section's content; exit 1 when it is absent
#   replace <issue> <heading> <file>   replace the section's content with the file's lines
#   append  <issue> <heading> <file>   add the file's lines to the end of the section
#
# <heading> is the text after `## `, for example "Acceptance criteria". A section runs from its
# heading to the next `## ` heading, or to the end of the body. A `## ` line counts as a heading
# only outside a ``` or ~~~ fence, so `###` lines and fenced examples belong to the section.
#
# replace and append change nothing, and exit 1, when:
#   - the body has no such section outside a fence (they never add one);
#   - the body has the heading twice;
#   - the content file holds a `## ` heading outside a fence.
#
# The race with other writers. GitHub has no conditional write for an issue body, so:
#   1. The script reads the body and GraphQL `lastEditedAt` together.
#   2. Just before it writes, it reads `lastEditedAt` again. If it moved, it re-reads the body and
#      applies its one-section change to the new body.
#   3. After it writes, it reads `userContentEdits`. If any edit other than its own landed after its
#      read, it prints each such edit's timestamp and editor and exits 1. It does not retry: a retry
#      could overwrite the other edit again. The old text is in the issue's edit history on GitHub.
#   4. Otherwise it confirms that its section holds the new content and that every other section is
#      still there. If not, it writes once more, then exits 1 if the read-back still fails.
#
# Task 2.3 of issue 88: whether GitHub records two body edits in quick succession as two
# `userContentEdits` entries is NOT yet verified on a live issue. Step 3 relies on it. Record the
# result here once it is checked on a scratch issue.
#
# Every write goes through a mktemp file under $TMPDIR and `gh issue edit --body-file`. Nothing read
# from GitHub is placed in argv. A trap removes the temp files on exit.
#
# bash 3.2 compatible (macOS default): no associative arrays, no mapfile, no GNU-only flags.
set -euo pipefail

usage() {
  echo "usage: issue-body.sh get <issue> <heading>" >&2
  echo "       issue-body.sh replace <issue> <heading> <file>" >&2
  echo "       issue-body.sh append <issue> <heading> <file>" >&2
  exit 2
}

die() {
  echo "issue-body: $*" >&2
  exit 1
}

cmd="${1:-}"
[[ $# -ge 1 ]] || usage
shift
case "$cmd" in
  get) [[ $# -eq 2 ]] || usage ;;
  replace | append)
    [[ $# -eq 3 ]] || usage
    [[ -f "$3" && -r "$3" ]] || usage
    ;;
  *) usage ;;
esac
issue="$1"
heading="$2"
content="${3:-}"
[[ "$issue" =~ ^[0-9]+$ ]] || usage
nl=$'\n'
[[ -n "$heading" && "$heading" != \#* && "$heading" != *"$nl"* ]] || usage

tmp="$(mktemp -d "${TMPDIR:-/tmp}/issue-body.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# The one parser. Prints "<line number><TAB><heading text>" for each `## ` heading outside a fence,
# then "END<TAB><line count>". A fence opens with three or more backticks or tildes, indented at
# most three spaces, and closes with a run of the same character at least as long and nothing after
# it. A trailing CR is ignored, so a body saved by the web editor with CRLF still parses.
# shellcheck disable=SC2016 # awk's $0 and $1, not the shell's
PARSER='
function marker(line,   s, i, n) {
  s = line
  i = 0
  while (i < 3 && substr(s, 1, 1) == " ") { s = substr(s, 2); i++ }
  m_char = substr(s, 1, 1)
  if (m_char != "`" && m_char != "~") return 0
  n = 0
  while (substr(s, n + 1, 1) == m_char) n++
  if (n < 3) return 0
  m_len = n
  m_rest = substr(s, n + 1)
  return 1
}
{
  line = $0
  sub(/\r$/, "", line)
  if (in_fence) {
    if (marker(line) && m_char == f_char && m_len >= f_len && m_rest ~ /^[ \t]*$/) in_fence = 0
    next
  }
  if (marker(line)) {
    in_fence = 1
    f_char = m_char
    f_len = m_len
    next
  }
  if (substr(line, 1, 3) == "## ") {
    text = substr(line, 4)
    sub(/[ \t]+$/, "", text)
    print NR "\t" text
  }
}
END { print "END\t" NR }
'

parse() { awk "$PARSER" "$1"; }

# Sets sec_count (how many times the target heading occurs), sec_start (its first heading's line),
# sec_end (the section's last line) and total (the file's line count).
locate() {
  local n text
  sec_count=0 sec_start=0 sec_end=0 total=0
  while IFS=$'\t' read -r n text; do
    if [[ "$n" == END ]]; then
      total="$text"
      continue
    fi
    if [[ $sec_start -gt 0 && $sec_end -eq 0 ]]; then
      sec_end=$((n - 1))
    fi
    if [[ "$text" == "$heading" ]]; then
      sec_count=$((sec_count + 1))
      if [[ $sec_start -eq 0 ]]; then sec_start="$n"; fi
    fi
  done < <(parse "$1")
  if [[ $sec_start -gt 0 && $sec_end -eq 0 ]]; then sec_end="$total"; fi
}

slice() { awk -v a="$2" -v b="$3" 'NR >= a && NR <= b' "$1"; }

# Drops CRs and leading and trailing blank lines: the form two sections are compared in.
trim() {
  awk '{ sub(/\r$/, ""); lines[NR] = $0; if ($0 ~ /[^ \t]/) { if (!first) first = NR; last = NR } }
       END { if (first) for (i = first; i <= last; i++) print lines[i] }'
}

# Drops trailing blank lines only, keeping every other byte of the lines it keeps.
trim_end() {
  awk '{ lines[NR] = $0; if ($0 ~ /[^ \t\r]/) last = NR } END { for (i = 1; i <= last; i++) print lines[i] }'
}

no_section() {
  echo "issue-body: issue #${issue} has no '## ${heading}' section outside a code fence." >&2
  [[ "$cmd" == get ]] || echo "Nothing was written. Tell the owner the section is missing." >&2
  exit 1
}

duplicate() {
  die "issue #${issue} has the heading '## ${heading}' ${sec_count} times, so the target is ambiguous. Nothing was written."
}

ISSUE_ARGS=(-F "owner={owner}" -F "repo={repo}" -F "number=${issue}")
# The $names below are GraphQL variables, not the shell's.
# shellcheck disable=SC2016
Q_READ='query($owner: String!, $repo: String!, $number: Int!) { repository(owner: $owner, name: $repo) { issue(number: $number) { body lastEditedAt createdAt } } }'
# shellcheck disable=SC2016
Q_STAMP='query($owner: String!, $repo: String!, $number: Int!) { repository(owner: $owner, name: $repo) { issue(number: $number) { lastEditedAt } } }'
# shellcheck disable=SC2016
Q_POST='query($owner: String!, $repo: String!, $number: Int!) { viewer { login } repository(owner: $owner, name: $repo) { issue(number: $number) { body userContentEdits(last: 100) { nodes { editedAt editor { login } } } } } }'

# Reads the body into $tmp/body, and sets read_le (lastEditedAt, empty when never edited) and
# read_ca (createdAt).
read_issue() {
  if ! gh api graphql "${ISSUE_ARGS[@]}" -f query="$Q_READ" \
         --jq '.data.repository.issue | if . == null then error("no such issue") else (.lastEditedAt // ""), .createdAt, .body end' \
         > "$tmp/read" 2> "$tmp/err"; then
    die "couldn't read issue #${issue}: $(cat "$tmp/err")"
  fi
  { IFS= read -r read_le; IFS= read -r read_ca; cat > "$tmp/body"; } < "$tmp/read"
}

# Writes $tmp/new: the body in $1 with the target section replaced or appended to.
build_new() {
  locate "$1"
  [[ $sec_count -gt 0 ]] || no_section
  [[ $sec_count -eq 1 ]] || duplicate
  {
    slice "$1" 1 "$sec_start"
    if [[ "$cmd" == replace ]]; then
      echo ""
      trim < "$content"
    else
      slice "$1" $((sec_start + 1)) "$sec_end" > "$tmp/existing"
      if [[ -n "$(trim < "$tmp/existing")" ]]; then
        trim_end < "$tmp/existing"
      else
        echo ""
      fi
      trim < "$content"
    fi
    if [[ $sec_end -lt $total ]]; then
      echo ""
      slice "$1" $((sec_end + 1)) "$total"
    fi
  } > "$tmp/new"
}

# The target section, trimmed, on stdout. Returns 1 unless the heading occurs exactly once.
section_of() {
  locate "$1"
  [[ $sec_count -eq 1 ]] || return 1
  slice "$1" $((sec_start + 1)) "$sec_end" | trim
}

headings_of() { parse "$1" | awk -F '\t' '$1 != "END" { print $2 }'; }

writes=0
write_body() {
  writes=$((writes + 1))
  if ! gh issue edit "$issue" --body-file "$tmp/new" > /dev/null 2> "$tmp/err"; then
    die "couldn't write issue #${issue}'s body: $(cat "$tmp/err")"
  fi
}

# Returns 0 when only this script's writes landed after its read and the read-back holds the new
# section with every other section in place; 1 after it has reported a lost edit; 2 when the
# read-back does not hold what was written.
post_check() {
  local viewer count since ts who skip lost=""
  if ! gh api graphql "${ISSUE_ARGS[@]}" -f query="$Q_POST" \
         --jq '.data.viewer.login, (.data.repository.issue.userContentEdits.nodes | length), (.data.repository.issue.userContentEdits.nodes[] | "\(.editedAt) \(.editor.login // "ghost")"), .data.repository.issue.body' \
         > "$tmp/post" 2> "$tmp/err"; then
    die "wrote issue #${issue}'s body, but couldn't read it back to check it: $(cat "$tmp/err")"
  fi
  viewer="$(sed -n 1p "$tmp/post")"
  count="$(sed -n 2p "$tmp/post")"
  # Not `sed -n 3,2p` for zero edits: sed prints line 3 when the range runs backwards.
  awk -v last="$((2 + count))" 'NR >= 3 && NR <= last' "$tmp/post" > "$tmp/edits"
  tail -n +"$((3 + count))" "$tmp/post" > "$tmp/after"

  # The edits after the read, newest first. This script's own writes are the newest `writes` of
  # them by the viewer; every other one is an edit this script may have overwritten.
  since="${read_le:-$read_ca}"
  skip="$writes"
  while read -r ts who; do
    if [[ $skip -gt 0 && "$who" == "$viewer" ]]; then
      skip=$((skip - 1))
      continue
    fi
    lost="${lost}  ${ts} by ${who}${nl}"
  done < <(awk -v since="$since" '$1 > since' "$tmp/edits" | sort -r)
  if [[ -n "$lost" ]]; then
    echo "issue-body: another edit to issue #${issue}'s body landed after this script read it, and this write may have replaced it:" >&2
    printf '%s' "$lost" >&2
    echo "Not retried. Tell the owner: the old text is recoverable from the issue's edit history on GitHub." >&2
    return 1
  fi

  section_of "$tmp/new" > "$tmp/want" || return 2
  section_of "$tmp/after" > "$tmp/got" || return 2
  cmp -s "$tmp/want" "$tmp/got" || return 2
  headings_of "$tmp/new" > "$tmp/want_headings"
  headings_of "$tmp/after" > "$tmp/got_headings"
  cmp -s "$tmp/want_headings" "$tmp/got_headings" || return 2
  return 0
}

read_issue

if [[ "$cmd" == get ]]; then
  locate "$tmp/body"
  [[ $sec_count -gt 0 ]] || no_section
  [[ $sec_count -eq 1 ]] || duplicate
  slice "$tmp/body" $((sec_start + 1)) "$sec_end" | trim
  exit 0
fi

bad_heading="$(headings_of "$content" | head -1)"
if [[ -n "$bad_heading" ]]; then
  die "the content file holds its own '## ${bad_heading}' heading, which would split the section. Nothing was written."
fi

build_new "$tmp/body"

# The pre-check: if the body moved since the read, apply the change to the new body instead.
if ! stamp="$(gh api graphql "${ISSUE_ARGS[@]}" -f query="$Q_STAMP" \
                --jq '.data.repository.issue.lastEditedAt // ""' 2> "$tmp/err")"; then
  die "couldn't re-check issue #${issue} before writing: $(cat "$tmp/err"). Nothing was written."
fi
if [[ "$stamp" != "$read_le" ]]; then
  read_issue
  build_new "$tmp/body"
fi

if cmp -s "$tmp/body" "$tmp/new"; then
  echo "issue-body: issue #${issue}'s '## ${heading}' section already holds that content; nothing was written."
  exit 0
fi

for attempt in 1 2; do
  write_body
  pc=0
  post_check || pc=$?
  case "$pc" in
    0)
      echo "issue-body: issue #${issue}: the '## ${heading}' section is written and confirmed."
      exit 0
      ;;
    1) exit 1 ;;
  esac
  if [[ $attempt -eq 1 ]]; then
    echo "issue-body: the read-back of issue #${issue} does not hold the new '## ${heading}' section yet; writing once more." >&2
  fi
done
die "after two writes, issue #${issue}'s '## ${heading}' section still does not read back as written, or another section is missing. Check the issue by hand."
