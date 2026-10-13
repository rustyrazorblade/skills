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
  make_arms "$tmp_root/arms-reserved" baseline
  mkdir -p "$tmp_root/arms-reserved/$reserved"
  printf '#!/bin/sh\n' > "$tmp_root/arms-reserved/$reserved/easy-db-lab"
  chmod +x "$tmp_root/arms-reserved/$reserved/easy-db-lab"
  printf '%s\n' "$reserved" >> "$tmp_root/arms-reserved/arms"
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
trap 'stop_mimir; rm -rf "$tmp_root"' EXIT

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
trap 'stop_mimir; stop_grafana; rm -rf "$tmp_root"' EXIT

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
for p in panelId=7 from=1790848800000 to=1790849400000 var-cluster=graph-1a2b var-job=a+b width=1200 height=600 tz=UTC; do
  expect_contains "render: the request holds $p" "$req" "$p"
done
expect_eq "render: no file in docs/ holds the Grafana URL" "" "$(grep -rl "${grafana_url#http://}" "$gdocs" 2>/dev/null)"

rm -f "$grafana_log"
out="$(render "$grafana_url" relative --from now-93600s --to now 2>&1)"
expect_eq "render: a relative range exits 0" "0" "$?"
req="$(cat "$grafana_log" 2>/dev/null)"
expect_contains "render: now-93600s goes out unchanged" "$req" "from=now-93600s&"
expect_contains "render: now goes out unchanged" "$req" "to=now&"

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
rm -f "$gdocs/images/keep.png" "$gdocs/images/panel.png" "$gdocs/images/relative.png"

# --- report-graph.py plot ---

# pixel_colours <png> <hex>...: print each hex colour that some pixel of the PNG has exactly.
pixel_colours() {
  uv run --quiet --no-project --with pillow python3 - "$@" <<'PYEOF'
import sys
from PIL import Image
img = Image.open(sys.argv[1]).convert("RGB")
seen = set(img.getdata())
for h in sys.argv[2:]:
    if tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) in seen:
        print(h)
PYEOF
}

# plot reads CSVs from <docs>/data, as fetch writes them.
cp "$fixtures/graph/"* "$gdocs/data/"
gfix="$gdocs/data"
out="$("$graph" plot --csv "$gfix/baseline.csv" --csv "$gfix/candidate.csv" --name scrape-alloc \
  --title "Scrape allocation (MB/s)" --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
expect_eq "plot: two arms exit 0" "0" "$?"
expect_file "plot: writes images/<name>.png" "$gdocs/images/scrape-alloc.png"
colours="$(pixel_colours "$gdocs/images/scrape-alloc.png" 999999 0072B2 e6e6e6 2>&1 | tr '\n' ' ')"
expect_contains "plot: the baseline series is grey #999999" "$colours" "999999"
expect_contains "plot: the candidate series is blue #0072B2" "$colours" "0072B2"
expect_contains "plot: the PNG uses the shared style grid colour" "$colours" "e6e6e6"
expect_contains "plot: the block starts with the heading" "$out" "## Scrape allocation (MB/s)"
expect_contains "plot: the block holds the downloaded image" "$out" "![Scrape allocation (MB/s)](images/scrape-alloc.png)"
expect_contains "plot: the stats table has the default columns" "$out" "| Node | Arm | Samples | Min | p50 | Mean | p99 | Max | Unit |"
expect_contains "plot: numeric columns are right-aligned" "$out" "|:--|:--|--:|--:|--:|--:|--:|--:|:--|"
expect_contains "plot: a node row names the node with its role" "$out" "| db0 (baseline) | baseline | 21 | 26.92 |"
expect_contains "plot: one rollup row per arm, from pooled samples" "$out" "| all | baseline | 42 | 26.92 | 27.09 | 27.09 | 27.27 | 27.27 | MB/s |"
expect_contains "plot: the candidate rollup row" "$out" "| all | candidate | 21 | 32.72 |"
expect_contains "plot: the block holds the Window" "$out" "Window: 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s"
expect_contains "plot: the block holds the Query" "$out" 'Query: `sum by (instance)'
expect_contains "plot: the Data line links every CSV" "$out" "Data: [baseline.csv](data/baseline.csv), [candidate.csv](data/candidate.csv)"

out="$("$graph" plot --csv "$gfix/baseline.csv" --name counter --title "Counter" --stats samples,total,rate \
  --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
expect_contains "plot: --stats swaps the statistic columns" "$out" "| Node | Arm | Samples | Total | Rate | Unit |"
expect_contains "plot: swapped columns stay right-aligned" "$out" "|:--|:--|--:|--:|--:|:--|"

