# Topic: Compaction Overview and UCS

## Objective
Understand what compaction is, why it's necessary, and why Unified Compaction Strategy (UCS) is the right choice for Cassandra 5.0+.

## Why This Matters
Compaction directly affects read performance, write amplification, and disk usage. Choosing the wrong compaction strategy is one of the most common causes of gradual performance degradation in Cassandra clusters — it starts fine and gets worse over months as SSTable count grows. Getting this right at table creation time is far cheaper than migrating later.

---

## Concept

### Why Compaction Exists

Cassandra uses a **Log-Structured Merge (LSM) tree** storage model. Writes go to an in-memory structure (memtable) and are flushed to immutable files on disk called **SSTables**. Cassandra never modifies an SSTable in place — updates and deletes are new writes (updates overwrite, deletes become tombstones).

Over time, a table accumulates many SSTables. Reading a row requires checking all of them to find the most recent version. As SSTable count grows, reads get slower.

**Compaction** merges SSTables together, resolving which data is current and dropping tombstoned (deleted) data. The result is fewer, larger SSTables — and faster reads.

```
SSTable 1 + SSTable 2 + SSTable 3
         ↓ compaction
    SSTable merged (newer values win, tombstones removed after gc_grace)
```

### The Trade-off

Compaction consumes CPU and disk I/O. More aggressive compaction = faster reads but higher write amplification. Less aggressive = slower reads but lower background overhead. Choosing a strategy is choosing where on this spectrum you sit.

### Compaction Strategies

| Strategy | Short Name | Behavior | Use Case | Jon's Take |
|----------|-----------|----------|----------|------------|
| Size-Tiered Compaction | STCS | Groups SSTables by size, merges similar-sized ones | Default, general | Avoid in most cases — high read amplification over time. Narrow exception on pre-5.0: write-heavy workloads with frequent overwrites where LCS can't keep up with disk I/O. |
| Leveled Compaction | LCS | Organizes into fixed-size levels | Most workloads pre-5.0 | Best option for Cassandra < 5.0 |
| Time-Window Compaction | TWCS | Groups SSTables by time window | Time series append-only | Situational — see below |
| **Unified Compaction Strategy** | **UCS** | Single strategy adapting to workload | **Everything** | **Use this in C* 5.0+** |

### UCS: Unified Compaction Strategy (Cassandra 5.0+)

UCS replaces all previous strategies with a single adaptive algorithm. It:
- Eliminates the need to choose between STCS, LCS, TWCS
- Adapts compaction behavior to actual read/write patterns
- Reduces worst-case read amplification compared to STCS
- Handles mixed workloads (reads + writes + time series) gracefully

**Rule: Use UCS for all tables on Cassandra 5.0+. No exceptions.**

### LCS: Best Option for Cassandra < 5.0

For clusters running Cassandra 3.x or 4.x, LCS is the best choice for most workloads — not just read-heavy tables. It keeps SSTable count bounded and provides predictable read performance.

**LCS + bucketing for time series (pre-5.0):** Even for time series data, LCS can be a good choice when combined with time bucketing. Bucketed partitions mean each SSTable covers a bounded time range, which limits write amplification at higher LCS levels — one of the main drawbacks of LCS on write-heavy workloads.

An important bonus: LCS with time bucketing enables **Zero Copy Streaming** (Cassandra 4.0+), which streams entire SSTables directly from disk to network without JVM heap involvement — dramatically faster bootstrap and repair. This only works when SSTables don't overlap in token range, which LCS guarantees for everything above L0 (freshly-flushed SSTables at L0 may still overlap). (Bootstrap and repair aren't covered in detail in this training yet — for now, think of both as operator-triggered processes that move data between nodes. See [Repair](../../general/repair.md) and [Streaming](../../general/streaming.md) for the full references.)

### TWCS: Last Resort for Pre-5.0 High-Write Time Series

If LCS can't keep up with write throughput even with bucketing, TWCS is the fallback. However, it comes with a serious operational cost:

TWCS performs a **major compaction to finalize each time window**, producing one large SSTable per window. Because each SSTable spans the full token range, they are **ineligible for Zero Copy Streaming**. Without ZCS, streaming must go through the JVM heap — severely limiting how large nodes can be. In practice, this can force you to use much smaller nodes and many more of them, **increasing the cost of running your cluster by up to 5x**.

**Strong recommendation:** If you're on Cassandra 5.0, use UCS instead. UCS handles high-write time series workloads without these trade-offs, and supports Zero Copy Streaming. Nodes can safely hold 20TB+ of data, which dramatically reduces cluster cost and operational complexity compared to a TWCS-based pre-5.0 cluster.

---

## Examples

### Setting UCS at table creation (Cassandra 5.0+)
```sql
CREATE TABLE user_events (
    user_id uuid,
    event_time timestamp,
    event_type text,
    data text,
    PRIMARY KEY (user_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC)
  AND compaction = {
      'class': 'UnifiedCompactionStrategy'
  };
```

### Migrating an existing table to UCS
```sql
ALTER TABLE user_events
WITH compaction = {
    'class': 'UnifiedCompactionStrategy'
};
```

### Checking compaction activity
```bash
# See compaction in progress
nodetool compactionstats

# See compaction history
nodetool compactionhistory

# See pending compaction tasks per table
nodetool tablestats <keyspace>.<table>
# Look for: "SSTable count" — high counts (50+) mean compaction is falling behind
```

### Verifying a table's compaction strategy
```sql
SELECT table_name, compaction FROM system_schema.tables
WHERE keyspace_name = 'my_keyspace'
  AND table_name = 'user_events';
```

---

## Pulse Check

> You're setting up a new Cassandra 5.0 cluster with three tables:
> - A user profile table (mostly reads, occasional updates)
> - A time series table for sensor readings
> - A high-write event log
>
> **Which compaction strategy should you use for all three? Why is one strategy now the right answer for everything?**

*(Expected answer: UCS for all three. In Cassandra 5.0+, UCS replaces all other strategies — it adapts to each table's actual access pattern rather than requiring you to predict it upfront. Previously you'd use LCS for the profile table, TWCS for time series, STCS as fallback — but UCS handles all of these well without manual tuning.)*

---

## See Also

**In this session:**
- [Partition Storage](./05-partition-storage.md)
- [The Read and Write Paths](./10-read-write-paths.md)
- [Table Options](./12-table-options.md)

**Reference:**
- [Compaction](../../general/compaction.md)
- [Streaming (Zero Copy Streaming)](../../general/streaming.md)
- [SSTable Components](../../general/sstable-components.md)
- [cassandra.yaml (Cassandra 5.0)](../../cassandra-5.0/cassandra-yaml.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
- [Compaction Strategies and Performance (Rusty Razorblade)](https://rustyrazorblade.com/post/2025/07-compaction-strategies-and-performance/)
- [Compaction Throughput Performance (Rusty Razorblade)](https://rustyrazorblade.com/post/2025/04-compaction-throughput/)
