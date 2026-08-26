#!/usr/bin/env bash
# Dev-only convenience for QA'ing explain's own source end to end: builds a small throwaway git
# repo from scripts/preview-fixture/ (a baseline commit, then an uncommitted "in-flight change")
# and renders it with every generate-explain.py input flag combined into ONE view -- explain is a
# single interface for code diffs, docs, issues, and OpenSpec content together, not separate
# tools, so the preview demonstrates all of it at once rather than one feature at a time:
#
#   - OpenSpec delta spec (ADDED/MODIFIED/REMOVED, with a real Currently:/This change: baseline
#     comparison), path-detected via --diff, same as a real in-flight OpenSpec change would be
#   - a MODIFIED code file diff (the code implementing the MODIFIED requirement above)
#   - a NEW code file diff (implementing the ADDED requirement) -- "new" badge
#   - a DELETED code file diff (the code the REMOVED requirement retires) -- "deleted" badge
#   - --blame commit-history context on the modified file
#   - --explain-map overriding the new file's blame with a real curated explanation
#   - --doc (a plain markdown file, no delta headers) and --code (a plain code file, not a diff)
#   - --symbol blast-radius search
#   - --issue (a primary issue + a related one via both a dependency link and a #N mention) and
#     --pr review comments (one anchored inside the diff, one outside it) -- via a fake `gh` on
#     PATH, so this needs no real GitHub repo or network access
#
# NOT part of the skill's shipped CLI surface -- nothing in SKILL.md documents this as a feature
# of `explain` itself. macOS bash 3.2 compatible.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
fixture_dir="$script_dir/preview-fixture"
generate_explain="$script_dir/generate-explain.py"

if [[ ! -d "$fixture_dir" ]]; then
  echo "preview: fixture dir not found at $fixture_dir — was scripts/preview-fixture/ removed?" >&2
  exit 1
fi

command -v git >/dev/null 2>&1 || { echo "preview: 'git' is required but not on PATH." >&2; exit 1; }

# A throwaway git repo, rebuilt fresh every run -- generate-explain.py's --diff needs real git
# history to diff against, which a plain fixture directory (no .git of its own -- nesting one
# inside this repo's own tracked tree would create a submodule-like gitlink) can't provide.
repo="$(mktemp -d "${TMPDIR:-/tmp}/explain-preview-repo.XXXXXX")"
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT

git -C "$repo" init -q
git -C "$repo" config user.email "preview@example.com"
git -C "$repo" config user.name "explain preview"

# Baseline commit: the widget capability BEFORE the in-flight "demo" change -- its baseline spec
# and the two source files it touches (one to be modified, one to be deleted).
mkdir -p "$repo/openspec/specs/widget" "$repo/src"
cp "$fixture_dir/openspec/specs/widget/spec.md" "$repo/openspec/specs/widget/spec.md"
cp "$fixture_dir/baseline-src/widget.py" "$repo/src/widget.py"
cp "$fixture_dir/baseline-src/legacy_export.py" "$repo/src/legacy_export.py"
git -C "$repo" add -A
git -C "$repo" commit -q -m "baseline"
base_sha="$(git -C "$repo" rev-parse HEAD)"

# Uncommitted "in-flight change": the delta spec (new file), the code implementing its MODIFIED
# requirement (edits the tracked widget.py), the code implementing its ADDED requirement (a new
# file), and the REMOVED requirement's retirement (deletes legacy_export.py). Left uncommitted,
# the same as a real change explain would be pointed at mid-review.
mkdir -p "$repo/openspec/changes/demo/specs/widget"
cp "$fixture_dir/openspec/changes/demo/specs/widget/spec.md" "$repo/openspec/changes/demo/specs/widget/spec.md"
cp "$fixture_dir/src/widget.py" "$repo/src/widget.py"
cp "$fixture_dir/src/widget_renaming.py" "$repo/src/widget_renaming.py"
rm "$repo/src/legacy_export.py"
git -C "$repo" add -A  # stages the new delta spec + new file so `git diff <base>` picks them up

# --doc/--code are plain disk reads, no git tracking required -- copied in (untracked, outside
# the diff) purely so they display with clean relative paths in the tree instead of this
# machine's absolute fixture path.
mkdir -p "$repo/docs"
cp "$fixture_dir/docs/widget-notes.md" "$repo/docs/widget-notes.md"
cp "$fixture_dir/src/widget_helpers.py" "$repo/src/widget_helpers.py"

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/explain-preview.XXXXXX")"
out="$out_dir/explain-preview.html"

(
  cd "$repo" && PATH="$fixture_dir/fake-gh:$PATH" python3 "$generate_explain" \
    --diff --base "$base_sha" --blame \
    --issue 1 \
    --pr 42 \
    --doc docs/widget-notes.md \
    --code src/widget_helpers.py \
    --symbol attachments \
    --explain-map "$fixture_dir/explain-map.json" \
    --title "explain preview — every feature" \
    --subtitle "OpenSpec delta spec + modified/new/deleted code diffs + doc + code + blast-radius + issue/PR comments, all in one view" \
    --out "$out" --open
)
# generate-explain.py itself already prints the output path + "open <path>" on success -- no
# need to repeat it here.