out="$("$graph" plot --csv "$gfix/tiny.csv" --name tiny --title "Tiny" --stats samples,min,mean \
  --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
expect_contains "plot: a value below 1e-4 is fixed-point, which report-check reads" "$out" "| all | baseline | 2 | 0.00001234 | 0.00001234 | s |"

out="$("$graph" plot --csv "$gfix/empty.csv" --name empty --title "Empty" --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "plot: empty input exits non-zero"; else fail "plot: empty input exits non-zero"; fi
expect_contains "plot: empty input gives a clear message" "$out" "no rows"
expect_no_file "plot: empty input writes no PNG" "$gdocs/images/empty.png"

for m in unit step query; do
  out="$("$graph" plot --csv "$gfix/baseline.csv" --csv "$gfix/mismatch-$m.csv" --name "mm-$m" --title "M" \
    --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then pass "plot: a mismatched $m is an error"; else fail "plot: a mismatched $m is an error"; fi
  expect_contains "plot: the error names the $m" "$out" "$m"
  expect_no_file "plot: a mismatched $m writes no PNG" "$gdocs/images/mm-$m.png"
done

out="$("$graph" plot --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-candidate.csv" --name read-latency \
  --title "Read latency (ms)" --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "plot: mismatched windows without --align are an error"; else fail "plot: mismatched windows without --align are an error"; fi
expect_contains "plot: the window error suggests --align elapsed" "$out" "--align elapsed"

out="$("$graph" plot --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-candidate.csv" --name read-latency \
  --title "Read latency (ms)" --align elapsed --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
expect_eq "plot: --align elapsed exits 0" "0" "$?"
expect_contains "plot: --align writes the baseline Window line" "$out" "Window (baseline): 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s"
expect_contains "plot: --align writes the candidate Window line" "$out" "Window (candidate): 2026-10-01T11:30:00Z to 2026-10-01T11:40:00Z (10m 0s), step 30s"
expect_contains "plot: --align keys nodes by arm" "$out" "| db0 (candidate) | candidate |"
expect_file "plot: --align writes the PNG" "$gdocs/images/read-latency.png"

out="$("$graph" plot --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-candidate.csv" \
  --csv "$gfix/latency-baseline-late.csv" --name shared-arm --title "Shared arm" --align elapsed \
  --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "plot: --align refuses two CSVs that share an arm"; else fail "plot: --align refuses two CSVs that share an arm"; fi
expect_contains "plot: the shared-arm refusal names the arm" "$out" "arm baseline"
expect_no_file "plot: the shared-arm refusal writes no PNG" "$gdocs/images/shared-arm.png"

# An arm in two CSVs with one window has one window, as report-check reads it.
out="$("$graph" plot --csv "$gfix/latency-baseline.csv" --csv "$gfix/latency-baseline-db2.csv" \
  --csv "$gfix/latency-candidate.csv" --name same-window --title "Same window" --align elapsed \
  --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
expect_eq "plot: --align accepts an arm in two CSVs with one window" "0" "$?"
expect_contains "plot: the same-window arm keeps both CSVs' nodes" "$out" "| db2 (baseline) | baseline |"

# time_labels <minutes>: the x tick labels that time_axis gives a window of that length, one per |.
time_labels() {
  uv run --quiet --no-project --with 'matplotlib>=3.8' python3 - "$graph" "$1" <<'PYEOF'
import importlib.util
import sys
from datetime import datetime, timedelta, timezone
spec = importlib.util.spec_from_file_location("report_graph", sys.argv[1])
graph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(graph)
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
t0 = datetime(2026, 10, 13, 12, 18, 30, tzinfo=timezone.utc)
xs = [t0 + timedelta(seconds=15 * i) for i in range(int(sys.argv[2]) * 4 + 1)]
ax.plot(xs, range(len(xs)))
graph.time_axis(ax)
fig.canvas.draw()
print("|".join(t.get_text() for t in ax.get_xticklabels() if t.get_text()))
PYEOF
}
for minutes in 4 600; do
  labels="$(time_labels "$minutes" 2>&1)"
  distinct="$(printf '%s\n' "$labels" | tr '|' '\n' | sort | uniq -d)"
  if [[ "$labels" == *"|"* && -z "$distinct" ]]; then
    pass "plot: a $minutes-minute window has distinct time labels"
  else
    fail "plot: a $minutes-minute window has distinct time labels" "$labels"
  fi
done

# Each arm filters on its own cluster label, so the queries differ only in the cluster matcher.
out="$("$graph" plot --csv "$gfix/cluster-baseline.csv" --csv "$gfix/cluster-candidate.csv" --name arm-cluster \
  --title "Arm cluster" --align elapsed --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
