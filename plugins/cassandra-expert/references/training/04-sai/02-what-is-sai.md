# Topic: What SAI Is and Why the Partition Key Rule Exists

## Objective
Understand how SAI works at the storage layer and why queries without the partition key degrade as data grows.

## Why This Matters
SAI is powerful, but its performance characteristics are fundamentally different from a dedicated table. Developers who don't understand the SSTable search model will write queries that work fine in development and degrade silently in production as data accumulates. The partition key rule is not a suggestion — it's the difference between O(1) and O(N) at cluster scale.

---

## Concept

### How SAI Works

Cassandra stores data in immutable files called **SSTables**. When you create an SAI index on a column, Cassandra builds a per-SSTable index file alongside each SSTable. When a new SSTable is written (flush or compaction), a new index file is built for it.

```
SSTable 1  →  SAI index file 1
SSTable 2  →  SAI index file 2
SSTable 3  →  SAI index file 3
...
```

When you query using an SAI index, Cassandra must search the index files to find matching rows.

### The Partition Key Problem

**Without the partition key**, Cassandra has no way to know which SSTables could contain your data. It must search the index files of every SSTable on every node. As your dataset grows and more SSTables accumulate, the number of index files to search grows with it:

```
Query WITHOUT partition key:
→ Coordinator fans out concurrently to every node; each node searches every index file for every SSTable it owns
→ Cost = O(N) where N = total SSTables in the cluster
→ Gets slower as data grows
```

**With the partition key**, Cassandra first determines which node and which SSTables own that partition. SAI only searches the index files for those SSTables — a small, bounded set:

```
Query WITH partition key:
→ Hash partition key → identify owning node and SSTables
→ Search only those index files
→ Cost = O(1) at cluster scale
→ Stays fast regardless of total dataset size
```

### The Rule

**Always include the partition key in SAI queries.** If you can't guarantee the partition key will be present, you need a different approach — either a dedicated denormalized table, or a rethink of the data model.

### What About SASI?

SASI (Storage-Attached SSTable Indexes) is the original, legacy implementation that predates SAI. Never use SASI — it has serious performance and correctness problems. If you see `USING 'org.apache.cassandra.index.sasi.SASIIndex'` in a schema, treat it as a bug to fix.

Always use SAI: `USING 'sai'`.

### Vector Search

SAI also supports vector similarity search. Do not use Cassandra for vector search in production — it has known stability problems and performs poorly compared to purpose-built vector databases (Weaviate, Qdrant, Milvus, pgvector). Cassandra is the wrong tool for this use case.

---

## Examples

### The same query — with and without partition key

```sql
CREATE TABLE orders (
    customer_id uuid,
    order_id    uuid,
    status      text,
    total       decimal,
    created_at  timestamp,
    PRIMARY KEY (customer_id, order_id)
);

CREATE INDEX orders_by_status ON orders (status) USING 'sai';

-- GOOD: partition key present → SAI searches only this customer's SSTables
SELECT * FROM orders
WHERE customer_id = ?
  AND status = 'pending';

-- BAD: no partition key → SAI searches ALL SSTables in the cluster
-- Works in dev, degrades in production as data grows
SELECT * FROM orders
WHERE status = 'pending';
```

### Checking how many SSTables a table has
```bash
nodetool tablestats <keyspace>.<table>
# Look for: "SSTable count"
# Each SSTable means one more index file SAI must search without a partition key
```

---

## Pulse Check

> You have a `products` table with partition key `category` and an SAI index on `price`. Your query is:
>
> ```sql
> SELECT * FROM products WHERE price < 50.00;
> ```
>
> **What's the problem with this query, and how would you fix it?**

*(Expected answer: The query has no partition key. SAI must search index files across all SSTables in the cluster — O(N) cost that degrades as data grows. Fix: always include the partition key. For example: `WHERE category = ? AND price < 50.00`. If you need to search across all categories, a dedicated table or a different data model is the right answer — not an SAI query without a partition key.)*

---

## See Also

**In this session:**
- [SAI Overview — Why This Session Exists](./01-sai-overview.md)
- [Creating and Managing SAI Indexes](./03-creating-managing-indexes.md)
- [Querying with SAI — Patterns and Anti-Patterns](./04-querying-with-sai.md)
- [SAI vs. Denormalization](./05-sai-vs-denormalization.md)
- [SASI — What It Is and Why to Avoid It](./06-sasi-never-use.md)

**Reference:**
- [SAI FAQ (Apache Cassandra)](https://cassandra.apache.org/doc/latest/cassandra/developing/cql/indexing/sai/sai-faq.html)
- [SSTable Components](../../general/sstable-components.md)
- [Compaction](../../general/compaction.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
