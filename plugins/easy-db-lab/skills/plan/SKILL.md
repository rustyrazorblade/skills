---
name: plan
description: Help the user design a lab workflow — ask what they want to accomplish, work through the steps together, and write the result to plan.md.
argument-hint: [what you want to accomplish — e.g. "benchmark Cassandra 5.0 vs 4.1", "test ClickHouse with S3 tiering"]
user-invocable: true
---

# Easy DB Lab — Plan

You are helping the user design a lab workflow. Your job is to ask the right questions, help them think through the steps, and produce a clear `plan.md` they can follow.

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, observability stack, Cassandra config patches, SSH access, and the `source env.sh` requirement after `up`.

## Session Log

Load `../../references/history.md` for instructions on maintaining `docs/history.md`. Read `docs/history.md` if it exists — past actions and observations should inform the plan.

## Issues Log

Load `../../references/issues.md` for instructions on maintaining `docs/issues.md`. Read `docs/issues.md` if it exists — known friction or doc gaps should inform how you write the plan steps.

## Discover the Command Surface First

Before writing any plan step that uses `easy-db-lab`, run:

```bash
easy-db-lab commands
```

Use this output as the authoritative source for flag names, subcommand structure, and available options. Never guess flags — if a flag isn't in the output of `easy-db-lab commands`, do not use it.

## Step 1 — Understand the Goal

Ask the user what they want to accomplish. If they've provided an argument, use that as the starting point. Probe for:

- **What are they testing or benchmarking?** (a specific database, a config change, a workload pattern)
- **What does success look like?** (metrics, observations, a pass/fail condition)
- **Are there constraints?** (time, cost, instance types, existing infrastructure)

Ask one question at a time. Don't move on until you have a clear goal.

## Step 2 — Identify the Components

Based on the goal, determine which components are needed. Ask about each that's relevant:

**Infrastructure:**
- How many db nodes? What instance type?
- Are app/stress nodes needed? How many?
- Any availability zone requirements?

**Instance type and storage — ask explicitly:**
- If the user picks an instance type with local NVMe (e.g. `i4i.xlarge`, `im4gn.xlarge`), no EBS config is needed.
- If the user picks an instance type without local NVMe (e.g. `m5.xlarge`, `r6i.xlarge`, `c6i.xlarge`), EBS **must** be configured. Ask which volume type:
  - **gp3** — general purpose SSD, good default for most workloads (default if they don't specify)
  - **io2** — high-IOPS SSD, for latency-sensitive workloads requiring provisioned IOPS
  Present these as a menu. If they choose io2, also ask for the IOPS value.
- If the user doesn't specify an instance type, recommend `i4i.xlarge` for database nodes (local NVMe, no EBS needed).

**Databases** — load the relevant reference file(s) for accurate command details:
- Cassandra → `../../references/cassandra.md`
- ClickHouse → `../../references/clickhouse.md`
- Spark → `../../references/spark.md`
- OpenSearch → `../../references/opensearch.md`

**AWS credentials:**
- Ask which `AWS_PROFILE` to use for any AWS CLI commands in this plan. Do not assume or encode a default — always ask.

**Sidecar image (bulk import workflows only):**
- If the plan involves bulk SSTable import (e.g. IAM Bulk Writer, Spark), ask whether a custom sidecar image is needed. If yes, get the full image URI now — it must be passed at `cassandra start` time via `--sidecar-image`.

**Workload:**
- What stress workload? (for Cassandra: `easy-db-lab cassandra stress list`)
- How long should the test run? How many threads?
- Any custom tags for metrics?

**Observability:**
- Will Grafana be used to monitor? (it's part of the default stack)
- Are log queries needed during the test?

## Step 3 — Build the Plan

Once you have enough information, construct a step-by-step plan. Each step should be a concrete action with the exact command to run. Group steps logically:

1. Provision the environment
2. Configure the database(s)
3. Run the workload or test
4. Observe / collect results
5. Tear down (if applicable)

## Step 4 — Write the Plan

Write the plan to `plan.md` in the **current directory** (wherever the user is running this skill — not necessarily a cluster directory). This is the working copy they'll refine before provisioning.

Format:

```markdown
# Lab Plan: <goal>

## Goal
<one or two sentences describing what this plan accomplishes and what success looks like>

## Environment
<summary of infrastructure: nodes, instance types, storage>

## Steps

### 1. <Step name>
<brief description>
\```bash
<command>
\```

### 2. <Step name>
...

## Notes
<any caveats, things to watch for, or follow-up ideas>
```

Show the user the plan before writing it and ask for confirmation. After writing, tell them to run `/easy-db-lab:run` to execute it.

## When a Cluster Directory Is Created

When the plan includes an `easy-db-lab init` or `easy-db-lab up` step that creates a cluster directory, the run skill will set up `docs/` inside that directory and copy `plan.md` into it as `docs/plan.md`. The `docs/` directory is the canonical home for all lab documentation once a cluster exists. See the run skill for details.
