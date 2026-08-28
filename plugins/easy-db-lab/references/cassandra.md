# Cassandra Workflow

Cassandra runs directly on the EC2 instances — not in Kubernetes. Do not use `kubectl` for any Cassandra operations. The Cassandra sidecar runs in k8s on port 9043.

## Known Gotchas

Hard-won discoveries from real planning/run sessions that aren't obvious from the command reference alone. When a future session discovers something similar — a flag that silently does more than it looks like, a default that undermines a stated objective, a command whose scope is narrower than its name suggests — add it here so it doesn't have to be rediscovered.

- **`cassandra use <version>` silently switches JDK.** `cassandra_versions.yaml` maps each Cassandra version to a specific JDK, and running `easy-db-lab cassandra use <version>` changes the JDK on every targeted node as a side effect, even when that's not the intent. If a test needs to hold the JDK constant (e.g. comparing a stock release against a personal fork), pin it explicitly with `--java <version>` on every `cassandra use` invocation rather than trusting the version's default.
- **`cassandra use` silently re-applies `cassandra.patch.yaml` to every host it targets.** Its last step is an internal `update-config` against the default patch file, scoped to the same `--hosts`. Any per-host configuration applied earlier is discarded with no warning. In an A/B or any run with divergent per-node config, `use` must come first — and must not be run again without re-applying the per-host files. See **Configuration** below.
- **`update-config` replaces the whole config, it never accumulates.** Each apply rebuilds `cassandra.yaml` from `conf.orig`, so a patch file containing only the key you want to change silently drops seeds, cluster name and data directories, and the node fails to start. Every patch file must be a complete config. See **Configuration** below.
- **`cleanup --kit <name>` only resets K8s-kit data, not Cassandra data.** It targets the kit's LPV (local persistent volume) data at `$DB_MOUNT_PATH/<kit>`. There is no dedicated command to reset Cassandra's own data directories between runs. To wipe Cassandra data, use `easy-db-lab exec run -t cassandra -- sudo rm -rf <path>` instead.
- **cassandra-easy-stress's `--populate` phase runs to completion before the `-d` duration timer starts.** Metrics reset when the timed portion of the run begins. Don't count populate time against the stated test duration when budgeting how long a run will take.
- **cassandra-easy-stress's `--rate` is per-thread, not a global target.** Total throughput is `--rate` × `--threads` — it scales linearly, it isn't a concurrency pool the tool uses to saturate a fixed ceiling. Doubling `--threads` doubles total throughput, full stop. It defaults to `--threads 1`, so `--rate 50000` with default threads gives exactly 50k total (not less, and not more). To hit a specific total throughput target, compute `--rate` and `--threads` so their product equals it (e.g. `--rate 5000 --threads 10` for 50k total) — don't put the full target in `--rate` and assume the tool will use threads to get there.

## Select Version

```bash
# Available: 3.0, 3.11, 4.0, 4.1 (check `easy-db-lab cassandra list` for current list)
easy-db-lab cassandra use 5.0

# Override Java version (8, 11, or 17)
easy-db-lab cassandra use 5.0 --java 17

# Target specific nodes
easy-db-lab cassandra use 5.0 --hosts db0,db1

# List available versions
easy-db-lab cassandra list
```

## Configuration

### How a patch is applied — read this before writing any config

A patch file is **the complete override set for a host, not a delta.** On every apply,
`patch-config` rebuilds `cassandra.yaml` from the pristine shipped config:

```bash
yq '. *= load(env(PATCH))' /usr/local/cassandra/$VERSION/conf.orig/cassandra.yaml > .../conf/cassandra.yaml
```

The merge base is always `conf.orig` — never the live `conf/cassandra.yaml`. So **`update-config`
replaces, it never accumulates.** Two calls with different files do not stack: the second discards
everything the first set. A file containing only the one key you want to change strips
`seed_provider`, `cluster_name` and the data directories, and the node dies at startup with:

```
IllegalArgumentException: Found no candidates during initialization. Check if the seeds are up: [/127.0.0.1:7000]
```

That error looks like a seeds problem. It is almost always an incomplete patch file.

**`cassandra use` re-applies `cassandra.patch.yaml` to every host it targets.** Its last act is an
internal `update-config` against the default file, scoped to the same `--hosts`. Consequences:

- `use` **does not create** `cassandra.patch.yaml` — it consumes it. `write-config` creates it.
- Any per-host config applied earlier is silently discarded by a later `use`.
- Always `use` first, then apply per-host files. Never `use` again mid-experiment without
  re-applying them.

**Never set these keys in a patch file** — they are managed for you and yours will be overwritten:

- `endpoint_snitch` — easy-db-lab configures `Ec2Snitch` automatically.
- `listen_address`, `rpc_address`, `broadcast_rpc_address` — stamped in per host from the node's
  private IP at upload time.

**Never overwrite an existing `cassandra.patch.yaml`.** `write-config` generates it with the
settings the cluster needs (cluster name, seeds, data directory paths, snitch, tokens). Read the
existing file and add keys to it. Replacing it with a minimal stub will break the cluster.

