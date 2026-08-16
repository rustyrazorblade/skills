#!/usr/bin/env bash
# Structural self-test for generate-explain.py + viewer.html. Builds a tiny throwaway git repo
# with a known change, runs the generator against it, and asserts on the output HTML — see
# README.md in this directory for how to run it. Exits non-zero if any assertion fails. macOS
# bash 3.2 compatible (no associative arrays, no mapfile); the JSON-shaped assertions delegate to
# python3, which the generator itself already requires.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
generate_explain="$script_dir/generate-explain.py"
viewer_html="$script_dir/../assets/viewer.html"

pass_count=0
fail_count=0

check() {
  # usage: check "<description>" <exit-status-where-0-is-pass>
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

command -v git >/dev/null 2>&1 || { echo "test-generate-explain: 'git' is required but not on PATH." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "test-generate-explain: 'python3' is required but not on PATH." >&2; exit 1; }

repo="$(mktemp -d)"
out_dir="$(mktemp -d)"
out_html="$out_dir/explain-test.html"

cleanup() { rm -rf "$repo" "$out_dir"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixture: a tiny repo with one committed file, then a known uncommitted change
# (exercises the default head = working tree), plus doc/code/change-dir inputs
# so the manifest covers all three node kinds.
# ---------------------------------------------------------------------------
git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"

printf 'line1\nline2\nline3\n' > "$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "initial"
base_sha="$(git -C "$repo" rev-parse HEAD)"

# Known small change, left uncommitted:
printf 'line1\nline2-modified\nline3\nline4\n' > "$repo/file.txt"

mkdir -p "$repo/docs" "$repo/src" "$repo/changes/demo/specs"
printf '# Note\n\nSome doc content.\n' > "$repo/docs/note.md"
printf 'def add(a, b):\n    return a + b\n' > "$repo/src/extra.py"
printf '# Proposal\n\nDo the thing.\n' > "$repo/changes/demo/proposal.md"
printf '# Design\n\nHow the thing works.\n' > "$repo/changes/demo/design.md"
printf '## ADDED Requirements\n\nfoo\n' > "$repo/changes/demo/specs/foo.md"
printf '## MODIFIED Requirements\n\nchanged\n\n## REMOVED Requirements\n\ngone\n' > "$repo/changes/demo/specs/bar.md"

(
  cd "$repo" && python3 "$generate_explain" \
    --diff \
    --base "$base_sha" \
    --change "$repo/changes/demo" \
    --doc "$repo/docs/note.md" \
    --code "$repo/src/extra.py" \
    --title "Test Explain" \
    --out "$out_html"
)
gen_status=$?
check "generate-explain.py exits 0" "$gen_status"

[[ -f "$out_html" ]]
check "output HTML file exists" $?

if [[ -f "$out_html" ]]; then
  ! grep -qF '<!--MANIFEST-->' "$out_html"
  check "no literal <!--MANIFEST--> marker left in output" $?

  ! grep -qE 'http://|https://|fetch\(' "$out_html"
  check "no http(s):// or fetch( in output (self-contained)" $?
else
  check "no literal <!--MANIFEST--> marker left in output" 1
  check "no http(s):// or fetch( in output (self-contained)" 1
fi

# ---------------------------------------------------------------------------
# JSON-shaped assertions: manifest parses, has the expected node count/kinds,
# and the diff node's patch round-trips the actual known change.
# ---------------------------------------------------------------------------
py_out="$(python3 - "$out_html" <<'PYEOF'
import json
import sys
from collections import Counter

path = sys.argv[1]
try:
    content = open(path, encoding="utf-8").read()
except OSError as e:
    print(f"FAIL: could not read output HTML ({e})")
    sys.exit(0)

start_marker = "<script>window.MANIFEST = "
try:
    start = content.index(start_marker) + len(start_marker)
    end = content.index(";</script>", start)
    manifest = json.loads(content[start:end])
    print("PASS: embedded window.MANIFEST JSON parses")
except Exception as e:
    print(f"FAIL: embedded window.MANIFEST JSON parses ({e})")
    sys.exit(0)

nodes = manifest.get("nodes", [])
if len(nodes) == 7:
    print("PASS: manifest has expected node count (7)")
else:
    print(f"FAIL: manifest has expected node count (7) — got {len(nodes)}")

kinds = Counter(n.get("kind") for n in nodes)
expected = Counter({"diff": 1, "markdown": 5, "code": 1})
if kinds == expected:
    print("PASS: manifest has expected node kinds (diff=1, markdown=5, code=1)")
else:
    print(f"FAIL: manifest has expected node kinds — got {dict(kinds)}")

diff_nodes = [n for n in nodes if n.get("kind") == "diff"]
if len(diff_nodes) == 1 and diff_nodes[0].get("path") == "file.txt":
    print("PASS: diff node path round-trips (file.txt)")
else:
    print(f"FAIL: diff node path round-trips — got {[n.get('path') for n in diff_nodes]}")

patch = diff_nodes[0].get("patch", "") if diff_nodes else ""
if "-line2" in patch and "+line2-modified" in patch and "+line4" in patch:
    print("PASS: diff node patch round-trips the known change")
else:
    print("FAIL: diff node patch round-trips the known change")

foo_node = next((n for n in nodes if n.get("path", "").endswith("foo.md")), {})
if foo_node.get("badge") == "ADDED" and foo_node.get("badgeClass") == "add":
    print("PASS: ADDED-only delta spec gets an ADDED/add tree badge")
else:
    print(f"FAIL: ADDED-only delta spec badge — got {foo_node.get('badge')}/{foo_node.get('badgeClass')}")

bar_node = next((n for n in nodes if n.get("path", "").endswith("bar.md")), {})
if bar_node.get("badge") == "REMOVED" and bar_node.get("badgeClass") == "del":
    print("PASS: MODIFIED+REMOVED delta spec badge prioritizes REMOVED")
else:
    print(f"FAIL: MODIFIED+REMOVED delta spec badge — got {bar_node.get('badge')}/{bar_node.get('badgeClass')}")

proposal_node = next((n for n in nodes if n.get("path", "").endswith("proposal.md")), {})
if "badge" not in proposal_node:
    print("PASS: a non-delta doc (proposal.md) gets no delta badge")
else:
    print(f"FAIL: a non-delta doc (proposal.md) got an unexpected badge — {proposal_node.get('badge')}")
PYEOF
)"
echo "$py_out"
py_pass="$(echo "$py_out" | grep -c '^PASS:')"
py_fail="$(echo "$py_out" | grep -c '^FAIL:')"
pass_count=$((pass_count + py_pass))
fail_count=$((fail_count + py_fail))

# ---------------------------------------------------------------------------
# Structural checks on the static viewer shell itself — no headless browser
# available here, so this is a grep-based check that the JS defines the
# right branches/functions, not an execution of it.
# ---------------------------------------------------------------------------
grep -qF 'window.MANIFEST' "$viewer_html"
check "viewer.html references window.MANIFEST" $?

grep -qF 'kind === "diff"' "$viewer_html"
check "viewer.html branches on kind === \"diff\"" $?

grep -qF 'kind === "code"' "$viewer_html"
check "viewer.html branches on kind === \"code\"" $?

grep -qF 'kind === "markdown"' "$viewer_html"
check "viewer.html branches on kind === \"markdown\"" $?

grep -qE 'function renderMarkdown' "$viewer_html"
check "viewer.html defines a markdown-render function" $?

grep -qE 'function parseDiff' "$viewer_html"
check "viewer.html defines a diff-parse function" $?

grep -qF 'DELTA_HEADING_RE' "$viewer_html"
check "viewer.html defines the ADDED/MODIFIED/REMOVED/RENAMED heading matcher" $?

grep -qF 'delta-section delta-' "$viewer_html"
check "viewer.html wraps delta-spec sections in a color-coded div" $?

# ---------------------------------------------------------------------------
# Argument validation: nothing to render at all should fail loudly, not
# silently produce an empty view — this is the exact bug an owner hit trying
# to view a plain backlog issue with no diff yet.
# ---------------------------------------------------------------------------
python3 "$generate_explain" >/dev/null 2>/dev/null
[[ $? -ne 0 ]]
check "no flags at all -> non-zero exit (never a silent empty view)" $?

# ---------------------------------------------------------------------------
# --issue mode: no git diff involved at all. Fakes `gh` on PATH so this runs
# offline — a primary issue (#1) linked to a blocked-by issue (#2) and
# mentioning a third (#3) in its body, exercising both the native-dependency
# and #N-mention relation paths without any code change existing.
# ---------------------------------------------------------------------------
fake_gh_dir="$(mktemp -d)"
cat > "$fake_gh_dir/gh" <<'GHEOF'
#!/usr/bin/env bash
case "$1" in
  repo)
    echo '{"nameWithOwner":"acme/widgets"}'
    ;;
  issue)
    case "$3" in
      1) echo '{"number":1,"title":"Primary issue","body":"See #3 for context.","url":"https://x/1","state":"OPEN","labels":[{"name":"P1"}],"comments":[{"author":{"login":"jon"},"createdAt":"2026-01-01T00:00:00Z","body":"Some research note."}]}' ;;
      2) echo '{"number":2,"title":"Blocked-by issue","body":"","url":"https://x/2","state":"OPEN","labels":[]}' ;;
      3) echo '{"number":3,"title":"Mentioned issue","body":"","url":"https://x/3","state":"CLOSED","labels":[]}' ;;
      *) exit 1 ;;
    esac
    ;;
  api)
    case "$2" in
      */dependencies/blocked_by) echo '[{"number":2}]' ;;
      */dependencies/blocking) echo '[]' ;;
      *) echo '[]' ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
