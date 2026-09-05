# Topic: SAI Overview — Why This Session Exists

## Objective
Orient the learner to what Storage-Attached Indexes (SAI) are, why Cassandra has them, and what this session will and will not cover.

## Why This Matters
In the Fundamentals session, the rule was "one table per access pattern." Every new query shape meant a new table. That rule is still right — denormalization is Cassandra's primary tool for serving fast queries. But there is a limited escape hatch for queries that don't justify a dedicated table, and that escape hatch is **SAI**.

Before diving into mechanics, it's worth understanding what SAI is trying to solve and the one rule that separates SAI done well from SAI used as a footgun.

---

## Concept

### Where SAI Fits

Cassandra's data model is the query plan. If you want to filter rows by a column, the normal answer is "make that column part of the primary key" — either by choosing it as the partition key, or by adding it as a clustering column. That's denormalization, and it's covered in the Fundamentals session.

SAI is for cases where denormalization is overkill:

- You already have the partition key in the query, but you want to filter further on another column.
- The query is low-volume enough that maintaining a second table isn't worth the write amplification.
- The filter column is added after the table already exists, and a schema redesign isn't practical.

SAI lets you add a secondary filter *without* a full table scan and *without* a new denormalized table — as long as you follow the rules.

### What SAI Is

**SAI (Storage-Attached Indexes)** is an indexing feature introduced in Cassandra 5.0. It builds index files that live alongside SSTables on disk — one index file per SSTable — so that filtering a query by an indexed column only requires touching those index files, not the raw SSTable data.

The syntax is deliberately simple:

```sql
CREATE INDEX users_by_email ON users (email) USING 'sai';
```

The next topic ([What SAI Is and Why the Partition Key Rule Exists](./02-what-is-sai.md)) covers *how* this works at the storage layer, and why the partition key rule exists.

### The One Rule

**Always include the partition key in SAI queries.**

This is the rule that separates SAI used correctly from SAI used as a footgun. Without the partition key, SAI has to search every SSTable on every node, and performance degrades as the dataset grows — silently and at production scale. With the partition key, SAI only searches the SSTables that could contain the partition, which is a small and bounded set.

The next topic explains why, in detail. For now: commit the rule to memory and build a habit of checking for the partition key every time you write an SAI query.

### What This Session Covers

| Topic | What you'll learn |
|---|---|
| [What SAI Is](./02-what-is-sai.md) | The per-SSTable storage model and why the partition key rule exists. |
| [Creating and Managing SAI Indexes](./03-creating-managing-indexes.md) | Syntax, naming, building, dropping, and operational considerations. |
| [Querying with SAI](./04-querying-with-sai.md) | Query patterns that work, patterns that don't, and how to identify problem queries. |
| [SAI vs. Denormalization](./05-sai-vs-denormalization.md) | When to use SAI and when to reach for a dedicated table instead. |
| [SASI — Never Use](./06-sasi-never-use.md) | How to identify SASI in existing schemas and migrate it to SAI. |

### What This Session Does NOT Cover

- **Vector search.** SAI supports vector similarity search (`ANN OF`) on vector columns. **Do not use Cassandra for vector search in production.** Serious use of vector tables has been observed to cause cluster instability — see [CASSANDRA-20809](https://issues.apache.org/jira/browse/CASSANDRA-20809) for a representative example (a COPY TO export crashes the node on a table with vector columns) — and performance lags well behind purpose-built vector databases. If you need vector search, use Weaviate, Qdrant, Milvus, pgvector, or OpenSearch — not Cassandra. Re-evaluate in future releases; this session will not teach you how to build vector search on Cassandra because you should not.
- **The internals of the index file format.** We care about observable behavior and query performance, not the on-disk layout of posting lists.
- **Legacy secondary indexes in depth.** They're covered as an anti-pattern in the Schema Anti-Patterns session. If you have them, migrate to SAI; don't maintain them.

---

## Pulse Check

> You're building a new feature on an existing `orders` table, partitioned by `customer_id`. The product team wants you to add a filter for "show me orders of status 'pending' for this customer." You estimate the query will run a few dozen times per hour per active customer.
>
> **Is this a case for a new denormalized table, or for SAI? What's the deciding factor?**

*(Expected answer: This is a reasonable case for SAI. The query always includes the partition key (`customer_id`), the query volume is modest, and building a second denormalized table would add write amplification on every order insert just to support an occasional filter. The deciding factors are: (1) the partition key is always present in the query — required for SAI; (2) the query is not hot enough to justify the write cost of a denormalized table; (3) the filter column (`status`) is one that SAI handles well. The next topics will walk through how to set this up correctly.)*

---

## See Also

**In this session:**
- [What SAI Is and Why the Partition Key Rule Exists](./02-what-is-sai.md)
- [Creating and Managing SAI Indexes](./03-creating-managing-indexes.md)
- [Querying with SAI — Patterns and Anti-Patterns](./04-querying-with-sai.md)
- [SAI vs. Denormalization](./05-sai-vs-denormalization.md)
- [SASI — What It Is and Why to Avoid It](./06-sasi-never-use.md)

**From other sessions:**
- [Denormalization](../01-fundamentals/20-denormalization.md)
- [Secondary Indexes Without Partition Keys](../03-schema-anti-patterns/08-secondary-indexes.md)

**Reference:**
- [SAI FAQ (Apache Cassandra)](https://cassandra.apache.org/doc/latest/cassandra/developing/cql/indexing/sai/sai-faq.html)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
- [SSTable Components](../../general/sstable-components.md)
