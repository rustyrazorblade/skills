#!/usr/bin/env bash
# Behavioral test for the easy-db-lab lab report: the scaffold that setup-cluster.sh writes, the
# layout scripts, the graph, check, and export scripts, the docs Makefile, and the skill text. It
# needs mdbook, uv, jq, and curl, and no cluster. A stub easy-db-lab binary, a stub Mimir, and a stub
# Grafana stand in for the real ones. Prints PASS or FAIL per case and exits 0 only when every case
# passes. macOS bash 3.2 compatible (no associative arrays, no mapfile). Touches nothing outside
# its own temp directory.
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

for tool in mdbook uv jq curl; do
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
for f in 1-summary.md 2-evidence.md 3-plan.md 4-journal.md 5-issues.md SUMMARY.md Makefile book.toml lab.css images data; do
  expect_file "scaffold: docs/$f exists" "$docs/$f"
done
for f in results.md plan.md journal.md issues.md lab.mplstyle; do
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
expect_contains "scaffold: book.toml opens in the coal theme" "$toml" 'default-theme = "coal"'
expect_contains "scaffold: book.toml keeps the coal theme on a dark OS, to match the dark renders" "$toml" 'preferred-dark-theme = "coal"'

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
expect_contains "css: system UI font stack" "$css" "-apple-system, BlinkMacSystemFont"
expect_contains "css: numeric cells use tabular figures" "$css" "font-variant-numeric: tabular-nums"
expect_contains "css: an evidence block reads as a card" "$css" "h2:has(+ p > img)"
expect_contains "css: the Window, Query, and Data lines are muted" "$css" ".table-wrapper ~ p"
expect_contains "css: the dark themes get their own card colours" "$css" ".navy"
expect_contains "css: coal, the default theme, has its own designed palette" "$css" ".coal {"
expect_contains "css: fenced blocks sit on one panel colour" "$css" "background: var(--lab-code-bg)"
expect_contains "css: journal entries are separated by a rule" "$css" ".content main > h3 {"
expect_contains "css: print keeps a heading with its image" "$css" "break-after: avoid"
expect_contains "css: print drops shadows" "$css" "box-shadow: none"

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

# A bad --arm writes nothing: a path in the name, a missing plan, a reserved name, a duplicate.
while read -r label args; do
  dest="$tmp_root/arm-bad"
  rm -rf "$dest"
  # shellcheck disable=SC2086 # args holds several words
  out="$(bash "$bin/setup-cluster.sh" "$dest" "$stub_edb" --name t $args 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then pass "arms: $label exits non-zero"; else fail "arms: $label exits non-zero"; fi
  expect_no_file "arms: $label writes nothing" "$dest"
done <<EOF
--arm-../x --arm ../x=$plan_src
--arm-a=/no/such --arm a=/no/such
--arm-docs --arm docs=$plan_src
--arm-bin --arm bin=$plan_src
--arm-data --arm data=$plan_src
--arm-images --arm images=$plan_src
--arm-export --arm export=$plan_src
--arm-arms --arm arms=$plan_src
a-duplicate-arm --arm a=$plan_src --arm b=$plan_src --arm a=$plan_src
a-b-and-a_b --arm a-b=$plan_src --arm a_b=$plan_src
Base-and-base --arm Base=$plan_src --arm base=$plan_src
--arm-Docs --arm Docs=$plan_src
EOF
out="$(bash "$bin/setup-cluster.sh" "$tmp_root/arm-collide" "$stub_edb" --name t --arm a-b="$plan_src" --arm a_b="$plan_src" 2>&1)"
expect_contains "arms: the a-b and a_b refusal names both arms" "$out" "arm names a-b and a_b collide"
out="$(bash "$bin/setup-cluster.sh" "$tmp_root/arm-collide" "$stub_edb" --name t --arm Base="$plan_src" --arm base="$plan_src" 2>&1)"
expect_contains "arms: the Base and base refusal names both arms" "$out" "arm names Base and base collide"
out="$(bash "$bin/setup-cluster.sh" "$tmp_root/arm-dup" "$stub_edb" --name t --arm a="$plan_src" --arm a="$plan_src" 2>&1)"
expect_contains "arms: the duplicate refusal names the arm" "$out" "duplicate arm name: a"
out="$(bash "$bin/setup-cluster.sh" "$tmp_root/arm-docs" "$stub_edb" --name t --arm docs="$plan_src" 2>&1)"
expect_contains "arms: the reserved refusal names the arm" "$out" "reserved arm name: docs"

# The kept-file rule holds for an arm: a rerun with --arm keeps an appended journal line.
echo "kept arm entry" >> "$td/docs/4-journal-baseline.md"
bash "$bin/setup-cluster.sh" "$td" "$stub_edb" --name T --arm baseline="$tmp_root/b.md" --arm candidate="$tmp_root/c.md" >/dev/null 2>&1
expect_contains "arms: a rerun keeps docs/4-journal-baseline.md" "$(cat "$td/docs/4-journal-baseline.md")" "kept arm entry"

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

# make_arms <dir> <arm>...: an arms marker listing each arm, and a wrapper for each arm.
make_arms() {
  local dir="$1" arm
  shift
  mkdir -p "$dir"
  : > "$dir/arms"
  for arm in "$@"; do
    printf '%s\n' "$arm" >> "$dir/arms"
    mkdir -p "$dir/$arm"
    printf '#!/bin/sh\n' > "$dir/$arm/easy-db-lab"
    chmod +x "$dir/$arm/easy-db-lab"
  done
}

make_arms "$tmp_root/arms-canary" baseline canary-1
layout="$(bash "$bin/detect-cluster-layout.sh" "$tmp_root/arms-canary" 2>&1)"
expect_contains "layout: the arm canary-1 gives EDB_CANARY_1" "$layout" "EDB_CANARY_1=$tmp_root/arms-canary/canary-1/easy-db-lab"
expect_contains "layout: the arm canary-1 gives STATE_CANARY_1" "$layout" "STATE_CANARY_1=unprovisioned"

make_arms "$tmp_root/arms-ghost" baseline
printf 'ghost\n' >> "$tmp_root/arms-ghost/arms"
layout="$(bash "$bin/detect-cluster-layout.sh" "$tmp_root/arms-ghost" 2>&1)"
expect_eq "layout: an arm with no wrapper exits 1" "1" "$?"
expect_contains "layout: the refusal names the arm with no wrapper" "$layout" "ghost"

make_arms "$tmp_root/arms-empty"
layout="$(bash "$bin/detect-cluster-layout.sh" "$tmp_root/arms-empty" 2>&1)"
expect_eq "layout: an empty arms marker exits 1" "1" "$?"
expect_contains "layout: the refusal says the marker lists no arm" "$layout" "lists no arm"

# Two marker arms that map to one EDB_ variable: a-b and a_b, and Base and base.
for pair in 'a-b a_b' 'Base base'; do
  # shellcheck disable=SC2086 # pair holds two arm names
  make_arms "$tmp_root/arms-collide" $pair
  layout="$(bash "$bin/detect-cluster-layout.sh" "$tmp_root/arms-collide" 2>&1)"
  expect_eq "layout: the marker arms $pair exit 1" "1" "$?"
  expect_contains "layout: the refusal for $pair names both arms" "$layout" "arm names ${pair% *} and ${pair#* } collide"
  expect_not_contains "layout: the marker arms $pair print no LAYOUT" "$layout" "LAYOUT="
  expect_not_contains "layout: the marker arms $pair print no EDB_ line for the first arm" "$layout" "EDB_$(echo "${pair% *}" | tr '[:lower:]-' '[:upper:]_')="
  rm -rf "$tmp_root/arms-collide"
done

# A hand-written marker can name a reserved directory; the refusal prints no EDB_ line at all.
for reserved in docs Docs bin data images export arms; do
  setup_err="$(
    {
      make_arms "$tmp_root/arms-reserved" baseline
      # arms is the marker file itself, so it cannot hold a wrapper; the marker line alone is refused.
      if [[ "$reserved" != arms ]]; then
        mkdir -p "$tmp_root/arms-reserved/$reserved"
        printf '#!/bin/sh\n' > "$tmp_root/arms-reserved/$reserved/easy-db-lab"
        chmod +x "$tmp_root/arms-reserved/$reserved/easy-db-lab"
      fi
      printf '%s\n' "$reserved" >> "$tmp_root/arms-reserved/arms"
    } 2>&1
  )"
  expect_not_contains "layout: the reserved arm $reserved setup gives no File exists" "$setup_err" "File exists"
  expect_not_contains "layout: the reserved arm $reserved setup gives no Not a directory" "$setup_err" "Not a directory"
  layout="$(bash "$bin/detect-cluster-layout.sh" "$tmp_root/arms-reserved" 2>&1)"
  expect_eq "layout: the reserved arm $reserved in the marker exits 1" "1" "$?"
  expect_contains "layout: the refusal names the reserved arm $reserved" "$layout" "reserved arm name: $reserved"
  expect_not_contains "layout: the reserved arm $reserved prints no EDB_ line" "$layout" "EDB_BASELINE="
  rm -rf "$tmp_root/arms-reserved"
done
layout="$(bash "$bin/detect-cluster-layout.sh" "$tmp_root/arms-ghost" 2>&1)"
expect_not_contains "layout: an arm with no wrapper prints no EDB_ line" "$layout" "EDB_BASELINE="

# shellcheck disable=SC2016 # a literal $( ) in an arm name
for bad in '../x' 'a;b' 'a$(id)'; do
  make_arms "$tmp_root/arms-bad" baseline
  mkdir -p "$tmp_root/arms-bad/$bad"
  printf '#!/bin/sh\n' > "$tmp_root/arms-bad/$bad/easy-db-lab"
  chmod +x "$tmp_root/arms-bad/$bad/easy-db-lab"
  printf '%s\n' "$bad" >> "$tmp_root/arms-bad/arms"
  layout="$(bash "$bin/detect-cluster-layout.sh" "$tmp_root/arms-bad" 2>&1)"
  expect_eq "layout: the arm name $bad in the marker exits 1" "1" "$?"
  expect_not_contains "layout: the arm name $bad prints no variable" "$layout" "LAYOUT="
  expect_not_contains "layout: the arm name $bad prints no EDB_ line" "$layout" "EDB_BASELINE="
  rm -rf "$tmp_root/arms-bad"
done

# The output is eval-safe: a cluster dir with a space and a $ in its name, and the DCS list.
odd="$tmp_root/odd \$dir"
make_arms "$odd" baseline
# shellcheck disable=SC2016 # the eval runs in the child shell
got="$(bash -c 'eval "$("$1" "$2")" && printf "%s" "$EDB_BASELINE"' _ "$bin/detect-cluster-layout.sh" "$odd" 2>&1)"
expect_eq "layout: eval keeps an arm wrapper path with a space and a \$" "$odd/baseline/easy-db-lab" "$got"
mkdir -p "$odd-multi/dc1" "$odd-multi/dc2"
for d in dc1 dc2; do
  printf '#!/bin/sh\n' > "$odd-multi/$d/easy-db-lab"
  chmod +x "$odd-multi/$d/easy-db-lab"
done
# shellcheck disable=SC2016 # the eval runs in the child shell
got="$(bash -c 'eval "$("$1" "$2")" && printf "%s|%s" "$DCS" "$EDB_DC1"' _ "$bin/detect-cluster-layout.sh" "$odd-multi" 2>&1)"
expect_eq "layout: eval keeps DCS and a DC wrapper path with a space" "dc1 dc2|$odd-multi/dc1/easy-db-lab" "$got"
# shellcheck disable=SC2016 # run/SKILL.md evals the output unquoted
got="$(bash -c 'eval $("$1" "$2") && printf "%s|%s" "$DCS" "$STATE"' _ "$bin/detect-cluster-layout.sh" "$ws_multi" 2>&1)"
expect_eq "layout: the unquoted eval in run/SKILL.md sets DCS and STATE" "dc1 dc2|unprovisioned" "$got"

# --- configure-multi-dc-seeds.sh ---

out="$(bash "$bin/configure-multi-dc-seeds.sh" "$td" --name T --dc baseline --dc candidate 2>&1)"
expect_eq "seeds: an arms marker makes the seeds script exit 1" "1" "$?"
expect_contains "seeds: the refusal names the arms marker" "$out" "arms marker"

# --- report-graph.py fetch ---

graph="$bin/report-graph.py"
gws="$tmp_root/graph-ws"
bash "$bin/setup-cluster.sh" "$gws" "$stub_edb" --name graph >/dev/null 2>&1
gdocs="$gws/docs"

mimir_pid=""
# start_mimir <response.json> <http-status>: start the stub Mimir and set mimir_url and mimir_log.
start_mimir() {
  local port_file="$tmp_root/mimir.port"
  mimir_log="$tmp_root/mimir.log"
  rm -f "$port_file" "$mimir_log"
  python3 "$fixtures/mimir/stub.py" "$1" "$2" "$port_file" "$mimir_log" &
  mimir_pid=$!
  local _
  for _ in $(seq 1 50); do
    [[ -s "$port_file" ]] && break
    sleep 0.1
  done
  mimir_url="http://127.0.0.1:$(cat "$port_file")/prometheus"
}
stop_mimir() {
  [[ -z "$mimir_pid" ]] || kill "$mimir_pid" 2>/dev/null
  wait "$mimir_pid" 2>/dev/null
  mimir_pid=""
}
socks_pid=""
# A dead SOCKS proxy: nothing listens on port 1.
dead_proxy="socks5h://127.0.0.1:1"
# start_socks: start the stub SOCKS5 forwarder and set socks_proxy and socks_log.  If the stub does
# not start, the case fails, and the log holds the cause, so each live case reports it.
start_socks() {
  local port_file="$tmp_root/socks.port"
  socks_log="$tmp_root/socks.log"
  rm -f "$port_file" "$socks_log"
  python3 "$fixtures/socks/forwarder.py" "$port_file" "$socks_log" &
  socks_pid=$!
  local _
  for _ in $(seq 1 50); do
    [[ -s "$port_file" ]] && break
    sleep 0.1
  done
  if [[ -s "$port_file" ]]; then
    socks_proxy="socks5h://127.0.0.1:$(cat "$port_file")"
  else
    fail "socks: the stub SOCKS5 forwarder starts" "socks stub did not start"
    echo "socks stub did not start" > "$socks_log"
    socks_proxy="$dead_proxy"
  fi
}
stop_socks() {
  [[ -z "$socks_pid" ]] || kill "$socks_pid" 2>/dev/null
  wait "$socks_pid" 2>/dev/null
  socks_pid=""
}
trap 'stop_mimir; stop_socks; rm -rf "$tmp_root"' EXIT

# fetch <mimir-url> <name> [extra args...]: run fetch on the graph workspace with the usual window
# and fetch_query, which filters on this cluster's label.
fetch_query='sum by (instance) (rate(jvm_gc_memory_allocated_bytes_total{cluster="graph-1a2b",instance=~"db.*"}[1m]))'
fetch() {
  local url="$1" name="$2"
  shift 2
  "$graph" fetch --mimir-url "$url" --tenant lab-tenant --query "$fetch_query" \
    --start 2026-10-01T10:00:00Z --end 2026-10-01T10:10:00Z --step 30s \
    --node-label instance --unit MB/s --scale 1e-6 --name "$name" --docs "$gdocs" "$@"
}

