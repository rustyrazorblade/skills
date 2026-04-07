# Rustyrazorblade Skills

A Claude Code plugin marketplace by Jon Haddad.

## Installation

```
/plugin marketplace add rustyrazorblade/skills
```

## Available Plugins

### cassandra-expert

Expert guidance for Apache Cassandra development and operations.

```
/plugin install cassandra-expert@rustyrazorblade-plugins
```

#### Skills

| Skill | Purpose |
|-------|---------|
| `/cassandra-expert:diagnose` | Systematic troubleshooting using USE method, outlier analysis, double loop learning |
| `/cassandra-expert:optimize` | Performance tuning, configuration analysis, JVM settings, compaction strategies |
| `/cassandra-expert:data-model` | Schema design, partition keys, time-series modeling, query patterns |
| `/cassandra-expert:expert` | General Cassandra questions, CQL analysis, best practices |
| `/cassandra-expert:token-skew` | Token ownership skew analysis using correct per-rack metric |

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

#### Problem-Solving Methodology

- **Double Loop Learning** - Goes beyond immediate fixes to identify root causes and prevent recurrence
- **USE Method** - Systematically analyzes Utilization, Saturation, and Errors for CPU, memory, disk, network, storage, and thread pools
- **Outlier Analysis** - Compares nodes to identify anomalies in latency, resource usage, and behavior
- **Configuration Analysis** - Reviews system settings, cassandra.yaml, JVM settings, and per-table configurations

#### Key Recommendations

Opinionated guidance based on real-world experience:

- **num_tokens**: Use 1 or max 4. Higher is always worse.
- **Compaction**: UCS for Cassandra 5.0+. Never use STCS.
- **Read-ahead**: Disable it. One of the worst settings you can have enabled.
- **Partitions**: Keep under 10MB. No downside to smaller partitions.
- **Row cache**: Keep disabled. Rarely beneficial.

## License

Apache 2.0
