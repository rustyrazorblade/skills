---
name: run
description: Execute a plan.md step by step in a lab workspace. Reads the plan, confirms with the user at each step, and updates history.md as work proceeds.
argument-hint: "optional — step number to start from, e.g. 'start from step 3'"
user-invocable: true
---

# Easy DB Lab — Run Plan

You execute a `plan.md` in the current lab workspace, one step at a time.

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, SSH access, and the `source env.sh` requirement after `up`.

## Session Log

Load `../../references/history.md` for instructions on maintaining `history.md`. Read `history.md` if it exists before taking any action — it tells you what has already been done.

## Discover the Command Surface First

Before executing any `easy-db-lab` command, run:

```bash
easy-db-lab commands
```

Use this output as the authoritative source for flag names and available options. Never guess flags.

## Before Starting

1. **Verify the workspace:**
   ```bash
   ls plan.md 2>/dev/null && echo EXISTS || echo MISSING
   ls state.json 2>/dev/null && echo EXISTS || echo EMPTY
   ```

   - If `plan.md` is missing, tell the user to create one with `/easy-db-lab:plan` first.
   - If `state.json` exists, run `easy-db-lab status` to confirm the current cluster state.

2. **Read `plan.md`** — display a numbered summary of all steps to the user before executing anything.

3. **If the user specified a starting step** (e.g. "start from step 3"), confirm which step that is and skip to it.

## Execution Loop

For each step in the plan, in order:

**1. Show the step**

Display the full step text and ask: "Ready to execute this step?"

Wait for the user to confirm before proceeding.

**2. Execute**

Run the required `easy-db-lab` commands (or AWS CLI, kubectl, etc.) for the step. Show the output.

**3. Verify**

After each step, confirm it succeeded:
- For `easy-db-lab up`: check that nodes are reachable via `easy-db-lab status`
- For cassandra start: check cluster health via `easy-db-lab cassandra status` or `nodetool status`
- For other steps: use the most appropriate check given the operation

**4. Update history.md**

Record what was done, the outcome, and any relevant output. See `../../references/history.md` for format.

**5. Proceed**

Ask: "Step N complete. Continue to step N+1?" before moving on.

## Pausing and Resuming

If the user asks to stop, record progress in `history.md` (last completed step + state) so the next session can resume cleanly.

When invoked again, read `history.md` to determine where to resume, then confirm with the user before continuing.

## Error Handling

If a step fails:
1. Show the error clearly.
2. Do not proceed to the next step.
3. Diagnose the failure — check logs, status, or node health as appropriate.
4. Propose a fix and wait for user approval before retrying.
5. Record the failure and resolution in `history.md`.

## Database Workflows

Load the relevant reference file when a step involves a specific database:

- **Cassandra** → `../../references/cassandra.md`
- **ClickHouse** → `../../references/clickhouse.md`
- **Spark** → `../../references/spark.md`
- **OpenSearch** → `../../references/opensearch.md`
