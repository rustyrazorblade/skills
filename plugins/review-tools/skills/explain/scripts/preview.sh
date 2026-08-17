#!/usr/bin/env bash
# Dev-only convenience for iterating on explain's own source: always renders the same canned
# OpenSpec fixture (ADDED + a MODIFIED requirement with a real baseline match + REMOVED), so the
# OpenSpec-aware rendering (and explain generally) can be seen and demonstrated regardless of
# whether this repo happens to have a real in-flight diff at the moment. NOT part of the skill's
# shipped CLI surface -- nothing in SKILL.md documents this as a feature of `explain` itself.
# macOS bash 3.2 compatible.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
fixture_dir="$script_dir/preview-fixture"
generate_explain="$script_dir/generate-explain.py"

if [[ ! -d "$fixture_dir" ]]; then
  echo "preview: fixture dir not found at $fixture_dir — was scripts/preview-fixture/ removed?" >&2
  exit 1
fi

out="$(mktemp -t explain-preview).html"

# Run from inside the fixture so --change's relative path resolves the same way a real caller's
# would, and so the delta spec's baseline lookup (openspec/specs/widget/spec.md) resolves
# relative to the SAME cwd -- see generate-explain.py's baseline_path_for()/read_file_at_ref().
(
  cd "$fixture_dir" && python3 "$generate_explain" \
    --change openspec/changes/demo \
    --title "explain preview" --subtitle "canned OpenSpec fixture — ADDED / MODIFIED / REMOVED" \
    --out "$out" --open
)

echo "preview: generated $out"
echo "open $out"
