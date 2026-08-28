---
name: run
description: Executes a plan step by step in an explicit cluster workspace, confirming each step with the user and updating journal.md as work proceeds. Use when the user says "run a plan", "execute the plan", "run this plan.md", "start/resume the lab run", or otherwise asks to run, execute, or resume a lab plan, benchmark, or database experiment.
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

## `state.json` Is Internal — Never Read It

`state.json` is an internal file of the `easy-db-lab` tool. It is not a documented interface. Its
shape can change at any time. Never read it, never parse it, and never quote its contents to the
user.

To learn the cluster state, run a command instead:

```bash
$EDB status
```

The one exception is a file-existence check. `detect-cluster-layout.sh` tests only whether the file
is present, to set `STATE=provisioned`. That is allowed. Reading the contents is not.

## Run Commands to Completion

Every cluster action goes through an `easy-db-lab` command. Run the command and wait for it to
finish before you do anything else.

- Do not run an `easy-db-lab` command in the background.
- Do not stop a command early with a short timeout.
- Do not poll `$EDB status` while another command is still running.
- Do not report a step as complete until the command exits.

Some commands are slow. `$EDB init ... --up` provisions AWS instances; it takes a few minutes to
finish. This is normal. Set the Bash tool timeout to its maximum (600000 ms) for these commands,
and let them run.

If a command does exceed the maximum timeout, do not retry it blindly. Run `$EDB status` first to
see what the command already did, then write an entry to `<cluster-dir>/docs/issues.md`.

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
>
> **Use this plugin's `setup-cluster.sh` (from this plugin's `bin/`) — nothing else.** The `easy-db-lab` product repo also ships a similarly named `bin/create-easy-db-lab-wrapper` script for developer convenience. It only creates the `easy-db-lab` wrapper and does **not** create the `docs/` report scaffold (`book.toml`, `SUMMARY.md`, `Makefile`) or copy `plan.md`. Running it instead of `setup-cluster.sh` succeeds silently but leaves the workspace unable to build a report later — do not use it here.

```bash
# Single DC (DCS=single)
setup-cluster.sh <cluster-dir> <binary|easy-db-lab> --name "$NAME" --plan <plan.md path> [--jdk <path>]

# Multi DC (DCS="dc1 dc2 ...")
setup-cluster.sh <cluster-dir> <binary|easy-db-lab> --name "$NAME" --plan <plan.md path> [--jdk <path>] --dc dc1 --dc dc2
```

**Verify the scaffold before continuing.** Confirm `<cluster-dir>/docs/Makefile`, `<cluster-dir>/docs/book.toml`, `<cluster-dir>/docs/SUMMARY.md`, and `<cluster-dir>/docs/plan.md` all exist. If any are missing, the wrong script ran (or scaffolding failed) — stop and fix this before executing any plan step; do not proceed on a partial workspace.

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

> **Before running any command that came from the plan file, verify its form against the
> references.** A plan is prose written earlier, possibly by a different session — its commands are
> not validated by anything. Load `../../references/commands.md` and the relevant database
> reference (see **Database Workflows** below) *before* the first step that touches that database,
> not after a command fails. Check the subcommand name and the flag spelling against the reference;
> if the plan and the reference disagree, the reference wins and the plan gets corrected.
>
> This is a blocking precondition, not advice. Two failure modes it prevents, both observed:
> invoking a subcommand by a name it does not have (`cassandra nodetool` — the command is `nt`),
> and omitting the `--` separator before passthrough args (`stress start -- <workload> -d 4h ...`).
> Both produce parser errors that read like bad flags rather than a wrong command.

Run the required `$EDB` commands (or AWS CLI, kubectl, etc.) for the step. Show the output.

Wait for each command to finish before you continue — see "Run Commands to Completion" above.
A provisioning step is slow; that is expected. Never read `state.json` to check progress.

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

**Verify it actually built.** Check the command's exit code and confirm `<cluster-dir>/docs/report/index.html` exists. If `make` fails or the output is missing, do not silently move on — diagnose the cause (missing scaffold files, broken `SUMMARY.md` links, mdbook errors), write an entry to `<cluster-dir>/docs/issues.md`, fix it, and re-run `make` before proceeding to step 3.

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
5. Diagnose the failure — check logs, status, or node health as appropriate. Every diagnostic command you run and every finding must be logged to `<cluster-dir>/docs/journal.md` as it happens, not summarized afterward. For Cassandra clusters, invoke the `cassandra-expert` agent to diagnose before proposing a fix — e.g. latency spikes, throughput mismatches, compaction storms, or unexpected behavior after a config or schema change.
6. Propose a fix and wait for user approval before retrying.
7. Update `<cluster-dir>/docs/journal.md` with the resolution once the fix is applied.

## Database Workflows

Load the relevant reference file when a step involves a specific database:

- **Cassandra** → `../../references/cassandra.md`
- **ClickHouse** → `../../references/clickhouse.md`
- **Spark** → `../../references/spark.md`
- **OpenSearch** → `../../references/opensearch.md`

## Unattended and parallel runs

The execution loop above assumes a human is present to confirm each step. Two situations break that assumption, and both are common for A/B benchmarking.

**Unattended.** When this skill runs inside a subagent, or any session that cannot prompt the user, proceed without confirmation — launching it that way *is* the user granting that. Everything else in the loop still applies without exception, above all the journal rule: with nobody watching, `docs/journal.md` is the only record of what happened. Report to whoever launched you at the points that would otherwise have been confirmation stops — a failed precondition, a gate, the start of a long-running step, and completion.

**Parallel arms.** An A/B comparison runs one cluster per arm, one agent per cluster, each with its own workspace and its own `docs/`. Rules that keep the comparison meaningful:

- Each agent touches only its own cluster. Never read or write a sibling's workspace.
- Generate every arm's plan from a single template so the arms cannot drift, then prove it: normalise the intended variables and diff the plans. They should come out byte-identical.
- Cross-arm gates are coordination, not reporting. Each agent records its numbers in its own journal and reports them to the coordinator, which does the comparing. Do not invent shared state files.
- The arms sit on different hardware, so run an identical short calibration workload before the measured run. It tells you whether the clusters are comparable at all, and its spread is the error bar on every delta you later report.
- No agent decides teardown on its own. See Completion.

## Team Agents

`cassandra-expert` ships as a **separate plugin** (`plugins/cassandra-expert`), not as part of this one. If it is not installed, the invocations below cannot run. Say so plainly and carry on — do not silently skip them, and do not improvise the analysis in its place. The user may want to install it before a Cassandra performance run.

Invoke `cassandra-expert` proactively for any Cassandra work — don't wait until something is wrong:
- On step failure or unexpected behavior, diagnose with it before proposing a fix (see Error Handling above).
- When schema or data modeling decisions come up during a run that weren't in the plan, ask it before improvising.
- When writing `results.md`, invoke it to add expert context to the Recommendations section — why the winning configuration worked, what the tradeoffs were, what to test next (see Completion above).

Record any agent findings relevant to the run in `<cluster-dir>/docs/journal.md`. If the work does not involve Cassandra, skip these invocations.
