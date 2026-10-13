#!/usr/bin/env bash
# Sets up a cluster workspace: directory structure, easy-db-lab wrapper(s), and lab report scaffold.
#
# Usage: setup-cluster.sh <cluster-dir> <binary-path> --name <cluster-name> [--jdk <path>] [--dc <dc-dir>]... [--plan <path>]
#        setup-cluster.sh <test-dir> <binary-path> --name <title> [--jdk <path>] [--plan <path>] --arm <arm>=<plan.md>...
#        setup-cluster.sh <cluster-dir> --docs-only --name <title>
#
# Arguments:
#   cluster-dir       Path to the cluster workspace root. Created if it does not exist.
#   binary-path       Full path to the easy-db-lab binary, or "easy-db-lab" if on PATH.
#
# Options:
#   --name <name>     Cassandra cluster name. Shared across all nodes in all DCs. Also the
#                     fallback lab report title; make takes the title from 1-summary.md.
#                     With --arm, each arm's cluster name comes from its plan, and --name is
#                     only the fallback title.
#   --jdk <path>      Java home directory. Bakes JAVA_HOME and PATH into every wrapper.
#   --dc <dc-dir>     Datacenter directory name (e.g. dc1, us-east). Repeat for each DC.
#                     When omitted, one wrapper is created at the cluster root (single DC).
#                     When provided, one wrapper is created per DC under <cluster-dir>/<dc-dir>/.
#   --plan <path>     Path to the plan. Copied to docs/3-plan.md as a record of what was executed.
#   --arm <arm>=<plan.md>
#                     One arm of a cross-cluster test. Repeat for each arm. Creates the wrapper
#                     <test-dir>/<arm>/easy-db-lab, copies the plan to docs/3-plan-<arm>.md, and
#                     lists the arm in the <test-dir>/arms marker. Excludes --dc. An arm name
#                     uses letters, digits, - and _, appears once, and is not docs, bin, data,
#                     images, export, or arms.
#   --docs-only       Write the docs scaffold only. Takes no binary and writes no wrapper.
#
# The script never rewrites an existing wrapper. It refuses a binary whose real path is a
# wrapper path it would write, and it refuses an easy-db-lab source checkout
# (<cluster-dir>/bin/easy-db-lab next to settings.gradle.kts or build.gradle.kts).
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
# Directory layout — cross-cluster arms:
#   <test-dir>/
#     arms              ← marker: one arm per line
#     <arm>/
#       easy-db-lab     ← wrapper (cds into <test-dir>/<arm>); one cluster per arm
#     docs/             ← the one report; per-arm 3-plan-<arm>.md, 4-journal-<arm>.md, 5-issues-<arm>.md
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

usage() {
  sed -n '/^# Usage:/,/^#$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '/^$/d' >&2
  exit 1
}

# arm_var <arm>: the EDB_/STATE_ suffix detect-cluster-layout.sh gives the arm.
arm_var() {
  echo "$1" | tr '[:lower:]' '[:upper:]' | tr '-' '_'
}

CLUSTER_DIR="${1:-}"
[[ -n "$CLUSTER_DIR" && "$CLUSTER_DIR" != --* ]] || usage
shift
BINARY_INPUT=""
if [[ $# -gt 0 && "$1" != --* ]]; then
  BINARY_INPUT="$1"
  shift
fi

CLUSTER_NAME=""
JDK_PATH=""
DCS=()
ARMS=()
ARM_PLANS=()
PLAN_FILE=""
DOCS_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)  CLUSTER_NAME="$2"; shift 2 ;;
    --jdk)   JDK_PATH="$2"; shift 2 ;;
    --dc)    DCS+=("$2"); shift 2 ;;
    --plan)  PLAN_FILE="$2"; shift 2 ;;
    --arm)
      [[ "$2" == *=* ]] || { echo "error: --arm takes <arm>=<plan.md>, got: $2" >&2; usage; }
      ARMS+=("${2%%=*}"); ARM_PLANS+=("${2#*=}"); shift 2 ;;
    --docs-only) DOCS_ONLY=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "error: --name <cluster-name> is required" >&2
  exit 1
