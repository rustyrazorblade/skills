# Topic: Creating and Managing SAI Indexes

## Objective
Create, name, inspect, and drop SAI indexes correctly, and understand what happens to the index during compaction and schema changes.

## Why This Matters
Unnamed indexes are hard to manage — you can't easily drop or reference them. Knowing how to inspect indexes in the system schema helps you audit existing clusters and debug unexpected query behavior.

---

## Concept

### Creating an SAI Index

```sql
-- Unnamed index (harder to manage — avoid in production)
CREATE INDEX ON orders (status) USING 'sai';

-- Named index (preferred)
CREATE INDEX orders_by_status ON orders (status) USING 'sai';
```

Always name your indexes. Unnamed indexes get auto-generated names that are hard to work with when you need to drop or reference them.

### What Columns Can Be Indexed

SAI supports indexing:
- **Scalar types**: text, int, bigint, float, double, decimal, boolean, uuid, timeuuid, timestamp, date, inet
- **Collections**: list, set, map (with some restrictions — see collection indexing below)

SAI does **not** support indexing:
- A partition key that is a single column — already the hash lookup key, Cassandra rejects the `CREATE INDEX` with "Cannot create secondary index on the only partition key column"
- Counter columns — rejected with "Secondary indexes on counter tables aren't supported"

SAI **does** support indexing:
- **Clustering columns** — useful when you want to filter on a clustering column without restricting the earlier ones (otherwise a range read with `ALLOW FILTERING` would be required)
- **Individual columns of a composite partition key** — e.g. `PRIMARY KEY ((tenant_id, region), ...)` lets you create an SAI on just `region`

### Indexing Collections

```sql
-- Index values in a set or list
CREATE INDEX orders_by_tag ON orders (tags) USING 'sai';
-- Query: WHERE tags CONTAINS 'urgent'

-- Index map values by key
CREATE INDEX orders_by_meta_key ON orders (metadata) USING 'sai';
-- Query: WHERE metadata CONTAINS KEY 'source'

-- Index map values
CREATE INDEX orders_by_meta_value ON orders (ENTRIES(metadata)) USING 'sai';
-- Query: WHERE metadata['source'] = 'web'
```

### Dropping an Index

```sql
DROP INDEX orders_by_status;

-- If you're unsure of the keyspace:
DROP INDEX my_keyspace.orders_by_status;
```

### What Happens During Compaction

SAI index files are rebuilt alongside SSTables during compaction. When SSTables are merged, the corresponding index files are merged too. This means:
- Index files stay in sync with SSTables automatically
- Compaction overhead increases slightly with SAI indexes
- Index files are cleaned up when SSTables are removed

---

## Examples

### Inspecting indexes in the system schema
```sql
-- List all indexes in a keyspace
SELECT table_name, index_name, kind, options
FROM system_schema.indexes
WHERE keyspace_name = 'my_keyspace';

-- Verify an index is SAI
SELECT options FROM system_schema.indexes
WHERE keyspace_name = 'my_keyspace'
  AND table_name = 'orders'
  AND index_name = 'orders_by_status';
-- options should contain: {'class_name': 'org.apache.cassandra.index.sai.StorageAttachedIndex'}
```

### Full example: orders table with multiple SAI indexes
```sql
CREATE TABLE orders (
    customer_id uuid,
    order_id    uuid,
    status      text,
    total       decimal,
    tags        set<text>,
    created_at  timestamp,
    PRIMARY KEY (customer_id, order_id)
);

-- Index for filtering by status within a customer's orders
CREATE INDEX orders_by_status ON orders (status) USING 'sai';

-- Index for filtering by total (supports range queries)
CREATE INDEX orders_by_total ON orders (total) USING 'sai';

-- Index for filtering by tags
CREATE INDEX orders_by_tag ON orders (tags) USING 'sai';

-- Valid queries (all include partition key):
SELECT * FROM orders WHERE customer_id = ? AND status = 'pending';
SELECT * FROM orders WHERE customer_id = ? AND total > 100.00;
SELECT * FROM orders WHERE customer_id = ? AND tags CONTAINS 'priority';

-- Combining SAI filters (both must include partition key):
SELECT * FROM orders
WHERE customer_id = ?
  AND status = 'pending'
  AND total > 100.00;
```

### Checking index build status after creation
```sql
-- SAI index builds happen asynchronously after CREATE INDEX.
-- Check progress via the system_views.indexes virtual table:
SELECT index_name, is_building, is_queryable
FROM system_views.indexes
WHERE keyspace_name = '<keyspace>' AND table_name = '<table>';
```

---

## Pulse Check

> You've just inherited a Cassandra schema. You need to find all indexes on the `events` table in the `analytics` keyspace and verify they are SAI (not SASI or legacy secondary indexes).
>
> **Write the CQL query to inspect them.**

*(Expected answer: `SELECT index_name, kind, options FROM system_schema.indexes WHERE keyspace_name = 'analytics' AND table_name = 'events';` — look at the `options` column for `class_name`. SAI will show `org.apache.cassandra.index.sai.StorageAttachedIndex`. SASI will show `org.apache.cassandra.index.sasi.SASIIndex`. Any SASI indexes should be migrated to SAI.)*

---

## See Also

**In this session:**
- [SAI Overview — Why This Session Exists](./01-sai-overview.md)
- [What SAI Is and Why the Partition Key Rule Exists](./02-what-is-sai.md)
- [Querying with SAI — Patterns and Anti-Patterns](./04-querying-with-sai.md)
- [SASI — What It Is and Why to Avoid It](./06-sasi-never-use.md)

**Reference:**
- [SAI FAQ (Apache Cassandra)](https://cassandra.apache.org/doc/latest/cassandra/developing/cql/indexing/sai/sai-faq.html)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
- [SSTable Components](../../general/sstable-components.md)
- [Compaction](../../general/compaction.md)