out="$(fetch http://127.0.0.1:1/prometheus unreachable --arm baseline=db0 --arm candidate=db2 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "fetch: an unreachable Mimir exits non-zero"; else fail "fetch: an unreachable Mimir exits non-zero"; fi
expect_contains "fetch: an unreachable Mimir gives a clear message" "$out" "cannot reach Mimir"
expect_no_file "fetch: an unreachable Mimir writes no CSV" "$gdocs/data/unreachable.csv"

# A tenant holds many clusters, so a query with no cluster matcher can return another cluster's series.
start_mimir "$fixtures/mimir/ok.json" 200
saved_query="$fetch_query"
fetch_query='sum by (instance) (rate(jvm_gc_memory_allocated_bytes_total{instance=~"db.*"}[1m]))'
out="$(fetch "$mimir_url" no-cluster --arm baseline=db0 --arm candidate=db2 2>&1)"
rc=$?
fetch_query="$saved_query"
stop_mimir
if [[ $rc -ne 0 ]]; then pass "fetch: a query with no cluster matcher is refused"; else fail "fetch: a query with no cluster matcher is refused"; fi
expect_contains "fetch: the refusal names the cluster matcher" "$out" 'cluster="'
expect_no_file "fetch: the cluster refusal writes no CSV" "$gdocs/data/no-cluster.csv"
expect_eq "fetch: the cluster refusal sends no request" "" "$(cat "$mimir_log" 2>/dev/null)"

start_mimir "$fixtures/mimir/empty.json" 200
out="$(fetch "$mimir_url" empty --arm baseline=db0 --arm candidate=db2 2>&1)"
rc=$?
stop_mimir
if [[ $rc -ne 0 ]]; then pass "fetch: zero series exits non-zero"; else fail "fetch: zero series exits non-zero"; fi
expect_contains "fetch: zero series gives a clear message" "$out" "no series"
expect_no_file "fetch: zero series writes no CSV" "$gdocs/data/empty.csv"

start_mimir "$fixtures/mimir/error.json" 400
out="$(fetch "$mimir_url" bad-query --arm baseline=db0 --arm candidate=db2 2>&1)"
rc=$?
stop_mimir
if [[ $rc -ne 0 ]]; then pass "fetch: a non-success status exits non-zero"; else fail "fetch: a non-success status exits non-zero"; fi
expect_contains "fetch: a non-success status shows the Mimir error" "$out" "parse error"
expect_no_file "fetch: a non-success status writes no CSV" "$gdocs/data/bad-query.csv"

start_mimir "$fixtures/mimir/ip-node.json" 200
out="$(fetch "$mimir_url" ip-node --arm baseline=db0 --arm candidate=db2 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "fetch: an unmapped IPv4 node value is refused"; else fail "fetch: an unmapped IPv4 node value is refused"; fi
expect_contains "fetch: the refusal says to map the node" "$out" "--node"
expect_no_file "fetch: the refusal writes no CSV" "$gdocs/data/ip-node.csv"
out="$(fetch "$mimir_url" ip-node --node 10.0.1.15:9500=db0 --arm baseline=db0 --arm candidate=db2 2>&1)"
expect_eq "fetch: a --node mapping covers an IPv4 node value" "0" "$?"
expect_not_contains "fetch: the mapped CSV holds no IP" "$(cat "$gdocs/data/ip-node.csv" 2>/dev/null)" "10.0.1.15"
stop_mimir

start_mimir "$fixtures/mimir/ec2-node.json" 200
out="$(fetch "$mimir_url" ec2-node --arm baseline=db0 --arm candidate=db2 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "fetch: an unmapped EC2 host name node value is refused"; else fail "fetch: an unmapped EC2 host name node value is refused"; fi
expect_contains "fetch: the EC2 refusal says to map the node" "$out" "--node"
expect_no_file "fetch: the EC2 refusal writes no CSV" "$gdocs/data/ec2-node.csv"
out="$(fetch "$mimir_url" ec2-node --node ip-10-0-1-15.us-west-2.compute.internal:9500=db0 --arm baseline=db0 --arm candidate=db2 2>&1)"
expect_eq "fetch: a --node mapping covers an EC2 host name node value" "0" "$?"
expect_not_contains "fetch: the mapped CSV holds no EC2 host name" "$(cat "$gdocs/data/ec2-node.csv" 2>/dev/null)" "ip-10-0-1-15"
stop_mimir

start_mimir "$fixtures/mimir/ok.json" 200
out="$(fetch "$mimir_url" lonely --arm baseline=db0 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "fetch: a node in no --arm is refused"; else fail "fetch: a node in no --arm is refused"; fi
expect_contains "fetch: the refusal names the node" "$out" "db2"
out="$(fetch "$mimir_url" scrape-alloc --arm baseline=db0 --arm candidate=db2 2>&1)"
expect_eq "fetch: a good response exits 0" "0" "$?"
stop_mimir
csv="$(cat "$gdocs/data/scrape-alloc.csv" 2>/dev/null)"
json="$(cat "$gdocs/data/scrape-alloc.json" 2>/dev/null)"
expect_eq "fetch: the CSV is long form" "timestamp_utc,node,arm,value" "$(head -n 1 "$gdocs/data/scrape-alloc.csv" 2>/dev/null)"
expect_contains "fetch: the CSV holds scaled values with the arm" "$csv" ",db0,baseline,26.92"
expect_contains "fetch: the CSV holds the candidate arm" "$csv" ",db2,candidate,32.72"
for key in query start end step unit scale arms; do
  expect_contains "fetch: the JSON holds $key" "$json" "\"$key\""
done
expect_contains "fetch: the JSON holds the unit" "$json" '"MB/s"'
expect_not_contains "fetch: the JSON holds no Mimir URL" "$json" "127.0.0.1"
expect_not_contains "fetch: the JSON holds no tenant" "$json" "lab-tenant"
expect_not_contains "fetch: the CSV holds no tenant" "$csv" "lab-tenant"
req="$(cat "$mimir_log" 2>/dev/null)"
expect_contains "fetch: the request goes to query_range under the Mimir URL" "$req" "/prometheus/api/v1/query_range?"
expect_contains "fetch: the request sends the tenant header" "$req" "tenant=lab-tenant"
expect_contains "fetch: the request sends the step" "$req" "step=30"

# --proxy: the request goes through the proxy.  A dead proxy is a reach failure, not a missing
# SOCKS dependency, and the request never gets to Mimir.
start_mimir "$fixtures/mimir/ok.json" 200
out="$(fetch "$mimir_url" dead-proxy --arm baseline=db0 --arm candidate=db2 --proxy "$dead_proxy" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "fetch: a dead --proxy exits non-zero"; else fail "fetch: a dead --proxy exits non-zero"; fi
expect_contains "fetch: a dead --proxy gives the reach message" "$out" "cannot reach Mimir"
expect_not_contains "fetch: a dead --proxy is not a missing SOCKS dependency" "$out" "Missing dependencies"
expect_not_contains "fetch: a dead --proxy is not an import error" "$out" "ImportError"
expect_eq "fetch: a dead --proxy sends no request to Mimir" "" "$(cat "$mimir_log" 2>/dev/null)"
expect_no_file "fetch: a dead --proxy writes no CSV" "$gdocs/data/dead-proxy.csv"
start_socks
out="$(fetch "$mimir_url" via-proxy --arm baseline=db0 --arm candidate=db2 --proxy "$socks_proxy" 2>&1)"
expect_eq "fetch: a live --proxy exits 0" "0" "$?"
stop_socks
mimir_hostport="${mimir_url#http://}"
expect_eq "fetch: a live --proxy connects to Mimir through the proxy" "${mimir_hostport%%/*}" "$(cat "$socks_log" 2>/dev/null)"
expect_contains "fetch: a live --proxy request gets to Mimir" "$(cat "$mimir_log" 2>/dev/null)" "/api/v1/query_range?"
stop_mimir
rm -f "$gdocs/data/via-proxy.csv" "$gdocs/data/via-proxy.json"

# The stub forwarder refuses a CONNECT to a closed port with SOCKS5 reply 05, connection refused,
# and does not drop the client.  The client prints the reply field, or "closed" for no reply.
start_socks
reply="$(python3 - "${socks_proxy##*:}" <<'EOF' 2>&1
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5)
s.sendall(b"\x05\x01\x00")
s.recv(2)
s.sendall(b"\x05\x01\x00\x01" + socket.inet_aton("127.0.0.1") + (1).to_bytes(2, "big"))
r = s.recv(10)
print(f"{r[1]:02x}" if len(r) >= 2 else "closed")
EOF
)"
stop_socks
expect_eq "socks stub: a CONNECT to a closed port gets reply 05, connection refused" "05" "$reply"

# --- report-graph.py render ---

grafana_pid=""
# start_grafana <mode> [dashboard.json]: start the stub Grafana and set grafana_url and grafana_log.
start_grafana() {
  local port_file="$tmp_root/grafana.port"
  grafana_log="$tmp_root/grafana.log"
  rm -f "$port_file" "$grafana_log"
  python3 "$fixtures/grafana/stub.py" "$1" "$port_file" "$grafana_log" ${2:+"$2"} &
  grafana_pid=$!
  local _
  for _ in $(seq 1 50); do
    [[ -s "$port_file" ]] && break
    sleep 0.1
  done
  grafana_url="http://127.0.0.1:$(cat "$port_file")"
}
stop_grafana() {
  [[ -z "$grafana_pid" ]] || kill "$grafana_pid" 2>/dev/null
  wait "$grafana_pid" 2>/dev/null
  grafana_pid=""
}
trap 'stop_mimir; stop_socks; stop_grafana; rm -rf "$tmp_root"' EXIT

# render <grafana-url> <name> [extra args...]: render panel 7 of one dashboard over the usual window.
render() {
  local url="$1" name="$2"
  shift 2
  "$graph" render --grafana-url "$url" --dashboard cassandra-overview --panel 7 \
    --from 2026-10-01T10:00:00Z --to 2026-10-01T10:10:00Z --name "$name" --docs "$gdocs" "$@"
}
panel_png="$fixtures/grafana/panel.png"

start_grafana png
out="$(render "$grafana_url" panel --var cluster=graph-1a2b --var "job=a b" 2>&1)"
expect_eq "render: a 200 PNG exits 0" "0" "$?"
if cmp -s "$panel_png" "$gdocs/images/panel.png"; then
  pass "render: writes the body byte for byte to images/<name>.png"
else
  fail "render: writes the body byte for byte to images/<name>.png" "$out"
fi
req="$(cat "$grafana_log" 2>/dev/null)"
expect_eq "render: one GET per render" "1" "$(grep -c . "$grafana_log" 2>/dev/null)"
expect_contains "render: the request goes to /render/d-solo/<UID>/" "$req" "/render/d-solo/cassandra-overview/?"
for p in panelId=7 from=1790848800000 to=1790849400000 var-cluster=graph-1a2b var-job=a+b width=1200 height=600 tz=UTC theme=dark; do
  expect_contains "render: the request holds $p" "$req" "$p"
