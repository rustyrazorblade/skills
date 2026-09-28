#!/usr/bin/env bash
# Close another issue M when issue N's PR merges. The owner picks this in activate step 1, for a
# backlog hit that N's work makes obsolete ("close M when this PR merges", or "fold M's scope into
# this issue").
#
# The record lives on issue N, as comments, so it reaches a PR opened in any later session:
#   - a record comment's first line is `🔗 Closes on merge`, and its next line is `- <M>: <title>`;
#   - a withdrawal comment's first line is `🔗 Closes on merge: withdrawn <M>`.
# The active records are the replay, in order, of every such comment written by the authenticated
# gh user: a record adds M, a withdrawal removes it. Anyone can comment on a public repo, so a
# stranger's marker comment never counts.
#
# Subcommands:
#   record       <N> <M>    link "M blocked by N", then comment on N and on M
#   withdraw     <N> <M>    withdrawal comment on N, remove the link, comment on M
#   closes       <N>        print `Closes #N`, then `Closes #M` per active record, in record order
#   close-merged <N> <PR>   only for a merged PR: close and clean each recorded M
#
# The "M blocked by N" link keeps M off the board's ready list until N closes. record sets it
# before it posts anything. If GitHub refuses the link, a loop included, record posts nothing.
# record also walks N's own blocked_by chain first and refuses when M is on it.
#
# Task 3.1 of issue 88, verified on live scratch issues 91-93 on 2026-09-28: GitHub refuses a direct
# two-issue loop with HTTP 422 ("this dependency would create a cycle where the target is already
# blocked by the source"). GitHub accepts a three-issue loop 91 -> 92 -> 93 -> 91. The chain walk is
# therefore required, not a fallback.
#
# Titles are fetched here and written through mktemp files under $TMPDIR with --body-file, never
# through argv. A trap removes the temp files on exit.
#
# bash 3.2 compatible (macOS default): no associative arrays, no mapfile, no GNU-only flags.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

MARK="🔗 Closes on merge"
WITHDRAWN="🔗 Closes on merge: withdrawn "

usage() {
  echo "usage: close-on-merge.sh record <issue> <other-issue>" >&2
  echo "       close-on-merge.sh withdraw <issue> <other-issue>" >&2
  echo "       close-on-merge.sh closes <issue>" >&2
  echo "       close-on-merge.sh close-merged <issue> <pr>" >&2
  exit 2
}

die() {
  echo "close-on-merge: $*" >&2
  exit 1
}

require_numbers() {
  local n
  for n in "$@"; do
    [[ "$n" =~ ^[0-9]+$ ]] || usage
  done
}

