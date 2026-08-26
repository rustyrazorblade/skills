#!/usr/bin/env bash
# Structural + behavioral test for board.py. Fakes `gh`/`git`/`claude` on PATH so this runs
# offline, deterministically, and exercises the branches this repo's own real board data
# doesn't (epics, PR/CI correlation, blocked/needs-attention reasons, stalled detection, the
# "next up" ladder) rather than relying on live GitHub state. Exits non-zero if any assertion
# fails. macOS bash 3.2 compatible (no associative arrays, no mapfile).
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
board="$script_dir/board.py"

pass_count=0
fail_count=0

check() {
  local desc="$1"
  local status="$2"
  if [[ "$status" -eq 0 ]]; then
    echo "PASS: $desc"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $desc"
    fail_count=$((fail_count + 1))
  fi
}

command -v python3 >/dev/null 2>&1 || { echo "test-board: 'python3' is required but not on PATH." >&2; exit 1; }

fake_bin_dir="$(mktemp -d)"
trap 'rm -rf "$fake_bin_dir"' EXIT

# ---------------------------------------------------------------------------
# Fixture: 8 issues covering every branch --
#   #10 status:spec-review, mine                  -> BLOCKED ON YOU
#   #11 status:in-review, mine, PR #90 CI green    -> BLOCKED ON YOU + next-up candidate
#   #12 status:in-progress, mine, NO agent:active  -> STALLED
#   #13 status:ready, unclaimed, P0                -> READY, next-up candidate if #11 didn't win
#   #14 status:ready, claimed by alice              -> READY, not "yours"
#   #15 blocked label, mine                         -> BLOCKED (reason from last matching comment)
#   #16 needs-attention label, mine                 -> BLOCKED ON YOU (reason from last comment)
#   #17 status:spec-review, alice's (not mine)       -> IN FLIGHT (visible, but not "blocked on
#                                                        you" -- regression: used to vanish
#                                                        entirely, since spec-review wasn't in
#                                                        the IN FLIGHT status set)
#   #20 epic (subIssuesSummary.total=2)              -> EPICS, excluded from every other bucket
#   #30 no status label                              -> BACKLOG
# ---------------------------------------------------------------------------
cat > "$fake_bin_dir/gh" <<'GHEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    cat <<'JSON'
[
  {"number":10,"title":"Spec review item","labels":[{"name":"status:spec-review"},{"name":"P1"}],"url":"https://x/10","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":11,"title":"In review item","labels":[{"name":"status:in-review"},{"name":"P0"},{"name":"agent:active"}],"url":"https://x/11","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":12,"title":"Stalled item","labels":[{"name":"status:in-progress"},{"name":"P2"}],"url":"https://x/12","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":13,"title":"Ready unclaimed","labels":[{"name":"status:ready"},{"name":"P0"}],"url":"https://x/13","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":14,"title":"Ready claimed by alice","labels":[{"name":"status:ready"},{"name":"P1"}],"url":"https://x/14","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":15,"title":"Blocked item","labels":[{"name":"status:in-progress"},{"name":"P1"},{"name":"blocked"},{"name":"agent:active"}],"url":"https://x/15","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":16,"title":"Needs attention item","labels":[{"name":"status:in-progress"},{"name":"P1"},{"name":"needs-attention"},{"name":"agent:active"}],"url":"https://x/16","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":17,"title":"Alice's spec review item","labels":[{"name":"status:spec-review"},{"name":"P1"},{"name":"agent:active"}],"url":"https://x/17","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":20,"title":"An epic","labels":[{"name":"status:ready"},{"name":"P1"}],"url":"https://x/20","assignees":[],"subIssuesSummary":{"completed":1,"percentCompleted":50,"total":2},"subIssues":{"nodes":[{"number":21,"title":"Sub one"},{"number":22,"title":"Sub two"}]}},
  {"number":30,"title":"Backlog item","labels":[],"url":"https://x/30","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}}
]
JSON
    ;;
  "pr list")
    cat <<'JSON'
[
  {"number":90,"headRefName":"issue-11","title":"In review item","reviewDecision":"","url":"https://x/pr/90","statusCheckRollup":[{"conclusion":"SUCCESS","status":"COMPLETED"}],"closingIssuesReferences":[{"number":11}]}
]
JSON
    ;;
  "api user")
    echo "me"
    ;;
  "repo view")
    echo "main"
    ;;
  "issue view")
    case "$3" in
      15) echo '{"comments":[{"body":"some earlier note"},{"body":"⛔ Blocked on #99 — waiting on infra work."}]}' ;;
      16) echo '{"comments":[{"body":"first pass"},{"body":"Stuck: ambiguous requirement, need owner input."}]}' ;;
      *) echo '{"comments":[]}' ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