expect_eq "plot: queries that differ only in the cluster matcher exit 0" "0" "$?"
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "plot: the baseline arm keeps its own Query line" "$out" 'Query (baseline): `histogram_quantile(0.99, sum by (instance, le) (rate(cassandra_read_latency_seconds_bucket{cluster="lab-baseline-1a2b",'
# shellcheck disable=SC2016 # the backticks are literal markdown
expect_contains "plot: the candidate arm keeps its own Query line" "$out" 'Query (candidate): `histogram_quantile(0.99, sum by (instance, le) (rate(cassandra_read_latency_seconds_bucket{cluster=~"lab-candidate-.*",'
expect_not_contains "plot: per-arm queries give no shared Query line" "$out" "Query: "
out="$("$graph" plot --csv "$gfix/cluster-baseline.csv" --csv "$gfix/cluster-other.csv" --name arm-other \
  --title "Arm other" --align elapsed --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "plot: queries that differ past the cluster matcher are an error"; else fail "plot: queries that differ past the cluster matcher are an error"; fi
expect_contains "plot: the error names the query" "$out" "differ in query"
expect_no_file "plot: a query mismatch past the cluster matcher writes no PNG" "$gdocs/images/arm-other.png"

# --name is a file name: no path, no leading dot.
for bad in '../x' 'a/b' '..' '.hidden' 'a..b'; do
  out="$("$graph" plot --csv "$gfix/baseline.csv" --name "$bad" --title "Bad" \
    --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then pass "plot: --name $bad is refused"; else fail "plot: --name $bad is refused"; fi
  expect_contains "plot: the --name $bad refusal names the rule" "$out" "--name"
  out="$(fetch http://127.0.0.1:1/prometheus "$bad" --arm baseline=db0 2>&1)"
  expect_contains "fetch: the --name $bad refusal names the rule" "$out" "--name"
  expect_not_contains "fetch: --name $bad is refused before the query" "$out" "cannot reach Mimir"
done

out="$("$graph" plot --csv "$gfix/baseline.csv" --name nested --title "Nested" --page evidence/latency.md \
  --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
expect_contains "plot: --page makes the image link relative to a nested page" "$out" "![Nested](../images/nested.png)"
expect_contains "plot: --page makes the Data link relative to a nested page" "$out" "Data: [baseline.csv](../data/baseline.csv)"

out="$("$graph" plot --csv "$fixtures/graph/baseline.csv" --name outside --title "Outside" \
  --style "$gdocs/lab.mplstyle" --docs "$gdocs" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "plot: a CSV outside <docs>/data is refused"; else fail "plot: a CSV outside <docs>/data is refused"; fi
expect_contains "plot: the refusal names the data dir" "$out" "/data"

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
EOF

# Not redaction: a 12-digit metric value in data/*.csv and its stats table, infrastructure IDs in
# the appendix journal, and a dotted version string in summary prose.
for name in redact-ok-big-value redact-ok-journal redact-ok-version; do
  run_check "$name"
  expect_eq "check: $name exits 0" "0" "$check_rc"
  expect_not_contains "check: $name has no redaction FAIL" "$check_out" "FAIL: redaction"
done

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
expect_contains "jira: -- stays two escaped hyphens, not an en dash" "$jira_esc" 'plot \-\-align elapsed'
expect_contains "jira: an emoticon such as (i) stays escaped" "$jira_esc" '\(i)'

"$exporter" zip "$xd" "$tmp_root/report.zip" >/dev/null 2>&1
expect_eq "zip: exits 0" "0" "$?"
listing="$(unzip -Z1 "$tmp_root/report.zip" 2>/dev/null | sort | tr '\n' ' ')"
for f in 1-summary.md 2-evidence.md evidence/latency.md images/scrape-alloc.png images/read-latency.png \
  images/noise-latency.png data/scrape-alloc.csv data/latency-baseline.csv data/latency-candidate.csv data/noise-latency.csv; do
  expect_contains "zip: holds $f" "$listing" "$f "
done
for f in 3-plan.md 4-journal.md 5-issues.md SUMMARY.md; do
  expect_not_contains "zip: holds no $f" "$listing" "$f"
done

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
  "### Threats to validity" "## Graphs" "## Prose Rules" "## Redaction" "## The Exit Rule" "## The Check" \
  "### The check subagent prompt" "### The check-failure rule" "### A redaction failure" "## Arms" \
  "### The arm gate" "### Final Finalize" "### Plot with --align elapsed"; do
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
fetch_ref="$(sed -n '/^### Fetch/,/^### Plot/p' "$plugin/references/report.md")"
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
