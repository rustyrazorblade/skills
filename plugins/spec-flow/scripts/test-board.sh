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
#   #16 needs-attention label, mine                 -> BLOCKED ON YOU (reason from 🆘-prefixed comment)
#   #17 status:spec-review, alice's (not mine)       -> IN FLIGHT (visible, but not "blocked on
#                                                        you" -- regression: used to vanish
#                                                        entirely, since spec-review wasn't in
#                                                        the IN FLIGHT status set)
#   #18 status:ready, mine, agent:active             -> BLOCKED ON YOU (activate's design stop --
#                                                        holds status:ready the whole wait)
#   #19 status:in-review, mine, NO linked PR (ci None) -> BLOCKED ON YOU, not "waiting on CI"
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
  {"number":18,"title":"Parked on my design choice","labels":[{"name":"status:ready"},{"name":"P2"},{"name":"agent:active"}],"url":"https://x/18","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":19,"title":"In review, PR never linked","labels":[{"name":"status:in-review"},{"name":"P2"}],"url":"https://x/19","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
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
      16) echo '{"comments":[{"body":"first pass"},{"body":"🆘 Needs attention: ambiguous requirement, need owner input."},{"body":"📚 Docs polished."}]}' ;;
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

echo "$out" | grep -q "NEEDS ATTENTION — 🆘 Needs attention: ambiguous requirement, need owner input."
check "needs-attention note comes from the matching 🆘-prefixed comment, not a later unrelated one" $?

# #16 carries agent:active but no live session matches it -- a crashed issue-pm, or one running on
# another machine. The label alone must not read as alive, but absence of a LOCAL session is not
# proof of death either, so this is its own state rather than 🟢 or 🔴.
echo "$out" | grep -q "#16 .*🟡 claimed — agent:active set, no session on this machine"
check "an agent:active label with no local session renders claimed, neither active nor stalled" $?

# --- issue 58: work blocked on the owner must be visible and must outrank starting new work ---

