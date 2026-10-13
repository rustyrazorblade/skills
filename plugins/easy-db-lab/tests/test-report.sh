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

# fetch <mimir-url> <name> [extra args...]: run fetch on the graph workspace with the usual window.
fetch() {
  local url="$1" name="$2"
  shift 2
  "$graph" fetch --mimir-url "$url" --tenant lab-tenant \
    --query 'sum by (instance) (rate(jvm_gc_memory_allocated_bytes_total{instance=~"db.*"}[1m]))' \
    --start 2026-10-01T10:00:00Z --end 2026-10-01T10:10:00Z --step 30s \
    --node-label instance --unit MB/s --scale 1e-6 --name "$name" --docs "$gdocs" "$@"
}

out="$(fetch http://127.0.0.1:1/prometheus unreachable --arm baseline=db0 --arm candidate=db2 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then pass "fetch: an unreachable Mimir exits non-zero"; else fail "fetch: an unreachable Mimir exits non-zero"; fi
expect_contains "fetch: an unreachable Mimir gives a clear message" "$out" "cannot reach Mimir"
expect_no_file "fetch: an unreachable Mimir writes no CSV" "$gdocs/data/unreachable.csv"

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
EOF

for name in noise-not-measured partial findings cassandra-done cassandra-not-installed; do
  run_check "$name"
  expect_eq "check: $name exits 0" "0" "$check_rc"
  expect_not_contains "check: $name has no FAIL" "$check_out" "FAIL"
done
run_check partial
expect_not_contains "check: the Partial token is not a numeral in prose" "$check_out" "WARN"

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
EOF

out="$("$checker" "$tmp_root/no-such-docs" 2>&1)"
expect_eq "check: a bad path exits 2" "2" "$?"
out="$("$checker" 2>&1)"
expect_eq "check: no path exits 2" "2" "$?"

out="$("$checker" "$ws_noplan/docs" 2>&1)"
expect_eq "check: the bare scaffold passes, so make works on it" "0" "$?"

# No file edit without --gate.
fixture_docs "$tmp_root/nogate" wrong-sign
before="$(tree_sum "$tmp_root/nogate")"
"$checker" "$tmp_root/nogate" >/dev/null 2>&1
expect_eq "check: no file edit without --gate" "$before" "$(tree_sum "$tmp_root/nogate")"

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

fixture_docs "$tmp_root/gate-redact" redact-tunnel
before="$(tree_sum "$tmp_root/gate-redact")"
"$checker" --gate "$tmp_root/gate-redact" >/dev/null 2>&1
expect_eq "gate: a redaction FAIL with --gate exits 3" "3" "$?"
expect_eq "gate: a redaction FAIL edits no file" "$before" "$(tree_sum "$tmp_root/gate-redact")"

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
