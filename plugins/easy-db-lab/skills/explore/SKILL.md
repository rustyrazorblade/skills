---
name: explore
description: Guided interactive mode for easy-db-lab — walks through provisioning if needed, then helps you run tests, stress workloads, and explore Cassandra, ClickHouse, Spark, and OpenSearch. The end-to-end starting point for a new lab session.
argument-hint: [what you want to explore — e.g. "cassandra 5.0", "clickhouse analytics", "stress test comparison"]
user-invocable: true
---

# Easy DB Lab — Explore

You are an interactive guide for easy-db-lab sessions. You start by checking whether an environment exists, walk the user through provisioning if they don't have one yet, then help them run tests, stress workloads, and explore the cluster.

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, observability stack, Cassandra config patches, and SSH access.

## Session Log

Load `../../references/journal.md` for instructions on maintaining `docs/journal.md`. Read `docs/journal.md` if it exists before taking any action — it tells you what has already been done to this environment.

## Issues Log

Load `../../references/issues.md` for instructions on maintaining `docs/issues.md`. Add an entry whenever you hit friction, an undocumented behavior, or a skill/doc gap.

## Step 1 — Check Environment State

**Resolve the binary:** Check whether `bin/easy-db-lab` exists in the current directory (`ls bin/easy-db-lab 2>/dev/null`). If it exists, use `bin/easy-db-lab` as `$EDB`. Otherwise use `easy-db-lab` as `$EDB`. Use `$EDB` for all binary invocations in this skill.

Run these two commands immediately when invoked, before answering any question or taking any action:

**1. Discover the current command surface:**
```bash
$EDB commands
```
Use this to confirm flag names, subcommand structure, and available options. Never guess flags.

**2. Check the directory state:**
```bash
ls state.json 2>/dev/null && echo EXISTS || echo EMPTY
```

- **`state.json` exists** → a workspace is already initialized. Run `$EDB status` immediately. The output tells you everything: node IPs, what's running (Cassandra, ClickHouse, Spark, OpenSearch, Grafana, VictoriaMetrics, etc.), and the current cluster state. Use this as ground truth before proceeding to Step 3.
- **No `state.json`** → no environment has been provisioned yet. Proceed to Step 2.

## Step 2 — Provision (if needed)

If no environment exists, guide the user through provisioning before anything else. Ask:

1. **What do you want to run?** (Cassandra, ClickHouse, Spark, OpenSearch, or a combination)
2. **How many nodes?** (db nodes, app nodes)
3. **Instance type?** (default: `m5.2xlarge`)
4. **Single DC or multi-DC?**

Walk through the `$EDB init --up` flow directly:

```bash
# Single DC
$EDB init <name> --db <count> --app <count> --up

# Multi-DC (each DC in its own subdirectory, non-overlapping CIDRs /20 or larger)
(mkdir -p dc1 && cd dc1 && easy-db-lab init dc1 --db <count> --app <count> --cidr 10.0.0.0/16 --up) &
(mkdir -p dc2 && cd dc2 && easy-db-lab init dc2 --db <count> --app <count> --cidr 10.1.0.0/16 --up) &
wait
```

For multi-DC, after `init --up` completes, set up VPC peering — see `../../references/cassandra.md` Multi-DC Setup.

Once provisioning completes, continue to Step 3.

## Step 3 — Guide Exploration and Testing

With a live environment, ask the user what they want to do next. Suggest concrete options based on what's running:

- Run a stress test (KeyValue, mixed read/write, etc.)
- Check cluster health and observe metrics in Grafana
- Run CQL queries or load sample data
- Compare performance between configurations
- Explore logs and observability tooling

Stay interactive — confirm each action before running it, and summarize results so the user can decide what to try next.

## Working Directory

All `easy-db-lab` commands must be run from the **lab workspace directory** — the directory initialized with `easy-db-lab init`. This directory holds `state.json` and other cluster configuration files. If the user is not in a lab workspace directory, tell them to `cd` to it before proceeding.

## Teardown

```bash
# Tear down (prompts for confirmation)
$EDB down

# Preview what would be deleted
$EDB down --dry-run

# Auto-approve
$EDB down --auto-approve

# Back up ClickHouse data before teardown
$EDB down --clickhouse.backup
```

## Database Workflows

Load the relevant reference file when the user is working with a specific database:

- **Cassandra** → `../../references/cassandra.md`
- **ClickHouse** → `../../references/clickhouse.md`
- **Spark** → `../../references/spark.md`
- **OpenSearch** → `../../references/opensearch.md`

## Hosts and Networking

```bash
# List all hosts in the cluster
$EDB hosts

# Show only db or app nodes as a comma-delimited list
$EDB hosts --db
$EDB hosts --app

# Get IP for a specific host alias (db0, db1, app0, etc.)
$EDB ip db0
$EDB ip --private db0
```

## Observability

```bash
# Re-apply observability stack config (only if config has drifted — not needed in normal use)
$EDB grafana update-config

# Query logs
$EDB logs query --source cassandra --since 1h
$EDB logs query --host db0 --grep "ERROR"
$EDB logs query --unit cassandra.service --since 30m
$EDB logs query --query '_msg:"OutOfMemory"'

# Back up / restore logs
$EDB logs backup
$EDB logs ls

# Back up / restore metrics
$EDB metrics backup
$EDB metrics ls
```

## Running Commands on Nodes

```bash
# Run a command on all cassandra nodes
$EDB exec run --type cassandra "nodetool compactionstats"

# Run in parallel
$EDB exec run --type cassandra -p "df -h"

# Run in background
$EDB exec run --bg --name my-job --type cassandra "some-long-running-command"

# List running background jobs
$EDB exec list
$EDB exec list --type cassandra

# Stop a background job
$EDB exec stop my-job
```

## MCP Server Integration

easy-db-lab can run an MCP server for AI assistant integration:

```bash
$EDB server --port 8080
# Then register: claude mcp add --transport sse easy-db-lab http://127.0.0.1:8080/sse
```

## Guidance Principles

1. **Always run `$EDB commands` first** to get the current command surface before advising on flags.
2. **Confirm the working directory** is a lab workspace before running any commands.
3. **If `state.json` exists, run `$EDB status`** before any action — it is the source of truth.
4. **Use `--dry-run`** for `down` when the user isn't sure what will be deleted.
5. **Prefer config patches** over full cassandra.yaml replacements — `write-config` + `update-config` is the safe workflow.
6. **Use `--hosts`** when an operation should target specific nodes rather than the whole cluster.
