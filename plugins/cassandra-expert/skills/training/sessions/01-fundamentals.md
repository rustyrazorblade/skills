# Session 1: Cassandra Fundamentals

**Audience:** Developers new to Cassandra or unsure of the basics.
**Goal:** Understand how Cassandra stores and distributes data, how to design tables correctly, and how to write applications that use Cassandra well.

---

## Section 1: Cluster and Schema Fundamentals

| # | Topic | Reference File |
|---|-------|---------------|
| 1 | Distribution of Data in a Cluster | `references/training/01-fundamentals/01-data-distribution.md` |
| 2 | Keyspaces | `references/training/01-fundamentals/02-keyspaces.md` |
| 3 | Basic Types | `references/training/01-fundamentals/03-types.md` |
| 4 | Tables and the Primary Key | `references/training/01-fundamentals/04-tables-primary-key.md` |
| 5 | Partition Storage | `references/training/01-fundamentals/05-partition-storage.md` |
| 6 | Partition Keys and Clustering Columns | `references/training/01-fundamentals/06-partition-key-clustering.md` |
| 7 | Advanced Types (Collections, Static, Counters) | `references/training/01-fundamentals/07-advanced-types.md` |
| 8 | User-Defined Types (UDTs) | `references/training/01-fundamentals/08-udts.md` |
| 9 | DML Basics (INSERT, UPDATE, DELETE, SELECT) | `references/training/01-fundamentals/09-dml-basics.md` |
| 10 | The Read and Write Paths | `references/training/01-fundamentals/10-read-write-paths.md` |
| 11 | Tombstones | `references/training/01-fundamentals/11-tombstones.md` |
| 12 | Table Options | `references/training/01-fundamentals/12-table-options.md` |
| 13 | Compaction Overview and UCS | `references/training/01-fundamentals/13-compaction-overview.md` |
| 14 | TTL (Time-To-Live) | `references/training/01-fundamentals/14-ttl.md` |
| 15 | Consistency Levels | `references/training/01-fundamentals/15-consistency-levels.md` |
| 16 | Prepared Statements | `references/training/01-fundamentals/16-prepared-statements.md` |

## Section 2: Table Patterns

| # | Topic | Reference File |
|---|-------|---------------|
| 17 | Single Key Pattern | `references/training/01-fundamentals/17-pattern-single-key.md` |
| 18 | Ordered Map Pattern | `references/training/01-fundamentals/18-pattern-ordered-map.md` |
| 19 | Time Series Pattern | `references/training/01-fundamentals/19-pattern-time-series.md` |

## Section 3: Denormalization and Consistency

| # | Topic | Reference File |
|---|-------|---------------|
| 20 | Denormalization | `references/training/01-fundamentals/20-denormalization.md` |
| 21 | BATCH — Logged, Unlogged, and When to Use Each | `references/training/01-fundamentals/21-batches.md` |
| 22 | Lightweight Transactions (LWT) | `references/training/01-fundamentals/22-lwt.md` |

---

## Session Introduction Script

> Welcome to Cassandra Fundamentals. Before we dive in, I want to tell you a bit about what we're going to cover and — more importantly — *why* we're covering it in this order.
>
> This session touches three things: **architecture**, **data modeling**, and **query patterns**. In a relational database you can mostly treat these as separate concerns — you learn SQL, you design tables against third normal form, and the database figures out how to execute your queries efficiently. Cassandra doesn't work that way. These three are deeply interrelated, and you can't make good decisions about any one of them without understanding the other two.
>
> - **Architecture** — how data is distributed across nodes, how writes and reads flow through the cluster, how replicas reconcile. This isn't "ops trivia" you can skip as a developer. It dictates the rules of data modeling.
> - **Data modeling** — how you lay out partitions, choose clustering columns, and design tables. Every choice here is a direct consequence of the architecture. A partition key isn't just an identifier; it's the thing that decides which node your data lives on and whether your workload creates hot spots.
> - **Query patterns** — what queries you're allowed to run efficiently, and what queries will burn the cluster down. In Cassandra, the query patterns you need *drive the table design*, not the other way around. There's no query planner to save you — if the table isn't designed for the query, the query either doesn't work or takes down production.
>
> Because of this feedback loop — architecture constrains modeling, modeling dictates queries, queries shape modeling — we'll weave between all three throughout the session rather than treating them as separate chapters. Most problems people hit with Cassandra come from applying relational thinking to a distributed system and trying to learn these pieces in isolation. The goal here is to build the right mental model from the start so these decisions feel natural instead of arbitrary.
>
> By the end you'll understand how Cassandra distributes data across a cluster, how to design partitions and tables that perform well under real workloads, and how to write application code that uses Cassandra correctly.
>
> We'll go through 22 topics across 4 sections. Each topic ends with a quick question to make sure the concept landed before we move on.
>
> **Ask questions any time.** If something is unclear, or you're curious about a detail we haven't covered yet, or you want to know how something applies to your specific situation — just ask. I can look up anything in the reference material and bring it back to the conversation. Training is more useful when it's a dialogue, not a lecture.

## Session Recap (deliver at end)

Key takeaways from Cassandra Fundamentals:

1. **Data distribution**: The partition key determines which node owns your data. Choose it to distribute load evenly.
2. **Partition size**: Target under 10MB. Partitions over 100MB cause real problems.
3. **Table design = query plan**: Design tables around your queries, not your entities. Denormalize.
4. **Table patterns**: Single key for lookups, ordered map for range access, time series for time-bucketed append-only data.
5. **UCS**: Use Unified Compaction Strategy on Cassandra 5.0+.
6. **Prepared statements**: Always prepare. Go does it automatically; Java and Python do not.
7. **Consistency**: QUORUM/QUORUM for strong consistency. LOCAL_QUORUM for multi-DC.
