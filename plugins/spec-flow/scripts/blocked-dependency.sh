#!/usr/bin/env bash
# Record and clear what blocks an issue. Each kind of blocker has its own record, and its own add
# and clear:
#
#   - A dependency on another ISSUE is GitHub's native blocked_by link, and nothing else. The link
#     knows when its blocker closes, so the board releases the issue by itself; nobody has to clear
#     anything when the blocker lands. The `blocked` label is never set for it: a label nothing
#     removes goes stale the moment the blocker closes.
#   - A blocker that is NOT an issue (an external PR, a third party) is the `blocked` label, with
#     the reason in a `Blocked by: <reason>` comment. scripts/board.py reads the last such comment.
#
# Subcommands:
#   add            <issue> <blocking-issue> <reason>  native link + `⛔ Blocked on #M` comment
#   add-external   <issue> <reason>                   label + `Blocked by: <reason>` comment
#   clear          <issue> <blocking-issue>           remove a WRONG native link in this repo
#   clear-external <issue>                            remove the label + `✅ Unblocked` comment
#   sweep          <issue>                            remove the label and EVERY native blocked_by
#                                                     link, without needing to know the blocking
#                                                     issue -- what finalize needs on a closed issue.
#
# bash 3.2 compatible (macOS default): no associative arrays, no mapfile, no GNU-only flags.
set -euo pipefail

usage() {
  echo "usage: blocked-dependency.sh add <issue> <blocking-issue> <reason>" >&2
  echo "       blocked-dependency.sh add-external <issue> <reason>" >&2
  echo "       blocked-dependency.sh clear <issue> <blocking-issue>" >&2
  echo "       blocked-dependency.sh clear-external <issue>" >&2
  echo "       blocked-dependency.sh sweep <issue>" >&2
  exit 2
}

# Every issue number must be present and numeric; anything else is a usage error.
require_numbers() {
  local n
  for n in "$@"; do
    [[ "$n" =~ ^[0-9]+$ ]] || usage
  done
}

# The BLOCKING issue's database `.id`, which is NOT its `.number` -- different values, and the
# dependencies API wants the id. Verified live.
blocking_id() {
  gh api "repos/{owner}/{repo}/issues/$1" --jq .id
}

# Prints the id of issue N's native blocked_by link to issue M in THIS repo, or nothing when there
# is no such link. Returns non-zero when the links or this repo's identity cannot be read, so a
# caller can tell "no link" from "don't know". A bare number names an issue in this repo, so a link
# to a same-numbered issue in another repo never matches; that one is removed by hand.
find_link() {
  local issue="$1" blocker="$2" repo links number id url
  repo=$(gh api "repos/{owner}/{repo}" --jq .url 2>/dev/null) || return 1
  [[ -n "$repo" ]] || return 1
  links=$(gh api "repos/{owner}/{repo}/issues/${issue}/dependencies/blocked_by" --paginate \
            --jq '.[] | "\(.number) \(.id) \(.repository_url)"' 2>/dev/null) || return 1
  while read -r number id url; do
    if [[ "$number" == "$blocker" && "$url" == "$repo" ]]; then
      echo "$id"
      return 0
    fi
  done <<<"$links"
  return 0
}

