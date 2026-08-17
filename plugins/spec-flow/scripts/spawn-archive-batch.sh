#!/usr/bin/env bash
# Launch the one-shot archive-batch worker (agents/archive-batch.md) as a separate background
# Claude Code process. Prints the session id and how to attach to it — nothing more.
# Invoked by the project-manager agent, only after it's already confirmed a pending batch with the
# owner (see skills/archive/SKILL.md) — this script itself does no threshold/confirmation logic.
# Background-only, deliberately, same as spawn-issue-pm.sh: the owner manages running sessions
# themselves via `claude agents` (an interactive picker — select the session by name/id; there is
# no direct "attach by id" command).
set -euo pipefail

for bin in claude jq gh git; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "spawn-archive-batch: '$bin' is required but not on PATH." >&2
    exit 1
  }
done

# Scoped to THIS repo, same reasoning as spawn-issue-pm.sh's REPO_ROOT: the session name below is
# fixed ("archive-batch", not per-issue), so on a machine running spec-flow in more than one repo,
# an unscoped name match would find a DIFFERENT repo's archive-batch session and wrongly report
# "already running" here. Only one archive-batch session is ever expected per repo at a time (not
# per-issue, so no numbering) — this scoping is what makes that true per-repo rather than
# machine-wide.
if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "spawn-archive-batch: 'git rev-parse --show-toplevel' failed — run this from inside the" >&2
  echo "target repo's primary checkout." >&2
  exit 1
fi

name="archive-batch"

claude_agents_out=$(mktemp)
if ! claude agents --json --all >"$claude_agents_out" 2>/dev/null; then
  rm -f "$claude_agents_out"
  echo "spawn-archive-batch: 'claude agents --json --all' failed — can't check for an existing session." >&2
  exit 1
fi
existing_id=$(jq -r --arg n "$name" --arg root "$REPO_ROOT" \
  '[.[] | select(.name == $n) | select((.cwd // "") == $root or ((.cwd // "") | startswith($root + "/")))] | sort_by(.startedAt) | last.id // empty' \
  "$claude_agents_out")
existing_state=$(jq -r --arg n "$name" --arg root "$REPO_ROOT" \
  '[.[] | select(.name == $n) | select((.cwd // "") == $root or ((.cwd // "") | startswith($root + "/")))] | sort_by(.startedAt) | last.state // empty' \
  "$claude_agents_out")
rm -f "$claude_agents_out"

if [[ -n "$existing_id" && ( "$existing_state" == "working" || "$existing_state" == "blocked" ) ]]; then
  # Same staleness check as spawn-issue-pm.sh: the registry's own `state` can lag reality.
  if claude logs "$existing_id" > /dev/null 2>&1; then
    echo "already running: ${name} ${existing_id} (attach: claude agents — select ${existing_id})" >&2
    exit 1
  fi
  echo "spawn-archive-batch: ${name} (${existing_id}) shows state=${existing_state} in the" >&2
  echo "registry, but 'claude logs' says it's gone — stale entry. Spawning fresh." >&2
fi

# No respawn path, deliberately (see agents/archive-batch.md's own rules) — a past, no-longer-live
# archive-batch session (crashed, finished, or a stale registry entry) is never resumed; every
# invocation just spawns fresh. Nothing owner-valuable survives between runs to resume: the worker
# recomputes its batch fresh from the default branch every time, so a past attempt's partial state
# (an abandoned worktree, at worst) is simply irrelevant to a new one.
if ! claude --bg \
  --agent spec-flow:archive-batch \
  --name "$name" \
  --permission-mode auto \
  "You are the archive-batch worker. Follow your agent instructions: create a short-lived worktree from the default branch, sync and archive every pending OpenSpec change you find there, commit them as one, open and merge one PR via scripts/archive-batch-pr.sh, comment on each archived issue, then report and finish." \
  > /dev/null; then
  echo "spawn-archive-batch: 'claude --bg' itself failed to launch ${name}" >&2
  exit 1
fi

# Excludes $existing_id (empty if there was no prior record at all) — fresh spawn is the ONLY
# path in this script, unlike spawn-issue-pm.sh where it's only reachable when no same-name
# record exists yet. Without this exclusion, a finished/failed/stale PAST archive-batch session
# would satisfy "name matches, cwd matches" just as well as the brand-new one, and registration
# for the new session can lag slightly behind `claude --bg` returning (same reason
# spawn-issue-pm.sh retries) — so the very first iteration could return the OLD session's id and
# report success while the real new worker runs unreported.
session_id=""
attempts=0
while [[ $attempts -lt 5 ]]; do
  lookup_out=$(mktemp)
  if claude agents --json --all >"$lookup_out" 2>/dev/null; then
    session_id=$(jq -r --arg n "$name" --arg root "$REPO_ROOT" --arg old "$existing_id" \
      '[.[] | select(.name == $n) | select((.cwd // "") == $root or ((.cwd // "") | startswith($root + "/"))) | select(.id != $old)] | sort_by(.startedAt) | last.id // empty' \
      "$lookup_out")
  fi
  rm -f "$lookup_out"
  [[ -n "$session_id" ]] && break
  attempts=$((attempts + 1))
  sleep 1
done

if [[ -z "$session_id" ]]; then
  echo "spawn-archive-batch: '${name}' did not appear in 'claude agents --json --all' after spawn" >&2
  exit 1
fi

echo "${name} ${session_id} — attach: claude agents — select ${session_id}"