```bash
# Download current JVM config files locally (cassandra*.yaml is deliberately excluded)
easy-db-lab cassandra download-config

# Write a new cassandra.yaml patch file
easy-db-lab cassandra write-config
easy-db-lab cassandra write-config --tokens 4

# Push patch to all nodes
easy-db-lab cassandra update-config cassandra.patch.yaml

# Push and restart in one step
easy-db-lab cassandra update-config cassandra.patch.yaml --restart

# Target specific nodes
easy-db-lab cassandra update-config cassandra.patch.yaml --hosts db0,db1
```

Config workflow: `write-config` → add keys to the YAML → `update-config <file> [--restart]`

> **Two commands accept arguments they silently ignore.** Verified in the source; work around them
> rather than trusting the flag.
>
> - `download-config --hosts <h>` — the flag parses but is never read. It always downloads from the
>   first Cassandra host. To inspect a specific node's live config, use
>   `ssh -F "$(dirname "$EDB")/sshConfig" <host> "cat /usr/local/cassandra/current/conf/cassandra.yaml"`.
> - `write-config <filename>` — the filename is ignored; output always goes to
>   `cassandra.patch.yaml`. To get a differently-named file, run `write-config` and copy the result.

### Per-host configuration (A/B tests)

`--hosts` scopes an apply to a subset, which is how you run different configs on different nodes.
Because a patch file is a complete config, **each arm needs its own complete file** — there is no
base-plus-overlay layer. Derive the variant from the baseline so the two can't drift:

```bash
# 1. use FIRST — it resets every targeted host to cassandra.patch.yaml
$EDB cassandra use 6.0-rustyrazorblade

# 2. build the variant arm as a full copy of the baseline plus the key under test
derive-host-patch.sh cassandra.patch.yaml arm-b.yaml cursor_compaction_enabled=false

# 3. apply per arm. The control arm keeps the baseline `use` already applied.
$EDB cassandra update-config arm-b.yaml --hosts db1,db2
```

`derive-host-patch.sh` is on PATH via the plugin's `bin/`. It copies the baseline and sets each
`key=value` with `yq`, so the arms differ only in what you named.

### Verify config before starting — always

A node that starts with a stripped config takes the cluster down with it, and the resulting error
points at seeds rather than at the config. Checking first is cheaper than diagnosing after:

```bash
CLUSTER_DIR=$(dirname "$EDB")
for h in db0 db1 db2; do
  echo "== $h"
  ssh -F "$CLUSTER_DIR/sshConfig" $h \
    "grep -E 'seeds:|cluster_name:' /usr/local/cassandra/current/conf/cassandra.yaml"
done
```

Every node must show `seeds:` and `cluster_name:`. If any node is missing them, do not start —
re-apply a complete patch file to that node. Add a grep for whatever key the test varies, and
confirm it is present on the treatment arm and absent (or default) on the control arm.

## Multi-DC Setup

This is the only correct procedure for multi-DC Cassandra. Follow it exactly — do not deviate.

### Prerequisites

VPC peering and security groups between DCs must already be in place. Each DC lives in its own workspace directory (e.g. `dc1/`, `dc2/`). All `easy-db-lab` commands for a DC must be run from its directory.

