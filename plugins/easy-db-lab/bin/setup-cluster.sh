#!/usr/bin/env bash
# Sets up a cluster workspace: directory structure, easy-db-lab wrapper(s), and lab report scaffold.
#
# Usage: setup-cluster.sh <cluster-dir> <binary-path> --name <cluster-name> [--jdk <path>] [--dc <dc-dir>]... [--plan <path>]
#
# Arguments:
#   cluster-dir       Path to the cluster workspace root. Created if it does not exist.
#   binary-path       Full path to the easy-db-lab binary, or "easy-db-lab" if on PATH.
#
# Options:
#   --name <name>     Cassandra cluster name. Shared across all nodes in all DCs. Also the
#                     fallback lab report title; make takes the title from 1-summary.md.
#   --jdk <path>      Java home directory. Bakes JAVA_HOME and PATH into every wrapper.
#   --dc <dc-dir>     Datacenter directory name (e.g. dc1, us-east). Repeat for each DC.
#                     When omitted, one wrapper is created at the cluster root (single DC).
#                     When provided, one wrapper is created per DC under <cluster-dir>/<dc-dir>/.
#   --plan <path>     Path to the plan. Copied to docs/3-plan.md as a record of what was executed.
#
# Directory layout — single DC:
#   <cluster-dir>/
#     easy-db-lab       ← wrapper (cds into cluster-dir)
#     docs/             ← lab report source
#
# Directory layout — multi-DC:
#   <cluster-dir>/
#     <dc1>/
#       easy-db-lab     ← wrapper (cds into <cluster-dir>/<dc1>)
#     <dc2>/
#       easy-db-lab
#     docs/             ← shared across DCs; one environment, multiple datacenters
#
# docs/ holds the tiered lab report.  Each file comes from scaffold/<file>.template:
#   1-summary.md, 2-evidence.md, 3-plan.md, 4-journal.md, 5-issues.md   ← tier files, copied only when absent
#   SUMMARY.md                                                         ← copied only when absent
#   book.toml, Makefile, lab.css, lab.mplstyle                         ← rewritten on every run
#   images/, data/                                                     ← graphs and their CSV
# The rules for the report are in references/report.md.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCAFFOLD="$SCRIPT_DIR/../scaffold"

CLUSTER_DIR="${1:?Usage: $0 <cluster-dir> <binary-path> --name <cluster-name> [--jdk <path>] [--dc <dc-dir>]... [--plan <path>]}"
BINARY_PATH="${2:?Usage: $0 <cluster-dir> <binary-path> --name <cluster-name> [--jdk <path>] [--dc <dc-dir>]... [--plan <path>]}"
shift 2
# The wrapper cd's into the cluster dir before exec'ing the binary, so the path baked
# into it MUST be absolute. realpath absolutizes a relative path (e.g. bin/easy-db-lab);
# command -v would leave a slash-containing relative path unchanged.
BINARY_INPUT="$BINARY_PATH"
if ! BINARY_PATH="$(realpath "$BINARY_INPUT" 2>/dev/null)" || [[ ! -x "$BINARY_PATH" ]]; then
  echo "error: easy-db-lab binary not found or not executable: $BINARY_INPUT" >&2
  exit 1
fi

CLUSTER_NAME=""
JDK_PATH=""
DCS=()
PLAN_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)  CLUSTER_NAME="$2"; shift 2 ;;
    --jdk)   JDK_PATH="$2"; shift 2 ;;
    --dc)    DCS+=("$2"); shift 2 ;;
    --plan)  PLAN_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "error: --name <cluster-name> is required" >&2
  exit 1
fi

mkdir -p "$CLUSTER_DIR"
CLUSTER_DIR=$(cd "$CLUSTER_DIR" && pwd)

# --- wrapper creation ---
make_wrapper() {
  local dir="$1"
  local wrapper="$dir/easy-db-lab"
  mkdir -p "$dir"
  {
    echo "#!/usr/bin/env bash"
    if [[ -n "$JDK_PATH" ]]; then
      echo "export JAVA_HOME=\"$JDK_PATH\""
      echo "export PATH=\"$JDK_PATH/bin:\$PATH\""
    fi
    echo "cd \"$dir\""
    echo "exec \"$BINARY_PATH\" \"\$@\""
  } > "$wrapper"
  chmod +x "$wrapper"
  echo "wrapper: $wrapper"
}

if [[ ${#DCS[@]} -eq 0 ]]; then
  make_wrapper "$CLUSTER_DIR"
else
  for dc in "${DCS[@]}"; do
    make_wrapper "$CLUSTER_DIR/$dc"
  done
fi

# --- lab report scaffold (shared; always at cluster root) ---
DOCS="$CLUSTER_DIR/docs"
mkdir -p "$DOCS/images" "$DOCS/data"

# sed_escape <text>: escape text for the right-hand side of a sed s|||.
sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# render <template> <dest>: copy a scaffold template with its placeholders filled in.
render() {
  sed -e "s|@CLUSTER_NAME@|$(sed_escape "$CLUSTER_NAME")|g" \
      -e "s|@EDB_LAB_BIN@|$(sed_escape "$SCRIPT_DIR")|g" "$1" > "$2"
}

for tpl in "$SCAFFOLD"/*.template; do
  name="$(basename "$tpl" .template)"
  case "$name" in
    [1-5]-*.md|SUMMARY.md) [[ -f "$DOCS/$name" ]] || render "$tpl" "$DOCS/$name" ;;
    *) render "$tpl" "$DOCS/$name" ;;
  esac
done

if [[ -n "$PLAN_FILE" ]]; then
  cp "$PLAN_FILE" "$DOCS/3-plan.md"
  echo "plan:    $DOCS/3-plan.md"
fi

# --- summary ---
echo "cluster: $CLUSTER_DIR"
echo "name:    $CLUSTER_NAME"
echo "docs:    $DOCS"
echo "binary:  $BINARY_PATH"
if [[ -n "$JDK_PATH" ]];   then echo "jdk:     $JDK_PATH"; fi
if [[ ${#DCS[@]} -gt 0 ]]; then echo "dcs:     ${DCS[*]}"; fi