cmd="${1:-}"; shift || usage
case "$cmd" in
  add)
    [[ $# -eq 3 && -n "$3" ]] || usage
    issue="$1"; blocker="$2"; reason="$3"
    require_numbers "$issue" "$blocker"
    if ! existing=$(find_link "$issue" "$blocker"); then
      echo "blocked-dependency: couldn't read #${issue}'s native blocked_by links, so nothing was applied." >&2
      exit 1
    fi
    # Re-running add with a new reason is a normal act, so a link that is already there counts as
    # present: no second link, and the new reason is still posted.
    if [[ -z "$existing" ]]; then
      if ! bid=$(blocking_id "$blocker" 2>&1); then
        echo "blocked-dependency: couldn't resolve blocking issue #${blocker} (${bid}), so nothing was applied." >&2
        exit 1
      fi
      # -F, not -f: the API wants an integer, not a string.
      if ! err=$(gh api "repos/{owner}/{repo}/issues/${issue}/dependencies/blocked_by" \
                   -F issue_id="$bid" -X POST 2>&1); then
        echo "blocked-dependency: couldn't create the native blocked_by link on #${issue}, so nothing was applied." >&2
        echo "Don't assume this was transient: ${err}" >&2
        exit 1
      fi
    fi
    if ! gh issue comment "$issue" --body "⛔ Blocked on #${blocker} — ${reason}" >/dev/null 2>&1; then
      echo "blocked-dependency: #${issue}'s native blocked_by link is in place (to #${blocker}), but the comment was not posted." >&2
      exit 1
    fi
    echo "blocked-dependency: #${issue} blocked on #${blocker} (native link, comment)."
    ;;
  add-external)
    [[ $# -eq 2 && -n "$2" ]] || usage
    issue="$1"; reason="$2"
    require_numbers "$issue"
    if ! gh issue edit "$issue" --add-label blocked >/dev/null 2>&1; then
      echo "blocked-dependency: couldn't add the 'blocked' label to #${issue}, so nothing was applied." >&2
      exit 1
    fi
    # The `Blocked by:` prefix is load-bearing: scripts/board.py finds the reason by it, exactly and
    # case-sensitively, and shows the last one. Keep it first.
    if ! gh issue comment "$issue" --body "Blocked by: ${reason}" >/dev/null 2>&1; then
      echo "blocked-dependency: the 'blocked' label is on #${issue}, but the 'Blocked by:' comment was not posted." >&2
      echo "The board shows 'see issue comments' as the reason until one is." >&2
      exit 1
    fi
    echo "blocked-dependency: #${issue} blocked by: ${reason} (label, comment)."
    ;;
  clear)
    [[ $# -eq 2 ]] || usage
    issue="$1"; blocker="$2"
    require_numbers "$issue" "$blocker"
    # For removing a link that should not be there. A blocker that closes needs no clear: the
    # native link releases the issue on the board by itself. The label is never touched here.
    if ! bid=$(find_link "$issue" "$blocker"); then
      echo "blocked-dependency: couldn't read #${issue}'s native blocked_by links. The link to #${blocker}, if any, is still there." >&2
      exit 1
    fi
    if [[ -z "$bid" ]]; then
      echo "blocked-dependency: #${issue} has no native link to #${blocker} in this repo — nothing to do."
      exit 0
    fi
    if ! err=$(gh api "repos/{owner}/{repo}/issues/${issue}/dependencies/blocked_by/${bid}" -X DELETE 2>&1); then
      echo "blocked-dependency: couldn't remove the native link from #${issue} to #${blocker}; it is still there." >&2
      echo "gh said: ${err}" >&2
      exit 1
    fi
    # Not "landed": clear removes a wrong link, and says nothing about the blocker's own state.
    if ! gh issue comment "$issue" --body "Dependency on #${blocker} removed." >/dev/null 2>&1; then
      echo "blocked-dependency: removed the native link from #${issue} to #${blocker}, but the comment was not posted." >&2
      exit 1
    fi
    echo "blocked-dependency: #${issue} no longer depends on #${blocker} (native link removed, comment)."
    ;;
  clear-external)
    [[ $# -eq 1 ]] || usage
    issue="$1"
    require_numbers "$issue"
    if ! labels=$(gh issue view "$issue" --json labels --jq '.labels[].name' 2>/dev/null); then
      echo "blocked-dependency: couldn't read #${issue}'s labels. The board will keep showing it as blocked" >&2
      echo "if the label is there. Retry, or remove it by hand: gh issue edit ${issue} --remove-label blocked" >&2
      exit 1
    fi
    # An exact match, never a substring: `blocked-upstream` is not the `blocked` label.
    had_label=1
    while read -r name; do
      [[ "$name" == "blocked" ]] && had_label=0
    done <<<"$labels"
    if [[ $had_label -ne 0 ]]; then
      echo "blocked-dependency: #${issue} has no 'blocked' label — nothing to do."
      exit 0
    fi
    if ! gh issue edit "$issue" --remove-label blocked >/dev/null 2>&1; then
      echo "blocked-dependency: #${issue} — the 'blocked' label could not be removed." >&2
      echo "The board will keep showing it as blocked. Retry, or remove it by hand:" >&2
      echo "  gh issue edit ${issue} --remove-label blocked" >&2
      exit 1
    fi
    if ! gh issue comment "$issue" --body "✅ Unblocked" >/dev/null 2>&1; then
      echo "blocked-dependency: removed the 'blocked' label from #${issue}, but the comment was not posted." >&2
      exit 1
    fi
    echo "blocked-dependency: #${issue} unblocked (label removed, comment)."
    ;;
  sweep)
    [[ $# -eq 1 ]] || usage
    issue="$1"
    require_numbers "$issue"
    # No comment here: sweep runs on a closed issue, where a "✅ Unblocked" note would be noise.
    if ids=$(gh api "repos/{owner}/{repo}/issues/${issue}/dependencies/blocked_by" --jq '.[].id' 2>/dev/null); then
      for bid in $ids; do
        gh api "repos/{owner}/{repo}/issues/${issue}/dependencies/blocked_by/${bid}" -X DELETE >/dev/null 2>&1 \
          || echo "blocked-dependency: warning — couldn't remove native blocked_by ${bid} from #${issue}." >&2
      done
    else
      echo "blocked-dependency: warning — couldn't list native blocked_by links on #${issue}; the label is still removed below." >&2
    fi
    gh issue edit "$issue" --remove-label blocked 2>/dev/null || true
    ;;
  *) usage ;;
esac
