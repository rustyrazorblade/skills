# Session 4: Storage-Attached Indexes (SAI)

**Audience:** Developers who have completed the Fundamentals session.
**Goal:** Understand how SAI works, use it correctly, recognize its limits, and avoid legacy SASI indexes.

---

## Section 1: SAI Fundamentals

| # | Topic | Reference File |
|---|-------|---------------|
| 1 | SAI Overview — Why This Session Exists | `references/training/04-sai/01-sai-overview.md` |
| 2 | What SAI Is and Why the Partition Key Rule Exists | `references/training/04-sai/02-what-is-sai.md` |
| 3 | Creating and Managing SAI Indexes | `references/training/04-sai/03-creating-managing-indexes.md` |
| 4 | Querying with SAI — Patterns and Anti-Patterns | `references/training/04-sai/04-querying-with-sai.md` |

## Section 2: Design Decisions

| # | Topic | Reference File |
|---|-------|---------------|
| 5 | SAI vs. Denormalization — Choosing the Right Tool | `references/training/04-sai/05-sai-vs-denormalization.md` |
| 6 | SASI — What It Is and Why to Avoid It | `references/training/04-sai/06-sasi-never-use.md` |

---

## Session Introduction Script

> In the Fundamentals session you learned that Cassandra's data model is the query plan — one table per access pattern. SAI gives you a limited escape hatch: the ability to filter on non-primary-key columns without a separate table.
>
> But SAI comes with a rule that cannot be broken: always include the partition key. Without it, SAI's performance degrades as your data grows — and it does so silently, which makes it one of the more dangerous mistakes to make in Cassandra.
>
> We'll cover how SAI works, how to use it correctly, when to prefer it over denormalization, and how to identify and migrate the legacy SASI implementation you'll encounter in older clusters.

## Session Recap (deliver at end)

1. **SAI is per-SSTable**: index files are attached to each SSTable. Without a partition key, Cassandra must search all of them — O(N) at cluster scale.
2. **Always include the partition key** in SAI queries. No exceptions.
3. **Named indexes**: always name your indexes. Unnamed indexes are hard to manage.
4. **SAI vs. denormalization**: use SAI for infrequent, flexible queries with the partition key present. Denormalize for high-throughput, latency-sensitive paths.
5. **Never use SASI**: if you find it, migrate it to SAI immediately.
6. **No vector search**: Cassandra's SAI-based vector search has stability problems. Use a purpose-built vector database.