done
expect_eq "render: no file in docs/ holds the Grafana URL" "" "$(grep -rl "${grafana_url#http://}" "$gdocs" 2>/dev/null)"

rm -f "$grafana_log"
out="$(render "$grafana_url" relative --from now-93600s --to now 2>&1)"
expect_eq "render: a relative range exits 0" "0" "$?"
req="$(cat "$grafana_log" 2>/dev/null)"
expect_contains "render: now-93600s goes out unchanged" "$req" "from=now-93600s&"
expect_contains "render: now goes out unchanged" "$req" "to=now&"

# The render matches the dark report page by default; --theme light asks for the light theme.
rm -f "$grafana_log"
out="$(render "$grafana_url" light --theme light 2>&1)"
expect_eq "render: --theme light exits 0" "0" "$?"
req="$(cat "$grafana_log" 2>/dev/null)"
expect_contains "render: --theme light sends theme=light" "$req" "theme=light"
expect_not_contains "render: --theme light sends no theme=dark" "$req" "theme=dark"

rm -f "$grafana_log"
out="$(render "$grafana_url" bad-theme --theme blue 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "render: --theme blue is refused"; else fail "render: --theme blue is refused"; fi
expect_eq "render: the theme refusal sends no request" "" "$(cat "$grafana_log" 2>/dev/null)"

rm -f "$grafana_log"
out="$(render "$grafana_url" bad-time --from yesterday 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "render: a time that is neither ISO nor relative is refused"; else fail "render: a time that is neither ISO nor relative is refused"; fi
expect_contains "render: the time refusal names the time" "$out" "yesterday"
expect_eq "render: the time refusal sends no request" "" "$(cat "$grafana_log" 2>/dev/null)"

# --name is a file name under images/, as for fetch.
for bad in '../x' 'a/b' '..' '.hidden' 'a..b'; do
  rm -f "$grafana_log"
  out="$(render "$grafana_url" "$bad" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then pass "render: --name $bad is refused"; else fail "render: --name $bad is refused"; fi
  expect_contains "render: the --name $bad refusal names the rule" "$out" "--name"
  expect_eq "render: --name $bad is refused before the request" "" "$(cat "$grafana_log" 2>/dev/null)"
done
stop_grafana

out="$(render http://127.0.0.1:1 unreachable 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "render: an unreachable Grafana exits non-zero"; else fail "render: an unreachable Grafana exits non-zero"; fi
expect_contains "render: an unreachable Grafana gives a clear message" "$out" "cannot reach Grafana"
expect_no_file "render: an unreachable Grafana writes no image" "$gdocs/images/unreachable.png"

# render_fails <mode> <message>: a failed render exits non-zero, names the cause, writes no image,
# and leaves an existing image with the same --name unchanged.
render_fails() {
  local mode="$1" msg="$2"
  start_grafana "$mode"
  out="$(render "$grafana_url" "fail-$mode" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then pass "render: the $mode response exits non-zero"; else fail "render: the $mode response exits non-zero"; fi
  expect_contains "render: the $mode response names the cause" "$out" "$msg"
  expect_no_file "render: the $mode response writes no image" "$gdocs/images/fail-$mode.png"
  printf 'old image\n' > "$gdocs/images/keep.png"
  render "$grafana_url" keep >/dev/null 2>&1
  expect_eq "render: the $mode response leaves the old image unchanged" "old image" "$(cat "$gdocs/images/keep.png")"
  stop_grafana
}
render_fails 500 "HTTP 500"
render_fails empty "empty body"
render_fails notpng "not a PNG"

# --proxy, as for fetch: a dead proxy is a reach failure that never gets to Grafana.
start_grafana png
out="$(render "$grafana_url" dead-proxy --proxy "$dead_proxy" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "render: a dead --proxy exits non-zero"; else fail "render: a dead --proxy exits non-zero"; fi
expect_contains "render: a dead --proxy gives the reach message" "$out" "cannot reach Grafana"
expect_not_contains "render: a dead --proxy is not a missing SOCKS dependency" "$out" "Missing dependencies"
expect_not_contains "render: a dead --proxy is not an import error" "$out" "ImportError"
expect_eq "render: a dead --proxy sends no request to Grafana" "" "$(cat "$grafana_log" 2>/dev/null)"
expect_no_file "render: a dead --proxy writes no image" "$gdocs/images/dead-proxy.png"
start_socks
out="$(render "$grafana_url" via-proxy --proxy "$socks_proxy" 2>&1)"
expect_eq "render: a live --proxy exits 0" "0" "$?"
stop_socks
expect_eq "render: a live --proxy connects to Grafana through the proxy" "${grafana_url#http://}" "$(cat "$socks_log" 2>/dev/null)"
expect_contains "render: a live --proxy request gets to Grafana" "$(cat "$grafana_log" 2>/dev/null)" "/render/d-solo/cassandra-overview/?"
stop_grafana
rm -f "$gdocs/images/via-proxy.png"
rm -f "$gdocs/images/keep.png" "$gdocs/images/panel.png" "$gdocs/images/relative.png"

# --- report-graph.py block ---

# block reads CSVs from <docs>/data, as fetch writes them, and images from <docs>/images, as render
# writes them.
cp "$fixtures/graph/"* "$gdocs/data/"
gfix="$gdocs/data"
gimg="$gdocs/images"
for i in scrape-alloc counter tiny read-latency arm-cluster nested throughput-baseline throughput-candidate; do
  cp "$panel_png" "$gimg/$i.png"
done

# docs_state: one line per file under the graph docs dir, with its checksum, so a case can prove
# that block wrote no file.
docs_state() { find "$gdocs" -type f -exec cksum {} + | sort; }

# block_err <args...>: run block, and set out (stdout), err (stderr), and rc.
block_err() {
  out="$("$graph" block "$@" 2>"$tmp_root/block.err")"
  rc=$?
  err="$(cat "$tmp_root/block.err")"
}

before="$(docs_state)"
out="$("$graph" block --csv "$gfix/baseline.csv" --csv "$gfix/candidate.csv" --image "$gimg/scrape-alloc.png" \
  --title "Scrape allocation (MB/s)" --docs "$gdocs" 2>&1)"
expect_eq "block: two arms exit 0" "0" "$?"
expect_eq "block: writes no file" "$before" "$(docs_state)"
expect_contains "block: the block starts with the heading" "$out" "## Scrape allocation (MB/s)"
expect_contains "block: the block cites the rendered image" "$out" "![Scrape allocation (MB/s)](images/scrape-alloc.png)"
expect_contains "block: the stats table has the default columns" "$out" "| Node | Arm | Samples | Min | p50 | Mean | p99 | Max | Unit |"
expect_contains "block: numeric columns are right-aligned" "$out" "|:--|:--|--:|--:|--:|--:|--:|--:|:--|"
expect_contains "block: a node row names the node with its role" "$out" "| db0 (baseline) | baseline | 21 | 26.92 |"
expect_contains "block: one rollup row per arm, from pooled samples" "$out" "| all | baseline | 42 | 26.92 | 27.09 | 27.09 | 27.27 | 27.27 | MB/s |"
expect_contains "block: the candidate rollup row" "$out" "| all | candidate | 21 | 32.72 |"
expect_contains "block: the block holds the Window" "$out" "Window: 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s"
expect_contains "block: the block holds the Query" "$out" 'Query: `sum by (instance)'
expect_contains "block: the Data line links every CSV" "$out" "Data: [baseline.csv](data/baseline.csv), [candidate.csv](data/candidate.csv)"
order="$(printf '%s\n' "$out" | grep -E '^(## |!\[|\| Node |Window|Query|Data: )' | cut -c1-6 | tr '\n' '|')"
expect_eq "block: heading, image, stats, Window, Query, Data, in that order" \
  "## Scr|![Scra|| Node|Window|Query:|Data: |" "$order"

out="$("$graph" block --csv "$gfix/baseline.csv" --image "$gimg/counter.png" --title "Counter" \
  --stats samples,total,rate --docs "$gdocs" 2>&1)"
expect_contains "block: --stats swaps the statistic columns" "$out" "| Node | Arm | Samples | Total | Rate | Unit |"
expect_contains "block: swapped columns stay right-aligned" "$out" "|:--|:--|--:|--:|--:|:--|"

out="$("$graph" block --csv "$gfix/tiny.csv" --image "$gimg/tiny.png" --title "Tiny" --stats samples,min,mean \
  --docs "$gdocs" 2>&1)"
expect_contains "block: a value below 1e-4 is fixed-point, which report-check reads" "$out" "| all | baseline | 2 | 0.00001234 | 0.00001234 | s |"

block_err --csv "$gfix/empty.csv" --image "$gimg/tiny.png" --title "Empty" --docs "$gdocs"
if [[ $rc -ne 0 ]]; then pass "block: empty input exits non-zero"; else fail "block: empty input exits non-zero"; fi
expect_contains "block: empty input gives a clear message" "$err" "no rows"
expect_eq "block: empty input prints no block" "" "$out"

for m in unit step query; do
  block_err --csv "$gfix/baseline.csv" --csv "$gfix/mismatch-$m.csv" --image "$gimg/tiny.png" --title "M" --docs "$gdocs"
  if [[ $rc -ne 0 ]]; then pass "block: a mismatched $m is an error"; else fail "block: a mismatched $m is an error"; fi
  expect_contains "block: the error names the $m" "$err" "$m"
  expect_eq "block: a mismatched $m prints no block" "" "$out"
done

block_err --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-candidate.csv" --image "$gimg/read-latency.png" \
  --title "Read latency (ms)" --docs "$gdocs"
if [[ $rc -ne 0 ]]; then pass "block: mismatched windows without --arm-windows are an error"; else fail "block: mismatched windows without --arm-windows are an error"; fi
expect_contains "block: the window error suggests --arm-windows" "$err" "--arm-windows"
expect_eq "block: mismatched windows print no block" "" "$out"

out="$("$graph" block --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-candidate.csv" --image "$gimg/read-latency.png" \
  --title "Read latency (ms)" --arm-windows --docs "$gdocs" 2>&1)"
expect_eq "block: --arm-windows exits 0" "0" "$?"
expect_contains "block: --arm-windows writes the baseline Window line" "$out" "Window (baseline): 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s"
expect_contains "block: --arm-windows writes the candidate Window line" "$out" "Window (candidate): 2026-10-01T11:30:00Z to 2026-10-01T11:40:00Z (10m 0s), step 30s"
expect_contains "block: --arm-windows keys nodes by arm" "$out" "| db0 (candidate) | candidate |"

block_err --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-candidate.csv" \
  --csv "$gfix/latency-baseline-late.csv" --image "$gimg/read-latency.png" --title "Shared arm" --arm-windows --docs "$gdocs"
if [[ $rc -ne 0 ]]; then pass "block: --arm-windows refuses two CSVs that share an arm"; else fail "block: --arm-windows refuses two CSVs that share an arm"; fi
expect_contains "block: the shared-arm refusal names the arm" "$err" "arm baseline"
expect_eq "block: the shared-arm refusal prints no block" "" "$out"

# An arm in two CSVs with one window has one window, as report-check reads it.
out="$("$graph" block --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-baseline-db2.csv" \
  --csv "$gfix/latency-candidate.csv" --image "$gimg/read-latency.png" --title "Same window" --arm-windows \
  --docs "$gdocs" 2>&1)"
expect_eq "block: --arm-windows accepts an arm in two CSVs with one window" "0" "$?"
expect_contains "block: the same-window arm keeps both CSVs' nodes" "$out" "| db2 (baseline) | baseline |"

# Each arm filters on its own cluster label, so the queries differ only in the cluster matcher.
out="$("$graph" block --csv "$gfix/cluster-baseline.csv" --csv "$gfix/cluster-candidate.csv" --image "$gimg/arm-cluster.png" \
  --title "Arm cluster" --arm-windows --docs "$gdocs" 2>&1)"
expect_eq "block: queries that differ only in the cluster matcher exit 0" "0" "$?"
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "block: the baseline arm keeps its own Query line" "$out" 'Query (baseline): `histogram_quantile(0.99, sum by (instance, le) (rate(cassandra_read_latency_seconds_bucket{cluster="lab-baseline-1a2b",'
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "block: the candidate arm keeps its own Query line" "$out" 'Query (candidate): `histogram_quantile(0.99, sum by (instance, le) (rate(cassandra_read_latency_seconds_bucket{cluster=~"lab-candidate-.*",'
expect_not_contains "block: per-arm queries give no shared Query line" "$out" "Query: "
block_err --csv "$gfix/cluster-baseline.csv" --csv "$gfix/cluster-other.csv" --image "$gimg/arm-cluster.png" \
  --title "Arm other" --arm-windows --docs "$gdocs"
if [[ $rc -ne 0 ]]; then pass "block: queries that differ past the cluster matcher are an error"; else fail "block: queries that differ past the cluster matcher are an error"; fi
expect_contains "block: the error names the query" "$err" "differ in query"
expect_eq "block: a query mismatch past the cluster matcher prints no block" "" "$out"

# Per-arm images: one regular-dashboard render per arm, each labelled by arm, and one stats table.
out="$("$graph" block --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-candidate.csv" \
  --image "baseline=$gimg/throughput-baseline.png" --image "candidate=$gimg/throughput-candidate.png" \
  --title "Throughput" --arm-windows --docs "$gdocs" 2>&1)"
expect_eq "block: per-arm images exit 0" "0" "$?"
expect_contains "block: --image baseline=<png> puts the arm in the alt text" "$out" "![Throughput (baseline)](images/throughput-baseline.png)"
expect_contains "block: --image candidate=<png> puts the arm in the alt text" "$out" "![Throughput (candidate)](images/throughput-candidate.png)"
expect_eq "block: per-arm images give one stats table" "1" "$(printf '%s\n' "$out" | grep -c '^| Node ')"
expect_contains "block: the one table holds the baseline rollup" "$out" "| all | baseline |"
expect_contains "block: the one table holds the candidate rollup" "$out" "| all | candidate |"

# An image must be a non-empty PNG under <docs>/images, as render writes it.
: > "$gimg/empty.png"
printf '<html>login</html>' > "$gimg/html.png"
cp "$panel_png" "$tmp_root/outside.png"
for bad in "missing:$gimg/no-such.png:no-such.png" "empty:$gimg/empty.png:empty" "non-PNG:$gimg/html.png:not a PNG" \
  "outside images/:$tmp_root/outside.png:/images"; do
  what="${bad%%:*}"
  rest="${bad#*:}"
  path="${rest%%:*}"
  msg="${rest#*:}"
  block_err --csv "$gfix/baseline.csv" --image "$path" --title "Bad image" --docs "$gdocs"
  if [[ $rc -ne 0 ]]; then pass "block: a $what image exits non-zero"; else fail "block: a $what image exits non-zero"; fi
  expect_contains "block: the $what image refusal is clear" "$err" "$msg"
  expect_eq "block: a $what image prints no block" "" "$out"
done
block_err --csv "$gfix/baseline.csv" --title "No image" --docs "$gdocs"
if [[ $rc -ne 0 ]]; then pass "block: no --image is a usage error"; else fail "block: no --image is a usage error"; fi
expect_contains "block: the usage error names --image" "$err" "--image"

# --name is a file name: no path, no leading dot.  block takes no --name; fetch does.
for bad in '../x' 'a/b' '..' '.hidden' 'a..b'; do
  out="$(fetch http://127.0.0.1:1/prometheus "$bad" --arm baseline=db0 2>&1)"
  expect_contains "fetch: the --name $bad refusal names the rule" "$out" "--name"
  expect_not_contains "fetch: --name $bad is refused before the query" "$out" "cannot reach Mimir"
done

out="$("$graph" block --csv "$gfix/baseline.csv" --image "$gimg/nested.png" --title "Nested" --page evidence/latency.md \
  --docs "$gdocs" 2>&1)"
expect_contains "block: --page makes the image link relative to a nested page" "$out" "![Nested](../images/nested.png)"
expect_contains "block: --page makes the Data link relative to a nested page" "$out" "Data: [baseline.csv](../data/baseline.csv)"

block_err --csv "$fixtures/graph/baseline.csv" --image "$gimg/nested.png" --title "Outside" --docs "$gdocs"
if [[ $rc -ne 0 ]]; then pass "block: a CSV outside <docs>/data is refused"; else fail "block: a CSV outside <docs>/data is refused"; fi
expect_contains "block: the refusal names the data dir" "$err" "/data"

# --- report-graph.py: the subcommands and the dependencies ---

help="$("$graph" --help 2>&1)"
subcommands="$(printf '%s\n' "$help" | sed -n 's/^  *{\(.*\)}.*/\1/p' | head -n 1)"
expect_eq "graph: --help lists fetch, render, and block only" "fetch,render,block" "$subcommands"
pep723="$(sed -n '/^# \/\/\/ script/,/^# \/\/\/$/p' "$graph")"
# The socks extra brings PySocks for --proxy.  A cached uv environment still holds PySocks after the
# extra goes, so the proxy cases alone stay green locally; this text check does not.
expect_contains "graph: the PEP 723 block declares requests with the socks extra" "$pep723" '"requests[socks]'
expect_not_contains "graph: the PEP 723 block holds no matplotlib" "$pep723" "matplotlib"

# --- references/report.md: the render steps, run as written against the stub Grafana ---

