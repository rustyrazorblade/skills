# Topic: Tombstones

## Objective
Understand how Cassandra handles deletes and why tombstones are a critical factor in partition and query performance.

## Why This Matters
Cassandra doesn't delete data immediately — it writes markers called tombstones. If you don't understand this, you'll design tables that accumulate massive tombstone counts, leading to slow reads, GC pressure, and eventually read failures. This is one of the most common production issues.

---

## Concept

When you delete a row or column in Cassandra, it doesn't remove the data from disk. Instead, it writes a **tombstone** — a deletion marker with a timestamp. The tombstone tells Cassandra "this data no longer exists as of this time."

Tombstones are necessary because Cassandra is distributed. A delete on one replica must eventually propagate to all replicas, and the tombstone is what carries that information during compaction and repair. (Repair isn't covered in detail in this training yet — for now, think of it as a background process that periodically reconciles data between replicas. See [Repair](../../general/repair.md) for the full reference.)

### Tombstone Lifecycle

1. **Write**: A `DELETE` or expired TTL creates a tombstone
2. **Accumulate**: Tombstones sit alongside live data in SSTables
3. **Eligible**: Once the tombstone is older than `gc_grace_seconds` (default: 10 days), it becomes *eligible* for removal — but eligibility alone doesn't drop it. Tombstones are only ever actually removed during a compaction. (Compaction was previewed in the [Read and Write Paths](./10-read-write-paths.md) topic as the background process that merges SSTables and throws away dead data; the full treatment is in the [Compaction Overview](./13-compaction-overview.md) topic later in this session.)
4. **Purge**: Compaction can drop the tombstone only if **every SSTable containing data older than the tombstone for the same partition is included in the same compaction**. Cassandra uses bloom filters and per-SSTable min/max timestamp metadata to identify which SSTables qualify — any SSTable whose partition data is *all newer* than the tombstone can be ignored. If even one older-data SSTable is missing from the compaction, the tombstone is kept around. Dropping it prematurely would resurrect the deleted row the next time a read merged the older SSTable back in.

> **Bloom filters** are a probabilistic data structure Cassandra keeps per SSTable to answer "does this SSTable *possibly* contain this partition?" without touching disk. They're allowed to say "maybe" when the answer is actually "no," but never the reverse. They're used throughout the read path and the purge logic above. Covered in more detail in the [SSTable Components](../../general/sstable-components.md) reference.

> **Note:** With `only_purge_repaired_tombstones` enabled, tombstones additionally must have been repaired before they can be dropped — a stricter mode aimed at preventing data resurrection across replicas that missed the delete.

### Why Tombstones Hurt Reads

When Cassandra reads a partition, it must scan through tombstones to determine which data is still live. A partition with 100 live rows and 100,000 tombstones still has to process all 100,000 tombstones before returning the 100 rows.

If a single read encounters too many tombstones (default threshold: 100,000), Cassandra will **abort the read** and return an error.

### Common Tombstone Traps

- **Queue-like patterns**: Using Cassandra as a queue (write, read, delete) generates enormous tombstone counts in a single partition
- **Overwriting with nulls**: Setting a column to `null` creates a tombstone — bulk updates that null out columns create tombstones for every cell
- **Short TTLs on wide partitions**: Every expired row becomes a tombstone; if data expires faster than compaction runs, tombstones pile up
- **Range deletes**: `DELETE FROM table WHERE partition_key = ? AND clustering_col > ?` creates range tombstones — efficient for large ranges but still need compaction to clean up

### How to Avoid Tombstone Problems

- **Keep partitions bounded** — smaller partitions mean fewer tombstones per partition
- **Use TTL instead of explicit deletes** where possible — lets compaction handle cleanup predictably
- **Don't use Cassandra as a queue** — the write-read-delete pattern is a tombstone factory
- **Monitor tombstone counts** — watch `TombstoneScannedHistogram` in metrics

---

## Examples

### Checking tombstone pressure
```bash
# Per-table tombstone stats
nodetool tablestats <keyspace>.<table>
# Look for: "Maximum tombstones per slice (last five minutes)"

# If this number is in the thousands, you have a problem
```

### TTL instead of explicit deletes
```sql
-- Instead of writing and later deleting:
INSERT INTO events (user_id, event_time, data)
VALUES (?, ?, ?)
USING TTL 7776000;  -- 90 days; row auto-expires, compaction cleans up
```

### Range tombstone from a range delete
```sql
-- Deletes all readings before a cutoff — creates a range tombstone
DELETE FROM sensor_readings
WHERE sensor_id = ? AND recorded_at < '2025-01-01';
```

---

## Pulse Check

> A team is using Cassandra to implement a job queue: they write a job, a worker reads it, then they delete it. The table has a single partition per queue name. After a few weeks, reads are getting slower and slower even though there are only ~100 pending jobs at any time.
>
> **What's happening, and how would you fix it?**

*(Expected answer: The partition is accumulating tombstones from all the deleted jobs. Even though only ~100 live rows exist, Cassandra is scanning through thousands of tombstones on every read. The fix is to stop using Cassandra as a queue — or at minimum, bucket by time so old tombstone-heavy partitions age out.)*

---

## See Also

**In this session:**
- [DML Basics — INSERT, UPDATE, DELETE, SELECT](./09-dml-basics.md)
- [The Read and Write Paths](./10-read-write-paths.md)
- [TTL (Time-To-Live)](./14-ttl.md)
- [Table Options](./12-table-options.md)

**Reference:**
- [Tombstones](../../general/tombstones.md)
- [Repair](../../general/repair.md)
- [Compaction](../../general/compaction.md)
- [Large Partitions](../../general/large-partitions.md)
