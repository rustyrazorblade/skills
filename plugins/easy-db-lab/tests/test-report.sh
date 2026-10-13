#!/usr/bin/env bash
# Behavioral test for the easy-db-lab lab report: the scaffold that setup-cluster.sh writes, the
# layout scripts, the graph, check, and export scripts, the docs Makefile, and the skill text. It
# needs mdbook and uv, and no cluster. A stub easy-db-lab binary and a stub Mimir stand in for the
# real ones. Prints PASS or FAIL per case and exits 0 only when every case passes. macOS bash 3.2
# compatible (no associative arrays, no mapfile). Touches nothing outside its own temp directory.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plugin="$(cd "$here/.." && pwd)"
bin="$plugin/bin"
scaffold="$plugin/scaffold"
fixtures="$here/fixtures"
stub_edb="$fixtures/bin/easy-db-lab"

pass_count=0
fail_count=0

pass() {
  echo "PASS: $1"
  pass_count=$((pass_count + 1))
}

fail() {
  echo "FAIL: $1"
  [[ -z "${2:-}" ]] || echo "      $2"
  fail_count=$((fail_count + 1))
}

expect_eq() { # desc expected actual
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

expect_contains() { # desc haystack needle
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected output to contain: $3" ;;
  esac
}

expect_not_contains() { # desc haystack needle
  case "$2" in
    *"$3"*) fail "$1" "expected output NOT to contain: $3" ;;
    *) pass "$1" ;;
  esac
}

expect_file() { # desc path
  if [[ -e "$2" ]]; then pass "$1"; else fail "$1" "missing: $2"; fi
}

expect_no_file() { # desc path
  if [[ -e "$2" ]]; then fail "$1" "unexpected: $2"; else pass "$1"; fi
}

for tool in mdbook uv; do
  command -v "$tool" >/dev/null 2>&1 || { echo "test-report: '$tool' is required but not on PATH." >&2; exit 1; }
done

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

# fixture_docs <dest> [overlay...]: copy the docs-agree tree to <dest>, then copy each overlay
# directory under fixtures/check/ over it. An overlay holds only the files that differ.
fixture_docs() {
  local dest="$1" overlay
  shift
  mkdir -p "$dest"
  cp -R "$fixtures/docs-agree/." "$dest/"
  for overlay in "$@"; do
    cp -R "$fixtures/check/$overlay/." "$dest/"
  done
}

# scaffold_only <file>: true when the file holds only headings, one-line comments, and blank
# lines.  This is the scaffold-only test in references/report-upload.md.
scaffold_only() {
  ! grep -v -E '^[[:space:]]*(#|<!--.*-->[[:space:]]*$|$)' "$1" >/dev/null
}

# --- scaffold: setup-cluster.sh on a new single-DC workspace ---

ws="$tmp_root/single"
plan_src="$tmp_root/plan-src.md"
printf '# Lab Plan: scaffold test\n\nStep one.\n' > "$plan_src"
out="$(bash "$bin/setup-cluster.sh" "$ws" "$stub_edb" --name lab-test --plan "$plan_src" 2>&1)"
expect_eq "scaffold: setup-cluster.sh exits 0" "0" "$?"
docs="$ws/docs"
for f in 1-summary.md 2-evidence.md 3-plan.md 4-journal.md 5-issues.md SUMMARY.md Makefile book.toml lab.css lab.mplstyle images data; do
  expect_file "scaffold: docs/$f exists" "$docs/$f"
done
for f in results.md plan.md journal.md issues.md; do
  expect_no_file "scaffold: no docs/$f" "$docs/$f"
done
expect_eq "scaffold: --plan is copied to docs/3-plan.md" "$(cat "$plan_src")" "$(cat "$docs/3-plan.md" 2>/dev/null)"
expect_contains "scaffold: setup-cluster.sh reports the plan tier" "$out" "$docs/3-plan.md"

for f in 1-summary.md 2-evidence.md 4-journal.md 5-issues.md; do
  if [[ -f "$docs/$f" ]] && scaffold_only "$docs/$f"; then
    pass "scaffold: $f holds only headings and comments"
  else
    fail "scaffold: $f holds only headings and comments"
  fi
done
expect_contains "scaffold: 2-evidence.md has Threats to validity" "$(cat "$docs/2-evidence.md" 2>/dev/null)" "## Threats to validity"

