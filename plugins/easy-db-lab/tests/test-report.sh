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

# --- setup-cluster.sh: --docs-only, wrapper guards, and the source-checkout guard ---

ws_docs="$tmp_root/docs-only"
bash "$bin/setup-cluster.sh" "$ws_docs" --docs-only --name "docs-only" >/dev/null 2>&1
expect_eq "docs-only: exits 0" "0" "$?"
expect_file "docs-only: writes the scaffold" "$ws_docs/docs/1-summary.md"
expect_no_file "docs-only: writes no wrapper" "$ws_docs/easy-db-lab"

ws_kept="$tmp_root/kept-wrapper"
mkdir -p "$ws_kept"
printf '#!/bin/sh\n# hand-made wrapper\n' > "$ws_kept/easy-db-lab"
chmod +x "$ws_kept/easy-db-lab"
before="$(cat "$ws_kept/easy-db-lab")"
bash "$bin/setup-cluster.sh" "$ws_kept" --docs-only --name kept >/dev/null 2>&1
expect_eq "docs-only: an existing wrapper is unchanged" "$before" "$(cat "$ws_kept/easy-db-lab")"
bash "$bin/setup-cluster.sh" "$ws_kept" "$stub_edb" --name kept >/dev/null 2>&1
expect_eq "wrapper: setup-cluster.sh never rewrites an existing wrapper" "$before" "$(cat "$ws_kept/easy-db-lab")"

ws_self="$tmp_root/self-wrapper"
mkdir -p "$ws_self"
printf '#!/bin/sh\n' > "$ws_self/easy-db-lab"
chmod +x "$ws_self/easy-db-lab"
out="$(bash "$bin/setup-cluster.sh" "$ws_self" "$ws_self/easy-db-lab" --name self 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "wrapper: a binary that is its own wrapper exits non-zero"; else fail "wrapper: a binary that is its own wrapper exits non-zero"; fi
expect_contains "wrapper: the refusal names the wrapper" "$out" "$ws_self/easy-db-lab"
expect_no_file "wrapper: the refusal writes nothing" "$ws_self/docs"

for gradle in settings.gradle.kts build.gradle.kts; do
  src="$tmp_root/checkout-$gradle"
  mkdir -p "$src/bin"
  printf '#!/bin/sh\n' > "$src/bin/easy-db-lab"
  chmod +x "$src/bin/easy-db-lab"
  touch "$src/$gradle"
  out="$(bash "$bin/setup-cluster.sh" "$src" --docs-only --name src 2>&1)"
  expect_eq "checkout: a source checkout with $gradle exits 1" "1" "$?"
  expect_contains "checkout: the refusal says to change to a workspace" "$out" "workspace"
  expect_no_file "checkout: the refusal writes nothing" "$src/docs"
done

out="$(bash "$bin/setup-cluster.sh" "$tmp_root/arm-dc" "$stub_edb" --name t --arm a="$plan_src" --dc dc1 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "arms: --arm with --dc exits non-zero"; else fail "arms: --arm with --dc exits non-zero"; fi
expect_contains "arms: --arm with --dc prints a usage message" "$out" "Usage"
expect_no_file "arms: --arm with --dc writes nothing" "$tmp_root/arm-dc"

ws_multi="$tmp_root/multi"
bash "$bin/setup-cluster.sh" "$ws_multi" "$stub_edb" --name multi --dc dc1 --dc dc2 >/dev/null 2>&1
expect_eq "multi-DC: setup-cluster.sh exits 0" "0" "$?"
if [[ -x "$ws_multi/dc1/easy-db-lab" && -x "$ws_multi/dc2/easy-db-lab" ]]; then
  pass "multi-DC: one wrapper per DC"
else
  fail "multi-DC: one wrapper per DC"
fi
expect_file "multi-DC: one shared docs scaffold" "$ws_multi/docs/1-summary.md"
expect_no_file "multi-DC: no arms marker" "$ws_multi/arms"

# --- setup-cluster.sh: the cross-cluster arms layout ---

td="$tmp_root/arms-test"
printf '# Plan template\n' > "$tmp_root/tpl.md"
printf '# Plan: baseline\n' > "$tmp_root/b.md"
printf '# Plan: candidate\n' > "$tmp_root/c.md"
bash "$bin/setup-cluster.sh" "$td" "$stub_edb" --name T --plan "$tmp_root/tpl.md" \
  --arm baseline="$tmp_root/b.md" --arm candidate="$tmp_root/c.md" >/dev/null 2>&1
