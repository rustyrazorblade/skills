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
```

### Codex
```
codex plugin marketplace add rustyrazorblade/skills
```

Codex exposes skills through `$` mentions instead of slash commands.

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
| `/cassandra-expert:expert` | General Cassandra questions, CQL analysis, best practices |
| `/cassandra-expert:token-skew` | Token ownership skew analysis using correct per-rack metric |
| `/cassandra-expert:training` | Interactive, session-based Cassandra training from fundamentals to advanced topics |

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

**Expert - General Questions**
```
/cassandra-expert:expert What consistency level should I use for multi-DC?
/cassandra-expert:expert Review this CQL query for anti-patterns
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

#### Key Recommendations

Opinionated guidance based on real-world experience:

- **num_tokens**: Use 1 or max 4. Higher is always worse.
- **Compaction**: UCS for Cassandra 5.0+. Never use STCS.
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
| `/easy-db-lab:provision` | Provision single or multi-DC environments including VPC peering, security groups, and Cassandra seed coordination |
| `/easy-db-lab:plan` | Interactively design a lab workflow and write it to `plan.md` |
| `/easy-db-lab:install` | Install and operate kits (databases, analytics engines, query engines, apps) |
| `/easy-db-lab:run` | Execute a `plan.md` step by step, confirming each step with the user and recording progress in `history.md` |

#### Usage Examples

```
/easy-db-lab:explore
/easy-db-lab:explore cassandra 5.0
/easy-db-lab:explore clickhouse analytics
/easy-db-lab:provision 3 node Cassandra cluster on m5.2xlarge
/easy-db-lab:provision 2 DCs, 3 nodes each, multi-DC setup
/easy-db-lab:plan benchmark Cassandra 5.0 vs 4.1
/easy-db-lab:install list available kits
```

#### Notes

- Skills must be run from a lab workspace directory (created by `easy-db-lab init`)
- Each DC in a multi-DC setup has its own subdirectory with independent state
- Session activity is tracked in `history.md` in the workspace directory
- Plans are written to `plan.md`

## License

Apache 2.0