GHEOF
chmod +x "$fake_gh_dir/gh"

issue_out_html="$out_dir/explain-issue-test.html"
(
  cd "$repo" && PATH="$fake_gh_dir:$PATH" python3 "$generate_explain" \
    --issue 1 \
    --out "$issue_out_html"
)
check "generate-explain.py --issue exits 0" $?

issue_py_out="$(python3 - "$issue_out_html" <<'PYEOF'
import json
import sys

path = sys.argv[1]
try:
    content = open(path, encoding="utf-8").read()
except OSError as e:
    print(f"FAIL: could not read --issue output HTML ({e})")
    sys.exit(0)

start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])

nodes = manifest.get("nodes", [])
paths = sorted(n.get("path") for n in nodes)
if paths == ["issue-1.md", "related/issue-2.md", "related/issue-3.md"]:
    print("PASS: --issue mode includes primary + both related issues (dependency + mention)")
else:
    print(f"FAIL: --issue mode node paths — got {paths}")

if all(n.get("kind") == "markdown" for n in nodes):
    print("PASS: --issue mode nodes are all markdown")
else:
    print("FAIL: --issue mode nodes are all markdown")

primary = next((n for n in nodes if n.get("path") == "issue-1.md"), {})
if "Some research note." in primary.get("md", ""):
    print("PASS: --issue mode includes the issue's discussion/comments")
else:
    print("FAIL: --issue mode includes the issue's discussion/comments")

if "base" not in manifest.get("meta", {}) and "head" not in manifest.get("meta", {}):
    print("PASS: --issue mode without --diff never computes/claims a diff base/head")
else:
    print(f"FAIL: --issue mode without --diff leaked diff meta — got {manifest.get('meta')}")
PYEOF
)"
echo "$issue_py_out"
issue_py_pass="$(echo "$issue_py_out" | grep -c '^PASS:')"
issue_py_fail="$(echo "$issue_py_out" | grep -c '^FAIL:')"
pass_count=$((pass_count + issue_py_pass))
fail_count=$((fail_count + issue_py_fail))

rm -rf "$fake_gh_dir"

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
