#!/usr/bin/env bash
# Structural self-test for generate-deck.py + viewer.html. Builds a tiny throwaway git repo with
# a known change, runs the generator against it, and asserts on the output HTML — see README.md
# in this directory for how to run it. Exits non-zero if any assertion fails. macOS bash 3.2
# compatible (no associative arrays, no mapfile); the JSON-shaped assertions delegate to python3,
# which the generator itself already requires.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
generate_deck="$script_dir/generate-deck.py"
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

command -v git >/dev/null 2>&1 || { echo "test-generate-deck: 'git' is required but not on PATH." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "test-generate-deck: 'python3' is required but not on PATH." >&2; exit 1; }

repo="$(mktemp -d)"
out_dir="$(mktemp -d)"
out_html="$out_dir/deck-test.html"

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

(
  cd "$repo" && python3 "$generate_deck" \
    --base "$base_sha" \
    --change "$repo/changes/demo" \
    --doc "$repo/docs/note.md" \
    --code "$repo/src/extra.py" \
    --title "Test Deck" \
    --out "$out_html"
)
gen_status=$?
check "generate-deck.py exits 0" "$gen_status"

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
if len(nodes) == 6:
    print("PASS: manifest has expected node count (6)")
else:
    print(f"FAIL: manifest has expected node count (6) — got {len(nodes)}")

kinds = Counter(n.get("kind") for n in nodes)
expected = Counter({"diff": 1, "markdown": 4, "code": 1})
if kinds == expected:
    print("PASS: manifest has expected node kinds (diff=1, markdown=4, code=1)")
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

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