expect_eq "arms: setup-cluster.sh exits 0" "0" "$?"
expect_eq "arms: the marker lists one arm per line" "baseline candidate" "$(tr '\n' ' ' < "$td/arms" 2>/dev/null | sed 's/ $//')"
for arm in baseline candidate; do
  if [[ -x "$td/$arm/easy-db-lab" ]]; then pass "arms: $arm has a wrapper"; else fail "arms: $arm has a wrapper"; fi
  for f in "3-plan-$arm.md" "4-journal-$arm.md" "5-issues-$arm.md"; do
    expect_file "arms: docs/$f exists" "$td/docs/$f"
  done
done
expect_no_file "arms: no wrapper at the test-dir root" "$td/easy-db-lab"
expect_eq "arms: --plan goes to docs/3-plan.md" "# Plan template" "$(cat "$td/docs/3-plan.md" 2>/dev/null)"
expect_eq "arms: --arm baseline goes to docs/3-plan-baseline.md" "# Plan: baseline" "$(cat "$td/docs/3-plan-baseline.md" 2>/dev/null)"
expect_eq "arms: --arm candidate goes to docs/3-plan-candidate.md" "# Plan: candidate" "$(cat "$td/docs/3-plan-candidate.md" 2>/dev/null)"
expect_file "arms: the coordinator has its own journal" "$td/docs/4-journal.md"
expect_file "arms: the coordinator has its own issues file" "$td/docs/5-issues.md"
appendix="$(sed -n '/^# Appendix/,$p' "$td/docs/SUMMARY.md" 2>/dev/null | grep '\](' | tr '\n' '|')"
expect_eq "arms: the SUMMARY.md Appendix lists the coordinator, then each arm" \
  "- [Plan](3-plan.md)|- [Coordinator journal](4-journal.md)|- [Coordinator issues](5-issues.md)|- [Plan: baseline](3-plan-baseline.md)|- [Journal: baseline](4-journal-baseline.md)|- [Issues: baseline](5-issues-baseline.md)|- [Plan: candidate](3-plan-candidate.md)|- [Journal: candidate](4-journal-candidate.md)|- [Issues: candidate](5-issues-candidate.md)|" \
  "$appendix"
expect_contains "arms: SUMMARY.md keeps the summary and evidence" "$(cat "$td/docs/SUMMARY.md" 2>/dev/null)" "- [Evidence](2-evidence.md)"

# --- detect-cluster-layout.sh ---

layout="$(bash "$bin/detect-cluster-layout.sh" "$td" 2>&1)"
expect_contains "layout: arms marker gives LAYOUT=arms" "$layout" "LAYOUT=arms"
expect_contains "layout: ARMS lists the arms" "$layout" 'ARMS="baseline candidate"'
expect_contains "layout: EDB_BASELINE" "$layout" "EDB_BASELINE=$td/baseline/easy-db-lab"
expect_contains "layout: EDB_CANDIDATE" "$layout" "EDB_CANDIDATE=$td/candidate/easy-db-lab"
expect_contains "layout: STATE_BASELINE" "$layout" "STATE_BASELINE=unprovisioned"
expect_contains "layout: STATE is unprovisioned with no arm up" "$layout" "STATE=unprovisioned"
touch "$td/candidate/state.json"
layout="$(bash "$bin/detect-cluster-layout.sh" "$td" 2>&1)"
expect_contains "layout: STATE_CANDIDATE is provisioned" "$layout" "STATE_CANDIDATE=provisioned"
expect_contains "layout: STATE is provisioned when any arm is" "$layout" "STATE=provisioned"
expect_not_contains "layout: arms mode is not multi" "$layout" "LAYOUT=multi"

ws_bin="$tmp_root/with-bin"
mkdir -p "$ws_bin/bin" "$ws_bin/dc1" "$ws_bin/dc2"
for d in bin dc1 dc2; do
  printf '#!/bin/sh\n' > "$ws_bin/$d/easy-db-lab"
  chmod +x "$ws_bin/$d/easy-db-lab"
done
layout="$(bash "$bin/detect-cluster-layout.sh" "$ws_bin" 2>&1)"
expect_contains "layout: multi-DC still detected" "$layout" "LAYOUT=multi"
expect_not_contains "layout: bin is not a DC" "$layout" "EDB_BIN="

# --- configure-multi-dc-seeds.sh ---

out="$(bash "$bin/configure-multi-dc-seeds.sh" "$td" --name T --dc baseline --dc candidate 2>&1)"
expect_eq "seeds: an arms marker makes the seeds script exit 1" "1" "$?"
expect_contains "seeds: the refusal names the arms marker" "$out" "arms marker"

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
