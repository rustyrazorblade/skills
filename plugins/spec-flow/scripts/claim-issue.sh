#!/usr/bin/env bash
# Claim a GitHub issue for this issue-manager session — assign, label agent:active, and post the
# "claimed" comment once, idempotently. `--add-assignee`/`--add-label` are safe to repeat, but the
# comment only posts on a genuinely fresh claim, not a re-activation of your own in-flight issue.
# See activate/SKILL.md step 1 (multi-user guard / claim) for the full reasoning.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: claim-issue.sh <issue-number>" >&2
  exit 1
fi
n="$1"
# Validate before anything reaches gh. Without this, `claim-issue.sh -5` is parsed as an OPTION by
# three separate gh calls, producing three confusing errors instead of one usage message.
# spawn-issue-manager.sh guards its own issue argument the same way.
if [[ ! "$n" =~ ^[0-9]+$ ]]; then
  echo "claim-issue: issue number must be numeric, got '$n'" >&2
  echo "usage: claim-issue.sh <issue-number>" >&2
  exit 1
fi

command -v gh >/dev/null 2>&1 || {
  echo "claim-issue: 'gh' is required but not on PATH." >&2
  exit 1
}

me=$(gh api user --jq .login)
# gh's own --jq flag does NOT support jq's --arg passthrough (confirmed live: "accepts at most
# 1 arg(s), received 3") — interpolate the value straight into the jq expression string instead.
# GitHub logins are alphanumeric/hyphen only, so this is safe to inline without escaping issues.
# Use exact-match `any(...)`, not `contains([...])` — jq's array `contains` is a SUBSTRING test
# on string elements (confirmed live: contains(["jon"]) matches login "jonhaddad"), which would
# false-positive already_mine for any login containing yours as a substring.
already_mine=$(gh issue view "$n" --json assignees --jq "[.assignees[].login] | any(. == \"$me\")")
gh issue edit "$n" --add-assignee @me --add-label agent:active >/dev/null
if [[ "$already_mine" != "true" ]]; then
  gh issue comment "$n" --body "🏗️ Claimed — starting design."
fi
echo "claim-issue: claimed #$n (already_mine=$already_mine, me=$me)"