# #18 is parked at activate's design-choice stop. It holds status:ready throughout that wait, so a
# status-only rule renders it as an untouched backlog item and the owner never learns a session is
# waiting on their answer.
# Section ranges must END at the next section header. The board's headers are emoji lines, not
# "##", so a /^##/ terminator ran to end-of-output and matched the issue in ANY later section --
# which made these assertions pass even with the fix reverted.
# awk, not sed: BSD sed (macOS default) has no `\|` alternation, so a `/^\(a\|b\)/` terminator
# never matches, the range runs to end of output, and the assertion passes vacuously.
# Section rows are indented two spaces; headers are not. Print rows until the next unindented line.
section() {
  echo "$out" | awk -v hdr="$1" '
    !inside && index($0, hdr) { inside = 1; next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^[^[:space:]]/  { exit }
    inside                      { print }
  '
}
blocked_section() { section "⛳ BLOCKED ON YOU"; }
ready_section()   { section "📋 READY"; }

blocked_section | grep -q "#18"
check "activate's design-choice stop shows under BLOCKED ON YOU, not as a plain ready item" $?

# Positive canary FIRST: a negative assertion against a section that no longer exists (renamed
# header, changed emoji) passes vacuously. #13 is the fixture's unclaimed ready item and must
# always be there, so this pins that ready_section actually resolves before the negative below.
ready_section | grep -q "#13"
check "ready_section resolves (canary — guards the negative assertion below from going vacuous)" $?

! ready_section | grep -q "#18"
check "an issue shown under BLOCKED ON YOU is not rendered again under READY" $?

# #19 is in-review with no PR resolvable through closingIssuesReferences, so ci is None. That is a
# missing correlation, not a running pipeline -- the owner is the blocker, not CI.
blocked_section | grep -q "#19"
check "status:in-review with no linked PR is blocked on you, not 'waiting on CI'" $?

# "Next up" must draw from the board's own top bucket. Previously the ladder went straight from
# mine+in-review+green to unclaimed-ready, so it told the owner to go groom while a spec sat
# waiting for their approval.
# Whatever it picks must come from the top bucket while that bucket is non-empty -- never a
# "groom" or "activate" recommendation, which is what the old ladder produced by skipping it.
echo "$out" | grep -qE "Next up — (finish|unblock):"
check "'next up' draws from BLOCKED ON YOU while that bucket is non-empty, never groom/activate" $?

# The fixture always has #11 (mine + in-review + green), so the "finish" rung always wins and the
# new "unblock" rung never executes through the fixture. Exercise the ladder directly instead,
# with no green in-review row present, so a regression that drops the rung is actually caught.
python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, sub_issues=[], sub_total=0, sub_completed=0, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# A spec awaiting approval, plus an unclaimed ready item. Nothing green and in-review.
rows = [row(number=10, status="spec-review"), row(number=30, status="ready", assignee=None, mine=False)]
rendered = board.render_board(rows, "me", 0)
out = rendered if isinstance(rendered, str) else "\n".join(rendered)
assert "Next up — unblock:" in out, "expected the unblock rung to win; got:\n" + out
assert "#10" in out or "10:" in out, "expected issue 10 to be recommended; got:\n" + out

# CI state mapping (issue 58 defect 4): queued/gated states are pending, never failing.
for st in ("PENDING", "WAITING", "REQUESTED", "EXPECTED"):
    got = board.ci_status([{"state": st}])
    assert got == "running", f"{st} -> {got}, expected running"
assert board.ci_status([{"status": "COMPLETED", "conclusion": None}]) == "running", "unknown conclusion must be pending"
assert board.ci_status([{"state": "SUCCESS"}]) == "green"
assert board.ci_status([{"conclusion": "FAILURE"}]) == "failing"
PYEOF
check "'next up' unblock rung fires with no green in-review item, and CI states map correctly" $?

# Separate block so a failure below reports under its own name, not the ladder/CI check's.
python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, sub_issues=[], sub_total=0, sub_completed=0, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# An unknown status: label must land in a visible bucket, not vanish from the board entirely.
out2 = board.render_board([row(number=99, status="in-progres", mine=False, assignee="alice")], "me", 0)
out2 = out2 if isinstance(out2, str) else "\n".join(out2)
assert "99" in out2, "an unrecognized status: label vanished from the board:\n" + out2

# gh can emit an explicit JSON null; .get(default) returns the null and the old code raised on it,
# taking down the whole render.
assert board.label_names({"labels": None}) == set()
assert board.status_of({"labels": None}) is None

# Set iteration is not ordered ACROSS PROCESSES -- string hashing is randomized per process, so
# it is stable within one run and varies between them. Looping in-process proves nothing; the
# answer has to be compared across several interpreters with different hash seeds.
import os, subprocess
# Probe EVERY adjacent lifecycle pair, not one: the first ordering shipped here got half the pairs
# backwards and the single-pair probe happened to be one it got right.
probe = (
    "import importlib.util,pathlib,sys,itertools;"
    "spec=importlib.util.spec_from_file_location('b',pathlib.Path(sys.argv[1])/'board.py');"
    "m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);"
    "L=['ready','spec-review','in-progress','in-review','addressing'];"
    "print(' '.join(m.status_of({'labels':[{'name':'status:'+a},{'name':'status:'+c}]})"
    " for a,c in itertools.combinations(L,2)),"
    "m.priority_of({'labels':[{'name':'P3'},{'name':'P0'}]}))"
)
# Each pair must resolve to the MORE advanced state -- a stale leftover label must never drag an
# issue backwards on the board.
expected = " ".join(
    c for a, c in __import__("itertools").combinations(
        ["ready", "spec-review", "in-progress", "in-review", "addressing"], 2)
) + " P0"
seen = set()
for seed in ("0", "1", "7", "42", "1234", "99999"):
    env = dict(os.environ, PYTHONHASHSEED=seed)
    seen.add(subprocess.run([sys.executable, "-c", probe, sys.argv[1]],
                            capture_output=True, text=True, env=env, check=True).stdout.strip())
assert seen == {expected}, f"status_of/priority_of wrong or hash-seed dependent: {seen} != {{{expected!r}}}"
PYEOF
check "unknown status label is rendered, null labels don't crash, label resolution is deterministic and lifecycle-ordered" $?

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