toml="$(cat "$docs/book.toml" 2>/dev/null)"
expect_contains "scaffold: book.toml title falls back to the cluster name" "$toml" 'title = "lab-test"'
expect_contains "scaffold: book.toml src is the docs dir" "$toml" 'src = "."'
expect_contains "scaffold: book.toml builds into report/" "$toml" 'build-dir = "report"'
expect_contains "scaffold: book.toml wires lab.css" "$toml" 'additional-css = ["lab.css"]'
expect_contains "scaffold: book.toml drops section numbers" "$toml" 'no-section-label = true'

expect_contains "scaffold: Makefile names the plugin bin" "$(cat "$docs/Makefile" 2>/dev/null)" "EDB_LAB_BIN ?= $bin"
expect_not_contains "scaffold: no placeholder is left in the Makefile" "$(cat "$docs/Makefile" 2>/dev/null)" "@EDB_LAB_BIN@"

summary_lines="$(grep -E '\]\(|^# ' "$docs/SUMMARY.md" 2>/dev/null | tr '\n' '|')"
expect_eq "scaffold: SUMMARY.md order is summary, evidence, Appendix" \
  "# Summary|[Summary](1-summary.md)|- [Evidence](2-evidence.md)|# Appendix|- [Plan](3-plan.md)|- [Journal](4-journal.md)|- [Issues](5-issues.md)|" \
  "$summary_lines"

# The kept-file rule: a second run keeps a tier file that already exists.
echo "kept entry" >> "$docs/4-journal.md"
bash "$bin/setup-cluster.sh" "$ws" "$stub_edb" --name lab-test >/dev/null 2>&1
expect_contains "scaffold: an existing 4-journal.md is kept" "$(cat "$docs/4-journal.md")" "kept entry"
expect_eq "scaffold: a rerun with no --plan keeps 3-plan.md" "$(cat "$plan_src")" "$(cat "$docs/3-plan.md")"

ws_noplan="$tmp_root/noplan"
bash "$bin/setup-cluster.sh" "$ws_noplan" "$stub_edb" --name lab-test >/dev/null 2>&1
expect_eq "scaffold: no --plan gives the 3-plan.md placeholder" \
  "$(cat "$scaffold/3-plan.md.template" 2>/dev/null)" "$(cat "$ws_noplan/docs/3-plan.md" 2>/dev/null)"

# --- scaffold: template naming and the house theme ---

misnamed=""
for f in "$scaffold"/*; do
  case "$f" in *.template) ;; *) misnamed="$misnamed $(basename "$f")" ;; esac
done
expect_eq "scaffold: every scaffold file is named <destination>.template" "" "$misnamed"
expect_file "scaffold: book.toml.template exists" "$scaffold/book.toml.template"
if grep -q '\[book\]' "$bin/setup-cluster.sh"; then
  fail "scaffold: setup-cluster.sh holds no book.toml heredoc"
else
  pass "scaffold: setup-cluster.sh holds no book.toml heredoc"
fi

css="$(cat "$docs/lab.css" 2>/dev/null)"
expect_contains "css: sticky table headers" "$css" "position: sticky"
expect_contains "css: zebra rows" "$css" "tbody tr:nth-child(even)"
for v in confirmed refuted inconclusive partial; do
  expect_contains "css: .verdict-$v badge" "$css" ".verdict-$v"
done
expect_contains "css: wider content column" "$css" "--content-max-width"
expect_contains "css: print styles" "$css" "@media print"

style="$(cat "$docs/lab.mplstyle" 2>/dev/null)"
expect_contains "style: names the palette source" "$style" "Okabe-Ito"
expect_contains "style: sets the colour cycle" "$style" "axes.prop_cycle"
expect_contains "style: sets the font size" "$style" "font.size"

mk="$(cat "$docs/Makefile" 2>/dev/null)"
expect_contains "make: all is check build export" "$mk" "all: check build export"
for t in build check export gate serve clean; do
  if grep -qE "^$t:" "$docs/Makefile" 2>/dev/null; then pass "make: target $t"; else fail "make: target $t"; fi
done

echo ""
echo "$pass_count passed, $fail_count failed"
if [[ $pass_count -eq 0 ]]; then
  echo "test-report: no case ran" >&2
  exit 1
fi
[[ $fail_count -eq 0 ]]
