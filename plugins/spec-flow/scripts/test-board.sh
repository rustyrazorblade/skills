#!/usr/bin/env bash
# Structural + behavioral test for board.py. Fakes `gh`/`git`/`claude` on PATH so this runs
# offline, deterministically, and exercises the branches this repo's own real board data
# doesn't (epics, PR/CI correlation, blocked/needs-attention reasons, stalled detection,
# "next up") rather than relying on live GitHub state. Exits non-zero if any assertion
# fails. macOS bash 3.2 compatible (no associative arrays, no mapfile).
#
# Four fixtures, each with a job:
#   1  the broad behavioral fixture -- every bucket, PR/CI correlation, liveness, notes
#   2  the concurrent comment prefetch and its per-row failure isolation
#   3  nothing to report -- the conditional-rendering fixture (no section, no zero count)
#   4  "next up" priority ordering and its refusal to name a claimed issue
# Plus in-process python blocks for the cases a PATH fixture can't reach cheaply: the three
# liveness states of one green in-review PR, backlog-size line invariance, and keycap alignment.
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
fake_bin_dir2="$(mktemp -d)"
fake_bin_dir3="$(mktemp -d)"
fake_bin_dir4="$(mktemp -d)"
trap 'rm -rf "$fake_bin_dir" "$fake_bin_dir2" "$fake_bin_dir3" "$fake_bin_dir4"' EXIT

# ---------------------------------------------------------------------------
# Fixture 1: 12 issues covering every branch --
#   #10 status:spec-review, mine                  -> BLOCKED ON YOU
#   #11 status:in-review, mine, PR #90 CI green    -> BLOCKED ON YOU (never a merge suggestion)
#   #12 status:in-progress, mine, NO agent:active  -> STALLED
#   #13 status:ready, unclaimed, P0                -> READY, and the "next up" pick
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
#   #20 epic (subIssuesSummary.total=2)              -> counted as "1 epic", rendered as no row
#   #30 no status label                              -> counted as "1 ungroomed", no row
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
  echo '[{"name":"issue-manager-11","state":"working","id":"sess-abc123"},{"name":"issue-pm-15-blocked-item-fix","state":"working","id":"sess-slug456"},{"name":"issue-manager-999","state":"done","id":"sess-dead"}]'
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
check "a session under the PRE-RENAME issue-pm- prefix still matches its issue (rename migration)" $?

echo "$out" | grep -q "#12 .*STALLED"
check "in-progress issue with no agent:active is marked STALLED" $?

! echo "$out" | grep -q "#20 .*BLOCKED ON YOU\|#20 .*READY"
check "epic never appears in READY/BLOCKED ON YOU" $?

echo "$out" | sed -n '/🔒 Blocked:/,$p' | grep -q "^  - 15: Blocked item — ⛔ Blocked on #99 — waiting on infra work.$"
check "blocked reason comes from the matching ⛔-prefixed comment, not just 'see issue comments'" $?

echo "$out" | grep -q "NEEDS ATTENTION — 🆘 Needs attention: ambiguous requirement, need owner input."
check "needs-attention note comes from the matching 🆘-prefixed comment, not a later unrelated one" $?

# #16 carries agent:active but no live session matches it -- a crashed issue-manager, or one running on
# another machine. The label alone must not read as alive, but absence of a LOCAL session is not
# proof of death either, so this is its own state rather than 🟢 or 🔴.
echo "$out" | grep -q "#16 .*🟡 claimed — agent:active set, no session on this machine"
check "an agent:active label with no local session renders claimed, neither active nor stalled" $?

# --- Unbounded categories report as counts, never as rows (spec: counts, not rows) ---

# The exact summary line, not a substring: this asserts BOTH that the two unbounded categories are
# counted and that every other count is still reported, in one place that a new fixture row breaks
# loudly rather than silently.
echo "$out" | grep -qxF "(1 ungroomed · 1 epic · 5 agent:active · 1 blocked · 1 needs-attention · 2 local sessions matched · 1 open PR)"
check "the summary line reports every non-zero count, including ungroomed and epics" $?

! echo "$out" | grep -q "#30"
check "the ungroomed backlog issue is counted, never rendered as its own row" $?

! echo "$out" | grep -q "BACKLOG"
check "no BACKLOG section is rendered at all" $?

! echo "$out" | grep -q "#20"
check "the epic is counted, never rendered as its own row" $?

! echo "$out" | grep -q "EPICS\|Sub one\|Sub two"
check "no EPICS section and no epic sub-issue rows are rendered" $?

# --- issue 58: work blocked on the owner must be visible ---

