# Rustyrazorblade Skills

A plugin marketplace by Jon Haddad.

## Installation

### Claude Code
```
/plugin marketplace add rustyrazorblade/skills
```

Then install whichever plugins you want:

```
/plugin install cassandra-expert@rustyrazorblade-plugins
/plugin install easy-db-lab@rustyrazorblade-plugins
/plugin install spec-flow@rustyrazorblade-plugins
```

### Codex
```
codex plugin marketplace add rustyrazorblade/skills
```

Codex exposes skills through `$` mentions instead of slash commands. `cassandra-expert` and
`easy-db-lab` ship Codex manifests; `spec-flow` is Claude Code only (it depends on Claude Code
agents and the `Workflow` runtime).

## Available Plugins

### cassandra-expert

Expert guidance for Apache Cassandra development and operations.

Claude Code:

```
/plugin install cassandra-expert@rustyrazorblade-plugins
```

Codex CLI:

Install `cassandra-expert` from the plugins section:

```
/plugins
```

#### Skills

| Skill | Purpose |
|-------|---------|
| `/cassandra-expert:diagnose` | Systematic troubleshooting using USE method, outlier analysis, double loop learning |
| `/cassandra-expert:optimize` | Performance tuning, configuration analysis, JVM settings, compaction strategies |
| `/cassandra-expert:data-model` | Schema design, partition keys, time-series modeling, query patterns |
| `/cassandra-expert:token-skew` | Token ownership skew analysis using correct per-rack metric |
| `/cassandra-expert:training` | Interactive, session-based Cassandra training from fundamentals to advanced topics |

#### Agent

The plugin also ships a `cassandra expert` agent for open-ended questions that don't fit a specific
skill — CQL review, replication, repair, cluster operations, troubleshooting. It reads the bundled
references rather than its training data, and it will **establish your exact Cassandra version
before giving any guidance**, because the right answer differs across 4.0, 5.0, and 6.0 (incremental
repair on 3.x and UCS on 4.x are the kind of version-blind advice it exists to prevent).

#### Usage Examples

**Diagnose - Troubleshooting Issues**
```
/cassandra-expert:diagnose Read latencies spiking on some nodes but not others
/cassandra-expert:diagnose Compaction can't keep up with writes
```

**Optimize - Performance Tuning**
```
/cassandra-expert:optimize Review my cassandra.yaml settings
/cassandra-expert:optimize What compaction strategy should I use?
```

**Data Model - Schema Design**
```
/cassandra-expert:data-model Design schema for user activity tracking
/cassandra-expert:data-model How should I model time-series data with 90-day retention?
```

**Token Skew - Ownership Analysis**
```
/cassandra-expert:token-skew Analyze this nodetool ring output for data imbalance
/cassandra-expert:token-skew nodetool status shows uneven Owns percentages — is this real?
```

**Training - Interactive Learning**
```
/cassandra-expert:training
/cassandra-expert:training Session 2: Query & Application Anti-Patterns
/cassandra-expert:training LWT         # general topic — matches across sessions
/cassandra-expert:training compaction  # multiple matches: the trainer offers options
```

For a general topic like `LWT` or `compaction`, the trainer lists every session/topic that matches and lets you pick one or say `all` to go through every match.

#### Problem-Solving Methodology

- **Double Loop Learning** - Goes beyond immediate fixes to identify root causes and prevent recurrence
- **USE Method** - Systematically analyzes Utilization, Saturation, and Errors for CPU, memory, disk, network, storage, and thread pools
- **Outlier Analysis** - Compares nodes to identify anomalies in latency, resource usage, and behavior
- **Configuration Analysis** - Reviews system settings, cassandra.yaml, JVM settings, and per-table configurations

#### Training Sessions

Interactive, instructor-led Cassandra training with pulse checks after each topic:

| Session | Topics |
|---------|--------|
| **Session 1: Fundamentals** | Data distribution, keyspaces, types, primary keys, partition storage, collections, UDTs, DML, read/write paths, tombstones, TTL, table options, table patterns (single-key, ordered-map, time-series), batches, LWT, compaction overview, denormalization, prepared statements, consistency levels |
| **Session 2: Query & Application Anti-Patterns** | IN() queries, ALLOW FILTERING, token range queries, BATCH misuse, lightweight transactions, counters, in-memory joins, synchronous queries, excessive async, in-memory sorting, aggregations, triggers |
| **Session 3: Schema Anti-Patterns** | Huge partitions, hot partitions, too many tables, too many columns, materialized views, unbounded collections, lists, secondary indexes, compaction strategy, large blobs |
| **Session 4: SAI** | What SAI is and the partition key rule, creating and managing indexes, querying patterns, SAI vs. denormalization, SASI migration |

Claims the training makes about what Cassandra actually accepts or rejects are backed by executable
verification scripts in `plugins/cassandra-expert/skills/training/scripts/`, which run against a live
cluster and exit non-zero if any claim no longer holds.

#### Key Recommendations

Opinionated guidance based on real-world experience:

- **num_tokens**: Use 1 or max 4. Higher is always worse.
- **Compaction**: UCS on Cassandra 5.0+ — there is no case where STCS is the right choice once UCS exists.
- **Read-ahead**: Disable it. One of the worst settings you can have enabled.
- **Partitions**: Keep under 10MB. No downside to smaller partitions.
- **Row cache**: Keep disabled. Rarely beneficial.

### easy-db-lab

Provision and operate AWS lab environments with Cassandra, ClickHouse, Spark, OpenSearch, and installable kits.

Claude Code:

```
/plugin install easy-db-lab@rustyrazorblade-plugins
```

Codex CLI:

Install `easy-db-lab` from the plugins section:

```
/plugins
```

#### Skills

| Skill | Purpose |
|-------|---------|
| `/easy-db-lab:explore` | **Start here** — interactive guided session that provisions an environment if needed, then helps you run tests and explore the cluster |
| `/easy-db-lab:plan` | Interactively design a lab workflow and write it to a `plan.md` |
| `/easy-db-lab:run` | Execute a plan step by step in a cluster workspace, confirming each step and journaling as it goes |
| `/easy-db-lab:create-kit` | Author a new kit (kit.yaml, K8s manifests, metrics, dashboards, docs) for any database or workload |

#### Agent

An `easy-db-lab operator` agent handles live-cluster work that isn't a scripted plan — provisioning,
configuring, benchmarking, and tearing down clusters via the `easy-db-lab` binary. Note that Grafana
and the rest of the observability stack are only reachable over Tailscale, so the operator always
hands you private IPs; public IPs will not work.

#### Usage Examples

```
/easy-db-lab:plan benchmark Cassandra 5.0 vs 4.1
/easy-db-lab:plan tune UCS --previous tests/clusters/20240530-143022
/easy-db-lab:run tests/clusters/20240530-143022
/easy-db-lab:run plan.md tests/clusters/20240530-143022 --binary ./bin/easy-db-lab
/easy-db-lab:create-kit valkey
```

`explore` takes a free-form topic, or nothing at all:

```
/easy-db-lab:explore
/easy-db-lab:explore cassandra 5.0
/easy-db-lab:explore clickhouse analytics
```

#### Notes

- Skills run from a lab workspace directory; `explore` will walk you through `easy-db-lab init --up` if none exists
- Each DC in a multi-DC setup gets its own subdirectory and binary wrapper (`<cluster-dir>/dc1/easy-db-lab`) with independent state
- `plan` writes to `plan.md` in the current directory unless `--output` says otherwise; `run` reads the plan from `<cluster-dir>/docs/plan.md`
- Every command and observation is journaled to `<cluster-dir>/docs/journal.md` as it happens, and friction is logged to `docs/issues.md` — this is what lets `run` resume a plan and `plan --previous` learn from a past run

### spec-flow

A session-driven, multi-agent delivery pipeline over **OpenSpec** + **GitHub**. You own the two
seams a human should own — defining/prioritizing the work, and final review + merge — and the
middle (spec → implement → review → fix → build → docs → PR) runs as agents you invoke turn-by-turn.

Claude Code only:

```
/plugin install spec-flow@rustyrazorblade-plugins
```

#### The pipeline

```
groom ─▶ activate ─▶ [SEAM 1: you approve the spec] ─▶ implement ─▶ [SEAM 2: you review + squash-merge] ─▶ finalize
  │          │                                              │
refine     design                                  5-lens review panel
(product)  (architect)
```

**Seam 1** — `activate` stops after committing the OpenSpec change. Nothing is implemented until
you approve, and this is where every significant design decision gets made: the `architect` agent
lays out options and trade-offs, and you decide.

**Seam 2** — the pipeline only ever pushes the issue branch and opens a PR. It never merges and
never pushes to `main`. You review in GitHub, optionally loop through `address`, and squash-merge
yourself.

#### Skills

| Skill | Purpose |
|-------|---------|
| `/spec-flow:groom` | Rough idea → scoped, labeled GitHub issue (scope, testable acceptance criteria, one `P0–P3`) |
| `/spec-flow:activate <N>` | Worktree + branch → OpenSpec explore+propose → commit spec → **stop for your approval** (Seam 1) |
| `/spec-flow:implement <N>` | After approval: open a draft PR early (keeps CI warm), run the background team (tdd-developer → 5-lens review panel → fix loop → build-engineer → docs) pushing at checkpoints, then mark the PR ready |
| `/spec-flow:address <N>` | Pull your PR review comments → fix in the worktree → push → reply per thread |
| `/spec-flow:sync-ci <N>` | When CI goes red: pull the failing tests into the branch's local flagged set so the fast local loop guards them until merge |
| `/spec-flow:board` | One view of every in-flight issue: stage, priority, PR/CI state, what's next, what's blocked on you |
| `/spec-flow:finalize <N>` | After you squash-merge: sync + archive the OpenSpec change, remove the worktree, close the issue |
| `/spec-flow:adopt-tiering` | One-time per repo: split an existing suite into the unit/integration tiers the tiering model needs, then open a PR |

