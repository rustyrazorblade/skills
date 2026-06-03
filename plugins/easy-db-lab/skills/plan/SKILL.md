---
name: plan
description: Helps the user design a lab workflow by asking questions, working through steps together, and writing the result to a plan.md file. Use when planning a new lab run, benchmarking test, or database experiment.
argument-hint: "[what you want to accomplish] [--binary <path>] [--output <path>] [--previous <cluster-dir>]"
user-invocable: true
---

# Easy DB Lab — Plan

You are helping the user design a lab workflow. Your job is to ask the right questions, help them think through the steps, and produce a clear `plan.md` they can follow.

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, observability stack, Cassandra config patches, and SSH access.

## Previous Run (optional)

If `--previous <cluster-dir>` was provided, read the following files before asking any planning questions:

- `<cluster-dir>/docs/journal.md` — what was done, what was observed, what worked and what didn't
- `<cluster-dir>/docs/issues.md` — friction, undocumented behavior, or gaps discovered during the run

Use these to inform the new plan: incorporate steps that were added ad-hoc, avoid approaches that failed, and address known issues. Load `../../references/journal.md` and `../../references/issues.md` for the format these files follow.

## Discover Before You Plan

Before asking the user anything, resolve the binary and run both discovery commands.

**Resolve the binary** — in priority order:
1. If `--binary <path>` was passed as an argument to this skill, use that path as `$EDB`
2. If `bin/easy-db-lab` exists in the current directory, use `bin/easy-db-lab` as `$EDB`
3. Otherwise use `easy-db-lab` as `$EDB`

Use `$EDB` for all binary invocations in this skill.

```bash
# Authoritative flag and subcommand reference
$EDB commands

# All installable software available in this environment
$EDB kit list
```

Use `commands` output as the authoritative source for flag names and subcommands — never guess flags.

Use `kit list` output as the authoritative list of installable software. Any database, tool, or app the plan needs to install must appear in this list. If the user asks for something not in the list, stop and ask them what they mean — do not guess, do not try alternatives, and never use `docker`.

If the binary cannot be found, load `../../references/commands.md` as a fallback and warn the user to verify flags when running the plan.

## Step 1 — Understand the Objective

Before asking about infrastructure or workloads, understand what the user is actually trying to learn. If they've provided an argument, use that as the starting point — but probe deeper.

**Ask one question at a time.** Do not move to Step 2 until you have a clear, specific objective.

Work through these areas in order:

1. **What question are you trying to answer?**
   Get the research question in concrete terms. Examples: "Does TWCS reduce compaction overhead for our time-series write pattern?" or "What sustained throughput can a 3-node cluster handle at p99 < 5ms?" Push past vague goals like "test Cassandra performance" — the question should be specific enough that you'd know whether the test answered it.

2. **What hypothesis or assumption is being tested?**
   What do they expect to happen, and why? This shapes the workload, the config, and what to measure. If they don't have one, help them form one.

3. **What does success look like?**
   A specific metric, a threshold, a comparison, or an observation. "p99 write latency stays below 5ms at 10k ops/s" is a success criterion. "Performance looks good" is not.

4. **What will they do with the results?**
   Inform a production decision? Share with the team? Satisfy curiosity? This affects how rigorous the test needs to be and what to record.

5. **Are there constraints?**
   Time budget, AWS cost limits, specific instance types, existing infrastructure, or a deadline.

Once the objective is clear and specific, move to Step 2 to design the test around it.

## Step 2 — Design the Test

With the objective in hand, determine what components and workload are needed to answer the research question. Don't ask about things the objective doesn't require. Ask one question at a time.

**Infrastructure:**
- What is the Cassandra cluster name? This is baked into the cluster configuration and shared across all nodes in all DCs.
- How many db nodes? What instance type?
- Are app/stress nodes needed? How many?
- Any availability zone requirements?
- Single DC or multi-DC? If multi-DC, what are the DC names and CIDR blocks? CIDRs must be non-overlapping and /20 or larger (e.g. dc1: `10.0.0.0/16`, dc2: `10.1.0.0/16`).

