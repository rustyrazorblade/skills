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

# A brand-new file, staged -- exercises the "*New file*" explain message (no prior history to
# blame at all, as opposed to a modified file with a real blame trail).
printf 'brand new content\n' > "$repo/newfile.txt"
git -C "$repo" add newfile.txt

mkdir -p "$repo/docs" "$repo/src" "$repo/changes/demo/specs"
printf '# Note\n\nSome doc content.\n' > "$repo/docs/note.md"
printf 'def add(a, b):\n    return a + b\n' > "$repo/src/extra.py"
printf '# Proposal\n\nDo the thing.\n' > "$repo/changes/demo/proposal.md"
printf '# Design\n\nHow the thing works.\n' > "$repo/changes/demo/design.md"
printf '## ADDED Requirements\n\nfoo\n' > "$repo/changes/demo/specs/foo.md"
printf '## MODIFIED Requirements\n\nchanged\n\n## REMOVED Requirements\n\ngone\n' > "$repo/changes/demo/specs/bar.md"

(
  cd "$repo" && python3 "$generate_explain" \
    --diff --blame \
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
if len(nodes) == 8:
    print("PASS: manifest has expected node count (8)")
else:
    print(f"FAIL: manifest has expected node count (8) — got {len(nodes)}")

kinds = Counter(n.get("kind") for n in nodes)
expected = Counter({"diff": 2, "markdown": 5, "code": 1})
if kinds == expected:
    print("PASS: manifest has expected node kinds (diff=2, markdown=5, code=1)")
else:
    print(f"FAIL: manifest has expected node kinds — got {dict(kinds)}")

diff_nodes = {n["path"]: n for n in nodes if n.get("kind") == "diff"}
if set(diff_nodes) == {"file.txt", "newfile.txt"}:
    print("PASS: diff node paths round-trip (file.txt modified, newfile.txt added)")
else:
    print(f"FAIL: diff node paths — got {sorted(diff_nodes)}")

patch = diff_nodes.get("file.txt", {}).get("patch", "")
if "-line2" in patch and "+line2-modified" in patch and "+line4" in patch:
    print("PASS: diff node patch round-trips the known change")
else:
    print("FAIL: diff node patch round-trips the known change")

blame_explain = diff_nodes.get("file.txt", {}).get("explain", "")
if "Test" in blame_explain and "initial" in blame_explain:
    print("PASS: --blame populates a modified file's explain with the full commit message")
else:
    print(f"FAIL: --blame explain — got {blame_explain!r}")

newfile_explain = diff_nodes.get("newfile.txt", {}).get("explain", "")
if "New file" in newfile_explain:
    print("PASS: a brand-new file gets an explicit 'New file' explain instead of no explain at all")
else:
    print(f"FAIL: new-file explain — got {newfile_explain!r}")

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

grep -qF 'function slugify' "$viewer_html"
check "viewer.html gives headings stable slugified anchor ids" $?

grep -qF 'function renderPrComment' "$viewer_html"
check "viewer.html defines a PR-comment renderer" $?

grep -qF 'commentsByKey' "$viewer_html"
check "viewer.html anchors PR comments to their diff row by side+line" $?

# ---------------------------------------------------------------------------
# Argument validation: nothing to render at all should fail loudly, not
# silently produce an empty view — this is the exact bug an owner hit trying
# to view a plain backlog issue with no diff yet.
# ---------------------------------------------------------------------------
python3 "$generate_explain" >/dev/null 2>/dev/null
[[ $? -ne 0 ]]
check "no flags at all -> non-zero exit (never a silent empty view)" $?

# ---------------------------------------------------------------------------
# --worktree / --branch: generic, git-only sugar for --diff's own base/head
# defaults -- no issue-number guessing, no spec-flow filename assumptions.
# ---------------------------------------------------------------------------
worktree_out_html="$out_dir/explain-worktree-test.html"
(
  cd "$repo" && python3 "$generate_explain" --worktree --out "$worktree_out_html"
)
check "generate-explain.py --worktree exits 0" $?

worktree_py_out="$(python3 - "$worktree_out_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
diff_nodes = [n for n in manifest.get("nodes", []) if n.get("kind") == "diff"]
if any(n.get("path") == "file.txt" for n in diff_nodes):
    print("PASS: --worktree resolves the same as --diff's own default (merge-base vs. working tree)")
else:
    print(f"FAIL: --worktree — got diff node paths {[n.get('path') for n in diff_nodes]}")
PYEOF
)"
echo "$worktree_py_out"
pass_count=$((pass_count + $(echo "$worktree_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$worktree_py_out" | grep -c '^FAIL:')))

# A second branch with a distinct, known commit -- proves --branch NAME actually resolves head
# to that branch's tip, not just falling back to the working-tree default. Built entirely with
# plumbing commands so the fixture's current branch/working tree/index are never touched --
# later tests in this file keep reusing the same $repo.
other_blob="$(printf 'line1\nline2\nline3\nfrom-other-branch\n' | git -C "$repo" hash-object -w --stdin)"
base_tree="$(git -C "$repo" rev-parse "$base_sha^{tree}")"
other_tree="$(
  { git -C "$repo" ls-tree "$base_tree" | grep -v $'\tfile\\.txt$'; printf '100644 blob %s\tfile.txt\n' "$other_blob"; } \
    | git -C "$repo" mktree
)"
other_commit="$(git -C "$repo" commit-tree "$other_tree" -p "$base_sha" -m "other-branch commit")"
git -C "$repo" branch -q other-branch "$other_commit"

