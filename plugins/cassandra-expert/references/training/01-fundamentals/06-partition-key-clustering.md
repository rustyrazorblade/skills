# Topic: Partition Keys and Clustering Columns

## Objective
Design a PRIMARY KEY that places data on the right node and sorts it in the right order for your queries.

## Why This Matters
In Cassandra, **the data model is the query plan**. There is no query optimizer, no index scan, no JOIN. If your table isn't structured to answer a specific query efficiently, that query either won't work or will be dangerously slow. The PRIMARY KEY — partition key + clustering columns — determines everything about how data is stored and retrieved.

---

## Recap from Previous Topics

You've already seen the PRIMARY KEY structure:

```sql
PRIMARY KEY ((partition_key), clustering_col_1, clustering_col_2, ...)
```

| Component | Role | What it controls |
|-----------|------|-----------------|
| **Partition key** | Routes data to a node | Which node(s) store this row |
| **Clustering columns** | Sort rows within a partition | Order of rows, what range queries are possible |

The partition key is hashed to determine which node stores the data, and it can be a single column or a tuple of multiple columns. Clustering columns (zero or more) define the sort order of rows within a partition.

This topic is about *designing* these components well.

---

## Concept

### Clustering Columns and Range Queries

Cassandra stores rows within a partition sorted by clustering columns on disk, so range queries on clustering columns are efficient — they read a contiguous slice of the partition.

```sql
PRIMARY KEY (device_id, recorded_at)
-- rows within a device_id partition are sorted by recorded_at
-- you can efficiently query: WHERE device_id = ? AND recorded_at > ?
```

**Order matters.** Cassandra only supports range queries on the *last* clustering column in a prefix match. You must specify equality on all preceding clustering columns before using a range on the next one.

```sql
-- Table: PRIMARY KEY (user_id, year, month, day)

-- ALLOWED: equality on year and month, range on day
SELECT * FROM events WHERE user_id = ? AND year = ? AND month = ? AND day > ?;

-- NOT ALLOWED: can't skip month and range on day
SELECT * FROM events WHERE user_id = ? AND year = ? AND day > ?;
```

### Clustering Column Sort Direction

You can control ascending or descending sort order per clustering column:

```sql
CREATE TABLE recent_events (
    user_id uuid,
    event_time timestamp,
    event_type text,
    PRIMARY KEY (user_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
-- Most recent events first — efficient for "get latest N events"
```

### Partition Size Guidelines

Now that you understand clustering columns, you can see how partitions grow: every new clustering key value adds another row to the partition. This is why partition size matters.

| Size | Status |
|------|--------|
| < 10MB | Ideal target |
| 10MB – 100MB | Acceptable — sometimes the right trade-off |
| > 100MB | Danger zone — expect latency and operational pain |
| Unbounded growth | Guaranteed production incident |

The right partition size depends on your access pattern. If a query needs to read the entire partition anyway (e.g., all events for a day), over-bucketing just forces multiple queries for no benefit. Choose a bucket size that matches how you read the data, not just how small you can make the partition.

### What Happens When Partitions Get Too Large

> **Note:** Several terms below (SSTables, compaction, tombstones) get their full treatment in later topics — for now, think of SSTables as the immutable on-disk files Cassandra writes data to, compaction as the background process that merges them, and tombstones as deletion markers. Each has a dedicated topic later in this session.

- **Read latency spikes**: Reading a 500MB partition means deserializing hundreds of thousands of rows, even if you only want a few.
- **GC pressure**: Large partition reads create enormous on-heap objects, triggering long GC pauses.
- **Compaction problems**: Merging large SSTables takes longer and requires more disk headroom.
- **Hot nodes**: A single large partition sits on one node — all traffic for it concentrates there.
- **Tombstone amplification**: Deletes leave tombstones inside the partition; large partitions accumulate huge tombstone counts.
- **Expensive repair**: Large partitions are more expensive to repair — the entire partition must be considered during repair. Incremental repair (Cassandra 4.0+) mitigates this, but small partitions are still cheaper. (Repair isn't covered in detail in this training yet — see [Repair](../../general/repair.md) for the full reference on full, subrange, and incremental repair.)

### What You Cannot Do Without Pain

- **Filter on non-primary-key columns**: Requires `ALLOW FILTERING` — never do this in production.
- **Sort by a column that isn't a clustering column**: Cassandra's sort order is fixed at write time.
- **Query across multiple partitions efficiently**: Each partition is a separate I/O operation.

If you need to query data a different way, the answer is a **separate table** (denormalization), not a filter.

---

## Examples

### Single column partition key, one clustering column
```sql
-- "Get all messages in a conversation, newest first"
CREATE TABLE messages (
    conversation_id uuid,
    sent_at timeuuid,
    sender_id uuid,
    body text,
    PRIMARY KEY (conversation_id, sent_at)
) WITH CLUSTERING ORDER BY (sent_at DESC);
```

### Composite partition key to control partition size
```sql
-- "Get all events for a user on a given day"
-- Bucketing by day keeps partition size bounded
CREATE TABLE user_events (
    user_id uuid,
    event_date date,     -- bucket
    event_time timestamp,
    event_type text,
    data text,
    PRIMARY KEY ((user_id, event_date), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```

### Multiple clustering columns
```sql
-- "Get all readings for a sensor in a region, by time"
CREATE TABLE sensor_readings (
    region text,
    sensor_id uuid,
    recorded_at timestamp,
    value double,
    PRIMARY KEY (region, sensor_id, recorded_at)
) WITH CLUSTERING ORDER BY (sensor_id ASC, recorded_at DESC);

-- Efficient query:
SELECT * FROM sensor_readings
WHERE region = 'us-west'
  AND sensor_id = ?
  AND recorded_at > '2025-01-01';
```

---

## Pulse Check

> You need to store support tickets. The query you must support is:
> **"Get all tickets for a given customer, ordered by creation time (newest first)."**
>
> **Write the PRIMARY KEY for this table.**

*(Expected answer: `PRIMARY KEY (customer_id, created_at)` with `CLUSTERING ORDER BY (created_at DESC)`. `customer_id` partitions tickets by customer; `created_at DESC` sorts newest first within that partition.)*

---

## See Also

**In this session:**
- [Tables and the Primary Key](./04-tables-primary-key.md)
- [Partition Storage](./05-partition-storage.md)
- [Pattern: Ordered Map](./18-pattern-ordered-map.md)
- [Pattern: Time Series](./19-pattern-time-series.md)

**Reference:**
- [Large Partitions](../../general/large-partitions.md)
- [Time Series Data Modeling](../../general/time-series.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Repair](../../general/repair.md)
