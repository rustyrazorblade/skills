#!/usr/bin/env bash
# Structural self-test for generate-walkthrough.py + viewer.html. Runs the generator against the
# checked-in fixtures/ manifests and asserts on the output HTML — see README.md in this directory
# for how to run it. Exits non-zero if any assertion fails. macOS bash 3.2 compatible (no
# associative arrays, no mapfile); the JSON-shaped assertions delegate to python3, which the
# generator itself already requires.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
generate_walkthrough="$script_dir/generate-walkthrough.py"
viewer_html="$script_dir/../assets/viewer.html"
fixtures="$script_dir/fixtures"

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

tally_py() {
  # usage: tally_py "<python output>" — counts its PASS:/FAIL: lines into the running totals
  local out="$1"
  echo "$out"
  pass_count=$((pass_count + $(echo "$out" | grep -c '^PASS:')))
  fail_count=$((fail_count + $(echo "$out" | grep -c '^FAIL:')))
}

# usage: expect_failure "<description>" <fixture-or-empty> [expected substring...]
# Asserts: non-zero exit, no output file produced, and (when given) each substring appears in
# stderr. The fixture is a basename under fixtures/, or an absolute path for one built on the
# fly; empty means "invoke with no --manifest at all".
expect_failure() {
  local desc="$1"
  local fixture="$2"
  shift 2

  local err_file="$out_dir/err.txt"
  local target="$out_dir/should-not-exist.html"
  rm -f "$target"

  local manifest_path="$fixtures/$fixture"
  [[ "$fixture" == /* ]] && manifest_path="$fixture"

  if [[ -n "$fixture" ]]; then
    python3 "$generate_walkthrough" --manifest "$manifest_path" --out "$target" \
      >/dev/null 2>"$err_file"
  else
    python3 "$generate_walkthrough" --out "$target" >/dev/null 2>"$err_file"
  fi
  local status=$?

  [[ "$status" -ne 0 ]]
  check "$desc -> non-zero exit" $?

  [[ ! -f "$target" ]]
  check "$desc -> no output file produced" $?

  local needle
  for needle in "$@"; do
    # -e, so a needle that itself starts with "-" (e.g. "--manifest") isn't read as a grep flag
    grep -qF -e "$needle" "$err_file"
    check "$desc -> error message mentions '$needle'" $?
  done
}

command -v python3 >/dev/null 2>&1 || { echo "test-generate-walkthrough: 'python3' is required but not on PATH." >&2; exit 1; }

out_dir="$(mktemp -d)"
out_html="$out_dir/walkthrough-test.html"
cleanup() { rm -rf "$out_dir"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Happy path: a valid multi-step manifest renders.
# ---------------------------------------------------------------------------
python3 "$generate_walkthrough" --manifest "$fixtures/valid.json" --out "$out_html"
check "generate-walkthrough.py exits 0 on a valid manifest" $?

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
# JSON-shaped assertions on the injected manifest: diagram present, steps in
# the manifest's own order, excerpts and their file:line references intact.
# ---------------------------------------------------------------------------
tally_py "$(python3 - "$out_html" <<'PYEOF'
import json
import sys

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

if manifest.get("title") == "How the widget store loads" and manifest.get("subtitle"):
    print("PASS: title/subtitle round-trip from the manifest")
else:
    print(f"FAIL: title/subtitle — got {manifest.get('title')!r}/{manifest.get('subtitle')!r}")

diagram = manifest.get("diagram") or {}
if diagram.get("type") == "html" and "WidgetStore" in diagram.get("source", "") and diagram.get("caption"):
    print("PASS: diagram (type, source, caption) round-trips from the manifest")
else:
    print(f"FAIL: diagram round-trip — got {diagram!r}")

steps = manifest.get("steps", [])
titles = [s.get("title") for s in steps]
if titles == ["The entry point", "The cache miss path", "Where invalidation happens"]:
    print("PASS: steps render in the exact order given in the manifest")
else:
    print(f"FAIL: step order — got {titles}")

# The diagram must precede ALL step content in the document, not just in the manifest: the
# shell renders #diagram before #steps, and the injected payload keeps that structure.
diagram_pos = content.find('id="diagram"')
steps_pos = content.find('id="steps"')
if diagram_pos != -1 and steps_pos != -1 and diagram_pos < steps_pos:
    print("PASS: the diagram container precedes all step content in the rendered document")
else:
    print(f"FAIL: diagram/steps document order — diagram@{diagram_pos}, steps@{steps_pos}")

second = steps[1] if len(steps) > 1 else {}
excerpts = second.get("excerpts", [])
if len(excerpts) == 2 and excerpts[0]["path"] == "src/widget_store.py" and excerpts[1]["path"] == "src/loader.py":
    print("PASS: a step carries more than one excerpt, in order")
else:
    print(f"FAIL: multi-excerpt step — got {excerpts!r}")

first_excerpt = (steps[0].get("excerpts") or [{}])[0]
if (first_excerpt.get("path") == "src/widget_store.py" and first_excerpt.get("startLine") == 12
        and first_excerpt.get("endLine") == 15 and "def get" in first_excerpt.get("code", "")):
    print("PASS: an excerpt's code and its path/startLine/endLine reference travel together")
else:
    print(f"FAIL: excerpt file:line reference — got {first_excerpt!r}")

if first_excerpt.get("lang") == "python" and first_excerpt.get("highlight") == [13]:
    print("PASS: optional excerpt lang/highlight round-trip")
else:
    print(f"FAIL: excerpt lang/highlight — got {first_excerpt.get('lang')!r}/{first_excerpt.get('highlight')!r}")

if steps[0].get("kind") == "explanation" and "kind" not in steps[1]:
    print("PASS: kind is carried when present and absent when omitted")
else:
    print(f"FAIL: kind presence — got {steps[0].get('kind')!r} / {'kind' in steps[1]}")
PYEOF
)"

# ---------------------------------------------------------------------------
# Content-agnostic across walkthrough kinds: a tech-debt/performance/
# recommendation manifest goes through the exact same renderer, and an
# unrecognized kind string still renders rather than failing validation.
# ---------------------------------------------------------------------------
kinds_html="$out_dir/walkthrough-kinds.html"
python3 "$generate_walkthrough" --manifest "$fixtures/kinds.json" --out "$kinds_html"
check "a non-'how it works' manifest (tech-debt/performance/recommendation) exits 0" $?

tally_py "$(python3 - "$out_html" "$kinds_html" <<'PYEOF'
import json
import sys


def read(path):
    content = open(path, encoding="utf-8").read()
    start = content.index("<script>window.MANIFEST = ") + len("<script>window.MANIFEST = ")
    end = content.index(";</script>", start)
    return content, json.loads(content[start:end])


explanation_content, explanation = read(sys.argv[1])
kinds_content, kinds = read(sys.argv[2])

kind_values = [s.get("kind") for s in kinds.get("steps", [])]
if kind_values == ["tech-debt", "performance", "recommendation", "tech-dept", None]:
    print("PASS: every kind value (including an unrecognized one) survives validation unchanged")
else:
    print(f"FAIL: kind values — got {kind_values}")

# Same code path: strip the injected payload from both outputs; the remaining shell must be
# byte-identical, proving no per-kind rendering branch exists in the generator.
def shell_only(content):
    start = content.index("<script>window.MANIFEST = ")
    end = content.index(";</script>", start) + len(";</script>")
    return content[:start] + content[end:]


if shell_only(explanation_content) == shell_only(kinds_content):
    print("PASS: an explanation and a tech-debt/performance walkthrough render through the identical shell (no per-kind code path)")
else:
    print("FAIL: per-kind rendering divergence between the two outputs")

if kinds.get("diagram", {}).get("type") == "svg":
    print("PASS: an svg diagram is accepted alongside html")
else:
    print(f"FAIL: svg diagram — got {kinds.get('diagram')!r}")
PYEOF
)"

# ---------------------------------------------------------------------------
# Content that could break out of the injected <script> tag. An excerpt from an
# HTML template is ordinary input for this tool, and "<!--" followed by
# "<script" puts HTML's script-data tokenizer into double-escaped state — after
# which a later "</script>" no longer closes the tag and the page silently
# renders the shell's demo fallback instead of the real walkthrough.
# ---------------------------------------------------------------------------
hostile_html="$out_dir/walkthrough-script-data.html"
python3 "$generate_walkthrough" --manifest "$fixtures/script-data-content.json" --out "$hostile_html"
check "a manifest containing </script> and a conditional comment exits 0" $?

tally_py "$(python3 - "$hostile_html" <<'PYEOF'
import json
import sys

content = open(sys.argv[1], encoding="utf-8").read()
start_marker = "<script>window.MANIFEST = "
start = content.index(start_marker) + len(start_marker)
end = content.index(";</script>", start)
payload = content[start:end]

lt = "<"
script_open = "<script>"
if lt not in payload:
    print("PASS: no raw angle bracket survives into the injected payload (script-data tokenizer cannot be re-entered)")
else:
    idx = payload.index(lt)
    print(f"FAIL: raw angle bracket in the injected payload - {payload[idx - 40:idx + 40]!r}")

manifest = json.loads(payload)
code = manifest["steps"][0]["excerpts"][0]["code"]
if code.startswith("<!--[if IE]><script src=") and "</script>" in code:
    print("PASS: the escaped payload still parses back to the exact authored code, markup intact")
else:
    print(f"FAIL: code round-trip — got {code!r}")

# The viewer shell has its own <script> plus the injected one, and nothing the content opened.
script_count = content.count(script_open)
if script_count == 2:
    print("PASS: content markup never opens an extra script tag in the rendered document")
else:
    print(f"FAIL: unexpected <script> count — {script_count}")
PYEOF
)"

# ---------------------------------------------------------------------------
# Structural checks on the static viewer shell itself — no headless browser
# available here, so this greps for the branches/handlers a browser test would
# otherwise exercise, the same convention test-generate-explain.sh uses.
# ---------------------------------------------------------------------------
grep -qF 'window.MANIFEST' "$viewer_html"
check "viewer.html references window.MANIFEST" $?

grep -qF 'DEMO_MANIFEST' "$viewer_html"
check "viewer.html has a DEMO_MANIFEST fallback for opening the shell directly" $?

grep -qE 'function renderMarkdown' "$viewer_html"
check "viewer.html defines a markdown-render function for step narration" $?

grep -qE 'function inlineMD' "$viewer_html"
check "viewer.html defines the inline-markdown helper" $?

grep -qF 'diagram.source' "$viewer_html"
check "viewer.html embeds the diagram's source directly" $?

grep -qF 'diagram.caption' "$viewer_html"
check "viewer.html renders the diagram caption when given" $?

grep -qF 'step-kind' "$viewer_html"
check "viewer.html renders a per-step kind badge" $?

grep -qE 'step\.kind' "$viewer_html"
check "viewer.html branches on the optional step.kind (omitted -> no badge)" $?

grep -qF '":" + ' "$viewer_html"
check "viewer.html builds each excerpt's file:line source reference" $?

grep -qF 'excerpt-code' "$viewer_html"
check "viewer.html renders excerpt code blocks" $?

grep -qF 'data-lang' "$viewer_html"
check "viewer.html carries an excerpt's lang through as data-lang" $?

grep -qF 'scroll-snap-type: x mandatory' "$viewer_html"
check "viewer.html switches to horizontal via CSS scroll-snap, no JS animation" $?

grep -qF 'id="layout-toggle"' "$viewer_html"
check "viewer.html ships the runtime layout toggle control" $?

grep -qF 'classList.toggle("horizontal")' "$viewer_html"
check "the toggle flips a .horizontal class on the steps container (and back)" $?

grep -qF 'id="step-counter"' "$viewer_html"
check "viewer.html has a step counter" $?

grep -qF 'id="prev-step"' "$viewer_html" && grep -qF 'id="next-step"' "$viewer_html"
check "viewer.html has prev/next buttons" $?

grep -qF 'ArrowLeft' "$viewer_html" && grep -qF 'ArrowRight' "$viewer_html"
check "viewer.html handles left/right keyboard navigation" $?

grep -qE 'addEventListener\("keydown"' "$viewer_html"
check "viewer.html registers a keydown handler for arrow navigation" $?

# Vertical is the DEFAULT: the shipped steps container must carry no .horizontal class until
# the toggle is used, and the CSS must define the horizontal variant separately.
! grep -qE '<div id="steps"[^>]*class="[^"]*horizontal' "$viewer_html"
check "the steps container starts WITHOUT the .horizontal class (vertical by default)" $?

grep -qE '#steps\.horizontal' "$viewer_html"
check "horizontal layout is a CSS variant of the same container, not a separate artifact" $?

! grep -qE 'http://|https://|fetch\(' "$viewer_html"
check "viewer.html shell itself has no http(s):// or fetch( (file://-safe)" $?

# ---------------------------------------------------------------------------
# Loud failure: no manifest, an empty/unparseable manifest, or a manifest with
# no steps must exit non-zero and never leave an output file behind.
# ---------------------------------------------------------------------------
expect_failure "no --manifest at all" "" "--manifest"
expect_failure "a nonexistent manifest path" "does-not-exist.json" "not found"
expect_failure "an empty manifest file" "empty.json"
expect_failure "an unparseable manifest file" "not-json.json"
expect_failure "a manifest with an empty step list" "empty-steps.json" "steps"
expect_failure "a manifest with no title" "no-title.json" "title"

# Diagram is mandatory.
expect_failure "a manifest with no diagram at all" "no-diagram.json" "diagram"
expect_failure "a diagram with an empty source" "empty-diagram-source.json" "diagram" "source"
expect_failure "a diagram with an unsupported type" "bad-diagram-type.json" "diagram" "type"

# Step-level failures name the offending step by 1-based position and title.
expect_failure "a step missing its title" "step-missing-title.json" "step 2" "title"
expect_failure "a step missing its narration" "step-missing-narration.json" "step 2" "The narrationless step" "narration"
expect_failure "a step with an empty excerpt list" "step-empty-excerpts.json" "step 2" "The excerptless step" "excerpts"

# Excerpt-level failures name BOTH the step and the excerpt within it.
expect_failure "an excerpt missing its path" "excerpt-missing-path.json" "step 2" "The pathless-excerpt step" "excerpt 2" "path"
expect_failure "an excerpt missing its startLine" "excerpt-missing-startline.json" "step 1" "The startLine-less-excerpt step" "excerpt 1" "startLine"
expect_failure "an excerpt missing its code" "excerpt-missing-code.json" "step 1" "The codeless-excerpt step" "excerpt 1" "code"

# `highlight` is the one optional field the viewer iterates directly — a wrong type there would
# blank the rendered presentation while the generator still exited 0.
expect_failure "an excerpt whose highlight isn't a list of line numbers" "bad-highlight.json" "excerpt 1" "highlight"

# A manifest that isn't valid UTF-8 is an unreadable manifest, not a traceback.
bad_bytes="$out_dir/bad-bytes.json"
printf '{"title": "\377\376bad"}' > "$bad_bytes"
expect_failure "a manifest that isn't valid UTF-8" "$bad_bytes" "couldn't read"

echo ""
echo "----------------------------------------"
echo "PASS: $pass_count  FAIL: $fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
