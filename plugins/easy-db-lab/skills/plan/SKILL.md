---
name: plan
description: Helps the user design a lab workflow by asking questions, working through steps together, and writing the result to a plan.md file. Use when planning a new lab run, benchmarking test, or database experiment.
argument-hint: "[what you want to accomplish] [--binary <path>] [--output <path>] [--previous <cluster-dir>] [--interactive]"
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

### `commands` is the index, not the documentation — run `--help` per command

**`$EDB commands` prints only a one-line description per subcommand. It silently drops the full help text, which is where the load-bearing warnings live.** Treat it as a table of contents for finding what exists, then read the actual entry.

**Once you know which commands the plan will use, run `--help` on each one** before writing any step that invokes it:

```bash
$EDB <subcommand path> --help
```

This is not optional and it is not redundant with `commands`. A worked example of the difference: `commands` renders `cassandra profiling start` as the single line *"Enable continuous profiling on Cassandra nodes."* Its `--help` additionally documents which async-profiler arguments the tool reserves and rejects, and carries a multi-paragraph warning that combining a CPU event with wall-clock sampling in one recording silently corrupts the resulting profile by up to three orders of magnitude. A plan written from `commands` alone can therefore contain a command that runs cleanly, produces plausible output, and is wrong — with the warning against it sitting unread in help the whole time.

Read `--help` for **every** command the plan will invoke, including ones you are confident about. Confidence is exactly the state in which a `--name` gets written where a positional belongs.

### What help cannot tell you

`--help` documents the *command surface*: flags, positionals, defaults, and whatever prose the author wrote. It does not document the system's *behavior*, and that is where the costlier planning errors live. Help will not tell you:

- **Where a command's output actually lands.** A wrapper script may `cd` before exec'ing the binary, so a relative output path resolves somewhere other than your shell's directory.
- **What runtime artifacts are named or where they live** — state files, metrics files, rotated or renamed data files.
- **The format of an identifier used for filtering** — a label, a series name, a job name. These are frequently derived (`<name>-<id>`), not the literal value you supplied.
- **Whether a command takes effect immediately.** A command that writes desired state and returns may rely on a reconciler, timer, or operator to act later. Verifying immediately after such a command reports a false failure.
- **How a third-party tool the command wraps behaves** — for instance, whether a converter merges all its inputs into one output.

For all of these, prefer the tool's own read-back commands (`status`, `list`, `info`) over asserting a path or filename you inferred. When a plan genuinely must reference a runtime path or identifier, derive it at run time from a workspace artifact or a command's output and bind it to a shell variable — never hardcode it into a step.

## Interactive Mode (`--interactive`)

If `--interactive` was passed, engage the Socratic dialogue protocol described below throughout this skill. If it was not passed, follow the steps as written — ask the required questions, collect answers, and build the plan without the extra probing and incremental display.

### Socratic Dialogue Protocol

**After each answer the user gives, before moving to the next question:**

0. **Distinguish decided from open.** If the phrasing signals a firm, already-considered decision ("i4i.2xlarge, that's final", "we're using TWCS, not up for debate") rather than an open or exploratory answer, apply steps 1-3 below at most once: surface the concern a single time, then accept the answer and move on regardless of their response. Do not re-raise it later in the session. Repeated pushback on a settled decision reads as arguing, not diligence. Reserve the full probing below for answers that are genuinely open or exploratory.

1. **Probe for completeness.** If the answer is vague ("test performance", "see how it handles load"), push back: "That's a reasonable goal — what specific number or observation would tell you the test succeeded? What would you do differently if the result was X vs Y?"

2. **Surface hidden assumptions.** Identify any assumption baked into their answer and name it: "That approach assumes writes are uniformly distributed across partition keys — is that true for your workload?" Do not move on until the assumption is confirmed or revised.

3. **Identify unknowns they haven't named.** After each answer, briefly flag one thing they may not have considered. For Cassandra workloads, ask the `cassandra-expert` agent: "What are the most common gaps in test plans for this workload type?" and use the response to generate the prompt. Example: "You haven't mentioned compaction strategy — the choice here will significantly affect the write latency picture you're trying to measure." Ask if they want to address it now or come back to it.

4. **Explain the 'why' for non-obvious design choices.** Whenever the plan requires a specific technical decision (instance type, storage, compaction strategy, replication factor, etc.), give a one-sentence rationale before asking. For Cassandra-specific choices, ask the `cassandra-expert` agent to supply the rationale — ask it for a one-sentence explanation the user will understand, not documentation prose. Example for infrastructure: "For write-heavy benchmarks, local NVMe (`i4i.xlarge`) removes the EBS bottleneck from the picture, which is usually what you want when isolating Cassandra performance. Does that match your goal?"