GHEOF
chmod +x "$fake_bin_dir/gh"

cat > "$fake_bin_dir/git" <<'GITEOF'
#!/usr/bin/env bash
if [[ "$1" == "ls-tree" ]]; then
  printf 'issue-5\nissue-9\narchive\n'
  exit 0
fi
exit 1
GITEOF
chmod +x "$fake_bin_dir/git"

cat > "$fake_bin_dir/claude" <<'CLAUDEEOF'
#!/usr/bin/env bash
if [[ "$1" == "agents" ]]; then
  echo '[{"name":"issue-pm-11","state":"working","id":"sess-abc123"},{"name":"issue-pm-15-blocked-item-fix","state":"working","id":"sess-slug456"},{"name":"issue-pm-999","state":"done","id":"sess-dead"}]'
  exit 0
fi
exit 1
CLAUDEEOF
chmod +x "$fake_bin_dir/claude"

out="$(PATH="$fake_bin_dir:$PATH" python3 "$board")"
status=$?
check "board.py exits 0" "$status"

echo "$out"
echo "---"

echo "$out" | grep -q "BLOCKED ON YOU"
check "renders a BLOCKED ON YOU section" $?

echo "$out" | grep -q "#10 "
check "spec-review issue assigned to me appears (blocked on you)" $?

echo "$out" | grep -q "#11 .*PR #90 ✅ CI"
check "in-review issue shows its correlated PR + green CI (via closingIssuesReferences)" $?

echo "$out" | grep -q "attach: claude agents — select sess-abc123"
check "live session (agent:active + matching claude agents name) offers an attach command" $?

echo "$out" | grep -q "attach: claude agents — select sess-slug456"
check "live session named with a title slug (issue-pm-15-blocked-item-fix) still matches issue #15 via boundary-safe prefix" $?

echo "$out" | grep -q "#12 .*STALLED"
check "in-progress issue with no agent:active is marked STALLED" $?

echo "$out" | grep -qE "^  \(no labels\)  #30"
check "issue with no status label lands in BACKLOG" $?

! echo "$out" | grep -q "#20 .*BLOCKED ON YOU\|#20 .*READY"
check "epic never appears in READY/BLOCKED ON YOU (only in its own EPICS section)" $?

# `check` only sees the LAST command's status, so every condition must be one expression.
echo "$out" | grep -q "EPICS" \
  && echo "$out" | grep -q "^      - 21: Sub one$" \
  && echo "$out" | grep -q "^      - 22: Sub two$"
check "epic lists its sub-issues one per line, as '- <number>: <title>'" $?

! echo "$out" | grep -q "Sub one), #22"
check "epic sub-issues are never comma-joined inline" $?

echo "$out" | sed -n '/🔒 Blocked:/,$p' | grep -q "^  - 15: Blocked item — ⛔ Blocked on #99 — waiting on infra work.$"
check "blocked reason comes from the matching ⛔-prefixed comment, not just 'see issue comments'" $?

echo "$out" | grep -q "NEEDS ATTENTION — Stuck: ambiguous requirement, need owner input."
check "needs-attention note comes from the issue's last comment" $?

echo "$out" | grep -q "specs pending archive: 2 → /spec-flow:archive"
check "archive-pending count excludes the 'archive' entry itself" $?

echo "$out" | grep -q "#17 .*@alice"
check "another user's spec-review issue is still shown (not silently dropped)" $?

! echo "$out" | sed -n '/BLOCKED ON YOU/,/^$/p' | grep -q "#17"
check "another user's spec-review issue is NOT counted as blocked on you" $?

echo "$out" | sed -n '/IN FLIGHT/,/^$/p' | grep -q "#17"
check "another user's spec-review issue shows under IN FLIGHT for visibility" $?

echo "$out" | sed -n '/Stalled (yours, no agent:active):/,$p' | grep -q "^  - 10: Spec review item →"
check "the stalled SUMMARY line includes a stalled spec-review item too, consistent with its inline 🔴 STALLED marker" $?

! echo "$out" | grep -q '{spawn}'
check "the stalled summary's spawn command is a real path, not a leftover {spawn} placeholder" $?

echo "$out" | grep -q "spawn-issue-pm.sh 10"
check "the stalled summary's spawn command resolves to the real script next to board.py" $?

echo "$out" | grep -q "^➡️  Next up — finish:$" \
  && echo "$out" | sed -n '/Next up — finish:/,$p' | grep -q "^  - 11: .* → PR #90 is green, merge it$"
check "'next up' picks the mine+in-review+green-CI item over a ready/unclaimed one" $?

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
