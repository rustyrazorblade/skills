---
name: run
description: Executes a plan step by step in an explicit cluster workspace, confirming each step with the user, journaling as work proceeds, and writing the tiered lab report. Use when the user says "run a plan", "execute the plan", "run this plan.md", "start/resume the lab run", or otherwise asks to run, execute, or resume a lab plan, benchmark, or database experiment.
argument-hint: "<cluster directory> [step N]  OR  <plan.md path> <cluster directory> [--binary <path>] [--jdk <path>] [step N]  OR  <test directory> --arm <arm> [step N]  OR  <cluster directory> --finalize"
user-invocable: true
---

# Easy DB Lab — Run Plan

You execute a plan step by step in an explicit cluster workspace, reading the plan from `<plan>` (`<cluster-dir>/docs/3-plan.md` in a single layout).

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, and SSH access.

## Lab Report

Load `../../references/report.md` for every report rule: the file roles `<plan>`, `<journal>`, and `<issues>`, the tiers, the summary layout, the evidence blocks, the exit rule, the check, Finalize, and the arms rules.  This skill says when to apply them; `report.md` says how.

## Session Log

Load `../../references/journal.md` for instructions on maintaining the journal. Once the cluster dir is established, read `<journal>` before taking any action — it tells you what has already been done.

## Issues Log

Load `../../references/issues.md` for instructions on maintaining the issues file. Add an entry to `<issues>` whenever you hit friction, an undocumented behavior, or a skill/doc gap.

## Discover the Command Surface First

After setting up `$EDB` in the Before Starting section, start with the task-oriented guides, then read the flag-level reference.

`$EDB help` lists task-oriented topic guides; `$EDB help <topic>` prints one. Each guide gives the intended workflow for a topic as an ordered command sequence, plus its prerequisites and gotchas — how the tool is meant to be used. Read the guide for any topic a plan step touches (for example, `stress-testing` before running load, `cassandra` before a version or config change) so your command sequence matches the intended one.

```bash
# List the available topic guides
$EDB help

# Read the guide for a topic before you act on it
$EDB help <topic>
```

If `$EDB help` errors with `Unmatched argument at index 0: 'help'`, the binary predates the topic guides. Skip this step and rely on `commands` below.

Then read the flag-level reference:

```bash
$EDB commands
```

Use this output as the authoritative source for flag names and available options. Never guess flags.  There is no fallback reference: if `$EDB` does not resolve, stop as described in Before Starting.

**Check for `report upload`.**  In the same `$EDB commands` output, check whether `report upload` is listed.  Record the result once.  If it is absent, follow the "Support Check" section of `../../references/report-upload.md`.  Discovery can run before scaffolding; if `<journal>` does not exist yet, write the note in the first journal entry after scaffolding.

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
see what the command already did, then write an entry to `<issues>`.

## Every Real `down` Is Gated on the Report Upload

Every real top-level `$EDB down` that this skill runs is gated by `../../references/report-upload.md`.  Immediately before it, run Finalize per `../../references/report.md`, then the upload procedure in `report-upload.md`.  Run `$EDB down --auto-approve` only if the upload exits 0; otherwise follow its failure handling.  Two exceptions: a non-redaction check failure never blocks the `down`, and a redaction failure skips the upload and lets the `down` run.  This rule applies wherever the `down` comes from: a Completion choice, a stated shutdown intent, a request during exploration, or a plan step.  `$EDB spark down` and `$EDB down --dry-run` are exempt.  If the binary has no `report upload` (see the support check in Discover the Command Surface First), skip the upload and run `$EDB down --auto-approve` with no gate.

## Before Starting

### 1. Determine the invocation mode

The skill is invoked in one of four ways:

**First run** — `<plan.md path> <cluster directory> [step N]`
The cluster directory does not exist yet (or has no `docs/3-plan.md`). Full scaffolding is required.

**Resume** — `<cluster directory> [step N]`
The cluster directory already exists and contains `docs/3-plan.md`. Skip scaffolding entirely.

