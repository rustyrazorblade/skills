#!/usr/bin/env bash
# Configures multi-DC Cassandra: dc_suffix, cluster name, and cross-DC seeds.
#
# Usage: configure-multi-dc-seeds.sh <cluster-dir> --name <cluster-name> --dc <dc1> --dc <dc2> ...
#
# For each DC:
#   1. Detects the version directory (where cassandra.patch.yaml lives)
#   2. Writes dc_suffix to <version>/cassandra-rackdc.properties
#   3. Gets the db0 seed IP via the DC's easy-db-lab wrapper
#   4. Merges cluster_name and seed_provider into cassandra.patch.yaml
#   5. Pushes the config via the DC's easy-db-lab wrapper
#
# Requires: python3 (for YAML merge)

set -euo pipefail

CLUSTER_DIR="${1:?Usage: $0 <cluster-dir> --name <cluster-name> --dc <dc1> --dc <dc2> ...}"
shift

CLUSTER_NAME=""
DCS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) CLUSTER_NAME="$2"; shift 2 ;;
    --dc)   DCS+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$CLUSTER_NAME" ]] && { echo "error: --name is required" >&2; exit 1; }
[[ ${#DCS[@]} -lt 2 ]]   && { echo "error: at least two --dc arguments are required" >&2; exit 1; }

CLUSTER_DIR=$(cd "$CLUSTER_DIR" && pwd)

# --- collect seed IPs (parallel arrays — bash 3.2 compatible) ---
DC_IPS_LIST=()
for dc in "${DCS[@]}"; do
  EDB="$CLUSTER_DIR/$dc/easy-db-lab"
  [[ -x "$EDB" ]] || { echo "error: wrapper not found: $EDB" >&2; exit 1; }
  IP=$("$EDB" ip db0)
  [[ -z "$IP" ]] && { echo "error: could not get IP for $dc/db0" >&2; exit 1; }
  DC_IPS_LIST+=("$IP")
  echo "seed ($dc/db0): $IP"
done

SEEDS=$(IFS=','; echo "${DC_IPS_LIST[*]}")

# --- configure each DC ---
for dc in "${DCS[@]}"; do
  EDB="$CLUSTER_DIR/$dc/easy-db-lab"
  DC_DIR="$CLUSTER_DIR/$dc"

  # Detect version directory (contains cassandra.patch.yaml)
  PATCH_FILE=$(find "$DC_DIR" -maxdepth 2 -name "cassandra.patch.yaml" | head -1)
  [[ -z "$PATCH_FILE" ]] && { echo "error: cassandra.patch.yaml not found in $DC_DIR — run 'easy-db-lab cassandra use <version>' first" >&2; exit 1; }
  VERSION_DIR=$(dirname "$PATCH_FILE")

  # Write dc_suffix
  RACKDC="$VERSION_DIR/cassandra-rackdc.properties"
  echo "dc_suffix=_${dc}" > "$RACKDC"
  echo "wrote:   $RACKDC"

  # Merge cluster_name and seeds into cassandra.patch.yaml
  python3 - "$PATCH_FILE" "$CLUSTER_NAME" "$SEEDS" <<'PYEOF'
import sys, yaml

patch_file, cluster_name, seeds = sys.argv[1], sys.argv[2], sys.argv[3]

with open(patch_file) as f:
    config = yaml.safe_load(f) or {}

config['cluster_name'] = cluster_name
config['seed_provider'] = [{
    'class_name': 'org.apache.cassandra.locator.SimpleSeedProvider',
    'parameters': [{'seeds': seeds}]
}]

with open(patch_file, 'w') as f:
    yaml.dump(config, f, default_flow_style=False)

print(f"updated: {patch_file}")
PYEOF

  # Push config
  "$EDB" cassandra update-config "$PATCH_FILE"
  echo "pushed:  $dc"
done

echo ""
echo "cluster name: $CLUSTER_NAME"
echo "seeds:        $SEEDS"
echo "dcs:          ${DCS[*]}"