# first_bash_block <file> <heading>: print the first ```bash block in the section under <heading>.
first_bash_block() {
  awk -v h="$2" '$0 == h { s = 1; next } s && !b && /^#/ { exit } s && /^```bash$/ { b = 1; next }
    b && /^```$/ { exit } b { print }' "$1"
}
report_ref="$plugin/references/report.md"
# render_log_line: the one render request in the stub log.
render_log_line() { grep '^/render/' "$grafana_log" 2>/dev/null; }

# A single-cluster render uses the block's measured window from data/<name>.json, as absolute times.
single_step="$(first_bash_block "$report_ref" "### Render")"
if [[ "$single_step" == *"report-graph.py render"* ]]; then
  pass "reference: Render holds the single-cluster render step"
else
  fail "reference: Render holds the single-cluster render step"
fi
cp "$fixtures/grafana/day.json" "$gdocs/data/day.json"
start_grafana png
out="$(GRAFANA_URL="$grafana_url" PROXY="" DOCS="$gdocs" NAME=day DASHBOARD=cassandra-overview PANEL=7 \
  CLUSTER=graph-1a2b PATH="$bin:$PATH" bash -c "$single_step" 2>&1)"
expect_eq "render step: the single-cluster step exits 0" "0" "$?"
req="$(render_log_line)"
expect_contains "render step: from is the block JSON's start" "$req" "from=1790848800000&"
expect_contains "render step: to is the block JSON's end, 24 hours later" "$req" "to=1790935200000&"
expect_contains "render step: the cluster variable is the run's cluster" "$req" "var-cluster=graph-1a2b"
expect_contains "render step: the render asks for the dark theme" "$req" "theme=dark"
expect_file "render step: the single-cluster step writes the image" "$gdocs/images/day.png"
stop_grafana
# The step passes PROXY to render: a dead proxy fails the step, and the request never gets to Grafana.
rm -f "$gdocs/images/day.png"
start_grafana png
out="$(GRAFANA_URL="$grafana_url" PROXY="$dead_proxy" DOCS="$gdocs" NAME=day DASHBOARD=cassandra-overview PANEL=7 \
  CLUSTER=graph-1a2b PATH="$bin:$PATH" bash -c "$single_step" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "render step: a dead PROXY fails the step"; else fail "render step: a dead PROXY fails the step"; fi
expect_contains "render step: a dead PROXY gives the reach message" "$out" "cannot reach Grafana"
expect_not_contains "render step: a dead PROXY is not a missing SOCKS dependency" "$out" "Missing dependencies"
expect_eq "render step: a dead PROXY sends no request to Grafana" "" "$(cat "$grafana_log" 2>/dev/null)"
expect_no_file "render step: a dead PROXY writes no image" "$gdocs/images/day.png"
start_socks
out="$(GRAFANA_URL="$grafana_url" PROXY="$socks_proxy" DOCS="$gdocs" NAME=day DASHBOARD=cassandra-overview PANEL=7 \
  CLUSTER=graph-1a2b PATH="$bin:$PATH" bash -c "$single_step" 2>&1)"
expect_eq "render step: a live PROXY exits 0" "0" "$?"
stop_socks
expect_eq "render step: a live PROXY connects to Grafana through the proxy" "${grafana_url#http://}" "$(cat "$socks_log" 2>/dev/null)"
expect_file "render step: a live PROXY writes the image" "$gdocs/images/day.png"
stop_grafana

# The overlay render: window variables when the dashboard has them, else the whole-run fallback.
overlay_step="$(first_bash_block "$report_ref" "### Overlay render")"
if [[ "$overlay_step" == *"report-graph.py render"* ]]; then
  pass "reference: Overlay render holds the overlay render step"
else
  fail "reference: Overlay render holds the overlay render step"
fi
cp "$fixtures/graph/latency-baseline.json" "$gdocs/data/overlay-baseline.json"
cp "$fixtures/graph/latency-candidate.json" "$gdocs/data/overlay-candidate.json"
base_start=1790848800 # 2026-10-01T10:00:00Z, the earlier arm's measured start
# overlay <dashboard.json or ""> [proxy]: run the overlay step and set out, rc, and req (the render
# request).  The step passes PROXY to the dashboard probe and to render.
overlay() {
  start_grafana png ${1:+"$1"}
  local t0 t1
  t0="$(date +%s)"
  out="$(GRAFANA_URL="$grafana_url" PROXY="${2:-}" DOCS="$gdocs" NAME=overlay ARM=candidate DASHBOARD=ab-comparison \
    PANEL=1001 BASE_CLUSTER=lab-baseline-1a2b CAND_CLUSTER=lab-candidate-3c4d PATH="$bin:$PATH" \
    bash -c "$overlay_step" 2>&1)"
  rc=$?
  t1="$(date +%s)"
  req="$(render_log_line)"
  n_min=$((t0 - base_start))
  n_max=$((t1 - base_start))
  stop_grafana
}
# expect_relative_range <desc>: from is now-<N>s with N from the earlier arm's start to the render.
expect_relative_range() {
  local n
  n="$(printf '%s\n' "$req" | sed -n 's/.*[?&]from=now-\([0-9]*\)s&.*/\1/p')"
  if [[ -n "$n" && "$n" -ge "$n_min" && "$n" -le "$n_max" ]]; then
    pass "$1"
  else
    fail "$1" "from=now-${n}s, want N in $n_min..$n_max: $req"
  fi
  expect_contains "$1: to is now" "$req" "&to=now&"
}

overlay "$fixtures/grafana/dashboard-window-vars.json"
expect_eq "overlay step: with window variables exits 0" "0" "$rc"
expect_contains "overlay step: the step reads the dashboard JSON" "$(cat "$grafana_log" 2>/dev/null)" "/api/dashboards/uid/ab-comparison"
expect_contains "overlay step: the request goes to the overlay panel" "$req" "/render/d-solo/ab-comparison/?panelId=1001&"
expect_contains "overlay step: baseline_cluster is set" "$req" "var-baseline_cluster=lab-baseline-1a2b"
expect_contains "overlay step: candidate_cluster is set" "$req" "var-candidate_cluster=lab-candidate-3c4d"
expect_contains "overlay step: base_from is the baseline start in epoch ms" "$req" "var-base_from=1790848800000"
expect_contains "overlay step: base_to is the baseline end in epoch ms" "$req" "var-base_to=1790849400000"
expect_contains "overlay step: cand_from is the candidate start in epoch ms" "$req" "var-cand_from=1790854200000"
expect_contains "overlay step: cand_to is the candidate end in epoch ms" "$req" "var-cand_to=1790854800000"
expect_relative_range "overlay step: with window variables the range is relative"
expect_not_contains "overlay step: with window variables there is no fallback caveat" "$out" "whole run"
expect_file "overlay step: writes the overlay image" "$gdocs/images/overlay-overlay-candidate.png"

overlay "$fixtures/grafana/dashboard-no-window-vars.json"
expect_eq "overlay step: without window variables exits 0" "0" "$rc"
for v in base_from base_to cand_from cand_to; do
  expect_not_contains "overlay step: without window variables the request holds no var-$v" "$req" "var-$v="
done
expect_contains "overlay step: the fallback still sets the clusters" "$req" "var-candidate_cluster=lab-candidate-3c4d"
expect_relative_range "overlay step: without window variables the range is relative"
caveat="$(printf '%s\n' "$out" | sed -n 's/^caveat: //p')"
expect_contains "overlay step: the fallback prints the Caveats line" "$caveat" "covers each cluster's whole run, not only the measured window"
overlay_ref="$(sed -n '/^### Overlay render/,/^### /p' "$report_ref")"
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "reference: the fallback puts the caveat line under ## Caveats in 1-summary.md" \
  "$overlay_ref" '`## Caveats` in `1-summary.md`'
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "reference: the fallback is noted in 4-journal.md" "$overlay_ref" '`4-journal.md`'

overlay ""
if [[ "$rc" -ne 0 ]]; then pass "overlay step: an unreadable dashboard exits non-zero"; else fail "overlay step: an unreadable dashboard exits non-zero"; fi
expect_contains "overlay step: an unreadable dashboard names the dashboard" "$out" "cannot read dashboard ab-comparison"
expect_eq "overlay step: an unreadable dashboard sends no render" "" "$req"

# A dead PROXY fails the probe, so nothing gets to Grafana; a live PROXY carries the probe and render.
rm -f "$gdocs/images/overlay-overlay-candidate.png"
overlay "$fixtures/grafana/dashboard-window-vars.json" "$dead_proxy"
if [[ "$rc" -ne 0 ]]; then pass "overlay step: a dead PROXY fails the step"; else fail "overlay step: a dead PROXY fails the step"; fi
expect_contains "overlay step: a dead PROXY names the dashboard it cannot read" "$out" "cannot read dashboard ab-comparison"
expect_not_contains "overlay step: a dead PROXY is not a missing SOCKS dependency" "$out" "Missing dependencies"
expect_eq "overlay step: a dead PROXY sends no request to Grafana" "" "$(cat "$grafana_log" 2>/dev/null)"
expect_no_file "overlay step: a dead PROXY writes no image" "$gdocs/images/overlay-overlay-candidate.png"
start_socks
overlay "$fixtures/grafana/dashboard-window-vars.json" "$socks_proxy"
stop_socks
expect_eq "overlay step: a live PROXY exits 0" "0" "$rc"
expect_eq "overlay step: a live PROXY sends the probe and the render through the proxy" \
  "${grafana_url#http://}|${grafana_url#http://}|" "$(tr '\n' '|' < "$socks_log" 2>/dev/null)"
expect_file "overlay step: a live PROXY writes the image" "$gdocs/images/overlay-overlay-candidate.png"
rm -f "$gdocs/images/day.png" "$gdocs/images/overlay-overlay-candidate.png"

# The SOCKS proxy step, run as written.  The wrapper's directory holds .socks5-proxy.env, or, from an
# older binary, .socks5-proxy-state.  The stub wrapper's `status` logs itself and, when STUB_RESTART
# names a port, writes a live tunnel on it: to the .env file when STUB_ENV is set, else to the state.
proxy_step="$(first_bash_block "$report_ref" "### The SOCKS proxy")"
if [[ "$proxy_step" == *".socks5-proxy-state"* ]]; then
  pass "reference: The SOCKS proxy holds the proxy step"
else
  fail "reference: The SOCKS proxy holds the proxy step"
fi
pdir="$tmp_root/proxy"
mkdir -p "$pdir"
cat >"$pdir/easy-db-lab" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$(dirname "$0")/status.log"
[[ -n "${STUB_RESTART:-}" ]] || exit 0
if [[ -n "${STUB_ENV:-}" ]]; then
  printf 'EDL_TAILSCALE_ACTIVE=false\nEDL_SOCKS_PORT=%s\nEDL_SOCKS_PID=%s\n' "$STUB_RESTART" "$STUB_LIVE_PID" \
    >"$(dirname "$0")/.socks5-proxy.env"
else
  printf '{"pid":%s,"port":%s}\n' "$STUB_LIVE_PID" "$STUB_RESTART" >"$(dirname "$0")/.socks5-proxy-state"
fi
EOF
chmod +x "$pdir/easy-db-lab"
sleep 600 &
live_pid=$!
(exit 0) &
dead_pid=$!
wait "$dead_pid"
# proxy <state json or ""> [STUB_RESTART port] [env file text or ""]: write the state files, run the
# step, and set out to PROXY and log to the status calls.  An env file text makes status write the env.
proxy() {
  rm -f "$pdir/.socks5-proxy-state" "$pdir/.socks5-proxy.env" "$pdir/status.log"
  [[ -z "$1" ]] || printf '%s\n' "$1" >"$pdir/.socks5-proxy-state"
  [[ -z "${3:-}" ]] || printf '%s\n' "$3" >"$pdir/.socks5-proxy.env"
  out="$(EDB="$pdir/easy-db-lab" STUB_RESTART="${2:-}" STUB_ENV="${3:-}" STUB_LIVE_PID="$live_pid" \
    bash -c "$proxy_step"$'\nprintf %s "$PROXY"' 2>/dev/null)"
  log="$(cat "$pdir/status.log" 2>/dev/null)"
}
proxy "{\"pid\":$live_pid,\"port\":49733}"
expect_eq "proxy step: a live tunnel gives its port" "socks5h://127.0.0.1:49733" "$out"
expect_eq "proxy step: a live tunnel runs no status" "" "$log"
proxy "{\"pid\":$dead_pid,\"port\":1080}" 50373
expect_eq "proxy step: a dead tunnel runs status" "status" "$log"
expect_eq "proxy step: a dead tunnel gives the restarted port" "socks5h://127.0.0.1:50373" "$out"
proxy "{\"pid\":$dead_pid,\"port\":1080}"
expect_eq "proxy step: a tunnel that status cannot restart gives no proxy" "" "$out"
proxy ""
expect_eq "proxy step: no state file gives no proxy" "" "$out"
expect_eq "proxy step: no state file runs no status" "" "$log"
env_live="$(printf 'EDL_TAILSCALE_ACTIVE=false\nEDL_SOCKS_PORT=24811\nEDL_SOCKS_PID=%s' "$live_pid")"
proxy "" "" "$env_live"
expect_eq "proxy step: a live tunnel in .socks5-proxy.env gives its port" "socks5h://127.0.0.1:24811" "$out"
expect_eq "proxy step: a live tunnel in .socks5-proxy.env runs no status" "" "$log"
proxy "{\"pid\":$live_pid,\"port\":1080}" "" "$env_live"
expect_eq "proxy step: .socks5-proxy.env wins over .socks5-proxy-state" "socks5h://127.0.0.1:24811" "$out"
proxy "" 27003 "$(printf 'EDL_TAILSCALE_ACTIVE=false\nEDL_SOCKS_PORT=24811\nEDL_SOCKS_PID=%s' "$dead_pid")"
expect_eq "proxy step: a dead tunnel in .socks5-proxy.env runs status" "status" "$log"
expect_eq "proxy step: a dead tunnel in .socks5-proxy.env gives the restarted port" "socks5h://127.0.0.1:27003" "$out"
proxy "" 27004 "EDL_TAILSCALE_ACTIVE=false"
expect_eq "proxy step: .socks5-proxy.env with no tunnel runs status" "status" "$log"
expect_eq "proxy step: .socks5-proxy.env with no tunnel gives the started port" "socks5h://127.0.0.1:27004" "$out"
proxy "" 27005 "EDL_TAILSCALE_ACTIVE=true"
expect_eq "proxy step: a Tailscale cluster gives no proxy" "" "$out"
expect_eq "proxy step: a Tailscale cluster runs no status" "" "$log"
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
graphs_ref="$(sed -n '/^## Graphs/,/^## Prose Rules/p' "$report_ref")"
expect_not_contains "reference: Graphs does not say Grafana is always on Tailscale" "$graphs_ref" "Grafana is reachable over Tailscale"
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "reference: Graphs says status restarts a dead tunnel" "$graphs_ref" '`$EDB status` restarts'
expect_contains "reference: Graphs runs the proxy step at each use" "$graphs_ref" "before each"
socks_ref="$(sed -n '/^### The SOCKS proxy/,/^### Fetch/p' "$report_ref")"
expect_not_contains "reference: the proxy step does not source the env file" "$socks_ref" "source "

# --- report-check.py ---

checker="$bin/report-check.py"
# run_check <fixture> [args...]: copy docs-agree plus the overlay <fixture> (none for "agree") to a
# fresh dir, run the checker on it, and set check_dir, check_out, and check_rc.
run_check() {
  local name="$1"
  shift
  check_dir="$tmp_root/check-$name"
  rm -rf "$check_dir"
  if [[ "$name" == agree ]]; then fixture_docs "$check_dir"; else fixture_docs "$check_dir" "$name"; fi
  check_out="$("$checker" "$@" "$check_dir" 2>&1)"
  check_rc=$?
}

tree_sum() { # dir -> one checksum of every file under it
  (cd "$1" && find . -type f | sort | xargs cat | cksum)
}

run_check agree
expect_eq "check: summary and evidence agree, exit 0" "0" "$check_rc"
expect_not_contains "check: agree has no FAIL" "$check_out" "FAIL"
expect_not_contains "check: agree has no WARN" "$check_out" "WARN"
expect_contains "check: the nested page and its slug resolve" "$check_out" "PASS: row Read latency p99 (ms)"
expect_contains "check: the (MB/s) heading slug resolves" "$check_out" "PASS: row Scrape allocation mean (MB/s)"
expect_contains "check: a measured noise floor is recomputed" "$check_out" "PASS: noise floor Read latency p99 (ms)"
expect_contains "check: not measured is accepted" "$check_out" "PASS: noise floor Scrape allocation mean (MB/s): not measured"

# fixture | the word the FAIL line must hold
while read -r name word; do
  run_check "$name"
  expect_eq "check: $name exits 1" "1" "$check_rc"
  if printf '%s\n' "$check_out" | grep '^FAIL' | grep -qi -- "$word"; then
    pass "check: $name FAIL names the $word"
  else
    fail "check: $name FAIL names the $word" "$(printf '%s\n' "$check_out" | grep '^FAIL' | head -3)"
  fi
done <<'EOF'
wrong-sign sign
wrong-size size
wrong-unit unit
wrong-value candidate
noise-empty noise floor
noise-non-numeric noise floor
noise-wrong-value noise floor
confirmed-inside-noise noise floor
bad-verdict verdict
verdict-mismatch class
incomplete-block query
grafana-link grafana
placeholder-title title
missing-anchor anchor
findings-bad-evidence evidence
cassandra-missing reasoning review
arm-two-windows two windows
EOF

for name in noise-not-measured partial partial-no-evidence inconclusive findings cassandra-done cassandra-not-installed arm-cluster; do
  run_check "$name"
  expect_eq "check: $name exits 0" "0" "$check_rc"
  expect_not_contains "check: $name has no FAIL" "$check_out" "FAIL"
done
run_check partial
expect_not_contains "check: the Partial token is not a numeral in prose" "$check_out" "WARN"
run_check arm-cluster
expect_contains "check: a block with one Query line per arm passes its row" "$check_out" "PASS: row Read latency p99 (ms)"

run_check numeral-in-prose
expect_eq "check: a numeral in prose exits 0" "0" "$check_rc"
expect_contains "check: a numeral in prose is a WARN" "$check_out" "WARN: numeral in summary prose"

while read -r name word; do
  run_check "$name"
  expect_eq "check: $name exits 3" "3" "$check_rc"
  if printf '%s\n' "$check_out" | grep '^FAIL' | grep -qi -- "$word"; then
    pass "check: $name FAIL names the $word"
  else
    fail "check: $name FAIL names the $word" "$(printf '%s\n' "$check_out" | grep '^FAIL' | head -3)"
  fi
done <<'EOF'
redact-ipv4-summary IPv4
redact-account account
redact-vpc vpc-
redact-subnet subnet-
redact-sg sg-
redact-tunnel tunnel
redact-query-ip IPv4
redact-json-ip IPv4
redact-account-period account
redact-ec2-host EC2 host name
redact-ec2-host-csv EC2 host name
redact-account-csv-node account
redact-account-stats-node account
redact-account-stats-bare account
redact-igw igw-
redact-instance i-
redact-port port number
redact-ipv4-period IPv4
EOF

# Not redaction: a 12-digit metric value in data/*.csv and its stats table, infrastructure IDs in
# the appendix journal, a dotted version string in summary prose, and a cluster label whose UUID
# ends in twelve digits.
for name in redact-ok-big-value redact-ok-journal redact-ok-version redact-ok-cluster-uuid; do
  run_check "$name"
  expect_eq "check: $name exits 0" "0" "$check_rc"
  expect_not_contains "check: $name has no redaction FAIL" "$check_out" "FAIL: redaction"
done

# The replace step, one line at a time: each kind, the overlap rule, and the text that stays.
cases_out="$(python3 "$here/redact-cases.py" "$checker" "$fixtures/redact/cases.tsv" 2>&1)"
[[ -n "$cases_out" ]] || fail "redact: the cases ran" "no output"
while IFS=$'\t' read -r verdict name detail; do
  if [[ "$verdict" == ok ]]; then pass "redact: $name"; else fail "redact: $name" "$verdict $detail"; fi
done <<<"$cases_out"

# SUMMARY.md: a customer page outside docs/ is a FAIL, and ./page and page are one page.
outside_docs="$tmp_root/outside/docs"
fixture_docs "$outside_docs" summary-outside
printf '# Secret\n\nAccount 123456789012.\n' > "$tmp_root/outside/secret.md"
abs_docs="$tmp_root/absolute/docs"
fixture_docs "$abs_docs"
printf '# Secret\n' > "$tmp_root/absolute/secret.md"
perl -pi -e 'print "- [Secret]('"$tmp_root"'/absolute/secret.md)\n" if /^# Appendix/' "$abs_docs/SUMMARY.md"
for d in "$outside_docs" "$abs_docs"; do
  out="$("$checker" "$d" 2>&1)"
  expect_eq "check: a SUMMARY.md page outside docs/ exits 1 (${d#"$tmp_root/"})" "1" "$?"
  expect_contains "check: the FAIL names the page outside docs/ (${d#"$tmp_root/"})" "$(printf '%s\n' "$out" | grep '^FAIL')" "secret.md"
done
run_check summary-dot
expect_eq "check: summary-dot exits 0" "0" "$check_rc"
expect_eq "check: ./2-evidence.md and 2-evidence.md load once" "1" \
  "$(printf '%s\n' "$check_out" | grep -c 'PASS: evidence block 2-evidence.md#scrape-allocation-mbs')"

out="$("$checker" "$tmp_root/no-such-docs" 2>&1)"
expect_eq "check: a bad path exits 2" "2" "$?"
out="$("$checker" 2>&1)"
expect_eq "check: no path exits 2" "2" "$?"
expect_contains "check: a bad path names the error" "$("$checker" "$tmp_root/no-such-docs" 2>&1)" "report-check: not a docs directory"

# An I/O error names its class: a customer page that is a directory.
io_docs="$tmp_root/io-error/docs"
fixture_docs "$io_docs"
mkdir -p "$io_docs/dir-page.md"
perl -pi -e 'print "- [Dir](dir-page.md)\n" if /^# Appendix/' "$io_docs/SUMMARY.md"
out="$("$checker" "$io_docs" 2>&1)"
expect_eq "check: a directory page exits 2" "2" "$?"
expect_contains "check: the I/O error names its class" "$out" "IsADirectoryError"

out="$("$checker" "$ws_noplan/docs" 2>&1)"
expect_eq "check: the bare scaffold passes, so make works on it" "0" "$?"

# No file edit without --gate.
fixture_docs "$tmp_root/nogate" wrong-sign
before="$(tree_sum "$tmp_root/nogate")"
"$checker" "$tmp_root/nogate" >/dev/null 2>&1
expect_eq "check: no file edit without --gate" "$before" "$(tree_sum "$tmp_root/nogate")"

# Malformed evidence data is a content FAIL (exit 1) that names the data file, not an exit 2.
# fixture | the data file the FAIL line must name
while read -r name file; do
  run_check "$name"
  expect_eq "check: $name exits 1" "1" "$check_rc"
  if printf '%s\n' "$check_out" | grep '^FAIL' | grep -q -- "$file"; then
    pass "check: $name FAIL names $file"
  else
    fail "check: $name FAIL names $file" "$(printf '%s\n' "$check_out" | head -3)"
  fi
  fixture_docs "$tmp_root/pristine-$name" "$name"
  expect_eq "check: $name edits no file without --gate" "$(tree_sum "$tmp_root/pristine-$name")" "$(tree_sum "$check_dir")"
  "$checker" --gate "$check_dir" >/dev/null 2>&1
  expect_eq "gate: --gate exits 0 on $name" "0" "$?"
  expect_contains "gate: --gate writes the Unchecked line on $name" "$(grep '^⚠ Unchecked: ' "$check_dir/1-summary.md")" "$file"
done <<'EOF'
data-non-numeric data/scrape-alloc.csv
data-no-column data/scrape-alloc.csv
data-json-no-start data/scrape-alloc.json
data-json-no-unit data/scrape-alloc.json
data-bad-time data/scrape-alloc.csv
data-bad-json data/scrape-alloc.json
EOF

# unchecked_lines <summary>: the Unchecked lines in the file.
unchecked_lines() {
  grep -c '^⚠ Unchecked: ' "$1"
}

run_check wrong-sign --gate --reason "the noise floor does not support the verdict"
expect_eq "gate: a content FAIL with --gate exits 0" "0" "$check_rc"
expect_eq "gate: writes one Unchecked line" "1" "$(unchecked_lines "$check_dir/1-summary.md")"
line="$(grep '^⚠ Unchecked: ' "$check_dir/1-summary.md")"
expect_contains "gate: the line holds the check reason" "$line" "sign"
expect_contains "gate: the line merges the --reason text" "$line" "the noise floor does not support the verdict"
caveats_next="$(sed -n '/^## Caveats/,$p' "$check_dir/1-summary.md" | grep -v '^$' | sed -n 2p)"
expect_eq "gate: the line is under ## Caveats" "$line" "$caveats_next"
"$checker" --gate "$check_dir" >/dev/null 2>&1
expect_eq "gate: a second --gate replaces the line" "1" "$(unchecked_lines "$check_dir/1-summary.md")"
out="$("$checker" "$check_dir" 2>&1)"
expect_not_contains "gate: the numeral WARN ignores the Unchecked line" "$(printf '%s\n' "$out" | grep WARN)" "Unchecked"

run_check stale-unchecked --gate
expect_eq "gate: a clean --gate exits 0" "0" "$check_rc"
expect_eq "gate: a clean --gate removes a stale line" "0" "$(unchecked_lines "$check_dir/1-summary.md")"

run_check agree --gate --reason "reviewer saw a confound"
expect_eq "gate: a --reason alone writes the line" "1" "$(unchecked_lines "$check_dir/1-summary.md")"

# A reason can hold a ; or a newline, so each reason has its own number on the one line.
run_check agree --gate --reason "the floor is wide; the run is short" --reason "$(printf 'two\nlines')"
expect_eq "gate: numbered reasons keep a ; and fold a newline on one line" \
  "⚠ Unchecked: (1) the floor is wide; the run is short (2) two lines" \
  "$(grep '^⚠ Unchecked: ' "$check_dir/1-summary.md")"
expect_eq "gate: a reason with a newline still writes one line" "1" "$(grep -c 'Unchecked\|^lines' "$check_dir/1-summary.md")"

fixture_docs "$tmp_root/gate-redact" redact-tunnel
before="$(tree_sum "$tmp_root/gate-redact")"
"$checker" --gate "$tmp_root/gate-redact" >/dev/null 2>&1
expect_eq "gate: a redaction FAIL with --gate exits 3" "3" "$?"
expect_eq "gate: a redaction FAIL edits no file" "$before" "$(tree_sum "$tmp_root/gate-redact")"

# --- report-export.py ---

exporter="$bin/report-export.py"
xd="$tmp_root/export-agree"
fixture_docs "$xd" jira-image
"$exporter" jira "$xd" "$tmp_root/jira.txt" >/dev/null 2>&1
expect_eq "jira: exits 0" "0" "$?"
jira="$(cat "$tmp_root/jira.txt" 2>/dev/null)"
expect_contains "jira: the title is a wiki heading" "$jira" "h1. Scrape allocation rises with the canary"
expect_contains "jira: the table is a wiki table" "$jira" "|| Metric || Baseline || Candidate || Delta || Noise floor || Verdict ||"
expect_contains "jira: an image is referenced by file name" "$jira" "!scrape-alloc.png!"
expect_not_contains "jira: no images/ path" "$jira" "images/"
expect_not_contains "jira: no .md links" "$jira" ".md"
expect_contains "jira: a link becomes its text" "$jira" "| Scrape allocation mean "
expect_contains "jira: the Refuted verdict maps to its colour" "$jira" "{color:#D55E00}*Refuted*{color}"
expect_contains "jira: the Confirmed verdict maps to its colour" "$jira" "{color:#009E73}*Confirmed*{color}"
expect_not_contains "jira: no HTML span" "$jira" "<span"
for v in partial inconclusive; do
  fixture_docs "$tmp_root/export-$v" "$v"
  "$exporter" jira "$tmp_root/export-$v" "$tmp_root/jira-$v.txt" >/dev/null 2>&1
done
expect_contains "jira: the Partial verdict maps to its colour" "$(cat "$tmp_root/jira-partial.txt" 2>/dev/null)" \
  "{color:#999999}*Partial: stopped after step 2*{color}"
expect_contains "jira: the Inconclusive verdict maps to its colour" "$(cat "$tmp_root/jira-inconclusive.txt" 2>/dev/null)" \
  "{color:#E69F00}*Inconclusive*{color}"
expect_not_contains "jira: holds only the summary tier" "$jira" "Threats to validity"

# pandoc escapes ( + and -, and its smart extension makes -- an en dash.
fixture_docs "$tmp_root/export-escapes" jira-escapes
"$exporter" jira "$tmp_root/export-escapes" "$tmp_root/jira-escapes.txt" >/dev/null 2>&1
jira_esc="$(cat "$tmp_root/jira-escapes.txt" 2>/dev/null)"
expect_contains "jira: the Metric link text keeps its unit readable" "$jira_esc" "| Scrape allocation mean (MB/s) |"
expect_contains "jira: a positive Delta keeps its plain sign" "$jira_esc" "| +20.8% |"
expect_contains "jira: a negative Delta keeps its plain sign" "$jira_esc" "| -26.4% |"
# JIRA renders -- as an en dash, so \-\- is the JIRA source for a literal --.
expect_contains "jira: -- stays two escaped hyphens, not an en dash" "$jira_esc" 'block \-\-arm-windows'
expect_contains "jira: an emoticon such as (i) stays escaped" "$jira_esc" '\(i)'

fixture_docs "$tmp_root/export-missing" missing-image
out="$("$exporter" zip "$tmp_root/export-missing" "$tmp_root/missing.zip" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "zip: a missing referenced file exits non-zero"; else fail "zip: a missing referenced file exits non-zero"; fi
expect_contains "zip: the error names the missing file" "$out" "images/missing.png"
expect_no_file "zip: a missing referenced file writes no zip" "$tmp_root/missing.zip"

for d in "$outside_docs" "$abs_docs"; do
  zip_out="$tmp_root/${d#"$tmp_root/"}"
  zip_out="${zip_out%/docs}.zip"
  out="$("$exporter" zip "$d" "$zip_out" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then pass "zip: a SUMMARY.md page outside docs/ exits non-zero (${d#"$tmp_root/"})"; else fail "zip: a SUMMARY.md page outside docs/ exits non-zero (${d#"$tmp_root/"})"; fi
  expect_contains "zip: the error names the page outside docs/ (${d#"$tmp_root/"})" "$out" "secret.md"
  expect_no_file "zip: a page outside docs/ writes no zip (${d#"$tmp_root/"})" "$zip_out"
done

out="$("$exporter" jira "$ws_noplan/docs" "$tmp_root/scaffold-jira.txt" 2>&1)"
expect_eq "jira: the bare scaffold exports" "0" "$?"
expect_not_contains "jira: scaffold comments are dropped" "$(cat "$tmp_root/scaffold-jira.txt" 2>/dev/null)" "<!--"

# --- make: the docs Makefile on the scaffold and on docs-agree ---

# toc_order <report-dir>: the sidebar entries in order, one per |, from mdbook's toc.html.
toc_order() {
  grep -oE 'href="[^"]+\.html"|part-title">[^<]+' "$1/toc.html" 2>/dev/null \
    | sed -e 's/^href="//' -e 's/"$//' -e 's/^part-title">/part:/' | tr '\n' '|'
}

if command -v report-check.py >/dev/null 2>&1; then
  fail "make: the test PATH holds no plugin bin/" "$(command -v report-check.py)"
else
  pass "make: the test PATH holds no plugin bin/"
fi

mws="$tmp_root/make-scaffold"
bash "$bin/setup-cluster.sh" "$mws" "$stub_edb" --name make-test >/dev/null 2>&1
make -s -C "$mws/docs" >/dev/null 2>&1
expect_eq "make: the bare scaffold builds" "0" "$?"
expect_file "make: the scaffold gives report/index.html" "$mws/docs/report/index.html"
expect_file "make: the scaffold gives export/jira.txt" "$mws/docs/export/jira.txt"
expect_file "make: the scaffold gives export/report.zip" "$mws/docs/export/report.zip"
expect_contains "make: the placeholder H1 falls back to the cluster name" \
  "$(grep -o 'menu-title">[^<]*' "$mws/docs/report/index.html" 2>/dev/null)" 'menu-title">make-test'
expect_contains "make: index.html is the summary page" "$(cat "$mws/docs/report/index.html" 2>/dev/null)" "What this means"
expect_eq "make: the scaffold sidebar is summary, Evidence, then the Appendix" \
  "1-summary.html|2-evidence.html|part:Appendix|3-plan.html|4-journal.html|5-issues.html|" \
  "$(toc_order "$mws/docs/report")"

aws_="$tmp_root/make-agree"
bash "$bin/setup-cluster.sh" "$aws_" "$stub_edb" --name make-agree >/dev/null 2>&1
cp -R "$fixtures/docs-agree/." "$aws_/docs/"
out="$(make -C "$aws_/docs" 2>&1)"
expect_eq "make: docs-agree builds" "0" "$?"
expect_contains "make: the check runs first" "$out" "PASS: row Scrape allocation mean (MB/s)"
rep="$aws_/docs/report"
for f in "$rep/index.html" "$aws_/docs/export/jira.txt" "$aws_/docs/export/report.zip"; do
  expect_file "make: docs-agree gives ${f#"$aws_/docs/"}" "$f"
done
expect_contains "make: the book title is the summary H1" \
  "$(grep -o 'menu-title">[^<]*' "$rep/index.html" 2>/dev/null)" 'menu-title">Scrape allocation rises with the canary'
expect_contains "make: index.html opens on the summary" "$(cat "$rep/index.html" 2>/dev/null)" 'id="scrape-allocation-rises-with-the-canary"'
expect_eq "make: the sidebar nests Latency under Evidence, above the Appendix" \
  "1-summary.html|2-evidence.html|evidence/latency.html|part:Appendix|3-plan.html|4-journal.html|5-issues.html|" \
  "$(toc_order "$rep")"
expect_contains "make: the (MB/s) heading id is the checker's slug" "$(cat "$rep/2-evidence.html" 2>/dev/null)" 'id="scrape-allocation-mbs"'
expect_contains "make: the nested heading id is the checker's slug" "$(cat "$rep/evidence/latency.html" 2>/dev/null)" 'id="read-latency-ms"'
expect_contains "make: index.html links lab.css" "$(cat "$rep/index.html" 2>/dev/null)" 'href="lab'
built_css="$(cat "$rep"/lab-*.css 2>/dev/null)"
for rule in "position: sticky" "tbody tr:nth-child(even)" ".verdict-confirmed" "--content-max-width" "@media print"; do
  expect_contains "make: the built lab.css holds $rule" "$built_css" "$rule"
done
expect_contains "make: a verdict renders as a badge span" "$(cat "$rep/index.html" 2>/dev/null)" '<span class="verdict verdict-refuted">Refuted</span>'
expect_contains "make: numeric columns are right-aligned in HTML" "$(cat "$rep/2-evidence.html" 2>/dev/null)" 'text-align: right'

# --- make export: report.zip is the shareable book, built from a redacted copy ---

sws="$tmp_root/make-share"
bash "$bin/setup-cluster.sh" "$sws" "$stub_edb" --name make-share >/dev/null 2>&1
fixture_docs "$sws/docs" share-book redact-ok-big-value
journal_before="$(cksum < "$sws/docs/4-journal.md")"
make -s -C "$sws/docs" >/dev/null 2>&1
expect_eq "zip: make builds the shareable book" "0" "$?"
listing="$(unzip -Z1 "$sws/docs/export/report.zip" 2>/dev/null | sort | tr '\n' ' ')"
for f in index.html 1-summary.html 2-evidence.html evidence/latency.html 3-plan.html 4-journal.html 5-issues.html \
  images/scrape-alloc.png images/read-latency.png images/noise-latency.png images/disk-bytes.png \
  data/scrape-alloc.csv data/latency-baseline.csv data/latency-candidate.csv data/noise-latency.csv data/disk-bytes.csv; do
  expect_contains "zip: holds $f" " $listing" " $f "
done
expect_contains "zip: holds the house theme css" "$listing" " lab"
expect_not_contains "zip: holds no markdown source" "$listing" ".md "
sx="$tmp_root/share-extract"
mkdir -p "$sx"
unzip -q "$sws/docs/export/report.zip" -d "$sx" 2>/dev/null
expect_eq "zip: the extracted sidebar lists every page, the appendix included" \
  "1-summary.html|2-evidence.html|evidence/latency.html|part:Appendix|3-plan.html|4-journal.html|5-issues.html|" \
  "$(toc_order "$sx")"
expect_contains "zip: the extracted book opens in the house theme" "$(cat "$sx/index.html" 2>/dev/null)" 'coal'
# Every relative link and source in the extracted pages resolves inside the tree, so the book
# works from file://.
broken=""
while IFS= read -r page; do
  dir="$(dirname "$page")"
  while IFS= read -r ref; do
    [[ -e "$dir/$ref" ]] || broken="$broken ${page#"$sx/"}:$ref"
  done < <(grep -oE '(href|src)="[^"#?:]+' "$page" | sed -E 's/^(href|src)="//' | sort -u)
done < <(find "$sx" -name '*.html')
expect_eq "zip: every relative link in the extracted book resolves" "" "$broken"
expect_contains "zip: the evidence page shows its image" "$(cat "$sx/2-evidence.html" 2>/dev/null)" 'src="images/scrape-alloc.png"'
expect_contains "zip: the evidence page links its data" "$(cat "$sx/2-evidence.html" 2>/dev/null)" 'href="data/scrape-alloc.csv"'

xj="$(cat "$sx/4-journal.html" 2>/dev/null)"
for p in private-ip ec2-host account-id vpc-id subnet-id sg-id igw-id instance-id port socks-proxy tunnel; do
  expect_contains "zip: the journal holds the <$p> placeholder" "$xj" "&lt;$p&gt;"
done
expect_contains "zip: an issues page port becomes a placeholder" "$(cat "$sx/5-issues.html" 2>/dev/null)" 'changed from &lt;port&gt; to &lt;port&gt;'
# book_text <dir>: what a reader sees in the extracted book: each page's <main>, the search index,
# and the data files, less the placeholders and the heading ids.  mdbook's own scripts and styles
# are not report content; its sidebar script holds 1080 as a screen width.
book_text() {
  local page
  while IFS= read -r page; do sed -n '/<main>/,/<\/main>/p' "$page"; done < <(find "$1" -name '*.html')
  cat "$1"/searchindex*.js "$1"/data/* 2>/dev/null
}
shown="$(book_text "$sx" | sed -E \
  -e 's/(\\?&lt;|\\?<)(private-ip|ec2-host|account-id|vpc-id|subnet-id|sg-id|igw-id|instance-id|port|socks-proxy|tunnel)(&gt;|>)/ /g' \
  -e 's/(id|href)="[^"]*"//g' -e 's/#[A-Za-z0-9_-]+//g')"
expect_contains "zip: the book text holds the journal" "$shown" "Cassandra 5.0.9 on db0"
for v in 10.0.1.15 10.0.1.20 127.0.0.1 vpc-0abc1234def567890 ip-10-0-1-15 123456789012 417835013894 subnet-0abc1234 \
  sg-0abc1234 igw-0abc1234 i-0abc1234def567890 1080 52764 socks5h; do
  expect_not_contains "zip: no $v in the extracted book" "$shown" "$v"
done
for w in socks tunnel; do
  hits="$(printf '%s\n' "$shown" | grep -oiw -- "$w" | sort -u | tr '\n' ' ')"
  expect_eq "zip: no $w wording in the extracted book" "" "$hits"
done
expect_contains "zip: \$EDB becomes the command name" "$xj" 'easy-db-lab status'
expect_contains "zip: \${EDB} becomes the command name" "$xj" '"easy-db-lab" down --auto-approve'
expect_contains "zip: \$EDB_BASELINE becomes the command name" "$xj" 'easy-db-lab report upload'
expect_contains "zip: \${EDB_CANDIDATE} becomes the command name" "$xj" '
easy-db-lab status'
hits="$(grep -rlF -- 'EDB' "$sx" 2>/dev/null | sed "s|^$sx/||" | tr '\n' ' ')"
expect_eq "zip: no EDB variable anywhere in the extracted book" "" "$hits"
expect_contains "zip: a version string survives" "$xj" 'Cassandra 5.0.9 on db0'
expect_contains "zip: a cluster label UUID survives" "$xj" 'report-ab-896195de-19a1-43fe-b315-751612345678'
expect_contains "zip: a 12-digit decimal measurement survives" "$xj" '214748364800.0 bytes'
expect_contains "zip: a 12-digit stats cell survives" "$(cat "$sx/2-evidence.html" 2>/dev/null)" '>214748364800<'
expect_contains "zip: a 12-digit CSV value survives" "$(cat "$sx/data/disk-bytes.csv" 2>/dev/null)" ',214748364800'
expect_eq "zip: the export leaves 4-journal.md unchanged" "$journal_before" "$(cksum < "$sws/docs/4-journal.md")"
lj="$(cat "$sws/docs/report/4-journal.html" 2>/dev/null)"
expect_contains "zip: the local report keeps the IPv4 address" "$lj" '10.0.1.15'
# shellcheck disable=SC2016 # the $EDB is literal page text
expect_contains "zip: the local report keeps \$EDB" "$lj" '$EDB status'

# The local book holds the report, not the build inputs: a build after an export copies no
# export/, zip, staging tree, Makefile, or book.toml into report/.
make -s -C "$sws/docs" build >/dev/null 2>&1
expect_eq "build: a rebuild after the export exits 0" "0" "$?"
expect_no_file "build: report/ holds no export/" "$sws/docs/report/export"
expect_eq "build: report/ holds no .zip" "" "$(find "$sws/docs/report" -name '*.zip')"
expect_no_file "build: report/ holds no Makefile" "$sws/docs/report/Makefile"
expect_no_file "build: report/ holds no book.toml" "$sws/docs/report/book.toml"
expect_file "build: report/ keeps its images" "$sws/docs/report/images/scrape-alloc.png"
expect_file "build: report/ keeps its data" "$sws/docs/report/data/scrape-alloc.csv"
expect_no_file "zip: the shareable book holds no book.toml" "$sx/book.toml"

# A value the replace step misses fails the export, and the error names the file and line.
lws="$tmp_root/make-share-leftover"
bash "$bin/setup-cluster.sh" "$lws" "$stub_edb" --name make-share-leftover >/dev/null 2>&1
fixture_docs "$lws/docs" share-book
out="$(cd "$lws/docs" && python3 - "$bin/report-export.py" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("report_export", sys.argv[1])
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)
exporter.redact = lambda rel, text: text
exporter.zip_report(".", "export/report.zip")
PY
)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "zip: a leftover identifier fails the export"; else fail "zip: a leftover identifier fails the export"; fi
expect_contains "zip: the leftover error names the file and line" "$out" "4-journal.md line 5"
expect_no_file "zip: a leftover identifier writes no zip" "$lws/docs/export/report.zip"

# A staged file name is not redacted, so an identifier in one fails the export.
bash "$bin/setup-cluster.sh" "$tmp_root/export-name" "$stub_edb" --name export-name >/dev/null 2>&1
nd="$tmp_root/export-name/docs"
fixture_docs "$nd" share-book
cp "$nd/images/scrape-alloc.png" "$nd/images/db-ip-10-0-1-15.png"
printf '\n![db0](images/db-ip-10-0-1-15.png)\n' >> "$nd/4-journal.md"
out="$("$exporter" zip "$nd" "$tmp_root/export-name/report.zip" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "zip: an identifier in a file name fails the export"; else fail "zip: an identifier in a file name fails the export"; fi
expect_contains "zip: the file name error names the kind and the file" "$out" "EC2 host name in the file name images/db-ip-10-0-1-15.png"
expect_no_file "zip: an identifier in a file name writes no zip" "$tmp_root/export-name/report.zip"

# Every referenced text file is redacted, whatever its extension; an SVG gets the entity form so
# it stays valid XML.  A referenced file that is neither text nor a known image fails the export.
bash "$bin/setup-cluster.sh" "$tmp_root/export-text" "$stub_edb" --name export-text >/dev/null 2>&1
xt="$tmp_root/export-text/docs"
fixture_docs "$xt" share-book
printf 'node 10.0.1.15 at /Users/someone/lab\n' > "$xt/data/notes.txt"
printf 'host: control0:3000\n' > "$xt/data/conf.yaml"
printf '<svg xmlns="http://www.w3.org/2000/svg"><text>10.0.1.15</text></svg>\n' > "$xt/images/diagram.svg"
printf '\n[notes](data/notes.txt), [conf](data/conf.yaml), and ![diagram](images/diagram.svg)\n' >> "$xt/5-issues.md"
out="$("$exporter" zip "$xt" "$tmp_root/export-text/report.zip" 2>&1)"
expect_eq "zip: text files of any extension export" "0" "$?"
xtx="$tmp_root/export-text/extract"
mkdir -p "$xtx"
unzip -q "$tmp_root/export-text/report.zip" -d "$xtx" 2>/dev/null
expect_eq "zip: a .txt data file is redacted" "node <private-ip> at <local-path>" "$(cat "$xtx/data/notes.txt" 2>/dev/null)"
expect_eq "zip: a .yaml data file is redacted" "host: <service-url>" "$(cat "$xtx/data/conf.yaml" 2>/dev/null)"
expect_contains "zip: an SVG is redacted with the entity form" "$(cat "$xtx/images/diagram.svg" 2>/dev/null)" '<text>&lt;private-ip&gt;</text>'
expect_eq "zip: a PNG is copied unchanged" "$(cksum < "$xt/images/scrape-alloc.png")" "$(cksum < "$xtx/images/scrape-alloc.png" 2>/dev/null)"

bash "$bin/setup-cluster.sh" "$tmp_root/export-binary" "$stub_edb" --name export-binary >/dev/null 2>&1
xb="$tmp_root/export-binary/docs"
fixture_docs "$xb" share-book
printf '\x00\xff\xfe binary' > "$xb/data/blob.bin"
printf '\n[blob](data/blob.bin)\n' >> "$xb/5-issues.md"
out="$("$exporter" zip "$xb" "$tmp_root/export-binary/report.zip" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "zip: a referenced binary that is not an image fails the export"; else fail "zip: a referenced binary that is not an image fails the export"; fi
expect_contains "zip: the binary error names the file" "$out" "data/blob.bin"
expect_no_file "zip: a referenced binary writes no zip" "$tmp_root/export-binary/report.zip"

# An mdbook include directive would pull an unredacted file into the book, so a staged page that
# holds one fails the export.
for directive in include rustdoc_include playground; do
  bash "$bin/setup-cluster.sh" "$tmp_root/export-$directive" "$stub_edb" --name "export-$directive" >/dev/null 2>&1
  xi="$tmp_root/export-$directive/docs"
  fixture_docs "$xi" share-book
  printf '\n{{#%s ../../secret.txt}}\n' "$directive" >> "$xi/5-issues.md"
  out="$("$exporter" zip "$xi" "$tmp_root/export-$directive/report.zip" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then pass "zip: a {{#$directive}} fails the export"; else fail "zip: a {{#$directive}} fails the export"; fi
  expect_contains "zip: the {{#$directive}} error names the page and line" "$out" "{{#$directive in 5-issues.md line 7"
  expect_no_file "zip: a {{#$directive}} writes no zip" "$tmp_root/export-$directive/report.zip"
done

# mdbook turns 10\.0\.1\.15 into 10.0.1.15, which the staged scan cannot see.  The scan of the
# built HTML catches it, names the file and line, and writes no zip.
bash "$bin/setup-cluster.sh" "$tmp_root/export-built" "$stub_edb" --name export-built >/dev/null 2>&1
xh="$tmp_root/export-built/docs"
fixture_docs "$xh" share-book
printf '\nEscaped: 10\\.0\\.1\\.15\n' >> "$xh/5-issues.md"
out="$("$exporter" zip "$xh" "$tmp_root/export-built/report.zip" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "zip: an identifier in the built HTML fails the export"; else fail "zip: an identifier in the built HTML fails the export"; fi
expect_contains "zip: the built HTML error names the page" "$out" "IPv4 address in 5-issues.html line"
expect_contains "zip: the built HTML error names the print page" "$out" "IPv4 address in print.html line"
expect_contains "zip: the built HTML error names the search index" "$out" "IPv4 address in searchindex"
expect_no_file "zip: an identifier in the built HTML writes no zip" "$tmp_root/export-built/report.zip"

ews="$tmp_root/make-empty-title"
bash "$bin/setup-cluster.sh" "$ews" "$stub_edb" --name fallback-name >/dev/null 2>&1
cp -R "$fixtures/docs-agree/." "$ews/docs/"
perl -pi -e 's/^# .*/#/ if $. == 1' "$ews/docs/1-summary.md"
make -s -C "$ews/docs" build >/dev/null 2>&1
expect_contains "make: an empty H1 keeps the book.toml title" \
  "$(grep -o 'menu-title">[^<]*' "$ews/docs/report/index.html" 2>/dev/null)" 'menu-title">fallback-name'

fws="$tmp_root/make-fail"
bash "$bin/setup-cluster.sh" "$fws" "$stub_edb" --name make-fail >/dev/null 2>&1
fixture_docs "$fws/docs" wrong-sign
out="$(make -C "$fws/docs" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "make: a check FAIL stops make"; else fail "make: a check FAIL stops make"; fi
expect_contains "make: the check flags the sign before the build" "$out" "wrong sign"
expect_no_file "make: a check FAIL builds no report" "$fws/docs/report/index.html"

out="$(make -C "$fws/docs" gate REASONS='--reason "reviewer saw a confound"' 2>&1)"
expect_eq "make: gate exits 0 on a content FAIL" "0" "$?"
expect_file "make: gate builds the report" "$fws/docs/report/index.html"
expect_file "make: gate writes the exports" "$fws/docs/export/report.zip"
expect_contains "make: gate passes REASONS to the checker" "$(grep '^⚠ Unchecked: ' "$fws/docs/1-summary.md")" "reviewer saw a confound"

# One bad-data fixture at make level; the check-level loop covers the rest.
bws="$tmp_root/make-data-bad-json"
bash "$bin/setup-cluster.sh" "$bws" "$stub_edb" --name data-bad-json >/dev/null 2>&1
fixture_docs "$bws/docs" data-bad-json
make -s -C "$bws/docs" gate >/dev/null 2>&1
expect_eq "make: gate exits 0 on bad data" "0" "$?"
expect_file "make: gate builds the report on bad data" "$bws/docs/report/index.html"
expect_file "make: gate writes the exports on bad data" "$bws/docs/export/report.zip"
expect_contains "make: gate writes the Unchecked line on bad data" "$(grep '^⚠ Unchecked: ' "$bws/docs/1-summary.md")" "data/scrape-alloc.json"

rws="$tmp_root/make-redact"
bash "$bin/setup-cluster.sh" "$rws" "$stub_edb" --name make-redact >/dev/null 2>&1
fixture_docs "$rws/docs" redact-tunnel
make -s -C "$rws/docs" gate >/dev/null 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then pass "make: gate stops on a redaction FAIL"; else fail "make: gate stops on a redaction FAIL"; fi
expect_no_file "make: a redaction FAIL builds no report" "$rws/docs/report/index.html"

mws2="$tmp_root/make-missing"
bash "$bin/setup-cluster.sh" "$mws2" "$stub_edb" --name make-missing >/dev/null 2>&1
fixture_docs "$mws2/docs" missing-image
make -s -C "$mws2/docs" >/dev/null 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then pass "make: a missing referenced image exits non-zero"; else fail "make: a missing referenced image exits non-zero"; fi
make -s -C "$mws2/docs" build export >/dev/null 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then pass "make: export alone also fails on the missing image"; else fail "make: export alone also fails on the missing image"; fi

out="$(PATH="$bin:$PATH" make -C "$aws_/docs" EDB_LAB_BIN=/no/such/dir check 2>&1)"
expect_eq "make: with no scripts in EDB_LAB_BIN, make finds them on PATH" "0" "$?"

make -s -C "$td/docs" build >/dev/null 2>&1
expect_eq "make: the arms scaffold builds" "0" "$?"
expect_contains "make: the arms sidebar lists each arm's journal" "$(toc_order "$td/docs/report")" "4-journal-candidate.html"

# --- references/report.md: the shared reference ---

ref="$(cat "$plugin/references/report.md" 2>/dev/null)"
for h in "## File Roles" "## The Tiers" "## The Summary Layout" "### Noise Floor" "## Evidence Blocks" \
  "### Threats to validity" "## Graphs" "## Prose Rules" "## Redaction" "### The shareable book" "## The Exit Rule" "## The Check" \
  "### The check subagent prompt" "### The check-failure rule" "### A redaction failure" "## Arms" \
  "### The arm gate" "### Final Finalize" "### Block with --arm-windows" "### Render" "### Block" \
  "### Overlay render" "### Hold and release"; do
  expect_contains "reference: report.md has $h" "$ref" "$h"
done
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "reference: <journal> is 4-journal.md in a single layout" "$ref" '| `<journal>` | `4-journal.md` | `4-journal-<arm>.md` |'
expect_contains "reference: the not-installed line" "$ref" "Reasoning review: not run (cassandra-expert not installed)"
expect_contains "reference: the finalize entry point" "$ref" "run <cluster-dir> --finalize"
expect_contains "reference: the Partial verdict" "$ref" "Partial: stopped after step N"
expect_contains "reference: a Partial summary with no evidence holds a Findings table" \
  "$(sed -n '/^## The Exit Rule/,/^## The Check/p' "$plugin/references/report.md")" "no measured evidence"
# The check writes its issues to <issues> before the subagent reads <issues>.
check_ref="$(sed -n '/^## The Check/,/^### The check subagent prompt/p' "$plugin/references/report.md")"
review_n="$(printf '%s\n' "$check_ref" | grep -n '^[0-9]\. \*\*The reasoning review' | cut -d: -f1)"
write_n="$(printf '%s\n' "$check_ref" | grep -n '^[0-9]\. \*\*Write the issues' | cut -d: -f1)"
subagent_n="$(printf '%s\n' "$check_ref" | grep -n '^[0-9]\. \*\*The check subagent' | cut -d: -f1)"
if [[ -n "$review_n" && -n "$write_n" && -n "$subagent_n" && "$review_n" -lt "$write_n" && "$write_n" -lt "$subagent_n" ]]; then
  pass "reference: the check writes <issues> before the subagent reads it"
else
  fail "reference: the check writes <issues> before the subagent reads it" "review=$review_n write=$write_n subagent=$subagent_n"
fi
fetch_ref="$(sed -n '/^### Fetch/,/^### The Grafana URL/p' "$plugin/references/report.md")"
expect_contains "reference: the Fetch example filters on the cluster label" \
  "$(printf '%s\n' "$fetch_ref" | grep -A1 'report-graph.py fetch')" '{cluster="'
expect_not_contains "reference: Fetch claims no tenant per arm" "$fetch_ref" "own Mimir URL and tenant"

# --- skills and references: no stale report structure ---

run_skill="$plugin/skills/run/SKILL.md"
explore_skill="$plugin/skills/explore/SKILL.md"
plan_skill="$plugin/skills/plan/SKILL.md"
upload_ref="$plugin/references/report-upload.md"
journal_ref="$plugin/references/journal.md"
issues_ref="$plugin/references/issues.md"
for f in "$plan_skill" "$run_skill" "$explore_skill" "$upload_ref" "$journal_ref" "$issues_ref"; do
  name="${f#"$plugin/"}"
  # results.md anywhere; the old docs/ paths; the old journal and issues names in backticks.  A
  # backticked plan.md is the plan skill's own output file, not a docs/ name.
  # shellcheck disable=SC2016 # the backticks are literal markdown
  stale="$(grep -nE 'results\.md|docs/(plan|journal|issues)\.md|`(journal|issues)\.md`|the fixed four' "$f")"
  expect_eq "docs: $name holds no old report file name" "" "$stale"
  if grep -qE 'report\.md|<journal>|<issues>|1-summary\.md' "$f"; then
    pass "docs: $name describes the tiered report or points to report.md"
  else
    fail "docs: $name describes the tiered report or points to report.md"
  fi
done
for f in "$run_skill" "$journal_ref"; do
  expect_eq "docs: ${f#"$plugin/"} holds no Grafana screenshot instruction" "" "$(grep -niE 'screenshot' "$f")"
done
# Grafana renders replaced local plotting: no plot step, no shared style, no fixed role colours, and
# no render as an optional appendix image.  Each file points to render and block instead.
for f in "$report_ref" "$journal_ref" "$run_skill" "$explore_skill"; do
  name="${f#"$plugin/"}"
  # shellcheck disable=SC2016 # the backticks are literal markdown
  expect_eq "docs: $name holds no plotting instruction" "" \
    "$(grep -niE 'report-graph\.py plot|`plot`|lab\.mplstyle|matplotlib|role colou?r|render image is optional|--align' "$f")"
  # shellcheck disable=SC2016 # the backticks are literal markdown
  if grep -qE '`render`|report-graph\.py.*render' "$f" && grep -qE '`block`|report-graph\.py.*block' "$f"; then
    pass "docs: $name points to render and block"
  else
    fail "docs: $name points to render and block"
  fi
done
# --- journal.md and issues.md: the entry format ---

# journal_lint <file>: print one line per format problem in a journal or issues text, and nothing for
# a clean text.  The rules are in references/journal.md "Format": a blank line between blocks, so
# markdown never joins two lines into one paragraph; each line 160 characters or fewer; and no
# command or absolute path in an inline code span, only in a fenced block.  A fence can be indented,
# and closes on a line of at least as many backticks; a fence open at the end is a problem.
journal_lint() {
  awk -v max=160 '
    function kind(l) { return l ~ /^#/ ? "heading" : l ~ /^ *([-*]|[0-9]+\.) / ? "list" : "prose" }
    function inline_commands(l,   s, n) {
      while (match(l, /`[^`]+`/)) {
        s = substr(l, RSTART + 1, RLENGTH - 2)
        l = substr(l, RSTART + RLENGTH)
        if (s ~ /^(\$[A-Za-z_]+|easy-db-lab|setup-cluster\.sh|detect-cluster-layout\.sh|report-graph\.py|report-check\.py|make|aws|curl|jq|cassandra|nodetool|cqlsh|bash|uv|ssh|cmp|sed) / ||
            s ~ /(^|[ =])\/[A-Za-z]/) n++
      }
      return n
    }
    {
      if (length($0) > max) printf "line %d: longer than %d characters\n", NR, max
      if (fence != "") { if ($0 ~ "^ *" fence "`*[ \t]*$") { fence = ""; prev = "fence" }; next }
      if ($0 ~ /^ *```/) {
        if (prev != "" && prev != "blank") printf "line %d: no blank line before the code block\n", NR
        match($0, /`+/); fence = substr($0, RSTART, RLENGTH); fence_line = NR; prev = "fence"; next
      }
      if ($0 ~ /^[ \t]*$/) { prev = "blank"; next }
      k = kind($0)
      if (prev == "heading") printf "line %d: no blank line after the heading\n", NR
      else if (prev == "prose") printf "line %d: joins the line above into one paragraph\n", NR
      else if (prev == "list" && k != "list") printf "line %d: no blank line after the list\n", NR
      else if (prev == "fence") printf "line %d: no blank line after the code block\n", NR
      if (inline_commands($0)) printf "line %d: a command or path in a sentence; put it in a code block\n", NR
      prev = k
    }
    END { if (fence != "") printf "line %d: unclosed code block\n", fence_line }' "$1"
}
# markdown_examples <file> <dir>: write each ```markdown or ````markdown block to <dir>/<line>.md,
# named for the line of its opening fence.
markdown_examples() {
  rm -rf "$2" && mkdir -p "$2"
  awk -v dir="$2" '
    out == "" && /^```+markdown$/ { match($0, /^`+/); fence = substr($0, 1, RLENGTH); out = dir "/" NR ".md"; next }
    out != "" && $0 == fence { close(out); out = ""; next }
    out != "" { print > out }' "$1"
}

expect_eq "journal lint: the good fixture is clean" "" "$(journal_lint "$fixtures/journal/good.md")"
bad_lint="$(journal_lint "$fixtures/journal/bad.md")"
for problem in "no blank line after the heading" "joins the line above into one paragraph" \
  "longer than 160 characters" "a command or path in a sentence"; do
  expect_contains "journal lint: the bad fixture (the real 19:13 entry) gives: $problem" "$bad_lint" "$problem"
done
# A fence closes on a line of at least as many backticks, with leading and trailing spaces.  A fence
# can be indented under a list item.  A fence still open at the end is a problem.
while IFS='|' read -r fixture want; do
  expect_eq "journal lint: bad-fence-$fixture.md gives: $want" "$want" \
    "$(journal_lint "$fixtures/journal/bad-fence-$fixture.md")"
done <<'EOF'
trailing-space|line 6: no blank line after the code block
longer-close|line 6: no blank line after the code block
indented|line 9: no blank line after the code block
unclosed|line 5: unclosed code block
EOF

for f in "$journal_ref" "$issues_ref"; do
  name="${f#"$plugin/"}"
  ex_dir="$tmp_root/examples-$(basename "$f" .md)"
  markdown_examples "$f" "$ex_dir"
  n=0
  for ex in "$ex_dir"/*.md; do
    [[ -e "$ex" ]] || continue
    n=$((n + 1))
    expect_eq "docs: $name example at line $(basename "$ex" .md) keeps the entry format" "" "$(journal_lint "$ex")"
  done
  if [[ $n -ge 2 ]]; then pass "docs: $name holds the format and an example"; else fail "docs: $name holds the format and an example" "$n examples"; fi
done
journal_examples="$(cat "$tmp_root/examples-journal"/*.md 2>/dev/null)"
expect_contains "docs: a journal example holds a command in a fenced block" "$journal_examples" '```bash'
expect_contains "docs: a journal example holds a failed result" "$journal_examples" "**Result: failed**"
expect_contains "docs: a journal example ends with the next step" "$journal_examples" "**Next:**"
journal_format="$(sed -n '/^## Format/,/^## Measurements/p' "$journal_ref")"
# shellcheck disable=SC2016 # the backticks and $ names are literal markdown
for rule in "blank line" "160 characters" '`\`' '`$EDB`' '`$DOCS`' '`$TEST_DIR`' "**Result: failed**" "one bullet" "fenced block" \
  "The first entry that uses a variable records its value" '`**Vars:**`' "values that matter to the failure" \
  '"Redaction" in `report.md`' "attempt count" "each distinct error"; do
  expect_contains "docs: the journal Format states the rule: $rule" "$journal_format" "$rule"
done
expect_contains "docs: a journal example records the value of EDB where it first uses it" "$journal_examples" "EDB=/"
expect_contains "docs: the failure example records the proxy it used" "$journal_examples" "PROXY=socks5h://"
expect_contains "docs: the failure example records the query of the failed fetch" "$journal_examples" "QUERY='"
expect_contains "docs: the failure example gives the retry loop one bullet" "$journal_examples" "**Retries:** 3 attempts"
# A step's first entry gets its result, in the same entry or a follow-up entry that names the step.
for f in "$run_skill" "$explore_skill" "$report_ref"; do
  expect_eq "docs: ${f#"$plugin/"} writes no bare starting entry" "" "$(grep -n '+ "starting"' "$f")"
done
# shellcheck disable=SC2016 # the backticks are literal markdown
run_step_journal="$(sed -n '/^\*\*2\. Write to `<journal>`/,/^\*\*3\. Execute/p' "$run_skill")"
expect_contains "run: the step entry gets its result" "$run_step_journal" "follow-up entry that names the step"
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "run: the step entry points to journal.md" "$run_step_journal" '`../../references/journal.md`'
# shellcheck disable=SC2016 # the backticks are literal markdown
run_outcome="$(sed -n '/^\*\*5\. Update `<journal>` with outcome/,/^\*\*6\./p' "$run_skill")"
expect_contains "run: the outcome names the step" "$run_outcome" "names the step"
check_ref="$(sed -n '/^## The Check/,/^### The check subagent prompt/p' "$report_ref")"
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "reference: the check logs its passes as one journal bullet" "$check_ref" 'one bullet in `<journal>`'
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "reference: the check puts each pass's details in <issues>" "$check_ref" 'details go to `<issues>`'

arms_rule="$(sed -n '/^\*\*Parallel arms\.\*\*/,/^## /p' "$run_skill")"
expect_contains "run: Parallel arms renders the overlays before Final Finalize" "$arms_rule" "overlay"
expect_contains "run: Parallel arms releases the render arm" "$arms_rule" "release"
for f in "$run_skill" "$explore_skill"; do
  expect_contains "docs: ${f#"$plugin/"} loads the shared reference" "$(cat "$f")" "../../references/report.md"
done
run_text="$(cat "$run_skill")"
expect_not_contains "run: the stale step 66 reference is gone" "$run_text" "step 66 above"
expect_contains "run: resume detects docs/3-plan.md" "$run_text" "docs/3-plan.md"
expect_contains "run: the --arm mode" "$run_text" "run <test-dir> --arm <arm>"
expect_contains "run: the --finalize mode" "$run_text" "run <cluster-dir> --finalize"
expect_contains "run: arms resume reads the arm plan" "$run_text" "docs/3-plan-<arm>.md"
expect_contains "run: teardown without --arm is refused in arms mode" "$run_text" "refuse"
expect_contains "run: the pause writes a Partial summary" "$run_text" "Partial: stopped after step N"
expect_contains "run: Parallel arms is one test directory" "$run_text" "LAYOUT=arms"
expect_contains "run: the calibration rule is unchanged" "$run_text" \
  "The arms sit on different hardware, so run an identical short calibration workload before the measured run. It tells you whether the clusters are comparable at all, and its spread is the error bar on every delta you later report."
expect_not_contains "run: no separate workspace per arm" "$run_text" "each with its own workspace and its own"
explore_text="$(cat "$explore_skill")"
# shellcheck disable=SC2016 # the command is literal skill text
expect_contains "explore: scaffolds with --docs-only" "$explore_text" 'setup-cluster.sh "$PWD" --docs-only --name "$(basename "$PWD")"'
expect_not_contains "explore: the DCS=bin special case is gone" "$explore_text" "DCS=bin"
expect_contains "explore: refuses a source checkout" "$explore_text" "source checkout"
expect_contains "explore: teardown writes a Findings table" "$explore_text" "Findings table"
plan_text="$(cat "$plan_skill")"
for f in 1-summary.md 4-journal.md 5-issues.md; do
  expect_contains "plan: --previous reads docs/$f" "$plan_text" "<cluster-dir>/docs/$f"
done
expect_not_contains "plan: no Performance Results section" "$plan_text" "Performance Results"
expect_contains "plan: points to report.md" "$plan_text" "references/report.md"
expect_contains "cassandra: Multi-DC Setup applies to LAYOUT=multi only" \
  "$(sed -n '/^## Multi-DC Setup/,/^### Prerequisites/p' "$plugin/references/cassandra.md")" "LAYOUT=multi"
expect_eq "readme: no easy-db-lab operator agent" "" "$(grep -n 'easy-db-lab operator' "$plugin/../../README.md")"

down_rule="$(sed -n '/^### A failed down after a good upload/,/^##/p' "$upload_ref")"
expect_contains "upload: a failed down after a good upload is not an upload failure" "$down_rule" "not an upload failure"
expect_contains "upload: a failed down re-runs the gate once" "$down_rule" "once"
expect_contains "upload: a second failed down names the workspace" "$down_rule" "workspace path"
expect_contains "upload: a failed down checks whether the infrastructure is gone" "$down_rule" "already gone"
expect_contains "upload: a failed down looks up the VPC by its ID" "$down_rule" "describe-vpcs --vpc-ids"
expect_contains "upload: a failed down names the retry error when the VPC is gone" "$down_rule" "vpc does not exist"
expect_contains "upload: gone infrastructure reports the stale local state" "$down_rule" "stale local state"
expect_contains "upload: a failed arm down re-runs the arm gate" "$down_rule" "In an arm, run the arm gate again"
gone_n="$(printf '%s\n' "$down_rule" | grep -n 'already gone' | head -n 1 | cut -d: -f1)"
retry_n="$(printf '%s\n' "$down_rule" | grep -n 'Run the gate again once' | head -n 1 | cut -d: -f1)"
if [[ -n "$gone_n" && -n "$retry_n" && "$gone_n" -lt "$retry_n" ]]; then
  pass "upload: the gone check comes before the retry"
else
  fail "upload: the gone check comes before the retry" "gone=$gone_n retry=$retry_n"
fi
arm_gate="$(sed -n '/^### The arm gate/,/^### /p' "$upload_ref")"
expect_contains "upload: the arm gate points to the failed-down rule" "$arm_gate" "A failed down after a good upload"
image_ref="$(sed -n '/^### Image and CSV support/,/^## /p' "$upload_ref")"
expect_contains "upload: a .md-only binary warns of broken images in the index" "$image_ref" "broken image"
expect_contains "upload: the warning names where the images are" "$image_ref" "export/report.zip"

# The image and CSV support probe in report-upload.md, run as written against the stub binary.  The
# stub's commands outputs have the real layout: report, upload, and <FILE> on three lines, plus a
# <FILE> line with .png and .csv under another command.
# shellcheck disable=SC2016 # a literal $EDB in the pattern
probe="$(sed -n '/^### Image and CSV support/,/^## /p' "$upload_ref" | grep -E '^\$EDB commands \|' | head -n 1)"
if [[ -z "$probe" ]]; then
  fail "upload: report-upload.md holds the image and CSV probe"
else
  pass "upload: report-upload.md holds the image and CSV probe"
  out="$(EDB="$stub_edb" STUB_COMMANDS="$fixtures/bin/commands-md-only.txt" bash -c "${probe//\$EDB/\"\$EDB\"}")"
  expect_eq "upload: a .md-only binary gets .md uploads only" "images and CSV: not supported" "$out"
  out="$(EDB="$stub_edb" STUB_COMMANDS="$fixtures/bin/commands-png-csv.txt" bash -c "${probe//\$EDB/\"\$EDB\"}")"
  expect_eq "upload: a .png and .csv binary gets images and CSV" "images and CSV: supported" "$out"
fi

# The SSO session check in report-upload.md, run as written against a stub aws and a temp HOME.
# The stub answers `configure get sso_session` and `configure get sso_start_url` from STUB_SESSION and
# STUB_START_URL, and exits 1 for an empty value, as the real aws does for an unset key.  It answers
# `sts get-caller-identity` with exit STUB_STS_RC; a failure prints a blank line and two error lines on
# stderr, as the real aws does.
sso_step="$(first_bash_block "$upload_ref" "## The AWS SSO Session")"
if [[ "$sso_step" == *"expiresAt"* ]]; then
  pass "upload: report-upload.md holds the SSO session check"
else
  fail "upload: report-upload.md holds the SSO session check"
fi
sso_bin="$tmp_root/sso-bin"
sso_home="$tmp_root/sso-home"
mkdir -p "$sso_bin" "$sso_home/.aws/sso/cache"
cat >"$sso_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "sts get-caller-identity --profile $STUB_PROFILE" ]]; then
  if [[ "${STUB_STS_RC:-0}" -ne 0 ]]; then
    echo "" >&2
    echo "An error occurred (ExpiredToken) when calling the GetCallerIdentity operation: The token is expired" >&2
    echo "second line" >&2
  else
    echo '{"Account": "123456789012"}'
  fi
  exit "${STUB_STS_RC:-0}"
fi
[[ "$1 $2 $4 $5" == "configure get --profile $STUB_PROFILE" ]] || exit 2
case "$3" in
  sso_session) v="${STUB_SESSION:-}" ;;
  sso_start_url) v="${STUB_START_URL:-}" ;;
  *) v= ;;
esac
[[ -n "$v" ]] || exit 1
echo "$v"
EOF
chmod +x "$sso_bin/aws"
# sso <session> <start url> <expiresAt or ""> [refresh|norefresh] [sts rc]: write the token cache
# for the key, with secret token values, and run the step.
sso() {
  rm -f "$sso_home/.aws/sso/cache/"*.json
  local key="${1:-$2}" refresh=""
  [[ "${4:-refresh}" == norefresh ]] || refresh=', "refreshToken": "SECRET-REFRESH-VALUE"'
  [[ -z "$3" ]] || printf '{"accessToken": "SECRET-ACCESS-VALUE", "expiresAt": "%s"%s}\n' "$3" "$refresh" \
    >"$sso_home/.aws/sso/cache/$(printf %s "$key" | shasum -a 1 | cut -d' ' -f1).json"
  out="$(HOME="$sso_home" AWS_PROFILE=lab-user STUB_PROFILE=lab-user STUB_SESSION="$1" STUB_START_URL="$2" \
    STUB_STS_RC="${5:-0}" PATH="$sso_bin:$PATH" bash -c "$sso_step" 2>&1)"
}
sso_warn() { echo "SSO: WARN: the access token has $1 minutes left; the SDK refreshes it from the refresh token"; }
in_2h="$(jq -nr 'now + 7230 | todate')"
sso easy-db-lab "" "$in_2h"
expect_eq "sso step: a refreshable session warns with the minutes left" "$(sso_warn 120)" "$out"
sso easy-db-lab "" "${in_2h%Z}.220061Z"
expect_eq "sso step: fractional seconds parse" "$(sso_warn 120)" "$out"
sso "" "https://example.awsapps.com/start" "${in_2h%Z}UTC"
expect_eq "sso step: a legacy start URL profile and a UTC suffix parse" "$(sso_warn 120)" "$out"
sso easy-db-lab "" "$(jq -nr 'now + 630 | todate')"
expect_eq "sso step: 10 minutes left with a refresh token is a warning, not a stop" "$(sso_warn 10)" "$out"
sso easy-db-lab "" "$(jq -nr 'now - 600 | todate')"
expect_eq "sso step: an expired access token with a refresh token is a warning" "$(sso_warn 0)" "$out"
sso easy-db-lab "" "$in_2h" norefresh
# shellcheck disable=SC2016 # a literal $AWS_PROFILE in the step output
expect_eq "sso step: no refresh token stops for a login" \
  'SSO: STOP: no refresh token for lab-user; run aws sso login --profile "$AWS_PROFILE"' "$out"
sso easy-db-lab "" "$in_2h" refresh 255
# shellcheck disable=SC2016 # a literal $AWS_PROFILE in the step output
expect_eq "sso step: an sts failure stops for a login and names the first error line" \
  'SSO: STOP: aws sts get-caller-identity failed for lab-user: An error occurred (ExpiredToken) when calling the GetCallerIdentity operation: The token is expired; run aws sso login --profile "$AWS_PROFILE"' "$out"
sso easy-db-lab "" ""
# shellcheck disable=SC2016 # a literal $AWS_PROFILE in the step output
expect_eq "sso step: no cached token stops for a login" \
  'SSO: STOP: no token for lab-user; run aws sso login --profile "$AWS_PROFILE"' "$out"
sso "" "" ""
expect_eq "sso step: a profile with no SSO is named" "SSO: lab-user is not an SSO profile" "$out"
sso easy-db-lab "" "$in_2h"
expect_not_contains "sso step: prints no token value" "$out" "SECRET"
sso easy-db-lab "" "$in_2h" norefresh
expect_not_contains "sso step: a stop prints no token value" "$out" "SECRET"
sso_ref="$(sed -n '/^## The AWS SSO Session/,/^## /p' "$upload_ref")"
# shellcheck disable=SC2016 # a literal $AWS_PROFILE in the skill text
expect_contains "upload: the SSO check names the login command" "$sso_ref" 'aws sso login --profile "$AWS_PROFILE"'
expect_contains "upload: the SSO check names sts" "$sso_ref" "get-caller-identity"
expect_contains "upload: a WARN never stops a run" "$sso_ref" "A WARN never stops a run"
expect_contains "upload: an expired-token failure before an upload or a teardown stops with the cluster up" "$sso_ref" \
  "Before each upload and each teardown"
expect_contains "upload: the expired-token rule names ExpiredToken" "$sso_ref" "ExpiredToken"
expect_contains "upload: an unattended expired-token stop reports CLUSTER STILL UP" "$sso_ref" "CLUSTER STILL UP"
expect_contains "upload: the run resumes at the gate after the login" "$sso_ref" "resume at the gate"
expect_not_contains "upload: no minutes-left stop rule" "$sso_ref" "If fewer minutes remain"
# shellcheck disable=SC2016 # a literal $AWS_PROFILE in the reference text
expect_eq "upload: every aws sso login names the profile" "" \
  "$(grep -n 'aws sso login' "$upload_ref" | grep -v 'aws sso login --profile "$AWS_PROFILE"')"
for f in "$run_skill" "$explore_skill"; do
  expect_contains "docs: ${f#"$plugin/"} runs the SSO session check" "$(cat "$f")" '"The AWS SSO Session"'
  expect_not_contains "docs: ${f#"$plugin/"} has no minutes-left stop" "$(cat "$f")" "real expiry"
done

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
