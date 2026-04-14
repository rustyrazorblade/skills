# Session 2: Query & Application Anti-Patterns

**Audience:** Developers who have completed Fundamentals.
**Goal:** Recognize runtime and application-level mistakes that turn a well-designed schema into a performance disaster, and master the correct patterns.

---

## Section 1: Query Anti-Patterns

| # | Topic | Reference File |
|---|-------|---------------|
| 1 | IN() Queries | `references/training/02-query-anti-patterns/01-in-queries.md` |
| 2 | ALLOW FILTERING | `references/training/02-query-anti-patterns/02-allow-filtering.md` |
| 3 | Token Range Queries | `references/training/02-query-anti-patterns/03-token-range-queries.md` |
| 4 | Aggregations (incl. UDAs) | `references/training/02-query-anti-patterns/04-aggregations.md` |

## Section 2: Write Anti-Patterns

| # | Topic | Reference File |
|---|-------|---------------|
| 5 | BATCH Misuse | `references/training/02-query-anti-patterns/05-batch-misuse.md` |
| 6 | Lightweight Transactions | `references/training/02-query-anti-patterns/06-lightweight-transactions.md` |
| 7 | Counters | `references/training/02-query-anti-patterns/07-counters.md` |
| 8 | Triggers | `references/training/02-query-anti-patterns/08-triggers.md` |

## Section 3: Application Anti-Patterns

| # | Topic | Reference File |
|---|-------|---------------|
| 9 | In-Memory Joins on Large Datasets | `references/training/02-query-anti-patterns/09-in-memory-joins.md` |
| 10 | Synchronous (Blocking) Queries | `references/training/02-query-anti-patterns/10-synchronous-queries.md` |
| 11 | Excessive Async Operations | `references/training/02-query-anti-patterns/11-excessive-async.md` |
| 12 | Sorting Partitions in Memory | `references/training/02-query-anti-patterns/12-in-memory-sorting.md` |

---

## Session Introduction Script

> A good schema is necessary but not sufficient. The way you query and interact with Cassandra matters just as much. ALLOW FILTERING can scan an entire cluster. IN() queries funnel a scatter-gather through a single coordinator. Synchronous blocking calls turn a fast database into a slow one. Excessive parallelism overwhelms the cluster in the other direction.
>
> This session covers the runtime anti-patterns — the ones that show up in application code and query patterns. We'll look at each one, understand why it's dangerous, and learn the right alternative.

## Session Recap (deliver at end)

1. **IN() queries**: a sub-optimal scatter-gather — one coordinator runs every lookup. Fire the individual queries concurrently from the application instead.
2. **ALLOW FILTERING**: never in production. Model around it or use a search system like OpenSearch.
3. **Token range queries**: use a dedicated analytics solution or the Spark bulk reader.
4. **Aggregations**: `COUNT`/`SUM`/`AVG` run single-threaded on one coordinator. UDAs are the same trap with extra security and stability risks. Pre-compute, aggregate in the app, or use Spark + the cassandra-analytics bulk reader.
5. **BATCH misuse**: batches are not a performance optimization. Use them to keep multiple tables in sync, not for throughput.
6. **Lightweight Transactions**: use sparingly — they are significantly slower than regular writes. Understand the cost before using.
7. **Counters**: potentially inaccurate under failure conditions. Use when small deviations are acceptable.
8. **Triggers**: run arbitrary Java against unstable internals in the write path, on the coordinator only, with no atomicity or retry guarantees. Use CDC or do the extra writes from the application.
9. **In-memory joins**: denormalize instead of fetching large datasets and joining in the application.
10. **Synchronous queries**: always use async. Blocking on Cassandra calls in a request handler kills throughput.
11. **Excessive async**: limit concurrency with a semaphore — unbounded async overwhelms the cluster.
12. **In-memory sorting**: use clustering columns. If you're sorting rows after reading them, the table is wrong.
