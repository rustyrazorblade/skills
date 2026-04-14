# Topic: Secondary Indexes Without Partition Keys

## Objective
Understand why legacy secondary indexes (2i) are dangerous and when SAI with a partition key is the correct alternative to denormalization.

## Why This Matters
Cassandra's legacy secondary indexes (created with `CREATE INDEX` without `USING 'sai'`) are one of the most misused features in the ecosystem. They appear to solve the "query by non-primary-key column" problem, but at scale they cause cluster-wide scatter-gather queries that degrade with data size. Many teams discover this only after deploying to production.

---

## Concept

### What Legacy Secondary Indexes (2i) Do

A legacy secondary index maintains a local index on each node. When you query by an indexed column, the coordinator must query **every node in the cluster** to find all matching rows — a scatter-gather across the entire cluster.

```
Query: SELECT * FROM orders WHERE status = 'pending'
          ↓
Coordinator sends query to ALL nodes
Each node searches its local 2i index
Results from all nodes are merged
          ↓
Response returned to client
```

This is O(N) in the number of nodes. It works at small scale, degrades badly at large scale, and gets worse as you add nodes.

### When 2i Causes the Most Damage

- **High-cardinality columns**: many distinct values means many index entries per node, large scatter results
- **Low-cardinality columns**: many matching rows per node, large result sets to merge
- **Both**: 2i is bad in both directions

### Why 2i Exists At All

Legacy 2i was designed for low-cardinality columns used alongside the partition key. Without the partition key, 2i fans out to every node in the cluster. With the partition key, it routes to the owning replicas only — but SAI is still preferable: its per-SSTable index model avoids the scatter that drives read amplification as SSTables accumulate, and it handles high- and low-cardinality columns that trip up 2i. SAI supersedes 2i entirely for Cassandra 5.0+.

### The Correct Alternatives

**Option 1: Denormalize** (preferred for high-throughput queries)
```sql
-- Dedicated table for the access pattern
CREATE TABLE orders_by_status (
    status     text,
    created_at timestamp,
    order_id   uuid,
    PRIMARY KEY (status, created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

**Option 2: SAI with partition key** (for infrequent queries where partition key is known)
```sql
CREATE INDEX orders_by_status ON orders (status) USING 'sai';

-- Scope SAI queries to a partition for best performance
-- (Session 4 covers how SAI query resolution works and why this matters)
SELECT * FROM orders WHERE customer_id = ? AND status = 'pending';
```

**Never use legacy 2i in production.**

### Identifying Legacy 2i in Existing Schemas

```sql
SELECT index_name, kind, options
FROM system_schema.indexes
WHERE keyspace_name = 'my_keyspace';

-- Legacy 2i: kind = 'COMPOSITES' or options contains no SAI/SASI class
-- SAI: options contains 'org.apache.cassandra.index.sai.StorageAttachedIndex'
-- SASI: options contains 'org.apache.cassandra.index.sasi.SASIIndex'
```

---

## Examples

### Anti-pattern: 2i for status filtering
```sql
-- ANTI-PATTERN: legacy secondary index
CREATE INDEX ON orders (status);  -- no USING 'sai' = legacy 2i

-- This query hits every node in the cluster:
SELECT * FROM orders WHERE status = 'pending';
```

### Correct: denormalize for high-traffic status queries
```sql
CREATE TABLE orders_pending (
    customer_id uuid,
    created_at  timestamp,
    order_id    uuid,
    total       decimal,
    PRIMARY KEY (customer_id, created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

### Correct: SAI for low-traffic, partition-key-scoped queries
```sql
CREATE INDEX orders_by_status ON orders (status) USING 'sai';

-- See Session 4 for how SAI query performance depends on partition-key scoping
SELECT * FROM orders WHERE customer_id = ? AND status = 'pending';
```

---

## Pulse Check

> A legacy Cassandra 4.x cluster has this index:
> ```sql
> CREATE INDEX ON payments (merchant_id);
> ```
> And this query runs thousands of times per second:
> ```sql
> SELECT * FROM payments WHERE merchant_id = ?;
> ```
>
> **Why is this dangerous, and what are your two options for fixing it?**

*(Expected answer: This is a legacy 2i. Every query fans out to all nodes in the cluster — O(N) in cluster size. At thousands of queries per second, this is constant cluster-wide scatter-gather load that gets worse as the cluster grows. Option 1: denormalize — create a `payments_by_merchant` table with `merchant_id` as the partition key. This is the right choice given the high query volume. Option 2: migrate to SAI — but only if `payment_id` (the partition key) is always available in the query. Given that the existing query has no partition key, denormalization is the correct fix here.)*

---

## See Also

**In this session:**
- [Too Many Tables](./03-too-many-tables.md)
- [Materialized Views](./05-materialized-views.md)

**From other sessions:**
- [SAI Overview](../04-sai/01-sai-overview.md) — the correct replacement for legacy 2i in Cassandra 5.0+

**Reference:**
- [SSTable Components](../../general/sstable-components.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