# #18 is parked at activate's design-choice stop. It holds status:ready throughout that wait, so a
# status-only rule renders it as an untouched backlog item and the owner never learns a session is
# waiting on their answer.
# Section ranges must END at the next section header. The board's headers are emoji lines, not
# "##", so a /^##/ terminator ran to end-of-output and matched the issue in ANY later section --
# which made these assertions pass even with the fix reverted.
# awk, not sed: BSD sed (macOS default) has no `\|` alternation, so a `/^\(a\|b\)/` terminator
# never matches, the range runs to end of output, and the assertion passes vacuously.
# Section rows are indented two spaces; headers are not. Print rows until the next unindented line.
# section_in takes the render to search, so a fixture other than fixture 1 can extract a block
# too. Counting rows over a whole board is a trap: a ready row rendered under BLOCKED ON YOU
# matches the same regex, and fixture 1's own render contains exactly such a row.
section_in() {
  echo "$1" | awk -v hdr="$2" '
    !inside && index($0, hdr) { inside = 1; next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^[^[:space:]]/  { exit }
    inside                      { print }
  '
}
section() { section_in "$out" "$1"; }
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

# --- "Next up" names only unclaimed ready work ---

# #11 is mine, in-review, with a green PR and a live session. That used to be the top "next up"
# rung ("PR #90 is green, merge it"). It names work #11's own issue-manager already drives, so the
# board reports the row and recommends the one issue nobody owns instead.
echo "$out" | grep -qx "➡️  Next up — activate:"
check "'next up' recommends activating unclaimed ready work" $?

echo "$out" | sed -n '/Next up — activate:/,$p' | grep -q "^  - 13: Ready unclaimed → /spec-flow:activate 13$"
check "'next up' names the highest-priority unclaimed ready issue (#13, P0)" $?

! echo "$out" | grep -q "merge it"
check "'next up' never recommends merging a green in-review PR" $?

! echo "$out" | grep -qE "Next up — (finish|unblock|groom):"
check "the finish/unblock/groom rungs are gone entirely" $?

! echo "$out" | sed -n '/Next up — activate:/,$p' | grep -q "^  - 16:"
check "a needs-attention issue is reported under BLOCKED ON YOU but never named by 'next up'" $?

blocked_section | grep -q "#16"
check "the same needs-attention issue does render its own BLOCKED ON YOU row" $?

# --- the rest of fixture 1's coverage ---

echo "$out" | grep -qx "🗄️  2 specs pending archive → /spec-flow:archive"
check "the archive suggestion is its own line, names the count, and excludes the 'archive' entry" $?

! echo "$out" | grep -q "specs pending archive:"
check "the archive suggestion is no longer wedged into the summary line" $?

echo "$out" | grep -q "#17 .*@alice"
check "another user's spec-review issue is still shown (not silently dropped)" $?

! blocked_section | grep -q "#17"
check "another user's spec-review issue is NOT counted as blocked on you" $?

section "🔧 IN FLIGHT" | grep -q "#17"
check "another user's spec-review issue shows under IN FLIGHT for visibility" $?

echo "$out" | sed -n '/Stalled (yours, no agent:active):/,$p' | grep -q "^  - 10: Spec review item →"
check "the stalled SUMMARY line includes a stalled spec-review item too, consistent with its inline 🔴 STALLED marker" $?

! echo "$out" | grep -q '{spawn}'
check "the stalled summary's spawn command is a real path, not a leftover {spawn} placeholder" $?

echo "$out" | grep -q "spawn-issue-manager.sh 10"
check "the stalled summary's spawn command resolves to the real script next to board.py" $?

# --- Keycap priority (spec: P0-P3 render as 0️⃣-3️⃣, unprioritized rows stay aligned) ---

echo "$out" | grep -q "#13    0️⃣ Ready unclaimed"
check "a P0 row's priority column renders the keycap, not the text 'P0'" $?

! echo "$out" | grep -qE "#1[0-9] +P[0-3] "
check "no row renders a literal P0/P1/P2/P3 in its priority column" $?

# ---------------------------------------------------------------------------
# In-process render tests: the cases a PATH fixture can't reach cheaply.
# ---------------------------------------------------------------------------
python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

def next_up_lines(rendered):
    lines = rendered.splitlines()
    hits = [i for i, l in enumerate(lines) if l.startswith("➡️  Next up")]
    if not hits:
        return []
    assert len(hits) == 1, f"more than one 'next up' header:\n{rendered}"
    return lines[hits[0]:hits[0] + 2]

# A green in-review PR is owned by that issue's own issue-manager whatever its liveness, so none of
# the three states may produce a merge recommendation, and none may displace the unclaimed ready
# item. The liveness marker is asserted too, so a state that stops being reachable fails loudly
# instead of passing vacuously.
for agent_active, attach_id, marker in ((True, "sess-1", "🟢 active"),
                                        (True, None, "🟡 claimed"),
                                        (False, None, "🔴 STALLED")):
    rows = [row(number=11, status="in-review", ci="green", pr_number=90,
                agent_active=agent_active, attach_id=attach_id),
            row(number=13, title="Ready unclaimed", status="ready", priority="P0",
                assignee=None, mine=False)]
    out = board.render_board(rows, "me", 0)
    assert marker in out, f"expected the {marker} state to be reachable; got:\n{out}"
    assert "merge" not in out, f"{marker}: recommended a merge; got:\n{out}"
    assert next_up_lines(out) == ["➡️  Next up — activate:",
                                  "  - 13: Ready unclaimed → /spec-flow:activate 13"], \
        f"{marker}: wrong 'next up'; got:\n{out}"
PYEOF
check "'next up' never recommends merging a green in-review PR, in any of the three liveness states" $?

python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# The property the caps could only approximate: the board's rendered length does not vary with the
# size of the backlog. Same state twice, differing only in how many ungroomed issues exist.
def render(n_backlog):
    rows = [row(number=10, status="spec-review"),
            row(number=13, status="ready", priority="P0", assignee=None, mine=False)]
    rows += [row(number=1000 + i, status=None, mine=False, assignee=None) for i in range(n_backlog)]
    return board.render_board(rows, "me", 3)

small, large = render(1), render(500)
assert len(small.splitlines()) == len(large.splitlines()), \
    f"backlog size changed the board's length: {len(small.splitlines())} vs {len(large.splitlines())}"
# ...because the size is reported, not because it is ignored.
assert "1 ungroomed" in small and "500 ungroomed" in large, f"backlog count not reported:\n{large}"

# A needs-attention issue reports its row, with its attach instruction, and is still not the thing
# "next up" names.
rows = [row(number=16, title="Needs attention item", status="in-progress", needs_attention=True,
            attention_note="🆘 Needs attention: owner input needed", agent_active=True,
            attach_id="sess-xyz"),
        row(number=13, title="Ready unclaimed", status="ready", priority="P0",
            assignee=None, mine=False)]
out = board.render_board(rows, "me", 0)
lines = out.splitlines()
start = lines.index("⛳ BLOCKED ON YOU")
blocked = lines[start + 1:lines.index("", start)]
assert any("#16" in l and "attach: claude agents — select sess-xyz" in l for l in blocked), \
    f"needs-attention row missing from BLOCKED ON YOU, or missing its attach instruction:\n{out}"
assert "  - 13: Ready unclaimed → /spec-flow:activate 13" in lines, f"wrong 'next up':\n{out}"
assert not any(l.startswith("  - 16:") for l in lines), f"'next up' named the owned issue:\n{out}"
PYEOF
check "backlog size does not change the board's length, and BLOCKED ON YOU reports without recommending" $?

python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

assert [board.keycap(p) for p in ("P0", "P1", "P2", "P3")] == ["0️⃣", "1️⃣", "2️⃣", "3️⃣"]
assert board.keycap(None) == board.keycap("P9") == "  ", "an unknown priority must render the blank"

# A keycap is three codepoints -- digit, U+FE0F, U+20E3 -- but a terminal draws it in two cells,
# so len() proves nothing about alignment. Substitute each keycap for the two spaces it occupies
# and measure what is left. That is exactly the equivalence PRIORITY_BLANK relies on.
def cells(s):
    for kc in board.PRIORITY_KEYCAP.values():
        s = s.replace(kc, "  ")
    return len(s)

rows = [row(number=13, title="AAA", status="ready", priority="P1", assignee=None, mine=False),
        row(number=14, title="BBB", status="ready", priority=None, assignee=None, mine=False)]
out = board.render_board(rows, "me", 0)
line_a = next(l for l in out.splitlines() if "AAA" in l)
line_b = next(l for l in out.splitlines() if "BBB" in l)
assert "1️⃣" in line_a and "P1" not in line_a, f"P1 did not render as a keycap:\n{line_a}"
assert cells(line_a[:line_a.index("AAA")]) == cells(line_b[:line_b.index("BBB")]), \
    f"prioritized and unprioritized rows misalign:\n{line_a}\n{line_b}"
PYEOF
check "priority renders as a keycap, and a prioritized row stays aligned with an unprioritized one" $?

# Separate block so a failure below reports under its own name, not the render checks'.
python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# An unknown status: label must land in a visible bucket, not vanish from the board entirely.
out2 = board.render_board([row(number=99, status="in-progres", mine=False, assignee="alice")], "me", 0)
assert "99" in out2, "an unrecognized status: label vanished from the board:\n" + out2

# CI state mapping (issue 58 defect 4): queued/gated states are pending, never failing.
for st in ("PENDING", "WAITING", "REQUESTED", "EXPECTED"):
    got = board.ci_status([{"state": st}])
    assert got == "running", f"{st} -> {got}, expected running"
assert board.ci_status([{"status": "COMPLETED", "conclusion": None}]) == "running", "unknown conclusion must be pending"
assert board.ci_status([{"state": "SUCCESS"}]) == "green"
assert board.ci_status([{"conclusion": "FAILURE"}]) == "failing"

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
check "unknown status label is rendered, CI states map correctly, null labels don't crash, label resolution is deterministic and lifecycle-ordered" $?

# ---------------------------------------------------------------------------
# issue 71: the READY cap's in-process properties -- the cases a PATH fixture
# cannot reach cheaply. One block per property, each with its own check(), so a
# failure reports under its own name rather than the whole cap's.
# ---------------------------------------------------------------------------
python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# Rows inside ONE block, never over the whole board: a ready row rendered under BLOCKED ON YOU
# carries the same status column, so a whole-board scan counts it under two headers.
def section_rows(rendered, header):
    lines = rendered.splitlines()
    if header not in lines:
        return []
    out = []
    for line in lines[lines.index(header) + 1:]:
        if not line or not line.startswith(" "):
            break
        out.append(line)
    return out

READY = "📋 READY"

def ready(number, priority="P2", **kw):
    return row(number=number, title=f"Ready {number}", status="ready", priority=priority, **kw)

# Next up survives the cut. Five claimed P0s fill the default cap exactly, so the one unclaimed
# issue is the one withheld. A cap applied before compute_next_up leaves the board with nothing to
# recommend, which is the whole reason render_board slices in render_ready and nowhere else.
rows = [ready(800 + i, "P0") for i in range(5)] + [ready(900, "P3", assignee=None, mine=False)]
out = board.render_board(rows, "me", 0)
assert "  - 900: Ready 900 \u2192 /spec-flow:activate 900" in out.splitlines(), \
    f"'next up' lost the withheld unclaimed issue:\n{out}"
rendered = section_rows(out, READY)
assert len(rendered) == 6, f"expected five rows plus the withheld line, got {len(rendered)}:\n{out}"
assert not any("#900" in line for line in rendered), \
    f"#900 was withheld from the block, yet rendered in it:\n{out}"
PYEOF
check "'next up' still names a ready issue the cap withheld" $?

python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# Rows inside ONE block, never over the whole board: a ready row rendered under BLOCKED ON YOU
# carries the same status column, so a whole-board scan counts it under two headers.
def section_rows(rendered, header):
    lines = rendered.splitlines()
    if header not in lines:
        return []
    out = []
    for line in lines[lines.index(header) + 1:]:
        if not line or not line.startswith(" "):
            break
        out.append(line)
    return out

READY = "📋 READY"

def ready(number, priority="P2", **kw):
    return row(number=number, title=f"Ready {number}", status="ready", priority=priority, **kw)

# The property the cap exists for: the board's rendered length does not vary with the size of the
# ready queue. Same board twice, differing only in how many ready issues exist.
def render_ready_queue(n):
    return board.render_board([ready(1000 + i) for i in range(n)], "me", 0)

six, many = render_ready_queue(6), render_ready_queue(506)
assert len(six.splitlines()) == len(many.splitlines()), \
    f"ready-queue size changed the board's length: {len(six.splitlines())} vs {len(many.splitlines())}"
# ...because each size is reported, not because it is ignored.
assert "1 more ready" in six, f"withheld count not reported at six ready:\n{six}"
assert "501 more ready" in many, f"withheld count not reported at 506 ready:\n{many}"
assert "1 more readys" not in six, f"a single withheld row read as plural:\n{six}"
PYEOF
check "the board's length holds at 6 and at 506 ready issues, each reporting its own withheld count" $?

python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# Rows inside ONE block, never over the whole board: a ready row rendered under BLOCKED ON YOU
# carries the same status column, so a whole-board scan counts it under two headers.
def section_rows(rendered, header):
    lines = rendered.splitlines()
    if header not in lines:
        return []
    out = []
    for line in lines[lines.index(header) + 1:]:
        if not line or not line.startswith(" "):
            break
        out.append(line)
    return out

READY = "📋 READY"

def ready(number, priority="P2", **kw):
    return row(number=number, title=f"Ready {number}", status="ready", priority=priority, **kw)

# The cap takes the highest priority, not the first N given. The two survivors are placed second
# and fourth in the list, so a slice of the unsorted input would render the wrong pair.
rows = [ready(910, "P3"), ready(911, "P0"), ready(912, "P3"), ready(913, "P1"), ready(914, "P3")]
out = board.render_board(rows, "me", 0, 2)
rendered = section_rows(out, READY)
assert [l for l in rendered if "#911" in l] and [l for l in rendered if "#913" in l], \
    f"the P0 and the P1 did not both render at ready_limit=2:\n{out}"
assert not any(f"#{n}" in l for l in rendered for n in (910, 912, 914)), \
    f"a P3 displaced a higher-priority row at ready_limit=2:\n{out}"
assert "3 more ready" in out, f"wrong withheld count at ready_limit=2 over five rows:\n{out}"
PYEOF
check "the cap renders the highest-priority rows, not the first N given" $?

python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# Rows inside ONE block, never over the whole board: a ready row rendered under BLOCKED ON YOU
# carries the same status column, so a whole-board scan counts it under two headers.
def section_rows(rendered, header):
    lines = rendered.splitlines()
    if header not in lines:
        return []
    out = []
    for line in lines[lines.index(header) + 1:]:
        if not line or not line.startswith(" "):
            break
        out.append(line)
    return out

READY = "📋 READY"

def ready(number, priority="P2", **kw):
    return row(number=number, title=f"Ready {number}", status="ready", priority=priority, **kw)

# Exactly at the cap: every row renders and nothing is withheld.
for n in (1, 3, 7):
    out = board.render_board([ready(920 + i) for i in range(n)], "me", 0, n)
    assert len(section_rows(out, READY)) == n, \
        f"{n} ready rows at ready_limit={n} did not render all {n}:\n{out}"
    assert "more ready" not in out, f"a withheld line rendered at exactly the cap (n={n}):\n{out}"

# Below the cap. max(0, ...) is what makes this hold: count_bit tests `if not n`, which is false
# for -1, so without the guard this renders "-1 more ready" under four rows.
out = board.render_board([ready(930 + i) for i in range(4)], "me", 0)
assert len(section_rows(out, READY)) == 4, \
    f"four ready rows below the default cap did not all render:\n{out}"
assert "more ready" not in out, f"a withheld line rendered below the cap:\n{out}"
PYEOF
check "at and below the cap every ready row renders, with no withheld line and no negative count" $?

python3 - "$script_dir" <<'PYEOF'
import sys, importlib.util, pathlib
spec = importlib.util.spec_from_file_location("board", pathlib.Path(sys.argv[1]) / "board.py")
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)

