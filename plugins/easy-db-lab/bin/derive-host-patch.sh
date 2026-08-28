#!/bin/bash
#
# Derive a complete per-host Cassandra patch file from a baseline.
#
# easy-db-lab's `update-config` REPLACES a node's config rather than layering onto it: the node-side
# `patch-config` merges the given file into the pristine `conf.orig/cassandra.yaml`, so whatever is
# not in the file is not on the node. A patch file is therefore a complete config, and running an
# A/B means writing one complete file per arm.
#
# This copies a baseline patch file and sets the keys that differ, so the arms cannot drift apart in
# anything except what was asked for.
#
#   derive-host-patch.sh cassandra.patch.yaml arm-b.yaml cursor_compaction_enabled=false
#   derive-host-patch.sh cassandra.patch.yaml arm-b.yaml concurrent_writes=128 trickle_fsync=false
#
# Values are parsed as YAML, so `false` is a boolean and `128` is an int. Quote to force a string:
#   derive-host-patch.sh base.yaml out.yaml 'some_key="true"'
#
# Apply the result to one arm; the other arm keeps whatever `cassandra use` already applied:
#   $EDB cassandra update-config arm-b.yaml --hosts db1,db2

set -euo pipefail

usage() {
    echo "usage: $(basename "$0") <baseline.yaml> <output.yaml> <key=value> [key=value ...]" >&2
    exit 1
}

[ $# -ge 3 ] || usage

BASELINE=$1
OUTPUT=$2
shift 2

if [ ! -f "$BASELINE" ]; then
    echo "ERROR: baseline not found: $BASELINE" >&2
    echo "Generate one with 'easy-db-lab cassandra write-config' first." >&2
    exit 2
fi

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq not found. Install it (brew install yq)." >&2
    exit 3
fi

# A baseline missing these is not a usable Cassandra config, and a node given it will fail to start
# with a misleading "Check if the seeds are up" error. Catch it here instead.
for required in cluster_name seed_provider; do
    if [ "$(yq "has(\"$required\")" "$BASELINE")" != "true" ]; then
        echo "ERROR: baseline $BASELINE has no '$required' — it is not a complete config." >&2
        echo "Do not derive from a partial file. Regenerate with 'easy-db-lab cassandra write-config'." >&2
        exit 4
    fi
done

cp "$BASELINE" "$OUTPUT"

for pair in "$@"; do
    case "$pair" in
        *=*) ;;
        *) echo "ERROR: expected key=value, got: $pair" >&2; exit 5 ;;
    esac
    key=${pair%%=*}
    value=${pair#*=}
    [ -n "$key" ] || { echo "ERROR: empty key in: $pair" >&2; exit 5; }
    KEY="$key" VALUE="$value" yq -i '.[strenv(KEY)] = (strenv(VALUE) | from_yaml)' "$OUTPUT"
done

echo "Wrote $OUTPUT (derived from $BASELINE):"
for pair in "$@"; do
    key=${pair%%=*}
    KEY="$key" yq "{strenv(KEY): .[strenv(KEY)]}" "$OUTPUT" | sed 's/^/  /'
done