**Instance type and storage — ask explicitly:**
- If the user picks an instance type with local NVMe (e.g. `i4i.xlarge`, `im4gn.xlarge`), no EBS config is needed.
- If the user picks an instance type without local NVMe (e.g. `m5.xlarge`, `r6i.xlarge`, `c6i.xlarge`), EBS **must** be configured. Ask which volume type:
  - **gp3** — general purpose SSD, good default for most workloads (default if they don't specify)
  - **io2** — high-IOPS SSD, for latency-sensitive workloads requiring provisioned IOPS
  Present these as a menu. If they choose io2, also ask for the IOPS value.
- If the user doesn't specify an instance type, recommend `i4i.xlarge` for database nodes (local NVMe, no EBS needed).

**Software to install:**
Identify every database, tool, or app the test requires. For each one:
- Confirm the exact name from the `kit list` output obtained above
- Run `$EDB kit info <name>` to get the kit's available flags, options, and any install-time configuration — use this as the authoritative source for the `kit install` command in the plan. Do not invent flags.
- Load the relevant reference file for accurate configuration details:
  - Cassandra → `../../references/cassandra.md`
  - ClickHouse → `../../references/clickhouse.md`
  - Spark → `../../references/spark.md`
  - OpenSearch → `../../references/opensearch.md`
  - Anything else → `../../references/kits.md`

**AWS credentials:**
- Ask which `AWS_PROFILE` to use for any AWS CLI commands in this plan. Do not assume or encode a default — always ask.

**Sidecar image (bulk import workflows only):**
- If the plan involves bulk SSTable import (e.g. IAM Bulk Writer, Spark), ask whether a custom sidecar image is needed. If yes, get the full image URI now — it must be passed at `cassandra start` time via `--sidecar-image`.

**Workload:**
- What stress workload? (for Cassandra: `$EDB cassandra stress list`)
- How long should the test run? How many threads?
- Any custom tags for metrics?

**Observability:**
- Will Grafana be used to monitor? (it's part of the default stack)
- Are log queries needed during the test?

## Step 3 — Build the Plan

Once you have enough information, construct a step-by-step plan. Each step should be a concrete action with the exact command to run. Group steps logically:

1. Provision the environment
2. Install software (specific `kit install <name>` commands, using exact names from `kit list`)
3. Configure the database(s)
4. Run the workload or test
5. Observe / collect results
6. Tear down (if applicable)

**The run skill handles all workspace scaffolding** (cluster directory, wrapper, docs) before executing any plan step. The first step in the plan must be provisioning (`easy-db-lab init ... --up`). Never include wrapper creation, directory setup, or `EDB=` assignments — those are handled automatically and must not appear in the plan.

## Step 4 — Write the Plan

Load `../../references/plan-template.md` and use it as the starting point. Fill in every section — do not leave any placeholder text in the output. Write the completed plan to the path specified by `--output`, if provided; otherwise default to `plan.md` in the current directory. Create any intermediate directories if needed.

**Multi-DC format for `## Datacenters`:**
```
- dc1: 10.0.0.0/16
- dc2: 10.1.0.0/16
```

Show the user the completed plan before writing it and ask for confirmation. After writing, move to Step 5.

## Step 5 — Review the Plan

Before finishing, review the written plan against the objective established in Step 1. Check:

- **Answers the question** — do the steps actually produce the data needed to answer the research question? If not, what's missing?
- **Success criteria are measurable** — is there a step that captures the specific metric or observation defined as success?
- **Every command is concrete** — no vague steps like "configure Cassandra"; each step has an exact command
- **No gaps in the sequence** — could someone follow this plan start to finish without needing to improvise?
- **Cassandra-specific:** if the plan involves Cassandra performance, does it cover the right config knobs for the question being asked (memtable implementation, compaction strategy, num_tokens, etc.)? Invoke the `cassandra-expert` agent if there's any doubt about whether the configuration is appropriate for the workload.

Present the review findings to the user as a short bulleted list — what looks good, and anything that should be changed. If changes are needed, update the plan file and confirm with the user. Once the plan passes review, tell them to run `/easy-db-lab:run` to execute it.