fi
if [[ ${#ARMS[@]} -gt 0 && ${#DCS[@]} -gt 0 ]]; then
  echo "error: --arm and --dc exclude each other" >&2
  usage
fi
if $DOCS_ONLY; then
  [[ -z "$BINARY_INPUT" ]] || { echo "error: --docs-only takes no binary" >&2; usage; }
  [[ ${#ARMS[@]} -eq 0 ]] || { echo "error: --docs-only excludes --arm" >&2; usage; }
else
  [[ -n "$BINARY_INPUT" ]] || usage
fi
for i in ${ARMS[@]+"${!ARMS[@]}"}; do
  [[ "${ARMS[$i]}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { echo "error: arm names use letters, digits, - and _: ${ARMS[$i]}" >&2; exit 1; }
  # An arm directory must not collide with the docs scaffold, the bin/ guard, or the arms marker.
  # The match ignores case, because APFS does.
  case "$(echo "${ARMS[$i]}" | tr '[:upper:]' '[:lower:]')" in
    docs|bin|data|images|export|arms) echo "error: reserved arm name: ${ARMS[$i]}" >&2; exit 1 ;;
  esac
  for j in "${!ARMS[@]}"; do
    [[ $j -lt $i ]] || continue
    [[ "${ARMS[$j]}" == "${ARMS[$i]}" ]] && { echo "error: duplicate arm name: ${ARMS[$i]}" >&2; exit 1; }
    # detect-cluster-layout.sh gives each arm an EDB_ variable: upper case, with - as _.
    [[ "$(arm_var "${ARMS[$j]}")" == "$(arm_var "${ARMS[$i]}")" ]] && { echo "error: arm names ${ARMS[$j]} and ${ARMS[$i]} collide: they give one EDB_$(arm_var "${ARMS[$i]}") variable" >&2; exit 1; }
  done
  [[ -f "${ARM_PLANS[$i]}" ]] || { echo "error: plan not found for arm ${ARMS[$i]}: ${ARM_PLANS[$i]}" >&2; exit 1; }
done

# --- guards: nothing is written until these pass ---

if [[ -e "$CLUSTER_DIR/bin/easy-db-lab" ]] && [[ -f "$CLUSTER_DIR/settings.gradle.kts" || -f "$CLUSTER_DIR/build.gradle.kts" ]]; then
  echo "error: $CLUSTER_DIR is an easy-db-lab source checkout; change to a workspace directory" >&2
  exit 1
fi

# Wrapper directories, relative to the cluster dir: "." for a single DC, else one per DC or arm.
WRAPPER_DIRS=()
if ! $DOCS_ONLY; then
  if [[ ${#ARMS[@]} -gt 0 ]]; then
    WRAPPER_DIRS=("${ARMS[@]}")
  elif [[ ${#DCS[@]} -gt 0 ]]; then
    WRAPPER_DIRS=("${DCS[@]}")
  else
    WRAPPER_DIRS=(".")
  fi

  # The wrapper cd's into the cluster dir before exec'ing the binary, so the path baked
  # into it MUST be absolute. realpath absolutizes a relative path (e.g. bin/easy-db-lab);
  # command -v would leave a slash-containing relative path unchanged.
  if ! BINARY_PATH="$(realpath "$BINARY_INPUT" 2>/dev/null)" || [[ ! -x "$BINARY_PATH" ]]; then
    echo "error: easy-db-lab binary not found or not executable: $BINARY_INPUT" >&2
    exit 1
  fi
  # A binary that is one of the wrappers would exec itself forever.
  for d in "${WRAPPER_DIRS[@]}"; do
    if [[ "$d" == "." ]]; then w="$CLUSTER_DIR/easy-db-lab"; else w="$CLUSTER_DIR/$d/easy-db-lab"; fi
    if [[ -e "$w" && "$(realpath "$w")" == "$BINARY_PATH" ]]; then
      echo "error: the binary is the wrapper this script would write: $w; pass the real easy-db-lab binary" >&2
      exit 1
    fi
  done
fi

mkdir -p "$CLUSTER_DIR"
CLUSTER_DIR=$(cd "$CLUSTER_DIR" && pwd)

# --- wrapper creation ---
make_wrapper() {
  local dir="$1"
  local wrapper="$dir/easy-db-lab"
  if [[ -e "$wrapper" ]]; then
    echo "wrapper: $wrapper (kept)"
    return
  fi
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

for d in ${WRAPPER_DIRS[@]+"${WRAPPER_DIRS[@]}"}; do
  if [[ "$d" == "." ]]; then make_wrapper "$CLUSTER_DIR"; else make_wrapper "$CLUSTER_DIR/$d"; fi
done

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

# The arms layout generates its own SUMMARY.md below.
for tpl in "$SCAFFOLD"/*.template; do
  name="$(basename "$tpl" .template)"
  case "$name" in
    SUMMARY.md) [[ ${#ARMS[@]} -gt 0 || -f "$DOCS/$name" ]] || render "$tpl" "$DOCS/$name" ;;
    [1-5]-*.md) [[ -f "$DOCS/$name" ]] || render "$tpl" "$DOCS/$name" ;;
    *) render "$tpl" "$DOCS/$name" ;;
  esac
done

if [[ -n "$PLAN_FILE" ]]; then
  cp "$PLAN_FILE" "$DOCS/3-plan.md"
  echo "plan:    $DOCS/3-plan.md"
fi

# --- cross-cluster arms: marker, per-arm files, and the generated SUMMARY.md ---
if [[ ${#ARMS[@]} -gt 0 ]]; then
  printf '%s\n' "${ARMS[@]}" > "$CLUSTER_DIR/arms"
  for i in "${!ARMS[@]}"; do
    arm="${ARMS[$i]}"
    cp "${ARM_PLANS[$i]}" "$DOCS/3-plan-$arm.md"
    [[ -f "$DOCS/4-journal-$arm.md" ]] || render "$SCAFFOLD/4-journal.md.template" "$DOCS/4-journal-$arm.md"
    [[ -f "$DOCS/5-issues-$arm.md" ]] || render "$SCAFFOLD/5-issues.md.template" "$DOCS/5-issues-$arm.md"
    echo "plan:    $DOCS/3-plan-$arm.md"
  done
  if [[ ! -f "$DOCS/SUMMARY.md" ]]; then
    {
      sed '/^# Appendix/,$d' "$SCAFFOLD/SUMMARY.md.template"
      echo "# Appendix"
      echo ""
      echo "- [Plan](3-plan.md)"
      echo "- [Coordinator journal](4-journal.md)"
      echo "- [Coordinator issues](5-issues.md)"
      for arm in "${ARMS[@]}"; do
        echo "- [Plan: $arm](3-plan-$arm.md)"
        echo "- [Journal: $arm](4-journal-$arm.md)"
        echo "- [Issues: $arm](5-issues-$arm.md)"
      done
    } > "$DOCS/SUMMARY.md"
  fi
fi

# --- summary ---
echo "cluster: $CLUSTER_DIR"
echo "name:    $CLUSTER_NAME"
echo "docs:    $DOCS"
if ! $DOCS_ONLY;           then echo "binary:  $BINARY_PATH"; fi
if [[ -n "$JDK_PATH" ]];   then echo "jdk:     $JDK_PATH"; fi
if [[ ${#DCS[@]} -gt 0 ]]; then echo "dcs:     ${DCS[*]}"; fi
if [[ ${#ARMS[@]} -gt 0 ]]; then echo "arms:    ${ARMS[*]}"; fi
