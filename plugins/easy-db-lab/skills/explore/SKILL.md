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

**Resolve the binary.**  Use `$EDB` for all binary invocations in this skill.  Resolve it in this order:

1. Run `detect-cluster-layout.sh "$PWD"` and read its output.  Do not `eval` it: shell state does not persist between Bash tool calls.  Copy the absolute wrapper paths from the output, and use those paths literally in every later command.
   - `LAYOUT=single`: use the `EDB=` path as `$EDB`.
   - `LAYOUT=multi`: use each `EDB_<DC>=` path as that DC's wrapper.  Run DC commands, uploads, and teardown through every DC wrapper.
   - `LAYOUT=multi` with `DCS=bin`: this is not a workspace.  The script matched `bin/easy-db-lab`, which is the binary in an easy-db-lab source checkout.  Ignore the output and go to item 2.
   - Exit 1 (no wrapper found): there is no wrapper.  Go to item 2.
2. Use `$PWD/bin/easy-db-lab` if it is executable.
3. Otherwise, use the path that `command -v easy-db-lab` prints.

```bash
detect-cluster-layout.sh "$PWD"
```

The workspace directory is `$PWD`.  In a multi-DC workspace it is the cluster root, which holds one directory per DC and the shared `docs/`.  This directory is `<cluster-dir>` everywhere in this skill and in `../../references/report-upload.md`.

If no binary resolves in an interactive session, ask the user for a path.  If the user has no path, or the path is not executable, stop and report the paths searched.  In an unattended session, do not ask: stop and report the paths searched.  Without a binary, write no command or file from memory.

Run these commands immediately when invoked, before answering any question or taking any action:

**1. Discover the current command surface, help-first:**
```bash
# List the task-oriented topic guides
$EDB help

# Read the guide for each topic the session touches
$EDB help <topic>

# The flag-level reference
$EDB commands
```
Each `help <topic>` guide gives the intended command sequence for a topic.  Use `$EDB commands`, and `$EDB <command> --help`, to confirm flag names, subcommand structure, and available options.  Never guess flags.  If `$EDB help` errors with `Unmatched argument at index 0: 'help'`, the binary predates the topic guides.  Skip the guides and use `commands` and `--help`.

In the same `$EDB commands` output, check whether `report upload` is listed.  Record the result once.  If it is absent, follow the "Support Check" section of `../../references/report-upload.md`.  If there is no `docs/` directory, tell the user instead of writing the journal note.

**2. Check the directory state:**
```bash
ls state.json 2>/dev/null && echo EXISTS || echo EMPTY
```

- **`state.json` exists** → a workspace is already initialized. Run `$EDB status` immediately. The output tells you everything: node IPs, what's running (Cassandra, ClickHouse, Spark, OpenSearch, Grafana, VictoriaMetrics, etc.), and the current cluster state. Use this as ground truth before proceeding to Step 3.
- **No `state.json`** → no environment has been provisioned yet. Proceed to Step 2.

In a multi-DC workspace, `state.json` lives in each DC directory, not in the current directory:

- **With DC wrappers:** use the `STATE` value from `detect-cluster-layout.sh`.  `provisioned` means run `$EDB status` through every DC wrapper, then go to Step 3.
- **With no DC wrappers** (for example, a multi-DC lab that this skill provisioned in Step 2): check the direct subdirectories with `ls */state.json 2>/dev/null`.  For each match, run `$EDB status` from that DC directory, then go to Step 3.  Do not go to Step 2.

**This is an existence check only.** `state.json` is an internal file of the `easy-db-lab` tool. It
is not a documented interface, and its shape can change at any time. Never read it, never parse it,
and never quote its contents to the user. `$EDB status` is the only source of cluster state.

## Step 2 — Provision (if needed)

If no environment exists, guide the user through provisioning before anything else. Ask:

1. **What do you want to run?** (Cassandra, ClickHouse, Spark, OpenSearch, or a combination)
2. **How many nodes?** (db nodes, app nodes)
3. **Instance type?** (default: `m5.2xlarge`)
4. **Single DC or multi-DC?**

