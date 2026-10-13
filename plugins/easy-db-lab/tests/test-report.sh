#!/usr/bin/env bash
# Behavioral test for the easy-db-lab lab report: the scaffold that setup-cluster.sh writes, the
# layout scripts, the graph, check, and export scripts, the docs Makefile, and the skill text. It
# needs mdbook and uv, and no cluster. A stub easy-db-lab binary and a stub Mimir stand in for the
# real ones. Prints PASS or FAIL per case and exits 0 only when every case passes. macOS bash 3.2
# compatible (no associative arrays, no mapfile). Touches nothing outside its own temp directory.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
fixtures="$here/fixtures"

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

echo ""
echo "$pass_count passed, $fail_count failed"
if [[ $pass_count -eq 0 ]]; then
  echo "test-report: no case ran" >&2
  exit 1
fi
[[ $fail_count -eq 0 ]]