5. **Confirm understanding before progressing.** At the end of each major block of questions (objective, infrastructure, workload, observability), briefly summarize what you've understood so far and ask for confirmation before continuing. Example: "So the goal is to measure sustained write throughput at p99 < 5ms on a 3-node `i4i.xlarge` cluster with TWCS, compared against STCS. Is that right?"

**Building the plan incrementally (interactive mode only):**

Instead of collecting all answers and writing the plan at the end, draft and display each section as it becomes answerable:

- After Step 1 is complete: display the `## Objective` section and ask for approval.
- After infrastructure decisions: display the `## Environment` section and ask for approval.
- After software and workload decisions: display the `## Steps` section outline (numbered steps, no commands yet) and ask if any steps are missing.
- After filling in all commands: display the complete plan and ask for a final review.

Each display should be followed by: "Does this look right, or would you like to change anything before I continue?"

**Gap analysis (interactive mode only):**

Before writing the final plan, explicitly run a gap check. For each of the following, state whether it is covered and flag any that are not:

- The test produces a specific, measurable output (a number, a graph, a comparison).
- There is a baseline or comparison point (otherwise it is hard to interpret "good" vs "bad").
- The workload reflects the actual access pattern being optimized for.
- The cluster configuration (replication factor, compaction, memtable) is appropriate for the stated workload.
- There is a step to collect and record results (not just "run the workload and look at Grafana").
- Teardown is included if AWS cost matters.

Present any gaps as: "One thing I don't see covered yet: [gap]. Do you want to add a step for this, or is it intentionally out of scope?"

---

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
- **If the objective involves measuring resource overhead** (CPU, memory, allocation, or similar), explicitly flag that an undersized instance can mask the very effect being measured — e.g. a memory regression won't show up if the instance is starved for memory regardless. Connect the sizing choice back to the objective rather than defaulting to a generic recommendation disconnected from what's being tested.

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
- **If the objective names a specific feature or change being evaluated** (a new compaction strategy, a config flag, a code path), confirm now — not later in review — that the workload's default schema/config actually activates that feature. Check `$EDB cassandra stress info <workload>` (or the equivalent for the tool in use) and don't assume the default schema exercises it; a workload can run to completion and produce clean numbers while never touching the thing under test. This is a required question, not something to catch opportunistically in Step 5.
- **If the plan sets an explicit rate/throughput target**, check how the tool actually combines its rate and concurrency flags to produce total throughput — don't assume a rate flag is a global target on its own. For cassandra-easy-stress, `--rate` is per-thread: total throughput is `--rate` × `--threads`, and it defaults to `--threads 1`. Threads aren't a concurrency pool the tool uses to help saturate a fixed target — doubling threads doubles total throughput linearly. When the objective specifies a total throughput number, set `--rate` and `--threads` so their product equals it (e.g. `--rate 5000 --threads 10` for 50k total), rather than putting the full target in `--rate` and leaving `--threads` at its default.