def row(**kw):
    base = dict(number=1, title="t", url="u", status=None, priority="P1", assignee="me", mine=True,
                is_epic=False, agent_active=False,
                blocked=False, needs_attention=False, ci=None, pr_number=None, attach_id=None)
    base.update(kw); return base

# Rows inside ONE block, never over the whole board: a ready row rendered under BLOCKED ON YOU
# carries the same status column, so a whole-board scan counts it under two headers.
def section_rows(rendered, header):
    lines = rendered.splitlines()
    if header not in lines:
        return []
    out = []
    for line in lines[lines.index(header) + 1:]:
        if not line or not line.startswith(" "):
            break
        out.append(line)
    return out

READY = "📋 READY"

# The cap applies to READY alone. Nine of each of the two other row buckets, at a limit far below
# and far above nine, so a cap wired into the shared render_section fails here either way.
BLOCKED, IN_FLIGHT = "\u26f3 BLOCKED ON YOU", "\U0001f527 IN FLIGHT (agents / CI)"
rows = ([row(number=940 + i, status="spec-review") for i in range(9)]
        + [row(number=950 + i, status="in-progress", assignee="alice", mine=False,
               agent_active=True, attach_id="s") for i in range(9)])
for limit in (1, 500):
    out = board.render_board(rows, "me", 0, limit)
    assert len(section_rows(out, BLOCKED)) == 9, \
        f"BLOCKED ON YOU was capped at ready_limit={limit}:\n{out}"
    assert len(section_rows(out, IN_FLIGHT)) == 9, \
        f"IN FLIGHT was capped at ready_limit={limit}:\n{out}"