Set up VPC peering with `setup-vpc-peering.sh` (available on PATH via the plugin's `bin/`) — creates the peering connection, route tables, and security groups for one DC pair. Run once per pair (3 DCs = 3 runs):

```bash
setup-vpc-peering.sh --dc1 <name> --vpc1 <id> --cidr1 <cidr> --dc2 <name> --vpc2 <id> --cidr2 <cidr> --region <region>
```

### Step 1 — Select a Cassandra version in each DC

```bash
cd dc1 && easy-db-lab cassandra use 5.0 && cd ..
cd dc2 && easy-db-lab cassandra use 5.0 && cd ..
```

### Step 2 & 3 — Set dc_suffix, cluster name, and cross-DC seeds

Run `configure-multi-dc-seeds.sh` (available on PATH via the plugin's `bin/`). It writes `dc_suffix` to each DC's `cassandra-rackdc.properties`, gets seed IPs via `easy-db-lab ip db0`, merges `cluster_name` and `seed_provider` into each DC's `cassandra.patch.yaml`, and pushes the config:

```bash
configure-multi-dc-seeds.sh <cluster-dir> --name <cluster-name> --dc dc1 --dc dc2
```

Requires `easy-db-lab cassandra use <version>` to have been run in each DC first, and `cassandra.patch.yaml` to exist in each DC's workspace (`write-config` creates it; `use` reads it and fails without it).

**If this cluster will use bulk SSTable import (e.g. IAM Bulk Writer, Spark), also add manually:**

```yaml
storage_compatibility_mode: NONE
```

Without this setting the sidecar will create restore jobs and immediately mark them removed without importing any data. The symptom is `inflightJobsCount=0` and `SELECT COUNT(*)` returning 0 after a successful Spark job.

### Step 4 — Start and verify

Start Cassandra in each DC (can be done in parallel):

```bash
(cd dc1 && easy-db-lab cassandra start) &
(cd dc2 && easy-db-lab cassandra start) &
wait
```

Verify all nodes from any DC:

```bash
cd dc1 && easy-db-lab cassandra nt status
```

All nodes from both DCs should appear. Each node's DC column should show `us-east-1_dc1` or `us-east-1_dc2`.

### Step 5 — Configure S3 bucket replication (for bulk import workflows)

If the workload writes SSTables to S3 (e.g. IAM Bulk Writer), replicate the source DC's bucket to the target DC's bucket.

**Find the replication IAM role** (one pre-created role exists per environment — search by name):

```bash
aws iam list-roles --query "Roles[?contains(RoleName, 'replication')].{Name:RoleName,Arn:Arn}" --output table
```

**Enable versioning** on both buckets (required for S3 replication):

```bash
DC1_BUCKET=$(cd dc1 && easy-db-lab aws s3-bucket)
DC2_BUCKET=$(cd dc2 && easy-db-lab aws s3-bucket)

aws s3api put-bucket-versioning --bucket $DC1_BUCKET --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket $DC2_BUCKET --versioning-configuration Status=Enabled
```

**Apply the replication configuration** to the source bucket:

```bash
REPLICATION_ROLE_ARN=$(aws iam list-roles --query "Roles[?contains(RoleName, 'replication')].Arn" --output text)

aws s3api put-bucket-replication \
  --bucket $DC1_BUCKET \
  --replication-configuration "{
    \"Role\": \"$REPLICATION_ROLE_ARN\",
    \"Rules\": [{
      \"Status\": \"Enabled\",
      \"Filter\": {\"Prefix\": \"\"},
      \"Destination\": {\"Bucket\": \"arn:aws:s3:::$DC2_BUCKET\"}
    }]
  }"
```

Replication is asynchronous. Objects written to `$DC1_BUCKET` will appear in `$DC2_BUCKET` within seconds to minutes depending on object size.

## Start / Stop / Restart

```bash
# Start Cassandra on all nodes (staggered by default)
easy-db-lab cassandra start

# Control sleep time between node starts (seconds)
easy-db-lab cassandra start --sleep 30

# Use a custom sidecar image (e.g. a custom ECR build for bulk import)
easy-db-lab cassandra start --sidecar-image <image-uri>

# Stop all nodes
easy-db-lab cassandra stop

# Restart all nodes
easy-db-lab cassandra restart

# Target specific nodes with --hosts on any command
easy-db-lab cassandra start --hosts db0
easy-db-lab cassandra stop --hosts db1,db2
```

**Changing the sidecar image on a running cluster:** The sidecar runs as a DaemonSet in k3s. Passing `--sidecar-image` only takes effect on a fresh start. If the cluster is already running with a different image, delete the existing DaemonSet first:

```bash
kubectl delete daemonset -n cassandra-sidecar --all
easy-db-lab cassandra start --sidecar-image <image-uri>
```

## Verify the Cluster

```bash
# Nodetool commands (args passed directly to nodetool)
easy-db-lab cassandra nt status
easy-db-lab cassandra nt ring
easy-db-lab cassandra nt compactionstats
easy-db-lab cassandra nt --hosts db0 tpstats

# Execute CQL inline
easy-db-lab cassandra cql "SELECT release_version FROM system.local"

# Execute CQL from a file
easy-db-lab cassandra cql --file schema.cql
```

**If `easy-db-lab cassandra cql` returns `No node was available` on a cluster where `nodetool status` shows all nodes UN**, the sidecar connection may not be ready yet. Wait 30 seconds and retry. If it continues to fail, run cqlsh directly via SSH:

```bash
ssh -i $(easy-db-lab ssh-key) ubuntu@$(easy-db-lab host db0) cqlsh
```

## Stress Testing

The stress subcommand wraps `cassandra-easy-stress` running on Kubernetes on the app nodes.

```bash
# List available workloads
easy-db-lab cassandra stress list

# Show available field generators
easy-db-lab cassandra stress fields

# Get details on a workload
easy-db-lab cassandra stress info KeyValue

# Start a stress job (remaining args passed directly to cassandra-easy-stress)
easy-db-lab cassandra stress start -- KeyValue -d 30m --threads 100

# Named job with custom metric tags
easy-db-lab cassandra stress start --name my-test --tags "run=baseline,nodes=3" \
  -- KeyValue -d 1h --threads 200

# Use a custom image
easy-db-lab cassandra stress start --image ghcr.io/apache/cassandra-easy-stress:latest \
  -- KeyValue -d 1h

# Monitor running jobs
easy-db-lab cassandra stress status
easy-db-lab cassandra stress status --name my-test

# View logs from a job
easy-db-lab cassandra stress logs my-test
easy-db-lab cassandra stress logs my-test --tail 100

# Stop a specific job
easy-db-lab cassandra stress stop my-test

# Stop all stress jobs
easy-db-lab cassandra stress stop --all

# Force stop without confirmation
easy-db-lab cassandra stress stop my-test --force
```
