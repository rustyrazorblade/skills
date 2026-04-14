# Topic: Partition Storage

## Objective
Understand what a partition is physically and how data is organized within it.

## Why This Matters
The partition is the fundamental unit of storage in Cassandra. Every decision about data modeling, performance, and operations comes back to how partitions are structured. Understanding what a partition is — before learning how to design good ones — is essential.

---

## Concept

A **partition** is the fundamental unit of storage and distribution in Cassandra. All rows that share the same partition key are stored together on disk, on the same node (and its replicas).

```
Partition Key → one node owns all rows with that key
```

Within a partition, rows are sorted by **clustering columns** (covered in the next topic). Cassandra can efficiently read a slice of a partition by specifying clustering column ranges.

### Partition vs. Row

| Concept | Definition |
|---------|-----------|
| **Partition** | All rows sharing the same partition key — stored together on one node |
| **Row** | A single record within a partition |
| **Wide partition** | A partition with many rows (common in time series, maps) |

---

## Examples

### A simple table with one row per partition
```sql
-- Each user_id is its own partition with exactly one row
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    email text
);
```

### Checking partition size in production
```bash
# Per-table partition size estimates
nodetool tablestats <keyspace>.<table>
# Look for: "Maximum live cells per slice (last five minutes)"
# and:      "Maximum tombstones per slice (last five minutes)"
#           (tombstones are deletion markers — covered in topic 11)
```

---

## Pulse Check

> A colleague says: "Each row in Cassandra is stored on a different node, just like rows in a sharded relational database." You need to correct them.
>
> **What's wrong with this statement? What is the actual unit of distribution, and what does that imply about how you should design tables?**

*(Expected answer: The unit of distribution is the partition, not the row. All rows that share a partition key live on the same node (and its replicas) — so many rows can end up on the same node, and a single huge partition concentrates all its traffic on one node. This is why partition key design matters so much: it controls where data lives, and getting it wrong creates hot spots or unbounded partitions.)*

---

## See Also

**In this session:**
- [Tables and the Primary Key](./04-tables-primary-key.md)
- [Partition Keys and Clustering Columns](./06-partition-key-clustering.md)
- [The Read and Write Paths](./10-read-write-paths.md)

**Reference:**
- [Large Partitions](../../general/large-partitions.md)
- [SSTable Components](../../general/sstable-components.md)
- [Memtables](../../general/memtables.md)
- [Compaction](../../general/compaction.md)
