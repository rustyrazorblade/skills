---
name: run
description: Executes a plan step by step in an explicit cluster workspace, confirming each step with the user and updating journal.md as work proceeds. Use when running or resuming a lab plan, benchmark, or database experiment.
argument-hint: "<cluster directory> [step N]  OR  <plan.md path> <cluster directory> [--binary <path>] [--jdk <path>] [step N]"
user-invocable: true
---

# Easy DB Lab — Run Plan

You execute a plan step by step in an explicit cluster workspace, reading the plan from `<cluster-dir>/docs/plan.md`.

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, and SSH access.

## Session Log

Load `../../references/journal.md` for instructions on maintaining the journal. Once the cluster dir is established, read `<cluster-dir>/docs/journal.md` before taking any action — it tells you what has already been done.

## Issues Log

Load `../../references/issues.md` for instructions on maintaining the issues file. Add an entry to `<cluster-dir>/docs/issues.md` whenever you hit friction, an undocumented behavior, or a skill/doc gap.

## Discover the Command Surface First

After setting up `$EDB` in the Before Starting section, run:

```bash
$EDB commands
```

Use this output as the authoritative source for flag names and available options. Never guess flags. If `$EDB` is not yet available, load `../../references/commands.md` as a fallback.

**Kit commands are only visible after installation.** If you need to look up the commands, flags, or endpoints for a kit that is not yet installed, use `kit info` instead of relying on `commands`:

```bash
$EDB kit info <name>
```

## Before Starting

### 1. Determine the invocation mode

The skill is invoked in one of two ways:

**First run** — `<plan.md path> <cluster directory> [step N]`
The cluster directory does not exist yet (or has no `docs/plan.md`). Full scaffolding is required.

**Resume** — `<cluster directory> [step N]`
The cluster directory already exists and contains `docs/plan.md`. Skip scaffolding entirely.

Detect which case applies by checking for `docs/plan.md` inside the provided directory. If the directory doesn't exist or has no `docs/plan.md`, treat it as a first run and require a plan path. If `docs/plan.md` exists, treat it as a resume.

If a required argument is missing, ask the user for it before continuing.

---

### First run

**Read the plan.** Extract the cluster name and datacenter configuration directly from the plan file:

- **Cluster name** — value under `## Cluster Name`
- **Datacenters** — if `## Datacenters` is `single`, it is a single-DC cluster; otherwise each `- <dc>: <cidr>` line defines a DC name and CIDR

**Ask the user only for anything missing:**
- **`easy-db-lab` binary path** (`--binary`) — check for `bin/easy-db-lab` in the current directory first, then try `which easy-db-lab`; only ask if neither is found.
- **Java 21 JDK home** (`--jdk`) — leave blank to inherit the system default.

**Scaffold the cluster workspace — run the script, never do this manually:**

> **NEVER create workspace files or directories by hand, and NEVER read `setup-cluster.sh` and perform its steps yourself. You MUST execute it as a script via bash. The tool requires a strict directory structure that only the script produces correctly. Any manual recreation will produce a broken workspace.**

```bash
# Single DC (DCS=single)
setup-cluster.sh <cluster-dir> <binary|easy-db-lab> --name "$NAME" --plan <plan.md path> [--jdk <path>]

# Multi DC (DCS="dc1 dc2 ...")
setup-cluster.sh <cluster-dir> <binary|easy-db-lab> --name "$NAME" --plan <plan.md path> [--jdk <path>] --dc dc1 --dc dc2
```

After scaffolding, set `$EDB` from the wrapper path(s) and use `<cluster-dir>/docs/plan.md` for all subsequent references — not the original plan file.

---

### Resume

The cluster dir is self-contained — plan, journal, and issues are all in `docs/`. The wrapper(s) already exist.

**Detect layout and state:**

```bash
eval $(detect-cluster-layout.sh <cluster-dir>)
# Sets: LAYOUT (single|multi), EDB or EDB_DC1/EDB_DC2/..., DCS, STATE (provisioned|unprovisioned)
```

If `STATE=provisioned`, run `$EDB status` to find the actual cluster state — it may still be running or may have been torn down externally.

**Read `<cluster-dir>/docs/journal.md`** to determine what was last completed, then confirm the resume point with the user.

---

### Both modes