Walk through the `$EDB init --up` flow directly:

```bash
# Single DC
$EDB init <name> --db.count <count> --app.count <count> --up

# Multi-DC (each DC in its own subdirectory, non-overlapping CIDRs /20 or larger)
(mkdir -p dc1 && cd dc1 && $EDB init dc1 --db.count <count> --app.count <count> --cidr 10.0.0.0/16 --up) &
(mkdir -p dc2 && cd dc2 && $EDB init dc2 --db.count <count> --app.count <count> --cidr 10.1.0.0/16 --up) &
wait
```

`init --up` provisions AWS instances. It takes a few minutes to finish. This is normal. Set the
Bash tool timeout to its maximum (600000 ms) and let the command run to completion. Do not stop it
early, and do not check progress by reading `state.json`.

The multi-DC form above is the one allowed background pattern: each DC provisions in parallel, and
`wait` blocks until both finish. Do not continue past `wait`.

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

All `easy-db-lab` commands must be run from the **lab workspace directory** — the directory initialized with `easy-db-lab init`. This directory holds `state.json` and other internal cluster configuration files, which you never read. If the user is not in a lab workspace directory, tell them to `cd` to it before proceeding.

## Teardown

Every real `$EDB down` is gated on the report upload.  Follow `../../references/report-upload.md` for the file selection, the upload procedure, the gate, and the failure handling.

`<cluster-dir>` is the workspace directory that you passed to `detect-cluster-layout.sh`, which is `$PWD`.  In a multi-DC workspace, it is the cluster root.

1. Choose the files with the explore rule in the reference.  List every existing `docs/*.md` by absolute path.  Exclude `SUMMARY.md`, and exclude `results.md` while it holds only the scaffold comments.  Name each excluded file in `docs/journal.md`.
2. If `docs/` does not exist, tell the user "docs/ not found; no report uploaded" before `down`.  In an unattended session, put this line in the report to the launcher.  If `docs/` does not exist, or no eligible file remains, do not upload.  Run `$EDB down --auto-approve`.
3. Otherwise, run one `$EDB report upload` command with the eligible files, per DC wrapper.
4. Run `$EDB down --auto-approve` only if every upload exits 0.  If an upload fails, or the CLI rejects the batch, do not run `down`.  Follow the failure handling in the reference.

In a multi-DC workspace, upload through every DC wrapper first.  Then run `$EDB down --auto-approve` through every DC wrapper.  If there is no wrapper, run each DC's commands from that DC's directory.

```bash
# Preview what would be deleted (destroys nothing; needs no upload)
$EDB down --dry-run

# Real teardown, only after the upload gate passes
$EDB down --auto-approve
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

Read `$EDB help observability` for the observability stack, its endpoints, and the log, metric, and annotation commands.  Confirm flags with `$EDB commands` before you run a command.

```bash
# Query logs
$EDB logs query --source cassandra --since 1h
$EDB logs query --host db0 --grep "ERROR"
$EDB logs query --unit cassandra.service --since 30m
```

## Running Commands on Nodes

```bash
# Run nodetool on all cassandra nodes (nodetool is not on PATH under exec run)
$EDB cassandra nt compactionstats

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

1. **Discover the command surface help-first** before advising on flags: run `$EDB help`, then `$EDB help <topic>` for each topic the session touches, then `$EDB commands` and `--help`.
2. **Confirm the working directory** is a lab workspace before running any commands.
3. **If `state.json` exists, run `$EDB status`** before any action — it is the source of truth. Test only that the file exists; never read its contents.
4. **Run every `easy-db-lab` command to completion** before you do anything else. Do not background it, do not cut it short with a timeout, and do not poll `$EDB status` while it runs.
5. **Use `--dry-run`** for `down` when the user isn't sure what will be deleted.
6. **Prefer config patches** over full cassandra.yaml replacements — `write-config` + `update-config` is the safe workflow.
7. **Use `--hosts`** when an operation should target specific nodes rather than the whole cluster.