**Arm agent** — `run <test-dir> --arm <arm> [step N]`
The test directory is a cross-cluster arms layout (`LAYOUT=arms`) that the coordinator already scaffolded.  Treat it as a resume of one arm: read the plan from `docs/3-plan-<arm>.md`, and bind `$EDB` to `EDB_<ARM>` only.  The roles `<plan>`, `<journal>`, and `<issues>` are the `-<arm>` files.  Follow the arms rules in `../../references/report.md`: write only this arm's files, fetch this arm's data after each measuring step, and use the arm gate before this arm's `down`.

**Finalize** — `run <cluster-dir> --finalize`
Run Finalize per `../../references/report.md` and upload the report.  Never run `down`.  Use it after a redaction failure is fixed, and as the coordinator's Final Finalize after the last arm of an arms test.  It works after `down` and in every layout.

Detect which case applies by checking for `docs/3-plan.md` inside the provided directory. If the directory doesn't exist or has no `docs/3-plan.md`, treat it as a first run and require a plan path. If `docs/3-plan.md` exists, treat it as a resume.

In an arms layout, refuse teardown unless the skill runs with `--arm`: each arm's `down` goes through that arm's gate.

If a required argument is missing, ask the user for it before continuing.

---

### First run

**Read the plan.** Extract the cluster name and datacenter configuration directly from the plan file:

- **Cluster name** — value under `## Cluster Name`
- **Datacenters** — if `## Datacenters` is `single`, it is a single-DC cluster; otherwise each `- <dc>: <cidr>` line defines a DC name and CIDR

**Ask the user only for anything missing:**
- **`easy-db-lab` binary path** (`--binary`) — check for `bin/easy-db-lab` in the current directory first, then try `which easy-db-lab`; only ask if neither is found.  If the user has no path, or the path is not executable, stop and report the paths searched.  An unattended run never asks: if neither is found, it stops and reports the paths searched.  Without a binary, write no workspace file and run no plan step.
- **Java 21 JDK home** (`--jdk`) — leave blank to inherit the system default.

**Scaffold the cluster workspace — run the script, never do this manually:**

> **NEVER create workspace files or directories by hand, and NEVER read `setup-cluster.sh` and perform its steps yourself. You MUST execute it as a script via bash. The tool requires a strict directory structure that only the script produces correctly. Any manual recreation will produce a broken workspace.**
>
> **Use this plugin's `setup-cluster.sh` (from this plugin's `bin/`) — nothing else.** The `easy-db-lab` product repo also ships a similarly named `bin/create-easy-db-lab-wrapper` script for developer convenience. It only creates the `easy-db-lab` wrapper and does **not** create the `docs/` report scaffold (`book.toml`, `SUMMARY.md`, `Makefile`, the tier files) or copy the plan to `docs/3-plan.md`. Running it instead of `setup-cluster.sh` succeeds silently but leaves the workspace unable to build a report later — do not use it here.

```bash
# Single DC (DCS=single)
setup-cluster.sh <cluster-dir> <binary|easy-db-lab> --name "$NAME" --plan <plan.md path> [--jdk <path>]

# Multi DC (DCS="dc1 dc2 ...")
setup-cluster.sh <cluster-dir> <binary|easy-db-lab> --name "$NAME" --plan <plan.md path> [--jdk <path>] --dc dc1 --dc dc2
```

**Verify the scaffold before continuing.** Confirm `<cluster-dir>/docs/Makefile`, `<cluster-dir>/docs/book.toml`, `<cluster-dir>/docs/SUMMARY.md`, `<cluster-dir>/docs/1-summary.md`, and `<cluster-dir>/docs/3-plan.md` all exist. Also confirm the wrapper exists. The wrapper lives at the cluster root, `<cluster-dir>/easy-db-lab` (single DC), or per DC, `<cluster-dir>/<dc>/easy-db-lab` (multi-DC) — never in a `bin/` subdirectory of the cluster. Do NOT check `<cluster-dir>/bin/`; no `bin/` directory is created there. The `bin/easy-db-lab` path in the binary lookup above (`--binary`, under First run) refers to the easy-db-lab source repo, not the cluster workspace. To locate the wrapper reliably, use `detect-cluster-layout.sh <cluster-dir>` rather than a hand-written `ls`. If any file is missing, the wrong script ran (or scaffolding failed) — stop and fix this before executing any plan step; do not proceed on a partial workspace.

