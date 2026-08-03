#!/usr/bin/env bash
# Launch a dedicated issue-pm as a separate background Claude Code process, then
# open a live, attached view of it in an iTerm2 tab or tmux window (per the owner's
# configured display mode). Invoked by the project-manager agent — never by a human
# directly, though it's safe to run by hand too.
set -euo pipefail

usage() {
  echo "usage: spawn-issue-pm.sh <issue-number> [--display iterm|tmux|none]" >&2
  exit 2
}

issue=""
display=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --display)   display="${2:?--display needs a value}"; shift 2 ;;
    --display=*) display="${1#*=}"; shift ;;
    -*)          usage ;;
    *)           issue="$1"; shift ;;
  esac
done
[[ -n "$issue" ]] || usage

for bin in claude jq gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "spawn-issue-pm: '$bin' is required but not on PATH" >&2; exit 1; }
done

repo_root=$(git rev-parse --show-toplevel)
conf="${repo_root}/.claude/spec-flow.conf"

# precedence: flag > env > repo config > autodetect
[[ -n "$display" ]] || display="${SPEC_FLOW_DISPLAY:-}"
if [[ -z "$display" && -f "$conf" ]]; then
  display=$(sed -n 's/^display=//p' "$conf" | tail -1 | tr -d '"'"'"' ')
fi
if [[ -z "$display" ]]; then
  if   [[ -n "${TMUX:-}" ]];                     then display=tmux
  elif [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then display=iterm
  else display=none
  fi
fi
case "$display" in
  iterm|tmux|none) ;;
  *) echo "spawn-issue-pm: unknown display mode: ${display}" >&2; exit 2 ;;
esac

open_iterm() {
  local title="$1" cmd="$2"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "spawn-issue-pm: --display iterm requires macOS + iTerm2. Set display=tmux instead (env SPEC_FLOW_DISPLAY, or 'display=tmux' in ${conf})." >&2
    exit 1
  fi
  osascript <<APPLESCRIPT
tell application "iTerm2"
  if (count of windows) = 0 then
    create window with default profile
  else
    tell current window to create tab with default profile
  end if
  tell current session of current window
    set name to "${title}"
    write text "${cmd}"
  end tell
  activate
end tell
APPLESCRIPT
}

open_tmux() {
  local title="$1" cmd="$2"
  if [[ -n "${TMUX:-}" ]]; then
    tmux new-window -n "$title" "$cmd"
    return
  fi
  local sess
  sess="spec-flow-$(basename "$repo_root")"
  if tmux has-session -t "$sess" 2>/dev/null; then
    tmux new-window -t "$sess" -n "$title" "$cmd"
  else
    tmux new-session -d -s "$sess" -n "$title" "$cmd"
  fi
  echo "detached: tmux attach -t ${sess}" >&2
}

name="issue-pm-${issue}"

# GitHub label check FIRST: agent:active is the cross-machine, cross-user signal — an issue-pm
# running on someone else's machine (or yours, earlier, on a different one) is invisible to the
# local `claude agents --json` check below, but not to this one. This is what actually makes it
# safe for two developers to work the same repo without duplicating an issue-pm.
active_label=$(gh issue view "$issue" --json labels \
  --jq '.labels[] | select(.name == "agent:active") | .name' 2>/dev/null)
if [[ -n "$active_label" ]]; then
  assignee=$(gh issue view "$issue" --json assignees --jq '.assignees[0].login // "unknown"' 2>/dev/null)
  echo "already active: issue #${issue} carries agent:active (assignee: ${assignee}) — an issue-pm may be running on another machine. Not spawning a duplicate." >&2
  exit 1
fi

# `claude agents --json` (no --all) lists only LIVE sessions on THIS machine — a narrower,
# local-only backstop for the case where the GitHub label somehow lagged (e.g. spawned seconds
# ago, activate hasn't set it yet).
existing=$(claude agents --json 2>/dev/null \
  | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)
if [[ -n "$existing" ]]; then
  echo "already running: ${name} ${existing} (attach: claude attach ${existing})"
  exit 1
fi

# No --worktree here: --bg does not accept it. Claude Code isolates every
# background session into its own worktree automatically before it touches any
# file (see docs.claude.com/en/worktrees) — that's the worktree issue-pm ends up
# running in, named and placed by Claude Code, not by this script.
claude --bg \
  --agent issue-pm \
  --name "$name" \
  --permission-mode acceptEdits \
  "You are the issue-pm for issue #${issue}. Claim it, then drive activate through finalize. Stop at both owner seams." \
  > /dev/null

session_id=$(claude agents --json \
  | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)

if [[ -z "$session_id" ]]; then
  echo "spawn-issue-pm: '${name}' did not appear in 'claude agents --json' after spawn" >&2
  exit 1
fi

state=$(claude agents --json \
  | jq -r --arg n "$name" '.[] | select(.name == $n) | .state')
if [[ "$state" == "failed" ]]; then
  echo "spawn-issue-pm: ${name} (${session_id}) exited immediately — check 'claude logs ${session_id}'" >&2
  exit 1
fi

attach_cmd="claude attach ${session_id}"

case "$display" in
  iterm) open_iterm "$name" "$attach_cmd" ;;
  tmux)  open_tmux  "$name" "$attach_cmd" ;;
  none)  ;;
esac

echo "${name} ${session_id} (${display}) attach: ${attach_cmd}"
