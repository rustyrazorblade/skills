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

lookup_session_id() {
  claude agents --json --all 2>/dev/null \
    | jq -r --arg n "$1" '[.[] | select(.name == $n)] | sort_by(.startedAt) | last.id // empty'
}
lookup_session_cwd() {
  claude agents --json --all 2>/dev/null \
    | jq -r --arg id "$1" '.[] | select(.id == $id) | .cwd // empty'
}
# `claude agents --json` registration can lag slightly behind `claude --bg`/`claude respawn`
# returning — retry briefly instead of trusting a single immediate check either way, in either
# direction (a false "didn't appear" removes a label that should stay; a false "unsafe" stops a
# perfectly healthy respawn).
retry_until_nonempty() {
  local out="" attempts=0
  while [[ $attempts -lt 5 ]]; do
    out=$("$@")
    [[ -n "$out" ]] && { echo "$out"; return 0; }
    attempts=$((attempts + 1))
    sleep 1
  done
  echo ""
}

# Local session lookup FIRST, and --all (not just live ones): a background session's worktree is
# tied to that SESSION, not to the issue, so a crashed/stopped issue-pm can only be put back in
# its own worktree (branch, uncommitted work, everything) by `claude respawn <id>` — a fresh
# `claude --bg` would start an unrelated, empty worktree branched from main. Confirmed empirically
# (2026-08-03): respawn keeps the same cwd/worktree and files; a fresh --bg does not.
# `sort_by(.startedAt) | last` picks the most recent if more than one past session shares the name.
# A PIPESTATUS check AFTER `existing_json=$(claude ... | jq ...)` is unreachable: under `set -e`,
# a failing left-hand command masked by jq's success-on-empty-input (jq exits 0 even when `claude`
# failed and produced nothing) still makes the ASSIGNMENT itself fail, via pipefail, and `set -e`
# kills the script at that line — before any later PIPESTATUS check could ever run (confirmed by
# test: `set -euo pipefail; v=$(false | cat); echo reached` never prints). Route `claude`'s output
# through a temp file instead of a pipe, so its exit status can be checked directly with a plain
# `if ! cmd; then`, with jq reading the file afterward — no pipeline, no PIPESTATUS ambiguity.
claude_agents_out=$(mktemp)
if ! claude agents --json --all >"$claude_agents_out" 2>/dev/null; then
  rm -f "$claude_agents_out"
  echo "spawn-issue-pm: 'claude agents --json --all' failed — can't check for an existing session." >&2
  exit 1
fi
existing_json=$(jq -c --arg n "$name" '[.[] | select(.name == $n)] | sort_by(.startedAt) | last // empty' "$claude_agents_out")
rm -f "$claude_agents_out"
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
    --jq '.labels[] | select(.name == "agent:active") | .name' 2>/dev/null) || true
  # (fail open on a `gh` hiccup here — we already have local evidence this respawn is ours,
  # unlike the fresh-spawn path below which has nothing local to fall back on)
  if [[ -n "$active_label" ]]; then
    me=$(gh api user --jq .login 2>/dev/null) || true   # can't verify -> fall through and respawn;
                                                          # we already have local evidence this is ours
    assignee=$(gh issue view "$issue" --json assignees --jq '.assignees[0].login // "unknown"' 2>/dev/null) || true
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
  respawned_cwd=$(retry_until_nonempty lookup_session_cwd "$session_id")
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
  # set (e.g. a human cleared it during the earlier crash, per docs/workflow.md's known gap). The
  # session is ALREADY LIVE at this point — a transient `gh` failure here must warn and continue,
  # not die: exiting now would abandon a healthy, running session with no label, the exact
  # false-negative (silently-unlabeled-but-live) the label exists to prevent.
  gh issue edit "$issue" --add-label agent:active 2>/dev/null || \
    echo "spawn-issue-pm: warning — couldn't set agent:active on #${issue} after respawn (transient gh failure?); ${name} (${session_id}) is running regardless. Set the label manually if this persists." >&2
else
  # No local record at all. GitHub's agent:active label is the cross-machine, cross-user signal —
  # an issue-pm running on someone else's machine (or yours, on a different one) is invisible to
  # the local lookup above, but not to this one. This is what actually makes it safe for two
  # developers to work the same repo without duplicating an issue-pm.
  if ! active_label=$(gh issue view "$issue" --json labels \
    --jq '.labels[] | select(.name == "agent:active") | .name' 2>/dev/null); then
    echo "spawn-issue-pm: 'gh issue view' failed — can't verify whether #${issue} is already" >&2
    echo "active. Nothing local backs a fresh spawn, so refusing rather than guessing; check" >&2
    echo "'gh auth status' and your network, then retry." >&2
    exit 1
  fi
  if [[ -n "$active_label" ]]; then
    # Purely informational (folded into the message below, then exiting regardless) — a `gh`
    # hiccup here should degrade to "unknown", not produce a different, more confusing failure
    # than the "already active" message this branch is already committed to reporting.
    assignee=$(gh issue view "$issue" --json assignees --jq '.assignees[0].login // "unknown"' 2>/dev/null) || assignee="unknown"
    echo "already active: issue #${issue} carries agent:active (assignee: ${assignee}) — an issue-pm may be running on another machine, or this one hasn't set the label yet. Not spawning a duplicate." >&2
    exit 1
  fi

  # Even without the label, the issue itself might already be assigned to someone else on
  # GitHub. Spawning anyway would plant agent:active on an issue this session has no business
  # working — activate's own multi-user guard would stop the spawned session, but nothing would
  # ever clear the label it left behind.
  if ! me=$(gh api user --jq .login 2>/dev/null); then
    echo "spawn-issue-pm: couldn't verify your GitHub identity ('gh api user' failed) — check" >&2
    echo "'gh auth status'. Refusing to spawn without being able to check the assignee: this is a" >&2
    echo "new spawn (unlike a respawn, nothing local backs the claim yet)." >&2
    exit 1
  fi
  # Fail loud, matching the `me=` check just above: this is the fresh-spawn path, nothing local
  # backs the claim yet, so a `gh` failure here must not silently fall through to spawning.
  if ! assignee=$(gh issue view "$issue" --json assignees --jq '.assignees[0].login // empty' 2>/dev/null); then
    echo "spawn-issue-pm: couldn't check #${issue}'s assignee ('gh issue view' failed) — check" >&2
    echo "'gh auth status'. Refusing to spawn without being able to verify it isn't someone else's." >&2
    exit 1
  fi
  if [[ -n "$assignee" && "$assignee" != "$me" ]]; then
    echo "issue #${issue} is already assigned to ${assignee} (not you) — not spawning; that's their claim." >&2
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

  session_id=$(retry_until_nonempty lookup_session_id "$name")

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