After scaffolding, set `$EDB` from the wrapper path(s) and use `<cluster-dir>/docs/3-plan.md` for all subsequent references — not the original plan file.

---

### Resume

The cluster dir is self-contained — plan, journal, and issues are all in `docs/`. The wrapper(s) already exist.

**Detect layout and state:**

```bash
eval $(detect-cluster-layout.sh <cluster-dir>)
# Sets: LAYOUT (single|multi|arms), EDB or EDB_DC1/EDB_DC2/... or EDB_<ARM>/STATE_<ARM>, DCS or ARMS, STATE (provisioned|unprovisioned)
```

If `STATE=provisioned`, run `$EDB status` to find the actual cluster state — it may still be running or may have been torn down externally.

**Read `<journal>`** to determine what was last completed, then confirm the resume point with the user.

---

### Both modes

Read `<plan>` and display a numbered summary of all steps. If the user specified a starting step, confirm which step that is and skip to it.

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

> **Non-negotiable rule: everything goes in `<journal>` — planned steps, debugging, investigation, retries, unplanned commands, and observations. Every command run and every finding, regardless of whether it was in the plan. Write each entry the moment the event occurs. Never batch. Never defer. An issue goes in `<issues>` the moment it is encountered. No exceptions.**

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

**2. Write to `<journal>` — before running any commands**

Immediately append a new entry: timestamp + step name + "starting". See `../../references/journal.md` for format.

**This is not part of the confirmation flow. It is required whether or not the user skips confirmations. Do not run any commands until this entry is written.**

**3. Execute**

> **Before running any command that came from the plan file, verify its form against the
> binary.** A plan is prose written earlier, possibly by a different session — its commands are
> not validated by anything. Before the first step that uses a command, check the subcommand name
> and the flag spelling against `$EDB commands`, the relevant `$EDB help <topic>`, and the
> command's `--help`.  Also load the relevant database reference (see **Database Workflows**
> below) *before* the first step that touches that database, not after a command fails.  If the
> plan and the binary disagree, the binary wins and the plan gets corrected.
>
> This is a blocking precondition, not advice. Two failure modes it prevents, both observed:
> invoking a subcommand by a name it does not have (the plan says `cassandra nodetool`; the
> binary has `cassandra nt`), and omitting the `--` separator before passthrough args
> (`stress start -- <workload> -d 4h ...`). Both produce parser errors that read like bad flags
> rather than a wrong command.

Run the required `$EDB` commands (or AWS CLI, kubectl, etc.) for the step. Show the output.

Wait for each command to finish before you continue — see "Run Commands to Completion" above.
A provisioning step is slow; that is expected. Never read `state.json` to check progress.

Every command you run — including any debugging, log inspection, status checks, or investigation not in the plan — must be appended to `<journal>` as it happens. Do not wait until the step is done. If you ran it, log it.

**Issues: write immediately.** The moment you encounter anything confusing, undocumented, or mismatched with the plan — stop and write an entry to `<issues>` before continuing. See `../../references/issues.md` for format. Do not finish the step first.

**4. Verify**

Confirm the step succeeded. Always use `$EDB` (the full path wrapper), not the bare `easy-db-lab` binary:
- For `$EDB up`: check that nodes are reachable via `$EDB status`
- For cassandra start: check cluster health via `$EDB cassandra nt status`
- For other steps: use the most appropriate check given the operation
- For multi-DC: run the check against each DC's wrapper (`$EDB_DC1`, `$EDB_DC2`, etc.)

**5. Update `<journal>` with outcome**

Update the journal entry with the final outcome and any relevant output. If the step measured something (throughput, latency, compaction), run `report-graph.py fetch` and then `render` while the cluster is up, then `block`, and append the evidence block per `../../references/report.md`, before the next step.

**6. Proceed**

Ask: "Step N complete. Continue to step N+1?" before moving on.

## Completion

When all steps are finished:

**1. Finalize the report per `../../references/report.md`**

Write `1-summary.md` and run the check, as the Finalize section of `report.md` says.  Apply its check-failure rule for Completion with no teardown.  When a teardown follows at once (a stated shutdown intent), the teardown gate runs Finalize with its own rule instead.