cmd="${1:-}"
[[ $# -ge 1 ]] || usage
shift
case "$cmd" in
  record | withdraw)
    [[ $# -eq 2 ]] || usage
    require_numbers "$1" "$2"
    [[ "$1" != "$2" ]] || usage
    ;;
  closes)
    [[ $# -eq 1 ]] || usage
    require_numbers "$1"
    ;;
  close-merged)
    [[ $# -eq 2 ]] || usage
    require_numbers "$1" "$2"
    ;;
  *) usage ;;
esac
n="$1"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/close-on-merge.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

title_of() { gh issue view "$1" --json title --jq .title; }

# Posts the text on stdin as a comment on issue $1, through a temp file.
comment() {
  local f
  f="$(mktemp "$tmp/comment.XXXXXX")"
  cat > "$f"
  gh issue comment "$1" --body-file "$f" > /dev/null
}

# Prints the active records on issue $1, one M per line, in record order. Returns non-zero when the
# gh user or the comments cannot be read.
active_records() {
  local me rows who first second m rest active=" "
  me="$(gh api user --jq .login)" || return 1
  [[ -n "$me" ]] || return 1
  # shellcheck disable=SC2016 # $l is a jq variable, not the shell's
  rows="$(gh api "repos/{owner}/{repo}/issues/$1/comments" --paginate \
            --jq '.[] | select(.body | startswith("🔗 Closes on merge"))
                  | (.body | split("\n")) as $l
                  | [.user.login, ($l[0] | rtrimstr("\r")), (($l[1] // "") | rtrimstr("\r"))] | @tsv')" \
    || return 1
  while IFS=$'\t' read -r who first second; do
    [[ -n "$who" && "$who" == "$me" ]] || continue
    m=""
    if [[ "$first" == "$MARK" && "$second" == "- "* ]]; then
      rest="${second#- }"
      m="${rest%%:*}"
      [[ "$m" =~ ^[0-9]+$ ]] || continue
      active="${active// $m / }${m} "
    elif [[ "$first" == "$WITHDRAWN"* ]]; then
      m="${first#"$WITHDRAWN"}"
      [[ "$m" =~ ^[0-9]+$ ]] || continue
      active="${active// $m / }"
    fi
  done <<< "$rows"
  for m in $active; do echo "$m"; done
}

is_active() { # records m
  local r
  for r in $1; do
    [[ "$r" == "$2" ]] && return 0
  done
  return 1
}

repo_url() { gh api "repos/{owner}/{repo}" --jq .url; }

# Prints "<number>" for each issue in this repo that issue $1 is blocked by.
blockers_of() {
  local repo="$2" rows number url
  rows="$(gh api "repos/{owner}/{repo}/issues/$1/dependencies/blocked_by" --paginate \
            --jq '.[] | "\(.number) \(.repository_url)"')" || return 1
  while read -r number url; do
    [[ -n "$number" && "$url" == "$repo" ]] && echo "$number"
  done <<< "$rows"
  return 0
}

# Returns 0 when issue $2 is on issue $1's blocked_by chain, 1 when not, 2 when a link list cannot
# be read. GitHub accepts a loop of three or more issues (task 3.1), so this walk is the only guard
# against one.
chain_reaches() {
  local start="$1" target="$2" repo queue seen x b bs
  repo="$(repo_url)" || return 2
  queue="$start"
  seen=" $start "
  while [[ -n "$queue" ]]; do
    x="${queue%% *}"
    if [[ "$queue" == *" "* ]]; then queue="${queue#* }"; else queue=""; fi
    bs="$(blockers_of "$x" "$repo")" || return 2
    for b in $bs; do
      [[ "$b" == "$target" ]] && return 0
      case "$seen" in
        *" $b "*) ;;
        *)
          seen="$seen$b "
          queue="${queue:+$queue }$b"
          ;;
      esac
    done
  done
  return 1
}

# The id of issue $1's native blocked_by link to issue $2 in this repo, or nothing.
link_id() {
  local repo rows number id url
  repo="$(repo_url)" || return 1
  rows="$(gh api "repos/{owner}/{repo}/issues/$1/dependencies/blocked_by" --paginate \
            --jq '.[] | "\(.number) \(.id) \(.repository_url)"')" || return 1
  while read -r number id url; do
    if [[ "$number" == "$2" && "$url" == "$repo" ]]; then
      echo "$id"
      return 0
    fi
  done <<< "$rows"
  return 0
}

# The newest of this gh user's "closes with N" notes on issue $1: "on", "off", or nothing.
note_state() {
  local me rows who first state=""
  me="$(gh api user --jq .login)" || return 1
  rows="$(gh api "repos/{owner}/{repo}/issues/$1/comments" --paginate \
            --jq '.[] | [.user.login, (.body | split("\n")[0] | rtrimstr("\r"))] | @tsv')" || return 1
  while IFS=$'\t' read -r who first; do
    [[ -n "$who" && "$who" == "$me" ]] || continue
    case "$first" in
      "Closes when the PR for $2: "*) state=on ;;
      "No longer closes with $2: "*) state=off ;;
    esac
  done <<< "$rows"
  echo "$state"
}

case "$cmd" in
  record)
    m="$2"
    if ! m_facts="$(gh issue view "$m" --json state,title --jq .state 2> "$tmp/err")"; then
      die "couldn't read issue #${m} ($(cat "$tmp/err")). Nothing was linked or posted."
    fi
    [[ "$m_facts" == OPEN ]] || die "issue #${m} is ${m_facts}, not open. Nothing was linked or posted."
    m_title="$(title_of "$m")" || die "couldn't read issue #${m}'s title. Nothing was linked or posted."
    n_title="$(title_of "$n")" || die "couldn't read issue #${n}'s title. Nothing was linked or posted."

    reach=0
    chain_reaches "$n" "$m" || reach=$?
    case "$reach" in
      0) die "#${n} is already blocked, directly or through a chain, by #${m}. Linking #${m} as blocked by #${n} would make a loop. Nothing was linked or posted." ;;
      2) die "couldn't read #${n}'s blocked_by chain, so a loop cannot be ruled out. Nothing was linked or posted." ;;
    esac

    existing="$(link_id "$m" "$n")" || die "couldn't read #${m}'s blocked_by links. Nothing was linked or posted."
    if [[ -z "$existing" ]]; then
      bid="$(gh api "repos/{owner}/{repo}/issues/${n}" --jq .id 2> "$tmp/err")" \
        || die "couldn't resolve issue #${n} ($(cat "$tmp/err")). Nothing was linked or posted."
      # -F, not -f: the API wants an integer, not a string.
      if ! gh api "repos/{owner}/{repo}/issues/${m}/dependencies/blocked_by" \
             -F issue_id="$bid" -X POST > /dev/null 2> "$tmp/err"; then
        echo "close-on-merge: GitHub refused to link #${m} as blocked by #${n}. Nothing was posted." >&2
        echo "GitHub said: $(cat "$tmp/err")" >&2
        exit 1
      fi
    fi

    records="$(active_records "$n")" \
      || die "#${m} is linked as blocked by #${n}, but #${n}'s comments could not be read, so the record was not posted. Re-run record."
    if ! is_active "$records" "$m"; then
      printf '%s\n- %s: %s\n\nWhen the PR for this issue merges, #%s closes too.\n' "$MARK" "$m" "$m_title" "$m" \
        | comment "$n" || die "#${m} is linked as blocked by #${n}, but the record comment on #${n} was not posted. Re-run record."
    fi

    note="$(note_state "$m" "$n")" \
      || die "the record is on #${n}, but #${m}'s comments could not be read, so its note was not posted. Re-run record."
    if [[ "$note" != on ]]; then
      printf 'Closes when the PR for %s: %s merges.\n' "$n" "$n_title" \
        | comment "$m" || die "the record is on #${n}, but the note on #${m} was not posted. Re-run record."
    fi
    echo "close-on-merge: #${m} closes when the PR for #${n} merges (link, record, note)."
    ;;

  withdraw)
    m="$2"
    # Safe to re-run after a partial failure. The withdrawal comment on N, the link, and the note
    # on M are each checked and done only if still due. The link belongs to this record only while
    # the record is active or M's newest note still says it closes with N; otherwise it may be a
    # blocking link the owner chose, and it is left alone.
    records="$(active_records "$n")" || die "couldn't read #${n}'s comments. Nothing was withdrawn."
    note="$(note_state "$m" "$n")" || die "couldn't read #${m}'s comments. Nothing was withdrawn."
    active=no
    if is_active "$records" "$m"; then active=yes; fi
    if [[ "$active" == no && "$note" != on ]]; then
      echo "close-on-merge: #${n} has no active record for #${m}; nothing to withdraw."
      exit 0
    fi
    n_title="$(title_of "$n")" || die "couldn't read issue #${n}'s title. Nothing was withdrawn."
    done_steps=""   # the steps this call ran, for the success line
    if [[ "$active" == yes ]]; then
      printf '%s%s\n' "$WITHDRAWN" "$m" | comment "$n" \
        || die "couldn't post the withdrawal on #${n}. Nothing was withdrawn."
      done_steps="withdrawn"
    fi
    if ! bid="$(link_id "$m" "$n")"; then
      die "the record is withdrawn on #${n}, but #${m}'s blocked_by links could not be read. Re-run withdraw."
    fi
    if [[ -n "$bid" ]]; then
      if ! gh api "repos/{owner}/{repo}/issues/${m}/dependencies/blocked_by/${bid}" -X DELETE > /dev/null 2> "$tmp/err"; then
        die "the record is withdrawn on #${n}, but the link from #${m} to #${n} was not removed ($(cat "$tmp/err")). Re-run withdraw."
      fi
      done_steps="${done_steps:+$done_steps, }link removed"
    fi
    if [[ "$note" == on ]]; then
      printf 'No longer closes with %s: %s.\n' "$n" "$n_title" | comment "$m" \
        || die "the record is withdrawn and the link removed, but the note on #${m} was not posted. Re-run withdraw."
      done_steps="${done_steps:+$done_steps, }note"
    fi
    echo "close-on-merge: #${m} no longer closes with #${n} (${done_steps:-nothing left to do})."
    ;;

  closes)
    records="$(active_records "$n")" || die "couldn't read #${n}'s comments. Do not write a PR body without its closing lines."
    echo "Closes #${n}"
    for m in $records; do echo "Closes #${m}"; done
    ;;

  close-merged)
    pr="$2"
    state="$(gh pr view "$pr" --json state --jq .state 2> "$tmp/err")" \
      || die "couldn't read PR #${pr} ($(cat "$tmp/err")). Nothing was closed."
    [[ "$state" == MERGED ]] || die "PR #${pr} is ${state}, not merged. Nothing was closed."
    records="$(active_records "$n")" || die "couldn't read #${n}'s comments. Nothing was closed."
    [[ -n "$records" ]] || { echo "close-on-merge: #${n} has no close-on-merge records."; exit 0; }
    n_title="$(title_of "$n")" || die "couldn't read issue #${n}'s title. Nothing was closed."

    failed=""
    for m in $records; do
      if ! m_state="$(gh issue view "$m" --json state --jq .state 2> "$tmp/err")"; then
        failed="${failed}  #${m}: couldn't read it ($(cat "$tmp/err")); it may still be open.
