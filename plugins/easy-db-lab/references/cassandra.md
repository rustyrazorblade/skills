# Cassandra Workflow

Cassandra runs directly on the EC2 instances — not in Kubernetes. Do not use `kubectl` for any Cassandra operations. The Cassandra sidecar runs in k8s on port 9043.

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

**Never change the snitch.** easy-db-lab configures `Ec2Snitch` automatically. Do not set `endpoint_snitch` in `cassandra.patch.yaml` or override it in any config command.

**Never overwrite an existing `cassandra.patch.yaml`.** `easy-db-lab cassandra use <version>` generates this file with correct settings (snitch, data directory paths, etc.). Always read the existing file and merge new keys into it. Replacing it with a minimal stub destroys those settings and will break the cluster.

```bash
# Download current JVM and YAML config files locally
easy-db-lab cassandra download-config
easy-db-lab cassandra download-config --hosts db0

# Write a new cassandra.yaml patch file
easy-db-lab cassandra write-config my-patch.yaml
easy-db-lab cassandra write-config my-patch.yaml --tokens 4

# Push patch to all nodes
easy-db-lab cassandra update-config my-patch.yaml

# Push and restart in one step
easy-db-lab cassandra update-config my-patch.yaml --restart

# Target specific nodes
easy-db-lab cassandra update-config my-patch.yaml --hosts db0,db1
```

Config workflow: `download-config` → edit the YAML fragment → `update-config <file> [--restart]`

## Multi-DC Setup

This is the only correct procedure for multi-DC Cassandra. Follow it exactly — do not deviate.

### Prerequisites

VPC peering and security groups between DCs must already be in place (handled by `/easy-db-lab:provision`). Each DC lives in its own workspace directory (e.g. `dc1/`, `dc2/`). All `easy-db-lab` commands for a DC must be run from its directory.

### Step 1 — Select a Cassandra version in each DC

```bash
cd dc1 && easy-db-lab cassandra use 5.0 && cd ..
cd dc2 && easy-db-lab cassandra use 5.0 && cd ..
```

### Step 2 — Set dc_suffix on each DC

easy-db-lab uses `Ec2Snitch`, which sets the DC name to the AWS region (e.g. `us-east-1`). The `dc_suffix` is appended to the region to produce the final DC name — so `dc_suffix=_dc1` in `us-east-1` gives `us-east-1_dc1`.

Write a `cassandra-rackdc.properties` file in the version directory for each DC:

```bash
# In dc1/
echo "dc_suffix=_dc1" > 5.0/cassandra-rackdc.properties

# In dc2/
echo "dc_suffix=_dc2" > 5.0/cassandra-rackdc.properties
```

**Never set `endpoint_snitch` or `dc` directly.** Ec2Snitch is already configured — changing it will break the cluster.

### Step 3 — Configure cluster name and cross-DC seeds

All DCs must share the same `cluster_name`. Seeds must include at least one node from each DC. The node IPs are available from `easy-db-lab status` output.

**Read the existing `cassandra.patch.yaml` before editing it.** `easy-db-lab cassandra use <version>` generates this file with correct snitch and data directory settings. Merge new keys in — never replace the file.

Merge the following into each DC's `cassandra.patch.yaml`:

```yaml
cluster_name: "<cluster-name>"
seed_provider:
  - class_name: org.apache.cassandra.locator.SimpleSeedProvider
    parameters:
      - seeds: "<dc1-db0-ip>,<dc2-db0-ip>"
```

**If this cluster will use bulk SSTable import (e.g. IAM Bulk Writer, Spark), also add:**

```yaml
storage_compatibility_mode: NONE
```

Without this setting the sidecar will create restore jobs and immediately mark them removed without importing any data. The symptom is `inflightJobsCount=0` and `SELECT COUNT(*)` returning 0 after a successful Spark job.

Push to each DC:

```bash
cd dc1 && easy-db-lab cassandra update-config cassandra.patch.yaml && cd ..
cd dc2 && easy-db-lab cassandra update-config cassandra.patch.yaml && cd ..
```

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
easy-db-lab cassandra stress start KeyValue -d 30m --threads 100

# Named job with custom metric tags
easy-db-lab cassandra stress start --name my-test --tags "run=baseline,nodes=3" \
  KeyValue -d 1h --threads 200

# Use a custom image
easy-db-lab cassandra stress start --image ghcr.io/apache/cassandra-easy-stress:latest \
  KeyValue -d 1h

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