#### Agents

The `project-manager` is the agent you talk to directly — it runs the board, tracks work in flight,
decides what's next, and delegates each stage to the skills and specialists. It coordinates; it
never implements and never crosses your two seams.

| Agent | Role |
|-------|------|
| `project-manager` | Orchestrator. Runs the board, decides what's next, delegates every unit of work |
| `product-manager` | Refines a rough idea into scope + testable acceptance criteria (consulted during `groom`) |
| `architect` | Turns the refined idea into a design, with trade-offs framed as owner decisions (consulted during `activate`) |
| `tdd-developer` | The implementer. Test-first (red→green→refactor), SOLID |
| `build-engineer` | Gets the build clean (format/lint/build), adapting to the project's tooling |

Three more agents — `reviewer`, `test-rigor-reviewer`, and `observability-reviewer` — make up three
of the five review lenses below.

`tdd-developer` picks up the bundled style guide matching the project's language (Rust and Kotlin
ship today, in `plugins/spec-flow/references/`) and holds itself to it. `tdd-developer` and
`build-engineer` are deliberately general-purpose bases: grow them in place with per-language and
per-framework practice, and every repo using the plugin inherits the improvement.

#### The 5-lens review panel

During `implement`, review is not one reviewer. Five lenses run **in parallel** each round, their
findings merge into one set, a fix round addresses every blocker/major from any lens, and approval
requires **every** lens to approve with no must-fix findings.

| Lens | Asks |
|------|------|
| `reviewer` | Does the implementation match the spec and the repo's own documented rules? Every `#### Scenario:` must have a backing test |
| `/code-review` | Correctness bugs: logic, boundaries, error paths, concurrency, resource leaks |
| `/security-review` | Input validation, auth, injection, secret exposure (self-gates when the diff touches no security surface) |
| `test-rigor-reviewer` | Are there antagonistic, regression-exposing tests over the public surface and its observable side effects? |
| `observability-reviewer` | Are the new code paths and failure modes diagnosable in prod? No silent failures, no secrets in telemetry |

To add or remove a lens, edit the `reviewLenses` array in `skills/implement/implement.workflow.js` —
the merge/approval loop generalizes over N lenses.

#### Setup

The consuming repo must provide the two backbones:

- **OpenSpec** — the `openspec` CLI installed and initialized in the repo
- **GitHub** — `gh` authenticated, repo hosted on GitHub
- **Labels** — bootstrap the `P0–P3` and `status:*` vocabulary once per repo (idempotent, safe to
  re-run). Run it with your cwd inside the target repo, pointing at the script in the plugin:
  ```bash
  bash /path/to/spec-flow/bin/bootstrap-labels.sh
  ```

The `/code-review` and `/security-review` lenses use Claude Code's built-in skills of the same name;
if they aren't available, those lenses degrade to an inline pass.

To land in the PM by default, set it in the consuming repo's `.claude/settings.json`:

```json
{ "agent": "project-manager" }
```

The plugin deliberately ships no root `settings.json` with an `agent` field — that would hijack the
main thread of every project that installs it. Opting a repo in is your choice, per repo.

#### Naming (1:1:1:1)

Every stage can recover the others from the issue number alone:

```
GitHub issue  #N  (slug derived from the title)
git branch        issue-N-slug
git worktree      .claude/worktrees/issue-N-slug
OpenSpec change   slug
pull request      body contains "Closes #N"
```

Worktrees are long-lived — one per issue, across many stages and sessions — so several issues can
be in flight at once. `/spec-flow:board` reports across all of them.

An issue's stage is carried entirely by its label, so any session can pick up where the last one
left off:

```
status:  ready ──▶ spec-review ──▶ in-progress ──▶ in-review ──▶ addressing ──▶ (merged)
          groom      activate        implement      (PR open)      address       finalize
                   + YOU approve                   + YOU review    ⟲ loop      + YOU merged
```

"What's next" is simply the highest-priority issue carrying `status:ready`.

#### Notes

- **Session-driven, not cron.** `implement` runs as a background `Workflow` that notifies on
  completion, but it's in-session — closing the session pauses the work. `address` is invoked by you
  when you return; nothing polls.
- **Test tiering — fast locally, full suite in CI.** `implement` runs the fast **unit** tier locally
  (plus any tests CI flagged on the branch, pulled in by `sync-ci`); the full/integration suite is
  CI's gate. It says so plainly in its report and the PR body rather than implying the full suite ran
  locally. Merge is gated on green CI.
- **Issue and PR numbers always carry a description** — `#85 (field identity)`, never a bare `#85`.

#### Overriding a bundled agent

Agents resolve **bare-first with a namespaced fallback**: the workflow tries `reviewer` before
`spec-flow:reviewer`. If your repo defines an agent with the same name in `.claude/agents/`, yours
wins — a deliberate way to specialize a reviewer or the developer for a repo's stack.

See [`plugins/spec-flow/docs/workflow.md`](plugins/spec-flow/docs/workflow.md) for the full design.

## License

Apache 2.0
