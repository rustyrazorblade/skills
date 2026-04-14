# Topic: Incorrect Compaction Strategy

## Objective
Recognize when a table's compaction strategy conflicts with its workload, and know the correct strategy for each Cassandra version.

## Why This Matters
The wrong compaction strategy is one of the most common causes of gradual, invisible performance degradation. A cluster that starts fast can become sluggish over weeks or months as SSTable counts grow and read amplification increases — and the root cause is a compaction strategy set at table creation and never revisited.

---

## Concept

### Quick Recap: What Compaction Does

Cassandra writes data to immutable SSTables. Compaction merges SSTables, resolves which version of data is current, and removes tombstones. Without compaction, SSTable count grows and reads must check more files to find the current value.

### The Correct Strategy by Version

| Version | Correct Strategy | Notes |
|---------|-----------------|-------|
| Cassandra 5.0+ | **UCS (UnifiedCompactionStrategy)** | Use for everything — replaces all others |
| Cassandra 4.x | **LCS (LeveledCompactionStrategy)** | Best for most workloads |
| Cassandra 3.x | **LCS** | Same — STCS is the default but not the best choice |

**STCS (SizeTieredCompactionStrategy)** is the default. It is not the best choice for most production workloads. High SSTable counts accumulate over time, read amplification grows, and space amplification is high during compaction.

### Common Mistakes

**Leaving tables on STCS (the default)**
STCS has a narrow niche on pre-5.0: write-heavy workloads with frequent overwrites, where LCS's constant re-leveling exceeds what the disks can sustain. (Immutable/time-series data uses TWCS, not STCS — see the TWCS note below.) For mixed or read-heavy workloads, STCS accumulates SSTables and degrades over time.

**Using TWCS without understanding the trade-offs**
TWCS performs a major compaction to finalize each time window. Finalized SSTables overlap in token range, breaking Zero Copy Streaming. This limits node size and can increase cluster cost by 5x. Use LCS + bucketing instead (pre-5.0), or UCS (5.0+).

**Using LCS with very high write rates without bucketing**
LCS write amplification increases at higher levels. Combined with time-series bucketing, this is manageable. Without bucketing on a high-write workload, LCS can fall behind.

**Mixing strategies across tables without reason**
Every table in a keyspace should use the same strategy unless there's a specific, documented reason for the exception.

### How to Check and Fix

```sql
-- Check current compaction strategy
SELECT table_name, compaction
FROM system_schema.tables
WHERE keyspace_name = 'my_keyspace';

-- Migrate to UCS (Cassandra 5.0+)
ALTER TABLE my_keyspace.my_table
WITH compaction = {'class': 'UnifiedCompactionStrategy'};

-- Migrate to LCS (Cassandra 4.x)
ALTER TABLE my_keyspace.my_table
WITH compaction = {
    'class': 'LeveledCompactionStrategy',
    'sstable_size_in_mb': '160'
};
```

### Monitoring Compaction Health

```bash
# See pending compaction tasks — high pending means strategy isn't keeping up
nodetool compactionstats

# Per-table SSTable count — high counts mean compaction is falling behind
nodetool tablestats <keyspace>.<table>
# "SSTable count" > 20-30 is a warning sign
```

---

## Pulse Check

> You inherit a Cassandra 5.0 cluster. Running `SELECT table_name, compaction FROM system_schema.tables WHERE keyspace_name = 'production'` shows all tables are using `SizeTieredCompactionStrategy`. The cluster is 18 months old and reads have been getting progressively slower.
>
> **What's the likely cause and what do you do?**

*(Expected answer: STCS is the default but wrong for most production workloads. Over 18 months, SSTables have accumulated — STCS merges same-sized SSTables slowly, leading to high SSTable counts and read amplification. On Cassandra 5.0, migrate all tables to UCS: `ALTER TABLE ... WITH compaction = {'class': 'UnifiedCompactionStrategy'}`. After migration, compaction will consolidate SSTables and read performance will recover. Monitor with `nodetool compactionstats` during the transition.)*

---

## See Also

**In this session:**
- [Huge Partitions](./01-huge-partitions.md)
- [Large Blob Storage](./10-large-blobs.md)

**Reference:**
- [Compaction](../../general/compaction.md)
- [Streaming (Zero Copy Streaming)](../../general/streaming.md)
- [SSTable Components](../../general/sstable-components.md)
- [cassandra.yaml (Cassandra 5.0)](../../cassandra-5.0/cassandra-yaml.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
- [Compaction Strategies and Performance (Rusty Razorblade)](https://rustyrazorblade.com/post/2025/07-compaction-strategies-and-performance/)
