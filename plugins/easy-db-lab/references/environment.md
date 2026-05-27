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

The following run in k3s and are part of every environment:

- **Grafana** — dashboards and visualization
- **VictoriaMetrics** — metrics storage and querying
- **VictoriaLogs** — log storage and querying

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

## After Running `up`

After `easy-db-lab up` completes, always run:

```bash
source env.sh
```

This sets up local files including `sshConfig`. Without this step, SSH and other local tooling will not be configured correctly.
