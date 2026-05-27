# ClickHouse Workflow

## Configure and Start

```bash
# Configure settings — run before first start
easy-db-lab clickhouse init
easy-db-lab clickhouse init --replicas-per-shard 3
easy-db-lab clickhouse init --s3-cache 10Gi --s3-cache-on-write true
easy-db-lab clickhouse init --s3-tier-move-factor 0.2

# Deploy ClickHouse cluster to K8s
easy-db-lab clickhouse start

# Set number of replicas explicitly (default: number of db nodes)
easy-db-lab clickhouse start --replicas 3

# Wait up to custom timeout for pods to be ready (default: 300s)
easy-db-lab clickhouse start --timeout 600

# Skip waiting for pods
easy-db-lab clickhouse start --skip-wait

# Restore from a named backup on startup
easy-db-lab clickhouse start --restore-from my-backup

# Check cluster status
easy-db-lab clickhouse status
```

## Backup and Restore

```bash
# Back up to the cluster S3 bucket
easy-db-lab clickhouse backup my-backup

# Back up in the background (returns immediately)
easy-db-lab clickhouse backup my-backup --async

# List available backups in S3
easy-db-lab clickhouse list-backups

# Restore from a named backup
easy-db-lab clickhouse restore my-backup

# Restore in the background
easy-db-lab clickhouse restore my-backup --async
```

## Stop

```bash
easy-db-lab clickhouse stop

# Force deletion without confirmation
easy-db-lab clickhouse stop --force
```
