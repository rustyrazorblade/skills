# OpenSearch Workflow

OpenSearch runs as an AWS managed domain. Provisioning takes 10–30 minutes. It can be enabled at init time with `--opensearch.enable` or started independently.

## Start

```bash
# Create an OpenSearch domain with defaults
easy-db-lab opensearch start

# Specify instance type, count, and storage
easy-db-lab opensearch start \
  --instance-type r5.large.search \
  --instance-count 3 \
  --ebs-size 100

# Wait for the domain to become active before returning
easy-db-lab opensearch start --wait
```

Or enable at `easy-db-lab init` time:
```bash
easy-db-lab init my-cluster --db 3 --app 1 --instance m5.2xlarge \
  --opensearch.enable \
  --opensearch.instance.type r5.large.search \
  --opensearch.instance.count 3 \
  --opensearch.version 2.11 \
  --opensearch.ebs.size 100
```

## Status

```bash
# Check domain status
easy-db-lab opensearch status

# Output only the endpoint URL (useful for scripting)
easy-db-lab opensearch status --endpoint
```

## Stop

```bash
easy-db-lab opensearch stop

# Force deletion without confirmation
easy-db-lab opensearch stop --force
```