# No ready issue renders nothing at all -- no header, no rows, no withheld line -- at any limit.
for limit in (1, 5, 500):
    out = board.render_board([row(number=960, status="in-progress", agent_active=True)], "me", 0, limit)
    assert READY not in out, f"a READY header rendered with no ready issue at limit {limit}:\n{out}"
    assert "more ready" not in out, \
        f"a withheld line rendered with no ready issue at limit {limit}:\n{out}"
PYEOF
check "no other bucket is capped, and no ready issue renders no READY block at all" $?

# ---------------------------------------------------------------------------
# Fixture 2: the concurrent-prefetch fixture. Eleven ungroomed issues and an
# epic with six sub-issues, both of which now report as counts -- kept at those
# sizes so a regression that reintroduces per-issue rows is unmistakable. Five
# blocked/needs-attention issues exercise the prefetch: a normal success (#401),
# a `gh issue view` process failure (#402), a malformed-JSON response (#405), a
# dual-labeled issue needing two independent calls (#404), and a plain
# needs-attention success (#403).
# ---------------------------------------------------------------------------
cat > "$fake_bin_dir2/gh" <<'GHEOF'
#!/usr/bin/env bash
log_dir="$(cd "$(dirname "$0")" && pwd)"
case "$1 $2" in
  "issue list")
    cat <<'JSON'
