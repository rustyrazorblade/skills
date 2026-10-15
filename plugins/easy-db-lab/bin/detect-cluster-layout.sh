#!/usr/bin/env bash
# Detects the layout of an existing cluster workspace.
#
# Usage: detect-cluster-layout.sh <cluster-dir>
#
# Output (eval-safe):
#   Single DC:
#     LAYOUT=single
#     EDB=<cluster-dir>/easy-db-lab
#     STATE=provisioned|unprovisioned
#
#   Multi DC:
#     LAYOUT=multi
#     DCS=<dc1 dc2 ...>
#     EDB_DC1=<cluster-dir>/dc1/easy-db-lab
#     EDB_DC2=<cluster-dir>/dc2/easy-db-lab
#     STATE=provisioned|unprovisioned   (provisioned if any DC has state.json)
#
#   Cross-cluster arms (a <cluster-dir>/arms marker, one arm per line; setup-cluster.sh --arm):
#     LAYOUT=arms
#     ARMS="<arm1 arm2 ...>"
#     EDB_<ARM>=<cluster-dir>/<arm>/easy-db-lab
#     STATE_<ARM>=provisioned|unprovisioned
#     STATE=provisioned|unprovisioned   (provisioned if any arm has state.json)
#
# Each value is quoted for eval with printf %q; ARMS is double-quoted, which is safe because an
# arm name must match the setup-cluster.sh rule, ^[A-Za-z0-9][A-Za-z0-9_-]*$.  The multi-DC scan
# skips docs/ and bin/.  Exit 1 if no wrapper is found, if the marker names a bad arm or a
# reserved one (docs, bin, data, images, export, arms, in any case), or if two marker arms give
# one variable, such as a-b and a_b.  On a refusal it prints no variable at all.

set -euo pipefail

CLUSTER_DIR="${1:?Usage: $0 <cluster-dir>}"
CLUSTER_DIR=$(cd "$CLUSTER_DIR" && pwd)

# var_name <dir>: the EDB_/STATE_ suffix for a DC or arm directory name.
var_name() {
  echo "$1" | tr '[:lower:]' '[:upper:]' | tr '-' '_'
}

# Cross-cluster arms: the marker comes before the wrapper scan.
if [[ -f "$CLUSTER_DIR/arms" ]]; then
  ARMS=()
  # Every line waits until all arms pass, so a refusal prints no EDB_ line.
  LINES=()
  STATE=unprovisioned
  while IFS= read -r arm || [[ -n "$arm" ]]; do
    [[ -n "$arm" ]] || continue
    if [[ ! "$arm" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
      echo "error: the arms marker names a bad arm (use letters, digits, - and _): $arm" >&2
      exit 1
    fi
    # The setup-cluster.sh rule: no arm directory is a scaffold directory or the marker, in any case.
    case "$(echo "$arm" | tr '[:upper:]' '[:lower:]')" in
      docs|bin|data|images|export|arms) echo "error: the arms marker names a reserved arm name: $arm" >&2; exit 1 ;;
    esac
    for other in ${ARMS[@]+"${ARMS[@]}"}; do
      if [[ "$(var_name "$other")" == "$(var_name "$arm")" ]]; then
        echo "error: in the arms marker, the arm names $other and $arm collide: they give one EDB_$(var_name "$arm") variable" >&2
        exit 1
      fi
    done
    wrapper="$CLUSTER_DIR/$arm/easy-db-lab"
    if [[ ! -x "$wrapper" ]]; then
      echo "error: arm $arm has no easy-db-lab wrapper: $wrapper" >&2
      exit 1
    fi
    ARMS+=("$arm")
    [[ -f "$CLUSTER_DIR/$arm/state.json" ]] && ARM_STATE=provisioned || ARM_STATE=unprovisioned
    [[ "$ARM_STATE" == provisioned ]] && STATE=provisioned
    LINES+=("$(printf 'EDB_%s=%q' "$(var_name "$arm")" "$wrapper")")
    LINES+=("STATE_$(var_name "$arm")=$ARM_STATE")
  done < "$CLUSTER_DIR/arms"
  if [[ ${#ARMS[@]} -eq 0 ]]; then
    echo "error: the arms marker lists no arm: $CLUSTER_DIR/arms" >&2
    exit 1
  fi
  printf '%s\n' "${LINES[@]}"
  echo "LAYOUT=arms"
  echo "ARMS=\"${ARMS[*]}\""
  echo "STATE=$STATE"
  exit 0
fi

if [[ -x "$CLUSTER_DIR/easy-db-lab" ]]; then
  [[ -f "$CLUSTER_DIR/state.json" ]] && STATE=provisioned || STATE=unprovisioned
  echo "LAYOUT=single"
  printf 'EDB=%q\n' "$CLUSTER_DIR/easy-db-lab"
  echo "STATE=$STATE"
  exit 0
fi

# Multi-DC: find wrappers in subdirectories (skip docs/ and bin/)
DCS=()
STATE=unprovisioned

for wrapper in "$CLUSTER_DIR"/*/easy-db-lab; do
  [[ -x "$wrapper" ]] || continue
  dc=$(basename "$(dirname "$wrapper")")
  [[ "$dc" == "docs" || "$dc" == "bin" ]] && continue
  DCS+=("$dc")
  printf 'EDB_%s=%q\n' "$(var_name "$dc")" "$wrapper"
  [[ -f "$CLUSTER_DIR/$dc/state.json" ]] && STATE=provisioned
done

if [[ ${#DCS[@]} -eq 0 ]]; then
  echo "error: no easy-db-lab wrapper found in $CLUSTER_DIR" >&2
  exit 1
fi

echo "LAYOUT=multi"
printf 'DCS=%q\n' "${DCS[*]}"
echo "STATE=$STATE"