**2. Build and upload the lab report**

```bash
make -C <cluster-dir>/docs
```

`make` checks the report, builds the book, and writes `export/jira.txt` and `export/report.zip`.

**Verify it actually built.** Check the command's exit code and confirm `<cluster-dir>/docs/report/index.html` exists. If `make` fails or the output is missing, do not silently move on — diagnose the cause (a check FAIL, missing scaffold files, broken `SUMMARY.md` links, mdbook errors), write an entry to `<issues>`, fix it, and re-run `make` before proceeding to step 3.

**Upload the report.**  The build is good only when `make` exits 0 and `<cluster-dir>/docs/report/index.html` exists.  Do not upload until the check passes and the build is good.  After a good build, and before step 3, run the upload procedure in `../../references/report-upload.md` with the five tier files: `1-summary.md`, `2-evidence.md`, `3-plan.md`, `4-journal.md`, and `5-issues.md`.  In a multi-DC workspace, upload through every DC's wrapper.  A failed upload here does not affect the cluster: follow the "at run Completion step 2" failure handling in the reference.  If the binary has no `report upload`, skip this upload.

**3. Decide what to do with the cluster**

If the user already stated their intent earlier in the session (e.g. "shut down when done", "tear it down after", "clean up automatically"), honor that instruction without prompting.  In an unattended run, a shutdown intent that the launcher stated counts the same way.  A stated shutdown intent tears the cluster down through the gate in `../../references/report-upload.md` (see Every Real `down` Is Gated on the Report Upload), with no prompt.

**Unattended, with no shutdown intent:** do not show the menu, and do not run `down`.  Report "cluster still up" to the launcher, with the workspace path, and stop.  A coordinator or the owner can tear the cluster down later through the "Completion / teardown" entry point in Pausing and Resuming.

Otherwise, present this menu and wait for the user to choose:

```
Plan complete. What would you like to do next?

  1) Explore  [default] — keep the cluster running and investigate, run stress workloads, or try more tests
  2) Shut down — destroy the cluster and release all AWS resources
     ⚠ Reprovisioning may take hours. Only choose this if you are done with the cluster.

Enter 1 or 2 (default: 1):
```

- **Option 1 (default):** Stay in this skill — do not hand off to `/easy-db-lab:explore`. Write a divider entry to `<journal>` marking the transition, then continue taking requests from the user, logging everything exactly as during plan execution.

  Journal divider format:
  ```
  ## Exploration — <timestamp>

  Plan complete. Continuing interactively.
  ```

  All subsequent commands, findings, and issues follow the same rules as during plan execution: log every command as it runs, write issues immediately to `<issues>`, never batch or defer.

  If the user later asks to shut down, tear the cluster down through the gate in `../../references/report-upload.md`.  The upload then holds the current journal.

- **Option 2:** Tear the cluster down through the gate in `../../references/report-upload.md`.  Log the teardown in `<journal>`.

If the user responds with something other than 1 or 2, ask them to clarify what they want before taking any action.

## Pausing and Resuming

If the user asks to stop, record progress in `<journal>` (last completed step + state) so the next session can resume cleanly.  Then write a Partial summary, `Partial: stopped after step N`, and run the check, per the exit rule in `../../references/report.md`.  A pause leaves the cluster up, so a check failure needs no other action.

When invoked again, read `<journal>` to determine where to resume, then confirm with the user before continuing.

### Resume entry point: Completion / teardown

Use this entry point to tear down a cluster whose plan is complete, for example after an unattended run reported "cluster still up".  A coordinator or the owner relaunches this skill on the workspace and asks for "Completion / teardown".  The skill then:

1. Resumes the workspace as described in Before Starting (Resume).  In an arms layout, the coordinator relaunches it once per arm as `run <test-dir> --arm <arm>`.
2. Tears the cluster down through the gate in `../../references/report-upload.md`, including its failure handling.  For an arm, that is the arm gate.

A coordinator never runs `$EDB down` itself.  To tear down a cluster, it relaunches this skill at "Completion / teardown".

## Error Handling