[
  {"number":201,"title":"Backlog 201","labels":[],"url":"https://x/201","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":202,"title":"Backlog 202","labels":[],"url":"https://x/202","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":203,"title":"Backlog 203","labels":[],"url":"https://x/203","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":204,"title":"Backlog 204","labels":[],"url":"https://x/204","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":205,"title":"Backlog 205 top priority","labels":[{"name":"P0"}],"url":"https://x/205","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":206,"title":"Backlog 206","labels":[],"url":"https://x/206","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":207,"title":"Backlog 207","labels":[],"url":"https://x/207","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":208,"title":"Backlog 208","labels":[],"url":"https://x/208","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":209,"title":"Backlog 209","labels":[],"url":"https://x/209","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":210,"title":"Backlog 210","labels":[],"url":"https://x/210","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":211,"title":"Backlog 211","labels":[],"url":"https://x/211","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":300,"title":"Big epic","labels":[{"name":"status:ready"},{"name":"P1"}],"url":"https://x/300","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":6},"subIssues":{"nodes":[{"number":301,"title":"Sub 301"},{"number":302,"title":"Sub 302"},{"number":303,"title":"Sub 303"},{"number":304,"title":"Sub 304"},{"number":305,"title":"Sub 305"},{"number":306,"title":"Sub 306"}]}},
  {"number":401,"title":"Blocked ok","labels":[{"name":"status:in-progress"},{"name":"blocked"}],"url":"https://x/401","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":402,"title":"Blocked process failure","labels":[{"name":"status:in-progress"},{"name":"blocked"}],"url":"https://x/402","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":403,"title":"Attention ok","labels":[{"name":"status:in-progress"},{"name":"needs-attention"}],"url":"https://x/403","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":404,"title":"Dual label","labels":[{"name":"status:in-progress"},{"name":"blocked"},{"name":"needs-attention"}],"url":"https://x/404","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":405,"title":"Blocked malformed json","labels":[{"name":"status:in-progress"},{"name":"blocked"}],"url":"https://x/405","assignees":[{"login":"me"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}}
]
JSON
    ;;
  "pr list")
    echo "[]"
    ;;
  "api user")
    echo "me"
    ;;
  "repo view")
    echo "main"
    ;;
  "issue view")
    echo "$3" >> "$log_dir/issue_view_calls.log"
    case "$3" in
      401) echo '{"comments":[{"body":"note"},{"body":"⛔ Blocked on #77 — waiting on review."}]}' ;;
      402) exit 1 ;;
      403) echo '{"comments":[{"body":"first"},{"body":"🆘 Needs attention: needs input on design choice."}]}' ;;
      404) echo '{"comments":[{"body":"first"},{"body":"⛔ Blocked on #88 — waiting on data."}]}' ;;
      405) echo 'not valid json{' ;;
      *) echo '{"comments":[]}' ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
