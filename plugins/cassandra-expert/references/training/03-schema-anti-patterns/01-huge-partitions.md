# Topic: Huge Partitions

## Objective
Recognize when a schema will produce partitions that grow too large, and apply bucketing or sharding to keep them bounded.

## Why This Matters
Huge partitions are one of the most common causes of production incidents in Cassandra. They degrade read latency, cause GC pressure, slow down compaction, make repair expensive, and concentrate load on a single node. The worst part: they're invisible until they've already grown large — and by then, fixing them requires a schema migration.

---

## Concept

A partition holds all rows with the same partition key. There is no automatic size limit — a partition will grow until you stop writing to it or the data expires. Left unbounded, partitions routinely reach hundreds of megabytes in production clusters.

### Why Large Partitions Are Dangerous

- **Read amplification**: reading even a small slice of a large partition deserializes far more data than needed
- **GC pressure**: large partition reads create massive on-heap objects
- **Compaction**: merging large SSTables requires more disk headroom and takes longer
- **Repair**: the entire partition must be considered during repair (incremental repair helps but doesn't eliminate the cost)
- **Hot nodes**: a large partition lives on one node — all traffic for it is concentrated there

### The Fix: Bucketing

Add a time or hash bucket to the partition key to split one logical partition into many physical ones.

```sql
-- ANTI-PATTERN: one partition per user, grows forever
CREATE TABLE user_events (
    user_id  uuid,
    event_id timeuuid,
    data     text,
    PRIMARY KEY (user_id, event_id)
);

-- CORRECT: one partition per user per day
CREATE TABLE user_events (
    user_id  uuid,
    day      date,
    event_id timeuuid,
    data     text,
    PRIMARY KEY ((user_id, day), event_id)
) WITH CLUSTERING ORDER BY (event_id DESC);
```

### Sizing Buckets

Target under 10MB per partition. Up to 100MB is acceptable for partitions that are rarely read. Calculate:

```
(rows/sec × bytes/row × seconds/bucket) < 10MB
```

Match the bucket size to how you read the data. If you always read a full day's worth of events, a daily bucket means one query. Smaller buckets mean more queries for the same time range — don't over-partition.

### Checking Partition Size in Production

```bash
nodetool tablestats <keyspace>.<table>
# Look for: "Maximum live cells per slice" and "Maximum tombstones per slice"
# High tombstone counts indicate delete-heavy workloads accumulating in large partitions
```

---

## Examples

### E-commerce: orders per customer
```sql
-- ANTI-PATTERN: grows forever for active customers
PRIMARY KEY (customer_id, order_id)

-- CORRECT: bounded by year
PRIMARY KEY ((customer_id, order_year), order_id)
```

### IoT: sensor readings
```sql
-- ANTI-PATTERN: one partition per sensor, unbounded
PRIMARY KEY (sensor_id, recorded_at)

-- CORRECT: one partition per sensor per day
PRIMARY KEY ((sensor_id, day), recorded_at)
```

---

## Pulse Check

> You're reviewing a schema for a logging system. Each service writes log entries to a table with `PRIMARY KEY (service_name, log_id)`. One service writes 1,000 entries per second.
>
> **What's the problem and how do you fix it?**

*(Expected answer: `service_name` as the sole partition key means all log entries for that service accumulate in one partition — unbounded growth and a hot node. At 1,000 entries/second and even 100 bytes/entry, that's 8.6GB/day in one partition. Fix: add a time bucket to the partition key, e.g., `PRIMARY KEY ((service_name, log_date), log_id)`, so each partition holds one day's worth of logs.)*

---

## See Also

**In this session:**
- [Hot Partitions](./02-hot-partitions.md)
- [Unbounded Collections](./06-unbounded-collections.md)
- [Incorrect Compaction Strategy](./09-compaction-strategy.md)
- [Large Blob Storage](./10-large-blobs.md)

**Reference:**
- [Large Partitions](../../general/large-partitions.md)
- [Time Series Data Modeling](../../general/time-series.md)
- [Compaction](../../general/compaction.md)
- [Repair](../../general/repair.md)