If a step fails:
1. Show the error clearly.
2. Immediately write to `<journal>` — record the failure, the error output, and the timestamp. Do not wait.
3. If the error was unhelpful, undocumented, or not anticipated by the plan, immediately write an entry to `<issues>`. Do not wait.
4. Do not proceed to the next step.
5. Diagnose the failure — check logs, status, or node health as appropriate. Every diagnostic command you run and every finding must be logged to `<journal>` as it happens, not summarized afterward. For Cassandra clusters, invoke the `cassandra-expert` agent to diagnose before proposing a fix — e.g. latency spikes, throughput mismatches, compaction storms, or unexpected behavior after a config or schema change.
6. Propose a fix and wait for user approval before retrying.
7. Update `<journal>` with the resolution once the fix is applied.

## Database Workflows

Load the relevant reference file when a step involves a specific database:

- **Cassandra** → `../../references/cassandra.md`
- **ClickHouse** → `../../references/clickhouse.md`
- **Spark** → `../../references/spark.md`
- **OpenSearch** → `../../references/opensearch.md`

## Unattended and parallel runs

The execution loop above assumes a human is present to confirm each step. Two situations break that assumption, and both are common for A/B benchmarking.

**Unattended.** When this skill runs inside a subagent, or any session that cannot prompt the user, proceed without confirmation — launching it that way *is* the user granting that. Everything else in the loop still applies without exception, above all the journal rule: with nobody watching, `<journal>` is the only record of what happened. Report to whoever launched you at the points that would otherwise have been confirmation stops — a failed precondition, a gate, the start of a long-running step, and completion.

**Parallel arms.** A cross-cluster A/B is one test directory (`LAYOUT=arms`): one cluster per arm, one agent per arm, one shared `docs/`, and one report.  The coordinator scaffolds it once with `setup-cluster.sh --arm`, as the Arms section of `../../references/report.md` shows.  Rules that keep the comparison meaningful:

- An arm agent runs as `run <test-dir> --arm <arm>` and runs commands only through its own wrapper.  In `docs/` it writes only its own files: `4-journal-<arm>.md`, `5-issues-<arm>.md`, `data/*-<arm>.*`, and `images/*-<arm>.png`.  It never writes another arm's files, `1-summary.md`, or `2-evidence.md`.  It renders its own panel only for a metric with no overlay panel.
- Generate every arm's plan from a single template so the arms cannot drift, then prove it: normalise the intended variables and diff the plans. They should come out byte-identical.
- Cross-arm gates are coordination, not reporting. Each arm reports its numbers to the coordinator, which does the comparing.  The per-arm files above are the only shared state.  Do not invent other shared state files.
- The arms sit on different hardware, so run an identical short calibration workload before the measured run. It tells you whether the clusters are comparable at all, and its spread is the error bar on every delta you later report.
- No agent decides teardown on its own.  The coordinator relaunches `run <test-dir> --arm <arm>` at the "Completion / teardown" entry point in Pausing and Resuming for each arm, and runs `run <test-dir> --finalize` once after the last arm reports.  It never runs `$EDB down` itself.
- Before Final Finalize, the coordinator renders each overlay image from the render arm, the last arm still up, per "Overlay render" in the Arms section of `../../references/report.md`.  It holds that arm by not relaunching it.  After the last overlay render, it relaunches the render arm for teardown: that relaunch is the release.  A failed overlay render is logged, gets one retry when interactive, and then the coordinator releases the arm.

## Team Agents

`cassandra-expert` ships as a **separate plugin** (`plugins/cassandra-expert`), not as part of this one. If it is not installed, the invocations below cannot run. Say so plainly and carry on — do not silently skip them, and do not improvise the analysis in its place. The user may want to install it before a Cassandra performance run.

Invoke `cassandra-expert` proactively for any Cassandra work — don't wait until something is wrong:
- On step failure or unexpected behavior, diagnose with it before proposing a fix (see Error Handling above).
- When schema or data modeling decisions come up during a run that weren't in the plan, ask it before improvising.
- At every exit, run the reasoning review in the Check section of `../../references/report.md`.

Record any agent findings relevant to the run in `<journal>`. If the work does not involve Cassandra, skip these invocations.