"
        continue
      fi
      if [[ "$m_state" == OPEN ]]; then
        # A failed close leaves M exactly as it was: its labels and its link to N still say it
        # waits on N, which is true while it is open.
        if ! gh issue close "$m" > /dev/null 2> "$tmp/err"; then
          failed="${failed}  #${m}: still open; the close failed ($(cat "$tmp/err")). Its labels and links are untouched.
"
          continue
        fi
        # A close that reports success is not trusted until M reads back closed.
        if ! m_state="$(gh issue view "$m" --json state --jq .state 2> "$tmp/err")" || [[ "$m_state" != CLOSED ]]; then
          failed="${failed}  #${m}: still open after the close${m_state:+ (state ${m_state})}. Its labels and links are untouched.
"
          continue
        fi
        printf 'Closed because PR #%s for %s: %s merged.\n' "$pr" "$n" "$n_title" | comment "$m" \
          || echo "close-on-merge: warning: #${m} is closed, but its closing comment was not posted." >&2
      fi

      # Clean M exactly as finalize cleans N. agent:active is never removed: another session may
      # own M. A removal's error is kept, to explain the label if it survives.
      rm_errors=""
      if ! labels="$(gh issue view "$m" --json labels --jq '.labels[].name' 2> "$tmp/err")"; then
        failed="${failed}  #${m}: couldn't read its labels ($(cat "$tmp/err")), so none were removed.
