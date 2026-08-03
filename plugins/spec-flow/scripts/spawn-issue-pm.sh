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
[[ "$issue" =~ ^[0-9]+$ ]] || usage   # never let a stray flag/string reach gh/osascript unvalidated

for bin in claude jq gh; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "spawn-issue-pm: '$bin' is required but not on PATH." >&2
    echo "If you can't install it (jq in particular): don't run this script — an agent can replicate" >&2
    echo "its logic directly (claude agents --json --all / gh issue view --json labels / claude respawn" >&2
    echo "or claude --bg), reading the JSON as text instead of piping it through jq. See project-manager.md." >&2
    exit 1
  }
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

# Local session lookup FIRST, and --all (not just live ones): a background session's worktree is
# tied to that SESSION, not to the issue, so a crashed/stopped issue-pm can only be put back in
# its own worktree (branch, uncommitted work, everything) by `claude respawn <id>` — a fresh
# `claude --bg` would start an unrelated, empty worktree branched from main. Confirmed empirically
# (2026-08-03): respawn keeps the same cwd/worktree and files; a fresh --bg does not.
# `sort_by(.startedAt) | last` picks the most recent if more than one past session shares the name.
existing_json=$(claude agents --json --all 2>/dev/null \
  | jq -c --arg n "$name" '[.[] | select(.name == $n)] | sort_by(.startedAt) | last // empty')
existing_id=$(jq -r '.id // empty' <<<"${existing_json:-null}" 2>/dev/null || true)
existing_state=$(jq -r '.state // empty' <<<"${existing_json:-null}" 2>/dev/null || true)

if [[ -n "$existing_id" && ( "$existing_state" == "working" || "$existing_state" == "blocked" ) ]]; then
  echo "already running: ${name} ${existing_id} (attach: claude attach ${existing_id})" >&2
  exit 1
fi

if [[ -n "$existing_id" ]]; then
  # We have a past session for this issue on THIS machine, not currently live (done/failed/
  # stopped) — respawn it rather than starting fresh, so it lands back in its own worktree with
  # its branch/uncommitted work intact instead of an empty one branched from main.
  #
  # If agent:active is already set, it's most likely OUR OWN prior claim from before the crash —
  # but it could also mean a different machine has since spawned a live session for this same
  # issue (e.g. after a human cleared a stale label and someone else raced in). Not fully
  # distinguishable without a real distributed lock, but the assignee is a cheap, meaningful
  # signal: if it's someone else, don't respawn on top of their claim.
  active_label=$(gh issue view "$issue" --json labels \
    --jq '.labels[] | select(.name == "agent:active") | .name' 2>/dev/null)
  if [[ -n "$active_label" ]]; then
    me=$(gh api user --jq .login 2>/dev/null)
    assignee=$(gh issue view "$issue" --json assignees --jq '.assignees[0].login // "unknown"' 2>/dev/null)
    if [[ -n "$me" && "$assignee" != "$me" ]]; then
      echo "already active: issue #${issue} carries agent:active, assigned to ${assignee} (not you) —" >&2
      echo "likely a live issue-pm on another machine. Not respawning on top of it." >&2
      exit 1
    fi
  fi

  echo "resuming: ${name} was ${existing_state} — respawning ${existing_id} in its existing worktree" >&2
  claude respawn "$existing_id" > /dev/null
  session_id="$existing_id"

  # FAIL-SAFE, confirmed by test (2026-08-03): if the worktree this session lived in has since
  # been removed (e.g. Claude Code's own cleanupPeriodDays sweep), respawn does NOT recreate it
  # and does NOT error — it silently falls back to the PRIMARY checkout. That means every command
  # this issue-pm runs from here would land in the owner's own working directory. Refuse to let
  # that happen silently: stop it immediately and surface it instead of trusting the respawn.
  # Empty/missing cwd data counts as unsafe too (-z), not just a confirmed wrong path — a
  # transient `claude agents` failure here must never be read as "must be fine, then."
  respawned_cwd=$(claude agents --json --all 2>/dev/null \
    | jq -r --arg id "$session_id" '.[] | select(.id == $id) | .cwd // empty')
  if [[ -z "$respawned_cwd" || "$respawned_cwd" != *"/.claude/worktrees/"* ]]; then
    claude stop "$session_id" > /dev/null 2>&1 || true
    gh issue edit "$issue" --remove-label agent:active 2>/dev/null || true
    echo "spawn-issue-pm: respawned ${name} (${session_id}) landed in '${respawned_cwd:-<empty>}'," >&2
    echo "NOT a confirmed isolated worktree — either its original worktree is gone (likely swept)," >&2
    echo "or the state couldn't be confirmed. Stopped it before it could touch anything. The branch" >&2
    echo "is still on origin (checkpoint pushes) if this issue-pm ever got that far; recover" >&2
    echo "manually: 'git worktree add <path> <branch>' from the existing branch, or start over with" >&2
    echo "a fresh spawn if nothing was pushed yet." >&2
    exit 1
  fi

  # Respawn confirmed safe — make sure agent:active reflects it, whether or not it was already
  # set (e.g. a human cleared it during the earlier crash, per docs/workflow.md's known gap).
  gh issue edit "$issue" --add-label agent:active
