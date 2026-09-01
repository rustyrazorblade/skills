#!/usr/bin/env bash
# Manage an issue's hard-dependency state: the `blocked` label, the explanatory comment, and
# GitHub's NATIVE blocked_by link, as one unit. These three drifted apart when each caller
# open-coded them: only `activate` ever had the mechanics, so a dependency found during
# `implement` had no procedure at all, and `finalize` dropped the label while leaving the native
# link on the closed issue forever (GitHub's UI still rendered it blocked).
#
# Subcommands:
#   add   <issue> <blocking-issue> <reason>   label + comment + native link
#   clear <issue> <blocking-issue>            remove the native link, drop the label, comment
#   sweep <issue>                             remove the label and EVERY native blocked_by link,
#                                             without needing to know the blocking issue --
#                                             what finalize needs on a closed issue.
#
# bash 3.2 compatible (macOS default): no associative arrays, no mapfile, no GNU-only flags.
set -euo pipefail

usage() {
  echo "usage: blocked-dependency.sh add <issue> <blocking-issue> <reason>" >&2
  echo "       blocked-dependency.sh clear <issue> <blocking-issue>" >&2
  echo "       blocked-dependency.sh sweep <issue>" >&2
  exit 2
}

# The BLOCKING issue's database `.id`, which is NOT its `.number` -- different values, and the
# dependencies API wants the id. Verified live.
blocking_id() {
  gh api "repos/{owner}/{repo}/issues/$1" --jq .id
}

cmd="${1:-}"; shift || usage
case "$cmd" in
  add)
    issue="${1:-}"; blocker="${2:-}"; reason="${3:-}"
    [[ -n "$issue" && -n "$blocker" && -n "$reason" ]] || usage
    [[ "$issue" =~ ^[0-9]+$ && "$blocker" =~ ^[0-9]+$ ]] || { echo "blocked-dependency: issue numbers must be numeric" >&2; exit 2; }
    gh issue edit "$issue" --add-label blocked
    # The ⛔ prefix is load-bearing: scripts/board.py finds the reason by it. Keep it first.
    gh issue comment "$issue" --body "⛔ Blocked on #${blocker} — ${reason}"
    # Guarded for the same reason as `clear` below: the label and comment are already applied by
    # this point, so an unguarded failure here would exit without telling the caller that.
    if ! bid=$(blocking_id "$blocker" 2>&1); then
      echo "blocked-dependency: couldn't resolve blocking issue #${blocker} (${bid})." >&2
      echo "The blocked label and comment on #${issue} still stand; the native link was not created." >&2
      exit 1
    fi
    # -F, not -f: the API wants an integer, not a string.
    if ! err=$(gh api "repos/{owner}/{repo}/issues/${issue}/dependencies/blocked_by" \
                 -F issue_id="$bid" -X POST 2>&1); then
      echo "blocked-dependency: couldn't create the native blocked_by link on #${issue}." >&2
      echo "The label and comment still stand. Don't assume this was transient: ${err}" >&2
      exit 1
    fi
    echo "blocked-dependency: #${issue} marked blocked on #${blocker} (label, comment, native link)."
    ;;
  clear)
    issue="${1:-}"; blocker="${2:-}"
    [[ -n "$issue" && -n "$blocker" ]] || usage
    [[ "$issue" =~ ^[0-9]+$ && "$blocker" =~ ^[0-9]+$ ]] || { echo "blocked-dependency: issue numbers must be numeric" >&2; exit 2; }
    # Unguarded, this kills the script under `set -e` before the label comes off -- so a blocker
    # that was since deleted or transferred would leave the issue permanently marked blocked.
    # The label is the part the owner sees; never let the link lookup hold it hostage.
    # Was it ever blocked? Re-running clear, or clearing after add's own partial failure, must be
    # a quiet no-op -- not a false alarm plus a duplicate "✅ Unblocked" comment.
    had_label=1
    if labels=$(gh issue view "$issue" --json labels --jq '.labels[].name' 2>/dev/null); then
      case "$labels" in *blocked*) had_label=0 ;; esac
    fi

    link_removed=1
    if bid=$(blocking_id "$blocker" 2>/dev/null) && [[ -n "$bid" ]]; then
      del_out=""
      if del_out=$(gh api "repos/{owner}/{repo}/issues/${issue}/dependencies/blocked_by/${bid}" -X DELETE 2>&1); then
        link_removed=0
      else
        # A 404 means the link is already absent, which IS the desired end state -- not a failure.
        case "$del_out" in
          *"Not Found"*|*"404"*) link_removed=0 ;;
        esac
      fi
    fi

    label_removed=0
    gh issue edit "$issue" --remove-label blocked 2>/dev/null || label_removed=1

    if [[ $had_label -eq 1 && $link_removed -eq 0 ]]; then
      echo "blocked-dependency: #${issue} was not blocked (no label, no native link) — nothing to do."
      exit 0
    fi

    gh issue comment "$issue" --body "✅ Unblocked — #${blocker} landed."
    if [[ $label_removed -ne 0 ]]; then
      # The opposite drift from the link case below, and just as bad: the board keeps rendering
      # this issue as blocked while the report claims it was cleared.
      echo "blocked-dependency: #${issue} — the 'blocked' LABEL could not be removed." >&2
      echo "The board will keep showing it as blocked. Retry, or remove it by hand:" >&2
      echo "  gh issue edit ${issue} --remove-label blocked" >&2
      exit 1
    fi
    if [[ $link_removed -eq 0 ]]; then
      echo "blocked-dependency: #${issue} unblocked from #${blocker} (link, label, comment)."
    else
      # Reporting success here would recreate exactly the label/link drift this script exists to
      # prevent: the label is gone, so nothing on the board shows it, but GitHub's UI still renders
      # the issue as blocked.
      echo "blocked-dependency: #${issue} label and comment cleared, but the native blocked_by link" >&2
      echo "could NOT be removed (blocking issue #${blocker} unresolvable, or the API call failed)." >&2
      echo "GitHub will still render #${issue} as blocked. Remove it by hand, or let finalize's" >&2
      echo "'sweep' clear it when the issue closes." >&2
      exit 1
    fi
    ;;
  sweep)
    issue="${1:-}"
    [[ -n "$issue" ]] || usage
    [[ "$issue" =~ ^[0-9]+$ ]] || { echo "blocked-dependency: issue number must be numeric" >&2; exit 2; }
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