"
        labels=""
      fi
      for l in $labels; do
        case "$l" in
          status:* | needs-attention | blocked | merge-on-green)
            if ! gh issue edit "$m" --remove-label "$l" > /dev/null 2> "$tmp/err"; then
              rm_errors="${rm_errors}${l} $(tr '\n' ' ' < "$tmp/err")
"
            fi
            ;;
          agent:active)
            echo "close-on-merge: #${m} carries agent:active; left in place, because another session may own it."
            ;;
        esac
      done
      "$BASH" "$script_dir/blocked-dependency.sh" sweep "$m" \
        || echo "close-on-merge: warning: sweeping #${m}'s blocked_by links failed." >&2
      # sweep exits 0 even when a DELETE fails, so read the links back.
      if ! left="$(gh api "repos/{owner}/{repo}/issues/${m}/dependencies/blocked_by" --paginate \
                     --jq '.[].number' 2> "$tmp/err")"; then
        failed="${failed}  #${m}: couldn't read its blocked_by links back ($(cat "$tmp/err")).
"
      else
        for b in $left; do
          failed="${failed}  #${m}: still blocked by #${b}; the sweep did not remove that link.
"
        done
      fi

      if ! after="$(gh issue view "$m" --json state,labels --jq '.state, (.labels[].name)' 2> "$tmp/err")"; then
        failed="${failed}  #${m}: couldn't read its labels back ($(cat "$tmp/err")).
"
        continue
      fi
      for l in $after; do
        case "$l" in
          CLOSED) ;;
          OPEN)
            failed="${failed}  #${m}: still open after the close.
"
            ;;
          status:* | needs-attention | blocked | merge-on-green)
            why="$(printf '%s' "$rm_errors" | awk -v l="$l" '$1 == l { $1 = ""; sub(/^ /, ""); print; exit }')"
            failed="${failed}  #${m}: the label ${l} survived its removal${why:+ (gh said: ${why})}.
"
            ;;
        esac
      done
    done
    if [[ -n "$failed" ]]; then
      echo "close-on-merge: PR #${pr} merged, but not every recorded issue is closed and clean:" >&2
      printf '%s' "$failed" >&2
      exit 1
    fi
    echo "close-on-merge: every issue recorded on #${n} is closed and clean."
    ;;
esac
