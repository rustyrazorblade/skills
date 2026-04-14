# Topic: SASI — What It Is and Why to Avoid It

## Objective
Recognize SASI indexes in existing schemas and know how to migrate them to SAI.

## Why This Matters
SASI is still present in many older Cassandra clusters. It was introduced before SAI existed and is still valid syntax — which means it won't cause an error when you create it. But it has serious performance and correctness problems that make it unsuitable for production. If you encounter it, treat it as a bug to fix.

---

## Concept

### What SASI Is

SASI (SSTable Attached Secondary Index) was Cassandra's first SSTable-attached secondary index — legacy 2i predates it. It was introduced in Cassandra 3.4 as an experimental feature and was never promoted to stable.

SAI (Storage-Attached Indexes) is the replacement, introduced in Cassandra 5.0. It is faster, more correct, and supports more data types and query patterns.

### Why SASI Is Dangerous

- **Correctness issues**: SASI has known bugs where queries can return incorrect results under certain conditions
- **Poor performance**: SASI does not scale well with data volume
- **Limited support**: SASI is not actively maintained or improved
- **No future**: SASI is effectively deprecated in favor of SAI

### How to Identify SASI

SASI indexes appear in the schema with the full class name rather than `'sai'`:

```sql
-- This is SASI — do not use
CREATE INDEX ON orders (status)
USING 'org.apache.cassandra.index.sasi.SASIIndex';

-- This is SAI — correct
CREATE INDEX ON orders (status) USING 'sai';
```

In `system_schema.indexes`, SASI shows a different `class_name`:

```sql
SELECT index_name, options
FROM system_schema.indexes
WHERE keyspace_name = 'my_keyspace'
  AND table_name = 'orders';

-- SASI will show:
-- options: {'class_name': 'org.apache.cassandra.index.sasi.SASIIndex', ...}

-- SAI will show:
-- options: {'class_name': 'org.apache.cassandra.index.sai.StorageAttachedIndex'}
```

### How to Migrate SASI to SAI

Migration is straightforward — drop the SASI index and create an SAI index in its place. There is a brief window where the index doesn't exist, so time this for low-traffic periods if the index is query-critical.

```sql
-- Step 1: Drop the SASI index
DROP INDEX my_keyspace.old_sasi_index_name;

-- Step 2: Create the SAI index
CREATE INDEX new_sai_index_name ON my_keyspace.orders (status) USING 'sai';

-- Step 3: Wait for the index to build (happens asynchronously).
-- Monitor with the system_views.indexes virtual table:
SELECT index_name, is_building, is_queryable
FROM system_views.indexes
WHERE keyspace_name = 'my_keyspace' AND table_name = 'orders';
```

---

## Examples

### Auditing a cluster for SASI indexes
```sql
-- Find all SASI indexes across all keyspaces
SELECT keyspace_name, table_name, index_name, options
FROM system_schema.indexes;

-- Filter results where options contains the SASI class name
-- (do this in your application or pipe through grep)
```

```bash
# From the command line via cqlsh:
cqlsh -e "SELECT keyspace_name, table_name, index_name, options FROM system_schema.indexes;" \
  | grep SASIIndex
```

### Full migration example
```sql
-- Before: SASI index on products.category
-- options shows: org.apache.cassandra.index.sasi.SASIIndex

DROP INDEX my_keyspace.products_category_idx;

CREATE INDEX products_by_category ON my_keyspace.products (category) USING 'sai';
```

---

## Pulse Check

> You're auditing an inherited Cassandra 5.0 cluster. You run:
>
> ```sql
> SELECT index_name, options FROM system_schema.indexes
> WHERE keyspace_name = 'inventory' AND table_name = 'products';
> ```
>
> And see:
> ```
> index_name          | options
> --------------------+----------------------------------------------------------
> products_name_idx   | {'class_name': 'org.apache.cassandra.index.sasi.SASIIndex'}
> products_sku_idx    | {'class_name': 'org.apache.cassandra.index.sai.StorageAttachedIndex'}
> ```
>
> **What action do you take, and what steps do you follow?**

*(Expected answer: `products_name_idx` is SASI — it must be migrated. `products_sku_idx` is SAI — no action needed. Steps: DROP INDEX inventory.products_name_idx; then CREATE INDEX products_name_idx ON inventory.products (name) USING 'sai'; then monitor the index build via the `system_views.indexes` virtual table. Schedule during low-traffic if name-based queries are critical.)*

---

## See Also

**In this session:**
- [SAI Overview — Why This Session Exists](./01-sai-overview.md)
- [What SAI Is and Why the Partition Key Rule Exists](./02-what-is-sai.md)
- [Creating and Managing SAI Indexes](./03-creating-managing-indexes.md)

**Reference:**
- [SAI FAQ (Apache Cassandra)](https://cassandra.apache.org/doc/latest/cassandra/developing/cql/indexing/sai/sai-faq.html)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
- [Cassandra 4.0 Notable Features](../../cassandra-4.0/notable-features.md)
- [SSTable Components](../../general/sstable-components.md)