GHEOF
chmod +x "$fake_bin_dir2/gh"

cat > "$fake_bin_dir2/git" <<'GITEOF'
#!/usr/bin/env bash
if [[ "$1" == "ls-tree" ]]; then
  printf 'archive\n'
  exit 0
fi
exit 1
GITEOF
chmod +x "$fake_bin_dir2/git"

cat > "$fake_bin_dir2/claude" <<'CLAUDEEOF'
#!/usr/bin/env bash
if [[ "$1" == "agents" ]]; then
  echo '[]'
  exit 0
fi
exit 1
CLAUDEEOF
chmod +x "$fake_bin_dir2/claude"

err2_log="$fake_bin_dir2/stderr.log"
out2="$(PATH="$fake_bin_dir2:$PATH" python3 "$board" 2>"$err2_log")"
status2=$?
check "fixture 2: board.py exits 0" "$status2"

echo "$out2" | grep -qxF "(11 ungroomed · 1 epic · 4 blocked · 2 needs-attention)"
check "the summary counts eleven ungroomed and one epic, and omits every zero count" $?

! echo "$out2" | grep -qE "#(20[1-9]|21[01]) "
check "none of the eleven ungroomed issues renders a row" $?

! echo "$out2" | grep -q "Sub 30"
check "none of the epic's six sub-issues renders a row" $?

! echo "$out2" | grep -q "Next up"
check "'next up' renders nothing when no unclaimed ready issue exists, even with a full backlog" $?

! echo "$out2" | grep -q "pending archive"
check "no archive line renders when nothing is pending archive" $?

echo "$out2" | grep -q "401.*BLOCKED on ⛔ Blocked on #77 — waiting on review."
check "prefetch: a successful blocked-note fetch renders normally, attached to its own row" $?

echo "$out2" | grep -q "402.*see issue comments"
check "prefetch: a failed gh issue view (process error) falls back to 'see issue comments'" $?

echo "$out2" | grep -q "405.*see issue comments"
check "prefetch: a malformed-JSON gh issue view response falls back to 'see issue comments'" $?

grep -q "^board: warning:.*402" "$err2_log"
check "prefetch: a stderr warning is printed for the process-error fetch (issue #402)" $?

grep -q "^board: warning:.*405" "$err2_log"
check "prefetch: a stderr warning is printed for the malformed-JSON fetch (issue #405)" $?

! grep -q "^board: warning:.*401" "$err2_log"
check "prefetch: no stderr warning is printed for the successful fetch (issue #401)" $?

echo "$out2" | grep -q "403.*NEEDS ATTENTION — 🆘 Needs attention: needs input on design choice."
check "prefetch: a successful needs-attention fetch renders normally, attached to its own row" $?

echo "$out2" | grep -q "404.*BLOCKED on ⛔ Blocked on #88 — waiting on data."
check "prefetch: a dual-labeled (blocked + needs-attention) issue's blocked note renders" $?

echo "$out2" | grep -q "404.*NEEDS ATTENTION"
check "prefetch: the same dual-labeled issue's needs-attention note also renders" $?

calls_402=$(grep -c '^402$' "$fake_bin_dir2/issue_view_calls.log")
if [[ "$calls_402" -eq 1 ]]; then status_calls_402=0; else status_calls_402=1; fi
check "prefetch: issue #402 was fetched exactly once, not retried after its failure" $status_calls_402

calls_404=$(grep -c '^404$' "$fake_bin_dir2/issue_view_calls.log")
if [[ "$calls_404" -eq 2 ]]; then status_calls_404=0; else status_calls_404=1; fi
check "prefetch: the dual-labeled issue got two independent gh calls (blocked + needs-attention)" $status_calls_404

total_calls=$(wc -l < "$fake_bin_dir2/issue_view_calls.log")
if [[ "$total_calls" -eq 6 ]]; then status_total_calls=0; else status_total_calls=1; fi
check "prefetch: total gh issue-view calls match the (issue, note-kind) pair count exactly" $status_total_calls

# ---------------------------------------------------------------------------
# Fixture 3: nothing to report. Three ungroomed issues and one epic -- both
# count-only categories -- and no delivery work at all, so every section, the
# archive line and "next up" must be absent, leaving three lines of board.
# ---------------------------------------------------------------------------
cat > "$fake_bin_dir3/gh" <<'GHEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    cat <<'JSON'
[
  {"number":501,"title":"Backlog 501","labels":[],"url":"https://x/501","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":502,"title":"Backlog 502","labels":[],"url":"https://x/502","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":503,"title":"Backlog 503","labels":[],"url":"https://x/503","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":600,"title":"Small epic","labels":[{"name":"status:ready"},{"name":"P1"}],"url":"https://x/600","assignees":[],"subIssuesSummary":{"completed":1,"percentCompleted":33,"total":3},"subIssues":{"nodes":[{"number":601,"title":"Sub 601"},{"number":602,"title":"Sub 602"},{"number":603,"title":"Sub 603"}]}}
]
JSON
    ;;
  "pr list")
    echo "[]"
    ;;
  "api user")
    echo "me"
    ;;
  "repo view")
    echo "main"
    ;;
  "issue view")
    echo '{"comments":[]}'
    ;;
  *)
    exit 1
    ;;