branch_out_html="$out_dir/explain-branch-test.html"
(
  cd "$repo" && python3 "$generate_explain" --branch other-branch --out "$branch_out_html"
)
check "generate-explain.py --branch exits 0" $?

branch_py_out="$(python3 - "$branch_out_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
diff_nodes = [n for n in manifest.get("nodes", []) if n.get("kind") == "diff"]
patch = next((n.get("patch", "") for n in diff_nodes if n.get("path") == "file.txt"), "")
if "+from-other-branch" in patch:
    print("PASS: --branch NAME resolves head to that branch's tip, not the working tree default")
else:
    print(f"FAIL: --branch — got patch {patch!r}")
PYEOF
)"
echo "$branch_py_out"
pass_count=$((pass_count + $(echo "$branch_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$branch_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# Commit-history context is now the DEFAULT for a code diff's explain pane --
# a code diff must never leave the owner looking at a silently-empty
# explanation pane. --no-blame is the real opt-out (git can only ever quote
# historical text someone else wrote, never explain what the current diff
# actually does -- a caller with a real --explain-map, or one that just wants
# speed on a large diff, can turn it off explicitly).
# ---------------------------------------------------------------------------
default_blame_html="$out_dir/explain-default-blame-test.html"
(
  cd "$repo" && python3 "$generate_explain" \
    --diff --base "$base_sha" --out "$default_blame_html"
)
check "generate-explain.py with --diff alone exits 0" $?

default_blame_py_out="$(python3 - "$default_blame_html" <<'PYEOF'
import json
import sys

path = sys.argv[1]
content = open(path, encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
diff_nodes = {n["path"]: n for n in manifest.get("nodes", []) if n.get("kind") == "diff"}

file_explain = diff_nodes.get("file.txt", {}).get("explain", "")
if "Test" in file_explain and "initial" in file_explain:
    print("PASS: commit-history context populates a modified file's explain pane by default (no flag needed)")
else:
    print(f"FAIL: --diff alone — got explain={file_explain!r}")

newfile_explain = diff_nodes.get("newfile.txt", {}).get("explain", "")
if "New file" in newfile_explain:
    print("PASS: a brand-new file gets an explicit 'New file' explain by default too")
else:
    print(f"FAIL: --diff alone, new-file explain — got {newfile_explain!r}")
PYEOF
)"
echo "$default_blame_py_out"
default_blame_py_pass="$(echo "$default_blame_py_out" | grep -c '^PASS:')"
default_blame_py_fail="$(echo "$default_blame_py_out" | grep -c '^FAIL:')"
pass_count=$((pass_count + default_blame_py_pass))
fail_count=$((fail_count + default_blame_py_fail))

# --no-blame is the real opt-out now (--blame is accepted but redundant -- already the default).
noblame_off_html="$out_dir/explain-noblame-off-test.html"
(
  cd "$repo" && python3 "$generate_explain" \
    --diff --base "$base_sha" --no-blame --out "$noblame_off_html"
)
check "generate-explain.py --no-blame exits 0" $?

noblame_off_py_out="$(python3 - "$noblame_off_html" <<'PYEOF'
import json
import sys

path = sys.argv[1]
content = open(path, encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
diff_nodes = [n for n in manifest.get("nodes", []) if n.get("kind") == "diff"]
if not diff_nodes:
    print(f"FAIL: --no-blame — expected diff nodes to check, got none at all")
elif all("explain" not in n for n in diff_nodes):
    print("PASS: --no-blame actually opts out -- no explain field on any diff node")
else:
    with_explain = [n["path"] for n in diff_nodes if "explain" in n]
    print(f"FAIL: --no-blame — expected no explain fields, got some on {with_explain}")
PYEOF
)"
echo "$noblame_off_py_out"
pass_count=$((pass_count + $(echo "$noblame_off_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$noblame_off_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# --explain-map: the REAL explanation path. A caller that has actually read
# the diff supplies {"path": "explanation"}; it must win over --blame for
# any path it covers, and leave other paths' blame context untouched.
# ---------------------------------------------------------------------------
explain_map_file="$out_dir/explain-map.json"
cat > "$explain_map_file" <<'JSONEOF'
{"file.txt": "This widens the retry window from 2 lines to 4 so a flaky\nnetwork blip during startup doesn't fail the whole request."}
JSONEOF

explain_map_out_html="$out_dir/explain-explainmap-test.html"
(
  cd "$repo" && python3 "$generate_explain" \
    --diff --blame --base "$base_sha" --explain-map "$explain_map_file" --out "$explain_map_out_html"
)
check "generate-explain.py --explain-map exits 0" $?

explainmap_py_out="$(python3 - "$explain_map_out_html" <<'PYEOF'
import json
import sys

path = sys.argv[1]
content = open(path, encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = {n["path"]: n for n in manifest.get("nodes", []) if n.get("kind") == "diff"}

file_explain = nodes.get("file.txt", {}).get("explain", "")
if "retry window" in file_explain and "Test" not in file_explain:
    print("PASS: --explain-map overrides --blame's commit-message content for a covered path")
else:
    print(f"FAIL: --explain-map override — got {file_explain!r}")

newfile_explain = nodes.get("newfile.txt", {}).get("explain", "")
if "New file" in newfile_explain:
    print("PASS: --explain-map leaves an uncovered path's --blame content untouched")
else:
    print(f"FAIL: uncovered-path fallback — got {newfile_explain!r}")
PYEOF
)"
echo "$explainmap_py_out"
explainmap_py_pass="$(echo "$explainmap_py_out" | grep -c '^PASS:')"
explainmap_py_fail="$(echo "$explainmap_py_out" | grep -c '^FAIL:')"
pass_count=$((pass_count + explainmap_py_pass))
fail_count=$((fail_count + explainmap_py_fail))

# --explain-map pointing at a missing file must fail loudly, not silently proceed.
python3 "$generate_explain" --diff --base "$base_sha" --explain-map "$out_dir/does-not-exist.json" >/dev/null 2>/dev/null
[[ $? -ne 0 ]]
check "--explain-map with a missing file fails loudly" $?

# ---------------------------------------------------------------------------
# --symbol blast-radius: a word-boundary git grep across the working tree
# (tracked files, uncommitted edits included) -- "line2-modified" exists only
# in file.txt's uncommitted content; "totally_absent_xyz" matches nothing.
# ---------------------------------------------------------------------------
symbol_out_html="$out_dir/explain-symbol-test.html"
(
  cd "$repo" && python3 "$generate_explain" \
    --symbol line2-modified --symbol totally_absent_xyz \
    --out "$symbol_out_html"
)
check "generate-explain.py --symbol exits 0" $?

symbol_py_out="$(python3 - "$symbol_out_html" <<'PYEOF'
import json
import sys

path = sys.argv[1]
content = open(path, encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = {n["path"]: n for n in manifest.get("nodes", [])}

found = nodes.get("blast-radius/line2-modified.md", {}).get("md", "")
if "file.txt" in found and "1 reference" in found:
    print("PASS: --symbol finds a real match with file:line context")
else:
    print(f"FAIL: --symbol found-case — got {found!r}")

absent = nodes.get("blast-radius/totally_absent_xyz.md", {}).get("md", "")
if "No references found" in absent:
    print("PASS: --symbol with zero matches still produces an explicit 'none found' node")
else:
    print(f"FAIL: --symbol zero-match case — got {absent!r}")
PYEOF
)"
echo "$symbol_py_out"
symbol_py_pass="$(echo "$symbol_py_out" | grep -c '^PASS:')"
symbol_py_fail="$(echo "$symbol_py_out" | grep -c '^FAIL:')"
pass_count=$((pass_count + symbol_py_pass))
fail_count=$((fail_count + symbol_py_fail))

# ---------------------------------------------------------------------------
# --path scoping: a second uncommitted change outside the scoped path must
# NOT show up in the diff nodes — this is what makes a "what changed since
# you last reviewed" view scoped to just one change dir, not the whole repo.
# ---------------------------------------------------------------------------
printf 'unrelated change\n' > "$repo/unrelated.txt"
git -C "$repo" add "$repo/unrelated.txt"

path_out_html="$out_dir/explain-path-test.html"
(
  cd "$repo" && python3 "$generate_explain" \
    --diff --base "$base_sha" --path file.txt \
    --out "$path_out_html"
)
check "generate-explain.py --path exits 0" $?

path_py_out="$(python3 - "$path_out_html" <<'PYEOF'
import json
import sys

path = sys.argv[1]
content = open(path, encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])

paths = sorted(n.get("path") for n in manifest.get("nodes", []))
if paths == ["file.txt"]:
    print("PASS: --path scopes the diff to only the given path (unrelated.txt excluded)")
else:
    print(f"FAIL: --path scoping — got {paths}")
PYEOF
)"
echo "$path_py_out"
path_py_pass="$(echo "$path_py_out" | grep -c '^PASS:')"
path_py_fail="$(echo "$path_py_out" | grep -c '^FAIL:')"
pass_count=$((pass_count + path_py_pass))
fail_count=$((fail_count + path_py_fail))

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
      */pulls/42/comments)
        echo '[
          {"path":"file.txt","line":4,"side":"RIGHT","body":"Why is this line here?","user":{"login":"reviewer1"},"created_at":"2026-01-02T00:00:00Z"},
          {"path":"nonexistent.txt","line":9,"side":"RIGHT","body":"Stale comment on a file not in this diff.","user":{"login":"reviewer2"},"created_at":"2026-01-02T00:01:00Z"}
        ]'
        ;;
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

# ---------------------------------------------------------------------------
# --pr mode: overlays file/line-anchored review comments onto --diff nodes.
# One comment anchors to a line that's actually IN the diff (file.txt:4, the
# "+line4" addition); one anchors to a file the diff doesn't touch at all, to
# exercise the "outside this diff" fallback rather than silently dropping it.
# ---------------------------------------------------------------------------
pr_out_html="$out_dir/explain-pr-test.html"
(
  cd "$repo" && PATH="$fake_gh_dir:$PATH" python3 "$generate_explain" \
    --diff --base "$base_sha" --pr 42 \
    --out "$pr_out_html"
)
check "generate-explain.py --pr exits 0" $?

pr_py_out="$(python3 - "$pr_out_html" <<'PYEOF'
import json
import sys

path = sys.argv[1]
content = open(path, encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = manifest.get("nodes", [])

file_node = next((n for n in nodes if n.get("path") == "file.txt"), {})
comments = file_node.get("comments", [])
if len(comments) == 1 and comments[0]["line"] == 4 and comments[0]["author"] == "reviewer1":
    print("PASS: --pr attaches a line-anchored comment to its diff node")
else:
    print(f"FAIL: --pr comment attachment — got {comments}")

outside = next((n for n in nodes if n.get("path") == "pr-comments/outside-diff.md"), None)
if outside and "nonexistent.txt" in outside.get("md", "") and "reviewer2" in outside.get("md", ""):
    print("PASS: --pr surfaces a comment on a file outside this diff instead of dropping it")
else:
    print(f"FAIL: --pr outside-diff fallback — got {outside}")
PYEOF
)"
echo "$pr_py_out"
pr_py_pass="$(echo "$pr_py_out" | grep -c '^PASS:')"
pr_py_fail="$(echo "$pr_py_out" | grep -c '^FAIL:')"
pass_count=$((pass_count + pr_py_pass))
fail_count=$((fail_count + pr_py_fail))

rm -rf "$fake_gh_dir"

# ---------------------------------------------------------------------------
# OpenSpec-aware rendering in --diff mode: a delta spec renders as content
# (not a diff), gets the ADDED/MODIFIED/REMOVED summary + jump nav, and a
# MODIFIED requirement gets a Currently:/This change: comparison against its
# baseline -- when a title match exists, and gracefully skipped when it
# doesn't. A brand-new NON-OpenSpec file in the same diff must stay a plain
# diff node, completely unaffected. Own repo (separate from $repo above) so
# its history doesn't interfere with the other cases.
# ---------------------------------------------------------------------------
ospec_repo="$out_dir/openspec-repo"
mkdir -p "$ospec_repo/openspec/specs/widget" "$ospec_repo/src"
git -C "$ospec_repo" init -q
git -C "$ospec_repo" config user.email "test@example.com"
git -C "$ospec_repo" config user.name "Test"

cat > "$ospec_repo/openspec/specs/widget/spec.md" <<'EOF'
## Purpose

Widget management baseline.

## Requirements

### Requirement: Widget deletion
The system SHALL allow deleting a widget by id.

#### Scenario: Delete succeeds
- **WHEN** a delete request is submitted
- **THEN** the widget is removed
EOF
printf 'print("existing")\n' > "$ospec_repo/src/existing.py"
git -C "$ospec_repo" add -A
git -C "$ospec_repo" commit -q -m "baseline"
ospec_base_sha="$(git -C "$ospec_repo" rev-parse HEAD)"

mkdir -p "$ospec_repo/openspec/changes/demo/specs/widget"
cat > "$ospec_repo/openspec/changes/demo/specs/widget/spec.md" <<'EOF'
## ADDED Requirements

### Requirement: Widget renaming
The system SHALL allow renaming a widget.

#### Scenario: Rename succeeds
- **WHEN** a rename request is submitted
- **THEN** the widget's name is updated

## MODIFIED Requirements

### Requirement: Widget deletion
The system SHALL allow deleting a widget by id, and SHALL cascade-delete its attachments.

#### Scenario: Delete succeeds
- **WHEN** a delete request is submitted
- **THEN** the widget and its attachments are removed

### Requirement: A title with no baseline match
The system SHALL do something with no prior version.

#### Scenario: New behavior
- **WHEN** something happens
- **THEN** something else happens

## REMOVED Requirements

### Requirement: Legacy widget export
**Reason**: Superseded by the new export system
**Migration**: Use the v2 export endpoint instead
EOF
printf 'print("brand new, not openspec")\n' > "$ospec_repo/src/newfile.py"
git -C "$ospec_repo" add -A

ospec_diff_html="$out_dir/explain-openspec-diff-test.html"
(
  cd "$ospec_repo" && python3 "$generate_explain" --diff --base "$ospec_base_sha" --out "$ospec_diff_html"
)
check "generate-explain.py exits 0 with an OpenSpec delta spec in the diff" $?

ospec_diff_py_out="$(python3 - "$ospec_diff_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = {n["path"]: n for n in manifest.get("nodes", [])}

spec_node = nodes.get("openspec/changes/demo/specs/widget/spec.md")
if spec_node and spec_node.get("kind") == "markdown":
    print("PASS: delta spec renders as a markdown node, not a diff, in --diff mode")
else:
    print(f"FAIL: delta spec kind — got {spec_node.get('kind') if spec_node else 'MISSING NODE'}")

if spec_node and spec_node.get("badge") == "REMOVED":
    print("PASS: delta spec badge reflects highest-priority category present (REMOVED)")
else:
    print(f"FAIL: delta spec badge — got {spec_node.get('badge') if spec_node else None}")

md = spec_node.get("md", "") if spec_node else ""
if "1 added" in md and "2 modified" in md and "1 removed" in md:
    print("PASS: summary line reflects actual per-category counts")
else:
    print(f"FAIL: summary line — got {md.splitlines()[0] if md else '(empty)'}")

if "(#added-requirements)" in md and "(#modified-requirements)" in md and "(#removed-requirements)" in md:
    print("PASS: jump links present for each category")
else:
    print("FAIL: jump links missing")

if "**Currently:**" in md and "The system SHALL allow deleting a widget by id.\n" in md and \
   "**This change:**" in md and "cascade-delete its attachments" in md:
    print("PASS: MODIFIED requirement with a baseline match gets the Currently:/This change: comparison")
else:
    print("FAIL: MODIFIED-with-match comparison missing or wrong content")

no_match_start = md.find("A title with no baseline match")
no_match_end = md.find("## REMOVED", no_match_start) if no_match_start != -1 else -1
if no_match_start != -1 and no_match_end != -1:
    no_match_section = md[no_match_start:no_match_end]
    if "Currently:" not in no_match_section:
        print("PASS: MODIFIED requirement with NO baseline match renders with no comparison block, no error")
    else:
        print("FAIL: no-match requirement unexpectedly got a comparison block")
else:
    print(f"FAIL: could not locate the no-baseline-match requirement's section in md — got {md[:200]!r}")

diff_node = nodes.get("src/newfile.py")
if diff_node and diff_node.get("kind") == "diff" and diff_node.get("badge") == "new":
    print("PASS: a brand-new NON-OpenSpec file in the same diff is completely unaffected")
else:
    print(f"FAIL: src/newfile.py — got {diff_node}")
PYEOF
)"
echo "$ospec_diff_py_out"
pass_count=$((pass_count + $(echo "$ospec_diff_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$ospec_diff_py_out" | grep -c '^FAIL:')))

# Same fixture content, reached via --change instead of --diff, must produce byte-identical
# enriched markdown -- the two entry points share markdown_node()'s enrichment.
ospec_change_html="$out_dir/explain-openspec-change-test.html"
(
  cd "$ospec_repo" && python3 "$generate_explain" --change openspec/changes/demo --out "$ospec_change_html"
)
check "generate-explain.py --change exits 0 against the same OpenSpec fixture" $?

ospec_parity_py_out="$(python3 - "$ospec_diff_html" "$ospec_change_html" <<'PYEOF'
import json
import sys

def spec_md(path):
    content = open(path, encoding="utf-8").read()
    start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
    end = content.index(";</script>", start)
    manifest = json.loads(content[start:end])
    for n in manifest.get("nodes", []):
        if n["path"].endswith("demo/specs/widget/spec.md"):
            return n.get("md")
    return None

diff_md = spec_md(sys.argv[1])
change_md = spec_md(sys.argv[2])
if diff_md is not None and diff_md == change_md:
    print("PASS: --diff (path-detected) and --change produce byte-identical enriched output")
else:
    print("FAIL: --diff vs --change enrichment mismatch")
PYEOF
)"
echo "$ospec_parity_py_out"
pass_count=$((pass_count + $(echo "$ospec_parity_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$ospec_parity_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# Fence-awareness: a requirement whose own body quotes a fenced example that
# LOOKS like markdown structure ("## "/"### " lines inside a ```-fenced block)
# must not get truncated at that fake heading, and the Currently:/This change:
# comparison must land after the fence closes, never spliced into it. Also
# covers path-detection for proposal.md (a non-delta doc) and a DELETED
# OpenSpec file staying a diff node -- own repo, own baseline commit.
# ---------------------------------------------------------------------------
ospec_repo2="$out_dir/openspec-repo2"
mkdir -p "$ospec_repo2/openspec/specs/widget" "$ospec_repo2/openspec/changes/demo"
git -C "$ospec_repo2" init -q
git -C "$ospec_repo2" config user.email "test@example.com"
git -C "$ospec_repo2" config user.name "Test"

cat > "$ospec_repo2/openspec/specs/widget/spec.md" <<'EOF'
## Requirements

### Requirement: Widget deletion
The system SHALL allow deleting a widget by id.
EOF
cat > "$ospec_repo2/openspec/changes/demo/proposal.md" <<'EOF'
# Proposal

Original proposal text.
EOF
cat > "$ospec_repo2/openspec/changes/demo/tasks.md" <<'EOF'
## 1. Tasks

- [ ] 1.1 Do the thing
EOF
git -C "$ospec_repo2" add -A
git -C "$ospec_repo2" commit -q -m "baseline"
ospec2_base_sha="$(git -C "$ospec_repo2" rev-parse HEAD)"

cat > "$ospec_repo2/openspec/changes/demo/proposal.md" <<'EOF'
# Proposal

Updated proposal text.
EOF
rm "$ospec_repo2/openspec/changes/demo/tasks.md"

mkdir -p "$ospec_repo2/openspec/changes/demo/specs/widget"
cat > "$ospec_repo2/openspec/changes/demo/specs/widget/spec.md" <<'EOF'
## MODIFIED Requirements

### Requirement: Widget deletion
The system SHALL allow deleting a widget by id. Example error response:

```
## MODIFIED Requirements
### Requirement: This is not real, just an example inside a fence
```

The above is illustrative only.

#### Scenario: Delete succeeds
- **WHEN** a delete request is submitted
- **THEN** the widget is removed
EOF
git -C "$ospec_repo2" add -A

ospec2_diff_html="$out_dir/explain-openspec-fence-test.html"
(
  cd "$ospec_repo2" && python3 "$generate_explain" --diff --base "$ospec2_base_sha" --out "$ospec2_diff_html"
)
check "generate-explain.py exits 0 with a fenced-example delta spec in the diff" $?

ospec2_py_out="$(python3 - "$ospec2_diff_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = {n["path"]: n for n in manifest.get("nodes", [])}

spec_node = nodes.get("openspec/changes/demo/specs/widget/spec.md")
md = spec_node.get("md", "") if spec_node else ""

fenced_verbatim = "```\n## MODIFIED Requirements\n### Requirement: This is not real, just an example inside a fence\n```"
if fenced_verbatim in md:
    print("PASS: fenced pseudo-headings inside a requirement body survive verbatim, not treated as section boundaries")
else:
    print(f"FAIL: fenced content corrupted or misparsed — got {md!r}")

illus_idx = md.find("The above is illustrative only.")
currently_idx = md.find("**Currently:**")
if illus_idx != -1 and currently_idx != -1 and currently_idx > illus_idx:
    print("PASS: Currently:/This change: comparison is spliced after the fenced block, not inside it")
else:
    print(f"FAIL: comparison splice position wrong — illustrative@{illus_idx}, Currently@{currently_idx}")

if spec_node and spec_node.get("badge") == "MODIFIED":
    print("PASS: a fenced pseudo-heading example does not corrupt the delta badge")
else:
    print(f"FAIL: badge — got {spec_node.get('badge') if spec_node else None}")

if md.startswith("1 modified") and "1 added" not in md.splitlines()[0] and "1 removed" not in md.splitlines()[0]:
    print("PASS: summary counts ignore fenced pseudo-requirement/section text")
else:
    print(f"FAIL: summary counts — got {md.splitlines()[0] if md else '(empty)'}")

proposal_node = nodes.get("openspec/changes/demo/proposal.md")
if (proposal_node and proposal_node.get("kind") == "markdown" and "badge" not in proposal_node
        and "Updated proposal text." in proposal_node.get("md", "")):
    print("PASS: proposal.md is path-detected as OpenSpec via --diff and renders its updated content, no badge")
else:
    print(f"FAIL: proposal.md via --diff — got {proposal_node}")

tasks_node = nodes.get("openspec/changes/demo/tasks.md")
if tasks_node and tasks_node.get("kind") == "diff" and tasks_node.get("badge") == "deleted":
    print("PASS: a deleted OpenSpec file stays a diff node with a deleted badge, never markdown")
else:
    print(f"FAIL: deleted OpenSpec file — got {tasks_node}")
PYEOF
)"
echo "$ospec2_py_out"
pass_count=$((pass_count + $(echo "$ospec2_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$ospec2_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# --doc mode: (a) a doc whose only delta-header text lives inside a fenced
# example (e.g. a doc *about* OpenSpec's own syntax) must not misfire a
# badge/summary, and (b) a delta spec reached via --doc must get the SAME
# MODIFIED-requirement baseline comparison --diff/--change already give
# (read_baseline is now wired for --doc too).
# ---------------------------------------------------------------------------
fenced_doc="$out_dir/fenced-example.md"
cat > "$fenced_doc" <<'EOF'
# How delta specs work

Here's an example of what a delta spec section looks like:

```
## ADDED Requirements

### Requirement: Example
Some example text.
```

That's the format OpenSpec expects.
EOF

fenced_doc_html="$out_dir/explain-fenced-doc-test.html"
(
  cd "$repo" && python3 "$generate_explain" --doc "$fenced_doc" --out "$fenced_doc_html"
)
check "generate-explain.py --doc exits 0 for a doc whose delta headers are only inside a code fence" $?

ospec_doc_html="$out_dir/explain-openspec-doc-test.html"
(
  cd "$ospec_repo" && python3 "$generate_explain" \
    --doc "openspec/changes/demo/specs/widget/spec.md" --out "$ospec_doc_html"
)
check "generate-explain.py --doc exits 0 against an OpenSpec delta spec path" $?

doc_py_out="$(python3 - "$fenced_doc_html" "$ospec_doc_html" <<'PYEOF'
import json
import sys

def manifest_of(path):
    content = open(path, encoding="utf-8").read()
    start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
    end = content.index(";</script>", start)
    return json.loads(content[start:end])

fenced_nodes = manifest_of(sys.argv[1]).get("nodes", [])
fenced_node = next((n for n in fenced_nodes if n.get("path", "").endswith("fenced-example.md")), None)
if fenced_node is not None and "badge" not in fenced_node:
    print("PASS: delta headers appearing only inside a fenced code example don't trigger a badge/summary via --doc")
else:
    print(f"FAIL: fenced-example doc unexpectedly got a badge — {fenced_node}")

doc_nodes = manifest_of(sys.argv[2]).get("nodes", [])
doc_node = next((n for n in doc_nodes if n.get("path", "").endswith("widget/spec.md")), None)
doc_md = doc_node.get("md", "") if doc_node else ""
if "**Currently:**" in doc_md and "cascade-delete its attachments" in doc_md:
    print("PASS: --doc mode also gets the MODIFIED-requirement baseline comparison, matching --diff/--change")
else:
    print(f"FAIL: --doc baseline comparison missing — got {doc_md!r}")
PYEOF
)"
echo "$doc_py_out"
pass_count=$((pass_count + $(echo "$doc_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$doc_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# Root-anchoring: --diff paths are always repo-root-relative (as `git diff`
# itself emits them), so the working-tree disk read for an OpenSpec file's
# content/baseline must resolve against the repo root, not the caller's cwd
# -- running from a subdirectory must not silently fall back to a raw diff.
# ---------------------------------------------------------------------------
ospec_subdir_html="$out_dir/explain-openspec-subdir-test.html"
(
  cd "$ospec_repo/src" && python3 "$generate_explain" --diff --base "$ospec_base_sha" --out "$ospec_subdir_html"
)
check "generate-explain.py --diff exits 0 when run from a repo subdirectory" $?

subdir_py_out="$(python3 - "$ospec_subdir_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = {n["path"]: n for n in manifest.get("nodes", [])}

spec_node = nodes.get("openspec/changes/demo/specs/widget/spec.md")
md = spec_node.get("md", "") if spec_node else ""
if spec_node and spec_node.get("kind") == "markdown" and "**Currently:**" in md:
    print("PASS: OpenSpec content + baseline comparison resolve correctly even when run from a repo subdirectory")
else:
    print(f"FAIL: subdirectory root-anchoring — got kind={spec_node.get('kind') if spec_node else 'MISSING NODE'}")
PYEOF
)"
echo "$subdir_py_out"
pass_count=$((pass_count + $(echo "$subdir_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$subdir_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# --diff --head <ref>: exercises the `git show ref:path` disk-read
# alternative (as opposed to every other OpenSpec case above, which reads
# the working tree via head=None) for the same enrichment.
# ---------------------------------------------------------------------------
git -C "$ospec_repo" commit -q -m "demo change"
ospec_head_sha="$(git -C "$ospec_repo" rev-parse HEAD)"

ospec_headref_html="$out_dir/explain-openspec-headref-test.html"
(
  cd "$ospec_repo" && python3 "$generate_explain" \
    --diff --base "$ospec_base_sha" --head "$ospec_head_sha" --out "$ospec_headref_html"
)
check "generate-explain.py --diff --head <ref> exits 0 against a committed OpenSpec change" $?

headref_py_out="$(python3 - "$ospec_headref_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = {n["path"]: n for n in manifest.get("nodes", [])}

spec_node = nodes.get("openspec/changes/demo/specs/widget/spec.md")
md = spec_node.get("md", "") if spec_node else ""
if (spec_node and spec_node.get("kind") == "markdown" and spec_node.get("badge") == "REMOVED"
        and "**Currently:**" in md):
    print("PASS: --head <ref> reads OpenSpec content + baseline via 'git show', not just the working tree")
else:
    print(f"FAIL: --head <ref> OpenSpec rendering — got {spec_node}")
PYEOF
)"
echo "$headref_py_out"
pass_count=$((pass_count + $(echo "$headref_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$headref_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# preview-fixture smoke check: proves the SHIPPED preview fixture's OpenSpec
# content (the baseline + delta spec preview.sh's own throwaway repo is built
# from) still exercises ADDED+MODIFIED+REMOVED+baseline-match end-to-end,
# reached the same way --change mode would. NOTE: this covers only that
# content, via --change -- it does NOT exercise preview.sh's own invocation
# (building the throwaway git repo, --diff-mode OpenSpec path detection, the
# fake-gh wiring, --blame/--explain-map/--doc/--code/--symbol/--issue/--pr) --
# nothing in CI runs preview.sh itself; a regression specific to that path
# would only surface by actually running it.
# ---------------------------------------------------------------------------
preview_fixture_dir="$script_dir/preview-fixture"
preview_smoke_html="$out_dir/explain-preview-smoke-test.html"
(
  cd "$preview_fixture_dir" && python3 "$generate_explain" \
    --change openspec/changes/demo --out "$preview_smoke_html"
)
check "generate-explain.py exits 0 against the shipped preview-fixture/" $?

preview_py_out="$(python3 - "$preview_smoke_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
end = content.index(";</script>", start)
manifest = json.loads(content[start:end])
nodes = {n["path"]: n for n in manifest.get("nodes", [])}

spec_node = nodes.get("openspec/changes/demo/specs/widget/spec.md")
md = spec_node.get("md", "") if spec_node else ""
if (spec_node and spec_node.get("badge") == "REMOVED" and "1 added" in md and "1 modified" in md
        and "1 removed" in md and "**Currently:**" in md and "cascade-delete" in md):
    print("PASS: shipped preview-fixture/ still exercises ADDED+MODIFIED+REMOVED+baseline-match end-to-end")
else:
    print(f"FAIL: preview-fixture smoke check — got {spec_node}")
PYEOF
)"
echo "$preview_py_out"
pass_count=$((pass_count + $(echo "$preview_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$preview_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# Default title: names what's actually being explained (branch, change dir)
# instead of the generic "Explain", when --title isn't passed.
# ---------------------------------------------------------------------------
title_branch_html="$out_dir/explain-title-branch-test.html"
(
  cd "$repo" && python3 "$generate_explain" --branch other-branch --out "$title_branch_html"
)
check "generate-explain.py --branch (no --title) exits 0" $?

title_change_html="$out_dir/explain-title-change-test.html"
(
  cd "$repo" && python3 "$generate_explain" --change "$repo/changes/demo" --out "$title_change_html"
)
check "generate-explain.py --change (no --title) exits 0" $?

# --head explicitly wins over --branch for the ACTUAL diff (see main()'s own resolution and
# --branch's help text) -- the title must reflect whichever one actually won, not just whichever
# was named --branch.
title_branch_head_html="$out_dir/explain-title-branch-head-test.html"
(
  cd "$repo" && python3 "$generate_explain" --diff --branch other-branch --head "$base_sha" --out "$title_branch_head_html"
)
check "generate-explain.py --branch with an explicit --head override exits 0" $?

title_py_out="$(python3 - "$title_branch_html" "$title_change_html" "$title_branch_head_html" "$base_sha" <<'PYEOF'
import json
import sys

def manifest_of(path):
    content = open(path, encoding="utf-8").read()
    start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
    end = content.index(";</script>", start)
    return json.loads(content[start:end])

branch_title = manifest_of(sys.argv[1]).get("title")
if branch_title == "Diff: other-branch":
    print("PASS: default title names the branch when --branch is used, not just 'Explain'")
else:
    print(f"FAIL: --branch default title — got {branch_title!r}")

change_title = manifest_of(sys.argv[2]).get("title")
if change_title == "demo":
    print("PASS: default title names the OpenSpec change dir when --change is used")
else:
    print(f"FAIL: --change default title — got {change_title!r}")

base_sha = sys.argv[4]
branch_head_title = manifest_of(sys.argv[3]).get("title")
if branch_head_title == f"Diff: {base_sha}":
    print("PASS: an explicit --head overriding --branch wins the title too, matching the actual diffed content")
else:
    print(f"FAIL: --branch+--head default title — got {branch_head_title!r}, expected 'Diff: {base_sha}'")
PYEOF
)"
echo "$title_py_out"
pass_count=$((pass_count + $(echo "$title_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$title_py_out" | grep -c '^FAIL:')))

# ---------------------------------------------------------------------------
# inject_manifest() shares html_shell.py with the walkthrough skill (issue-42)
# -- content containing "<!--" followed by "<script" would, under the old
# "</" -only escaping, put HTML's script-data tokenizer into double-escaped
# state and break the injected <script> tag open. explain is the consumer
# that actually ingests hostile third-party content (docs, diffs, issue
# bodies), so this needs its own regression coverage, not just walkthrough's.
# ---------------------------------------------------------------------------
hostile_doc="$out_dir/hostile-template.md"
cat > "$hostile_doc" <<'EOF'
# A doc quoting an HTML template

```html
<!--[if IE]><script src="shim.js"></script><![endif]-->
<div id="app"></div>
```
EOF

hostile_doc_html="$out_dir/explain-hostile-doc-test.html"
(
  cd "$repo" && python3 "$generate_explain" --doc "$hostile_doc" --out "$hostile_doc_html"
)
check "generate-explain.py --doc exits 0 for a doc quoting an HTML template with a script tag" $?

hostile_py_out="$(python3 - "$hostile_doc_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
payload = content[start:end]

if "<" not in payload:
    print("PASS: no raw angle bracket survives into the injected payload")
else:
    idx = payload.index("<")
    print(f"FAIL: raw angle bracket in the injected payload — {payload[idx - 40:idx + 40]!r}")

manifest = json.loads(payload)
node = next((n for n in manifest.get("nodes", []) if n.get("path", "").endswith("hostile-template.md")), None)
md = node.get("md", "") if node else ""
if "<!--[if IE]><script src=" in md and "</script>" in md:
    print("PASS: the escaped payload still parses back to the exact authored markdown, markup intact")
else:
    print(f"FAIL: markdown round-trip — got {md!r}")
PYEOF
)"
echo "$hostile_py_out"
pass_count=$((pass_count + $(echo "$hostile_py_out" | grep -c '^PASS:')))
fail_count=$((fail_count + $(echo "$hostile_py_out" | grep -c '^FAIL:')))

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