else
  # No local record at all. GitHub's agent:active label is the cross-machine, cross-user signal —
  # an issue-pm running on someone else's machine (or yours, on a different one) is invisible to
  # the local lookup above, but not to this one. This is what actually makes it safe for two
  # developers to work the same repo without duplicating an issue-pm.
  active_label=$(gh issue view "$issue" --json labels \
    --jq '.labels[] | select(.name == "agent:active") | .name' 2>/dev/null)
  if [[ -n "$active_label" ]]; then
    assignee=$(gh issue view "$issue" --json assignees --jq '.assignees[0].login // "unknown"' 2>/dev/null)
    echo "already active: issue #${issue} carries agent:active (assignee: ${assignee}) — an issue-pm may be running on another machine, or this one hasn't set the label yet. Not spawning a duplicate." >&2
    exit 1
  fi

  # Set the label OURSELVES, right here, before spawning — don't leave it to `activate` (which
  # only runs once the spawned session gets around to it, maybe well after spawn). That gap is
  # exactly the window two near-simultaneous spawns on different machines could both slip through.
  # Setting it this early narrows that window from minutes to the time this script takes to run;
  # it isn't a true compare-and-swap (gh has no atomic label-if-absent), but it's the tightest this
  # gets without one. Roll it back below if the spawn itself doesn't pan out.
  gh issue edit "$issue" --add-label agent:active

  # No --worktree here: --bg does not accept it. Claude Code isolates before an Edit/Write TOOL
  # call, but confirmed by test: NOT before a Bash-driven file write (printf/heredoc/an external
  # CLI writing files itself, e.g. `openspec`) — so the prompt below forces isolation as the very
  # first action via EnterWorktree, before step 1 of activate even runs, rather than trusting it to
  # happen implicitly. That's the worktree issue-pm ends up running in, named and placed by Claude
  # Code, not by this script.
  if ! claude --bg \
    --agent issue-pm \
    --name "$name" \
    --permission-mode acceptEdits \
    "Before doing anything else, call the EnterWorktree tool to isolate yourself into your own git worktree. Do this first, even though nothing has been written yet — every action after this point, tool-driven or Bash-driven (including gh/git/openspec commands), must happen inside that worktree, not the primary checkout. Once isolated: you are the issue-pm for issue #${issue}. Run /spec-flow:activate ${issue} to start (it claims the issue as its own first step — don't claim it yourself here), then drive through finalize. Stop at both owner seams." \
    > /dev/null; then
    gh issue edit "$issue" --remove-label agent:active 2>/dev/null || true
    echo "spawn-issue-pm: 'claude --bg' itself failed to launch ${name}" >&2
    exit 1
  fi

  session_id=$(claude agents --json --all \
    | jq -r --arg n "$name" '[.[] | select(.name == $n)] | sort_by(.startedAt) | last.id // empty')

  if [[ -z "$session_id" ]]; then
    gh issue edit "$issue" --remove-label agent:active 2>/dev/null || true
    echo "spawn-issue-pm: '${name}' did not appear in 'claude agents --json' after spawn" >&2
    exit 1
  fi
fi

state=$(claude agents --json --all \
  | jq -r --arg id "$session_id" '.[] | select(.id == $id) | .state')
if [[ "$state" == "failed" ]]; then
  gh issue edit "$issue" --remove-label agent:active 2>/dev/null || true
  echo "spawn-issue-pm: ${name} (${session_id}) is failed — check 'claude logs ${session_id}'" >&2
  exit 1
fi

attach_cmd="claude attach ${session_id}"

case "$display" in
  iterm) open_iterm "$name" "$attach_cmd" ;;
  tmux)  open_tmux  "$name" "$attach_cmd" ;;
  none)  ;;
esac

echo "${name} ${session_id} (${display}) attach: ${attach_cmd}"