esac
GHEOF
chmod +x "$fake_bin_dir3/gh"

cat > "$fake_bin_dir3/git" <<'GITEOF'
#!/usr/bin/env bash
if [[ "$1" == "ls-tree" ]]; then
  printf 'archive\n'
  exit 0
fi
exit 1
GITEOF
chmod +x "$fake_bin_dir3/git"

cat > "$fake_bin_dir3/claude" <<'CLAUDEEOF'
#!/usr/bin/env bash
if [[ "$1" == "agents" ]]; then
  echo '[]'
  exit 0
fi
exit 1
CLAUDEEOF
chmod +x "$fake_bin_dir3/claude"

out3="$(PATH="$fake_bin_dir3:$PATH" python3 "$board")"
status3=$?
check "fixture 3: board.py exits 0" "$status3"

# The whole render, exactly. A section that leaves its trailing blank-line separator behind, or a
# header with nothing under it, fails here and nowhere else.
expected3='## Delivery board

(3 ungroomed · 1 epic)'
if [[ "$out3" == "$expected3" ]]; then status_exact3=0; else status_exact3=1; fi
check "a board with nothing to report is three lines: the title and the two counts" "$status_exact3"

! echo "$out3" | grep -q "BLOCKED ON YOU"
check "the BLOCKED ON YOU header does not appear when nothing is blocked on the owner" $?

! echo "$out3" | grep -qE "IN FLIGHT|READY|UNRECOGNIZED|Stalled|Blocked:"
check "no other section header appears when it has no rows" $?

! echo "$out3" | grep -qE "(^|[ (·])0 "
check "no zero count is rendered anywhere" $?

! echo "$out3" | grep -q "pending archive"
check "no 'specs pending archive: 0' text appears when nothing is pending" $?

! echo "$out3" | grep -q "Next up"
check "no 'next up' line renders when no unclaimed ready issue exists" $?

# ---------------------------------------------------------------------------
# Fixture 4: "next up" ordering and the READY cap. Nine status:ready issues --
# P2, unprioritized and P0 unclaimed, a P1 claimed by alice, and five more P2s
# claimed by alice. The P0 (#705) is placed out of number order, and the claimed
# P1 (#706) outranks it by nothing but assignment, so a recommendation that
# ignores either priority or ownership names the wrong issue.
#
# Every added issue is alice's, not mine, so is_blocked_on_you stays false and
# all nine stay in READY. Sorted by (priority, number) the first five are
# 705, 706, 701, 707, 708 -- so the cap's pick is checked against a list whose
# order is neither the number order nor the JSON order.
# ---------------------------------------------------------------------------
cat > "$fake_bin_dir4/gh" <<'GHEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    cat <<'JSON'
[
  {"number":701,"title":"Ready 701","labels":[{"name":"status:ready"},{"name":"P2"}],"url":"https://x/701","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":702,"title":"Ready 702","labels":[{"name":"status:ready"}],"url":"https://x/702","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":705,"title":"Ready 705 top priority","labels":[{"name":"status:ready"},{"name":"P0"}],"url":"https://x/705","assignees":[],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":706,"title":"Ready 706 claimed","labels":[{"name":"status:ready"},{"name":"P1"}],"url":"https://x/706","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":707,"title":"Ready 707","labels":[{"name":"status:ready"},{"name":"P2"}],"url":"https://x/707","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":708,"title":"Ready 708","labels":[{"name":"status:ready"},{"name":"P2"}],"url":"https://x/708","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":709,"title":"Ready 709","labels":[{"name":"status:ready"},{"name":"P2"}],"url":"https://x/709","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":710,"title":"Ready 710","labels":[{"name":"status:ready"},{"name":"P2"}],"url":"https://x/710","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}},
  {"number":711,"title":"Ready 711","labels":[{"name":"status:ready"},{"name":"P2"}],"url":"https://x/711","assignees":[{"login":"alice"}],"subIssuesSummary":{"completed":0,"percentCompleted":0,"total":0},"subIssues":{"nodes":[]}}
]
JSON
    ;;
  "pr list")
    echo "[]"
    ;;
  "api user")
    echo "me"
    ;;
  "repo view")
    echo "main"
    ;;
  "issue view")
    echo '{"comments":[]}'
    ;;
  *)
    exit 1
    ;;
esac
GHEOF
chmod +x "$fake_bin_dir4/gh"

cat > "$fake_bin_dir4/git" <<'GITEOF'
#!/usr/bin/env bash
if [[ "$1" == "ls-tree" ]]; then
  printf 'issue-1\nissue-2\nissue-3\narchive\n'
  exit 0
fi
exit 1
GITEOF
chmod +x "$fake_bin_dir4/git"

cat > "$fake_bin_dir4/claude" <<'CLAUDEEOF'
#!/usr/bin/env bash
if [[ "$1" == "agents" ]]; then
  echo '[]'
  exit 0
