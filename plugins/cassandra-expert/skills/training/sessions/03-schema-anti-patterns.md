# Session 3: Schema Design Anti-Patterns

**Audience:** Developers who have completed Fundamentals.
**Goal:** Recognize schema design mistakes during the design phase — before they reach production — and understand the correct alternatives.

---

## Section 1: Partition Problems

| # | Topic | Reference File |
|---|-------|---------------|
| 1 | Huge Partitions | `references/training/03-schema-anti-patterns/01-huge-partitions.md` |
| 2 | Hot Partitions | `references/training/03-schema-anti-patterns/02-hot-partitions.md` |

## Section 2: Table and Column Design

| # | Topic | Reference File |
|---|-------|---------------|
| 3 | Too Many Tables | `references/training/03-schema-anti-patterns/03-too-many-tables.md` |
| 4 | Too Many Columns | `references/training/03-schema-anti-patterns/04-too-many-columns.md` |

## Section 3: Features That Cause More Problems Than They Solve

| # | Topic | Reference File |
|---|-------|---------------|
| 5 | Materialized Views | `references/training/03-schema-anti-patterns/05-materialized-views.md` |
| 6 | Unbounded Collections | `references/training/03-schema-anti-patterns/06-unbounded-collections.md` |
| 7 | Lists | `references/training/03-schema-anti-patterns/07-lists.md` |
| 8 | Secondary Indexes Without Partition Keys | `references/training/03-schema-anti-patterns/08-secondary-indexes.md` |

## Section 4: Operational Anti-Patterns

| # | Topic | Reference File |
|---|-------|---------------|
| 9 | Incorrect Compaction Strategy | `references/training/03-schema-anti-patterns/09-compaction-strategy.md` |
| 10 | Large Blob Storage | `references/training/03-schema-anti-patterns/10-large-blobs.md` |

---

## Session Introduction Script

> Every schema starts out looking reasonable. The problems appear at scale — and by then, they're expensive to fix. Huge partitions, hot spots, materialized views that can't be repaired, collections that grow without bound: these are the mistakes that turn a well-intentioned schema into a production incident.
>
> This session is about pattern recognition. We'll look at each anti-pattern, understand why it seems reasonable at first, and learn the correct alternative. The goal is to catch these decisions during design review — not during an outage.

## Session Recap (deliver at end)

1. **Huge partitions**: always bound partition size through bucketing or sharding. Target under 10MB, hard limit 100MB.
2. **Hot partitions**: high-traffic small data belongs in a cache, not a single Cassandra partition.
3. **Too many tables**: prefer fewer, wider tables over hundreds of narrow ones.
4. **Too many columns**: when a row has hundreds of dynamic columns, serialize to a blob or use a map.
5. **Materialized views**: never use in production — they can't be repaired. Denormalize manually.
6. **Unbounded collections**: collections that grow forever become partitions that grow forever. Use a table instead.
7. **Lists**: avoid lists; use sets (dedup) or maps (keyed access) instead.
8. **Secondary indexes without partition keys**: always include the partition key or use a denormalized table.
9. **Compaction strategy**: use UCS on 5.0+. Never use STCS on 5.0+. On older versions, prefer LCS — STCS has a narrow niche for write-heavy workloads with frequent overwrites where LCS can't keep up; otherwise avoid it.
10. **Large blobs**: store data in object storage (S3, GCS). Store the reference link in Cassandra.