**Observability:**
- Will Grafana be used to monitor? (it's part of the default stack)
- Are log queries needed during the test?

## Step 3 — Build the Plan

Once you have enough information, construct a step-by-step plan. Each step should be a concrete action with the exact command to run. Group steps logically:

In **interactive mode**, show the step outline (step names and brief descriptions, no commands yet) to the user before filling in commands. Ask: "Does this sequence cover everything, or are there steps you'd add or remove?" Incorporate feedback before generating any commands.

1. Provision the environment
2. Install software (specific `kit install <name>` commands, using exact names from `kit list`)
3. Configure the database(s)
4. Run the workload or test
5. Observe / collect results
6. Tear down (if applicable)

**The run skill handles all workspace scaffolding** (cluster directory, wrapper, docs) before executing any plan step. The first step in the plan must be provisioning (`easy-db-lab init ... --up`). Never include wrapper creation, directory setup, or `EDB=` assignments — those are handled automatically and must not appear in the plan.

**Validate every command before presenting the plan.** The "Discover Before You Plan" discipline of never guessing flags applies to every command in the draft, not just `kit install` lines — a flag can look plausible (borrowed from another CLI's conventions, like `--name` instead of a positional argument) and still be wrong. For each command:

(a) Confirm it matches a real subcommand and flag in the `$EDB commands` output captured during discovery.
(b) Confirm every required positional argument is present.
(c) Confirm any `--kit`, name, or enum-like argument value corresponds to something real — kit names against `kit list`, node types/hosts against the actual cluster config. Some flags accept a free-form string with no runtime validation (e.g. `--kit` on non-install commands like `cleanup`) — the tool will not catch a wrong value for you, so you must check it against the same authoritative source yourself.
(d) Confirm you have read that command's `--help`, not just its `commands` line, and that no warning or restriction in it contradicts what the step does.
(e) Confirm every file path, filename, and identifier the step references is either derived at run time from a command or workspace artifact, or was read from `--help` — never inferred from a design document, a naming convention, or memory.

Do this pass before showing the plan to the user, not after they've approved it.

**Check the plan's sequencing, not just its individual commands.** A plan can consist entirely of valid commands and still produce a meaningless result because of the order they run in.

- **Steps that change what is being produced must come after steps that consume what was already produced.** If step N reads accumulated artifacts — log files, data chunks, captured output — then any step that changes the *kind* of artifact being accumulated must come after it. Otherwise the consuming step silently mixes two kinds of data and reports a confident, wrong answer.
- **A cumulative counter or metric must be read in a window that isolates what you are testing.** Many counters increment on deliberate operations as well as on the fault you are hunting. Read them before the deliberate operations, or state an explicit quiet period first. A check placed where it cannot help but report a failure is worse than no check: it teaches the operator to ignore it.
- **A command that returns is not necessarily a command that has taken effect.** Where a reconciler, timer, or background process does the real work, put an explicit wait between the command and its verification, and say in the step how long and why.
- **Do not break something in one step and depend on it in a later one** without an explicit restore step in between, and a stated precondition on the step that follows.

**Make the workload outlast the observation.** Add up the waits every step in the plan needs — including the ones expressed as "wait a few minutes" — then set the workload duration comfortably beyond that total. A workload that expires two-thirds of the way through leaves the remaining steps observing an idle system, which quietly invalidates them rather than failing them. Where a step has a minimum elapsed time before it is meaningful, state that floor in the step itself rather than leaving it to the operator's pace.

## Step 4 — Write the Plan

**Run this quality gate before writing, in every mode.** Interactive mode additionally presents each gap to the user as a question and waits for an answer (see the Socratic Dialogue Protocol above); non-interactive mode still applies the gate itself and states any gap it could not close in the plan's Notes. The gate is not the part that is optional — only the conversation around it is.

For each of the following, state whether the plan covers it:

- **Every check is falsifiable.** For each verification step, say what a pass looks like and what a failure looks like, and confirm the plan's own earlier steps make both outcomes genuinely possible. A check on a value the plan never varies from its default cannot fail, and is therefore not a check. This is the single most common defect in a generated plan.
- **"The artifact exists" is not "the feature works."** For anything that produces data — files, metrics, profiles, logs, rows — include at least one check on whether the content is non-trivial and well-formed, not merely present. A feature can produce perfectly valid empty output indefinitely.
- **The plan verifies environmental preconditions it depends on** rather than assuming them: kernel settings, capabilities, installed binaries, service state. Settings applied imperatively by a provisioning script may not survive a reboot.
- **Multi-node claims are checked on more than one node.** If a command targets all nodes, verify more than the first one at least once.
- **Counts and aggregates are computed over the right unit.** When parsing tool output, confirm what one line or one record actually represents before counting them; many formats are one line per *distinct* item with a weight field, so a line count answers a different question than the one being asked.
- The test produces a specific, measurable output.
- There is a step that collects and records results, not just "look at the dashboard".
- Teardown is included if cost matters.

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
- **Cassandra-specific:** if the plan involves Cassandra, ask the `cassandra-expert` agent to do a final pass: "Does this plan's configuration match the stated workload and Cassandra version? Are there any settings that will skew the results or make the test harder to interpret?" Incorporate its findings before presenting the review to the user.

**Loop until clean.** After applying fixes from a review round, re-run the full review (including the `cassandra-expert` pass) before presenting the plan as final. A round that finds nothing new is what ends the loop — a round that produced fixes is not itself proof the plan is ready, since those fixes can introduce or expose new issues. Expect this to take multiple rounds on non-trivial plans; that's normal, not a sign something is wrong. Never present an interim state — one that still has an open round of unaddressed findings — as "done."

Present the review findings to the user as a short bulleted list — what looks good, and anything that should be changed. If changes are needed, update the plan file and confirm with the user. Once a review round passes with no new findings, tell them to run `/easy-db-lab:run` to execute it.