fi
exit 1
CLAUDEEOF
chmod +x "$fake_bin_dir4/claude"

out4="$(PATH="$fake_bin_dir4:$PATH" python3 "$board")"
status4=$?
check "fixture 4: board.py exits 0" "$status4"

echo "$out4" | sed -n '/Next up — activate:/,$p' | grep -q "^  - 705: Ready 705 top priority → /spec-flow:activate 705$"
check "'next up' names the P0 issue when unclaimed ready issues exist at P0 and P2" $?

! echo "$out4" | grep -qE "activate (701|702)$"
check "'next up' does not name a lower-priority or unprioritized ready issue" $?

! echo "$out4" | grep -q "activate 706"
check "'next up' does not name a status:ready issue that already has an assignee" $?

echo "$out4" | grep -qx "🗄️  3 specs pending archive → /spec-flow:archive"
check "the archive suggestion renders with its count when specs are pending" $?

# --- issue 71: the READY cap, end to end through the CLI ---

# Rows are counted INSIDE the extracted READY block, never over the whole board: a ready row
# rendered under BLOCKED ON YOU matches the same regex, and fixture 1's render holds exactly such
# a row. The same fake PATH backs all three runs, so only the flag differs between them.
ready_rows_in() { section_in "$1" "📋 READY" | grep -cE '^  ready +#[0-9]+'; }

out4_two="$(PATH="$fake_bin_dir4:$PATH" python3 "$board" --ready-limit 2)"
out4_all="$(PATH="$fake_bin_dir4:$PATH" python3 "$board" --ready-limit 100)"

# Canary first: nine ready issues must actually reach the bucket, or every count below is
# measuring an empty block and passing vacuously.
if [[ "$(ready_rows_in "$out4_all")" -eq 9 ]]; then status_ready_all=0; else status_ready_all=1; fi
check "--ready-limit 100 renders all nine ready rows (canary — a large N is the uncap)" "$status_ready_all"

! echo "$out4_all" | grep -q "more ready"
check "no withheld line renders when the limit exceeds the ready count" $?

if [[ "$(ready_rows_in "$out4")" -eq 5 ]]; then status_ready_def=0; else status_ready_def=1; fi
check "the default cap renders exactly five READY rows out of nine" "$status_ready_def"

# The five highest priority, in (priority, number) order -- not the first five by number, and not
# the JSON order. 702 is unprioritized and 709-711 are lower down the P2 run, so neither renders.
section_in "$out4" "📋 READY" | grep -qE '^  ready +#705 ' &&
  section_in "$out4" "📋 READY" | grep -qE '^  ready +#706 ' &&
  section_in "$out4" "📋 READY" | grep -qE '^  ready +#701 ' &&
  section_in "$out4" "📋 READY" | grep -qE '^  ready +#707 ' &&
  section_in "$out4" "📋 READY" | grep -qE '^  ready +#708 '
check "the five rendered rows are the highest-priority five (705, 706, 701, 707, 708)" $?

! section_in "$out4" "📋 READY" | grep -qE '^  ready +#(702|709|710|711) '
check "no lower-priority ready row displaces one of the five" $?

section_in "$out4" "📋 READY" | tail -1 | grep -qxF "  … 4 more ready — raise --ready-limit to see the rest"
check "the withheld line is the last line of the READY block and names the remedy" $?

if [[ "$(ready_rows_in "$out4_two")" -eq 2 ]]; then status_ready_two=0; else status_ready_two=1; fi
check "--ready-limit 2 renders exactly two READY rows" "$status_ready_two"

section_in "$out4_two" "📋 READY" | grep -qF "7 more ready"
check "the withheld count tracks an explicit --ready-limit (2 rendered, 7 withheld, 9 total)" $?

# --- issue 71: a limit below 1 is a usage error, not a smaller board ---

# `set -e` is not in effect here, but $? is still clobbered by the next command, so capture it on
# the line after the assignment and nowhere later.
usage_out="$(PATH="$fake_bin_dir4:$PATH" python3 "$board" --ready-limit 0 2>"$fake_bin_dir4/usage0.log")"
usage_status=$?
if [[ "$usage_status" -ne 0 && -z "$usage_out" ]]; then status_zero=0; else status_zero=1; fi
check "--ready-limit 0 exits non-zero and prints no board" "$status_zero"

grep -q "must be 1 or more" "$fake_bin_dir4/usage0.log"
check "--ready-limit 0 reports the usage error on stderr" $?

usage_out_neg="$(PATH="$fake_bin_dir4:$PATH" python3 "$board" --ready-limit -1 2>"$fake_bin_dir4/usage1.log")"
usage_status_neg=$?
if [[ "$usage_status_neg" -ne 0 && -z "$usage_out_neg" ]]; then status_neg=0; else status_neg=1; fi
check "--ready-limit -1 exits non-zero and prints no board" "$status_neg"

grep -q "must be 1 or more" "$fake_bin_dir4/usage1.log"
check "--ready-limit -1 reports the usage error on stderr" $?

# Note on prefetch transparency: fixture 1's blocked/needs-attention assertions match exact
# rendered note text, and are the transparency check -- they must still pass with
# last_comment_matching()'s calls behind the concurrent prefetch's dict-lookup indirection,
# proving the parallelized fetch produces the same note content as the serial code it replaced.

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
