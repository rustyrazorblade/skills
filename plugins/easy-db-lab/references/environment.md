# Environment Overview

## AWS

All easy-db-lab environments run on AWS. If easy-db-lab does not have a built-in command for an operation, use the AWS CLI or other AWS tools directly. The cluster's region and S3 bucket are available via:

```bash
easy-db-lab aws region
easy-db-lab aws s3-bucket
```

## Kubernetes (k3s)

The cluster runs k3s (lightweight Kubernetes). ClickHouse and the observability stack run in k3s. Cassandra runs directly on EC2. OpenSearch and Spark are AWS-managed services that run outside the cluster.

To connect to k3s, use the `kubeconfig` file in the workspace directory:

```bash
kubectl --kubeconfig kubeconfig get pods -A
```

Or export it for the session:

```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get pods -A
```

## Observability Stack

Every environment ships a full observability stack. Components run on every cluster node (collectors) or on the control node only (backends).

### Collectors (every node)

| Tool | Purpose |
|------|---------|
| OTel Collector | Receives metrics from workloads; config regenerated dynamically per running kit |
| Fluent Bit | Ships journald (systemd) logs to VictoriaLogs |
| Grafana Alloy | eBPF-based continuous profiling |
| Beyla | L7 RED metrics (rate, errors, duration) via eBPF |
| ebpf_exporter | Low-level kernel metrics: TCP, block I/O, VFS |
| YACE | Scrapes CloudWatch and bridges to Prometheus format |
| MAAC agent | Cassandra-specific metrics |

### Storage Backends (control node)

| Tool | Port | Purpose |
|------|------|---------|
| VictoriaMetrics | 8428 | Time-series metrics storage |
| VictoriaLogs | 9428 | Log storage |
| Tempo | 3200 | Distributed traces |
| Pyroscope | 4040 | Continuous profiling data |

### Visualization & Networking

| Tool | Port | Purpose |
|------|------|---------|
| Grafana | 3000 | Dashboards for all backends |
| Hubble (Cilium) | 9965 | L7 network visibility + Prometheus metrics |

The `easy-db-lab` CLI itself is auto-instrumented via the OpenTelemetry Java Agent, which captures HTTP client traces and JVM metrics without any manual instrumentation in the Kotlin code.

Use `easy-db-lab grafana update-config` to apply or refresh the full observability stack. Use `easy-db-lab logs` and `easy-db-lab metrics` for querying. If you need to interact with these directly (e.g. custom queries, imports), use `kubectl` with the `kubeconfig`.

## Cassandra

Cassandra runs directly on the EC2 instances, not in k3s. It is managed via `easy-db-lab cassandra` commands over SSH.

Configuration overrides are stored in **`cassandra.patch.yaml`** in the workspace directory. This file contains only the settings that differ from the base config — it is merged server-side with the base `cassandra.yaml`. Edit this file and push it with:

```bash
easy-db-lab cassandra update-config cassandra.patch.yaml [--restart]
```

## OpenSearch

OpenSearch runs as an AWS managed domain, not in k3s. It is provisioned and managed via `easy-db-lab opensearch` commands, which interact with AWS directly. See `opensearch.md` for the full workflow.

## Spark

Spark runs on AWS EMR, not in k3s. It is provisioned and managed via `easy-db-lab spark` commands. See `spark.md` for the full workflow.

## SSH

SSH access to all nodes is configured via **`sshConfig`** in the workspace directory. To use it directly:

```bash
ssh -F sshConfig db0
ssh -F sshConfig app0
```

## Node Filesystem Layout

### Cassandra installs — `/usr/local/cassandra/`

Every Cassandra version is installed as its own directory, named by the version prefix from `/etc/cassandra_versions.yaml`:

```
/usr/local/cassandra/
  3.0/        ← full Cassandra install
  3.11/
  4.0/
  4.1/
  5.0/
  5.0-HEAD/   ← custom builds or nightly tarballs
  trunk/
  current     ← symlink → active version directory
```

`bin/use-cassandra <version>` manages the `current` symlink:

```bash
sudo ln -vfns /usr/local/cassandra/$1 /usr/local/cassandra/current
sudo ln -vfns /usr/local/cassandra/$1/conf /etc/cassandra
```

`/etc/cassandra` is therefore also a symlink — it always points to the active version's `conf/` directory. The systemd service hardcodes `current`:

```
ExecStart=/usr/local/cassandra/current/bin/cassandra -f
```

Each version directory also contains `conf.orig/` and `cassandra.orig.yaml` — backups created at install time so you can always diff against the original config.

`/etc/cassandra_versions.yaml` is the source of truth for all installed versions, their download sources, and optional custom build URLs.

### Data disk — `/mnt/db1/`

`/mnt` is an ephemeral mount point at packer build time (unmounted so subdirectories can be created). At runtime it is an instance store or EBS volume — the high-I/O storage for everything.

**Cassandra data:**

```
/mnt/db1/cassandra/
  data/       ← data_file_directories
  commitlog/  ← commitlog_directory
  hints/      ← hints_directory
  logs/       ← CASSANDRA_LOG_DIR (system.log, debug.log, GC logs)
  artifacts/  ← CASSANDRA_HEAPDUMP_DIR
  stress/     ← cassandra-easy-stress logs
  tmp/        ← CASSANDRA_LOG_DIR fallback (env default, superseded)
```

**Observability backend data (control node):**

```
/mnt/db1/victoriametrics/
/mnt/db1/victorialogs/
/mnt/db1/grafana/
/mnt/db1/pyroscope/
/mnt/db1/clickhouse/
  logs/
  keeper/logs/
```

### Cassandra log path

Cassandra logs land in `/mnt/db1/cassandra/logs/`. This is set in three places that must agree:

1. `cassandra.service` — `Environment=CASSANDRA_LOG_DIR=/mnt/db1/cassandra/logs`
2. `cassandra.in.sh` — `CASSANDRA_LOG_DIR="/mnt/db1/cassandra/logs"`
3. `/etc/default/cassandra` — sets the `tmp/` fallback (superseded by the above two)

GC logs (JDK 17/21) also land in `CASSANDRA_LOG_DIR`. The OTel Collector mounts `/mnt/db1/cassandra/logs` as a hostPath volume and ships log files to VictoriaLogs.

### MAAC agents — `/opt/management-api/`

The MAAC (Management API for Apache Cassandra) Prometheus agent JARs are installed per Cassandra version:

```
/opt/management-api/
  4.0/datastax-mgmtapi-agent.jar
  4.1/datastax-mgmtapi-agent.jar
  5.0/datastax-mgmtapi-agent.jar
```

These are injected as `-javaagent:` args via `cassandra.in.sh` and expose Cassandra metrics to Prometheus.

### Other notable paths

| Path | Purpose |
|------|---------|
| `/usr/local/pyroscope/pyroscope.jar` | Pyroscope Java agent for continuous profiling |
| `/usr/share/axonops/<version>-agent/lib/` | AxonOps monitoring agents (per Cassandra version) |
| `/etc/cassandra_versions.yaml` | Source of truth for installed Cassandra versions and build URLs |
| `/var/log/easydblab/tools/` | exec tool logs shipped to VictoriaLogs by OTel Collector |

## After Running `up`

After `easy-db-lab up` completes, always run:

```bash
source env.sh
```

This sets up local files including `sshConfig`. Without this step, SSH and other local tooling will not be configured correctly.
