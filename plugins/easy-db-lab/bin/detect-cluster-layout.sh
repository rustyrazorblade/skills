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
# Exit 1 if no wrapper is found.

set -euo pipefail

CLUSTER_DIR="${1:?Usage: $0 <cluster-dir>}"
CLUSTER_DIR=$(cd "$CLUSTER_DIR" && pwd)

if [[ -x "$CLUSTER_DIR/easy-db-lab" ]]; then
  [[ -f "$CLUSTER_DIR/state.json" ]] && STATE=provisioned || STATE=unprovisioned
  echo "LAYOUT=single"
  echo "EDB=$CLUSTER_DIR/easy-db-lab"
  echo "STATE=$STATE"
  exit 0
fi

# Multi-DC: find wrappers in subdirectories (skip docs/)
DCS=()
STATE=unprovisioned

for wrapper in "$CLUSTER_DIR"/*/easy-db-lab; do
  [[ -x "$wrapper" ]] || continue
  dc=$(basename "$(dirname "$wrapper")")
  [[ "$dc" == "docs" ]] && continue
  DCS+=("$dc")
  VAR="EDB_$(echo "$dc" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
  echo "${VAR}=${wrapper}"
  [[ -f "$CLUSTER_DIR/$dc/state.json" ]] && STATE=provisioned
done

if [[ ${#DCS[@]} -eq 0 ]]; then
  echo "error: no easy-db-lab wrapper found in $CLUSTER_DIR" >&2
  exit 1
fi

echo "LAYOUT=multi"
echo "DCS=${DCS[*]}"
echo "STATE=$STATE"