Read `<cluster-dir>/docs/plan.md` and display a numbered summary of all steps. If the user specified a starting step, confirm which step that is and skip to it.

**Set terminal context indicators.** After the cluster directory and layout are known, run these three commands to orient the user's terminal for the session:

```bash
# 1. Terminal tab title
printf '\033]0;%s\007' "<cluster-name> [<db-count>db/<app-count>app]"

# 2. iTerm2 badge (base64-encoded, two lines: name on top, counts below)
printf '\e]1337;SetBadgeFormat=%s\a' \
  "$(printf '%s\n%sdb / %sapp' '<cluster-name>' '<db-count>' '<app-count>' | base64)"

# 3. Cluster summary header — printed to terminal output
echo "╔══════════════════════════════════════╗"
echo "  Cluster : <cluster-name>"
echo "  Dir     : <cluster-dir>"
echo "  Layout  : <single|multi-DC>"
echo "  Nodes   : <db-count> db  /  <app-count> app"
echo "╚══════════════════════════════════════╝"
```

Re-run all three after provisioning completes (when actual node counts are confirmed from `$EDB status`) so the badge and title reflect live state. Re-print the summary header each time the progress checklist is displayed.

## Execution Loop

> **Non-negotiable rule: everything goes in `journal.md` — planned steps, debugging, investigation, retries, unplanned commands, and observations. Every command run and every finding, regardless of whether it was in the plan. Write each entry the moment the event occurs. Never batch. Never defer. An issue goes in `issues.md` the moment it is encountered. No exceptions.**

Before executing any steps, build a checklist from the plan's `## Steps` section and display it. Each time the checklist is shown, print the cluster summary header above it:

```
╔══════════════════════════════════════╗
  Cluster : <cluster-name>
  Dir     : <cluster-dir>
  Layout  : <single|multi-DC>
  Nodes   : <db-count> db  /  <app-count> app
╚══════════════════════════════════════╝

Plan: <goal>

Progress:
- [ ] Step 1: <name>
- [ ] Step 2: <name>
- [ ] Step 3: <name>
...
```

Check off each step as it completes. Re-display the full block (header + checklist) after each step so the user can see progress at a glance.

For each step in the plan, in order:

**1. Show the step**

Display the full step text and ask: "Ready to execute this step?"

Wait for the user to confirm before proceeding, unless the user has asked to skip confirmations.

**2. Write to `<cluster-dir>/docs/journal.md` — before running any commands**

Immediately append a new entry: timestamp + step name + "starting". See `../../references/journal.md` for format.

**This is not part of the confirmation flow. It is required whether or not the user skips confirmations. Do not run any commands until this entry is written.**

**3. Execute**

Run the required `$EDB` commands (or AWS CLI, kubectl, etc.) for the step. Show the output.

Every command you run — including any debugging, log inspection, status checks, or investigation not in the plan — must be appended to `<cluster-dir>/docs/journal.md` as it happens. Do not wait until the step is done. If you ran it, log it.

**Issues: write immediately.** The moment you encounter anything confusing, undocumented, or mismatched with the plan — stop and write an entry to `<cluster-dir>/docs/issues.md` before continuing. See `../../references/issues.md` for format. Do not finish the step first.

**4. Verify**

Confirm the step succeeded. Always use `$EDB` (the full path wrapper), not the bare `easy-db-lab` binary:
- For `$EDB up`: check that nodes are reachable via `$EDB status`
- For cassandra start: check cluster health via `$EDB cassandra status` or `$EDB cassandra nodetool status`
- For other steps: use the most appropriate check given the operation
- For multi-DC: run the check against each DC's wrapper (`$EDB_DC1`, `$EDB_DC2`, etc.)

**5. Update `<cluster-dir>/docs/journal.md` with outcome**

Update the journal entry with the final outcome and any relevant output. If the step produced performance results (throughput, latency, compaction), download a Grafana screenshot to `<cluster-dir>/docs/images/` and embed it inline.

**6. Proceed**

Ask: "Step N complete. Continue to step N+1?" before moving on.

## Completion

When all steps are finished:

**1. Write `<cluster-dir>/docs/results.md`**

Populate the summary with a concise distillation of the run — not a copy of the journal, but the highlights a reader needs to understand what was tested and what was learned:

- **Goal** — what the lab set out to test or prove
- **Results** — did it succeed? What was the outcome?
- **Key Findings** — bullet points of the most important discoveries
- **Performance Results** — if benchmarks were run, include throughput, latency percentiles, and any Grafana screenshots from `docs/images/`
- **Configuration Notes** — any non-obvious settings that mattered to the outcome
- **Issues Encountered** — a brief summary of friction; full details are in `issues.md`
- **Recommendations** — what to use, what to avoid, what to test next

**Cassandra performance tests:** If the lab involved Cassandra performance — memtable implementation, compaction strategy, read/write tuning, SAI, etc. — explicitly call out the winning configuration and why. Invoke the `cassandra-expert` agent to add any relevant expert context (e.g. why trie memtables outperform heap, when TWCS is appropriate, SAI vs 2i tradeoffs) directly in the Recommendations section. This makes the summary a standalone reference, not just a pointer to the journal.

**2. Build the lab report**

```bash
make -C <cluster-dir>/docs
```

This generates the browsable lab report from the summary, journal, plan, and issues log.

**3. Decide what to do with the cluster**

If the user already stated their intent earlier in the session (e.g. "shut down when done", "tear it down after", "clean up automatically"), honor that instruction without prompting.

Otherwise, present this menu and wait for the user to choose:

```
Plan complete. What would you like to do next?

  1) Explore  [default] — keep the cluster running and investigate, run stress workloads, or try more tests
  2) Shut down — destroy the cluster and release all AWS resources
     ⚠ Reprovisioning may take hours. Only choose this if you are done with the cluster.

Enter 1 or 2 (default: 1):
```

- **Option 1 (default):** Stay in this skill — do not hand off to `/easy-db-lab:explore`. Write a divider entry to `<cluster-dir>/docs/journal.md` marking the transition, then continue taking requests from the user, logging everything exactly as during plan execution.

  Journal divider format:
  ```
  ## Exploration — <timestamp>

  Plan complete. Continuing interactively.
  ```

  All subsequent commands, findings, and issues follow the same rules as during plan execution: log every command as it runs, write issues immediately to `issues.md`, never batch or defer.

- **Option 2:** Run `$EDB down` and log the teardown in `<cluster-dir>/docs/journal.md`.

If the user responds with something other than 1 or 2, ask them to clarify what they want before taking any action.

## Pausing and Resuming

If the user asks to stop, record progress in `<cluster-dir>/docs/journal.md` (last completed step + state) so the next session can resume cleanly.

When invoked again, read `<cluster-dir>/docs/journal.md` to determine where to resume, then confirm with the user before continuing.

## Error Handling

If a step fails:
1. Show the error clearly.
2. Immediately write to `<cluster-dir>/docs/journal.md` — record the failure, the error output, and the timestamp. Do not wait.
3. If the error was unhelpful, undocumented, or not anticipated by the plan, immediately write an entry to `<cluster-dir>/docs/issues.md`. Do not wait.
4. Do not proceed to the next step.
5. Diagnose the failure — check logs, status, or node health as appropriate. Every diagnostic command you run and every finding must be logged to `<cluster-dir>/docs/journal.md` as it happens, not summarized afterward.
6. Propose a fix and wait for user approval before retrying.
7. Update `<cluster-dir>/docs/journal.md` with the resolution once the fix is applied.

## Database Workflows

Load the relevant reference file when a step involves a specific database:

- **Cassandra** → `../../references/cassandra.md`
- **ClickHouse** → `../../references/clickhouse.md`
- **Spark** → `../../references/spark.md`
- **OpenSearch** → `../../references/opensearch.md`

## Cassandra Expert

If Cassandra-related questions or issues arise during execution — errors, unexpected behavior, performance concerns, schema decisions — invoke the `cassandra-expert` agent. It has deep knowledge of Cassandra internals, CQL, and operational troubleshooting.

- Operational issues (node failures, latency, repair, compaction) → `/cassandra-expert:diagnose`
- Schema or data modeling questions → `/cassandra-expert:data-model`
- Performance tuning → `/cassandra-expert:optimize`
- General questions → invoke the `cassandra-expert` agent directly

Record any Cassandra expert findings relevant to the run in `<cluster-dir>/docs/journal.md`.
