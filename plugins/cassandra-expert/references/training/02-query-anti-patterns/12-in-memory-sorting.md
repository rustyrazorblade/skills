# Topic: Sorting Partitions in Memory

## Objective
Recognize when an application is sorting Cassandra results in memory and understand why that's a signal the schema is wrong.

## Why This Matters
Cassandra already stores clustering columns in a defined sort order on disk. If your application fetches rows and then sorts them in memory, you are either (a) paying for work Cassandra already did, or (b) working around a table that was designed for the wrong access pattern. In both cases, the fix is usually a schema change, not a better in-memory sort.

---

## Concept

### How Cassandra Stores Rows Within a Partition

Rows within a partition are stored sorted by their **clustering columns**, in the order defined by the primary key (and optionally reversed with `CLUSTERING ORDER BY`). When you read a partition, Cassandra returns rows in that same order, for free. There is no "sort step" — the data is already on disk in the order you asked for.

```sql
CREATE TABLE events (
    user_id    uuid,
    event_time timestamp,
    kind       text,
    data       text,
    PRIMARY KEY (user_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);

-- Returns events newest-first, directly from disk. No sort.
SELECT * FROM events WHERE user_id = ?;
```

### The Anti-Pattern: In-Memory Sort After a Read

Application code that looks like this is a red flag:

```python
# ANTI-PATTERN: read, then sort in application memory
rows = session.execute(get_events, [user_id]).all()
rows.sort(key=lambda r: r.event_time, reverse=True)
```

The fact that the application had to sort means one of the following:

1. **The clustering column order is wrong.** Change the table's `CLUSTERING ORDER BY`.
2. **The sort key isn't a clustering column.** Either add it to the primary key as a clustering column, or create a second denormalized table whose primary key supports the required order.
3. **The rows come from multiple partitions.** You're reading across partitions and re-sorting the combined result — this is the worst case (see below).

### Why Cross-Partition Sorts Are the Worst Case

Cassandra does **not** sort across partitions. If you query multiple partitions (e.g. `WHERE user_id IN (?, ?, ?)`) and need the combined result sorted, Cassandra returns rows grouped by partition, not merged in order. Your application ends up loading all rows into memory, sorting them, and possibly discarding most of them — the same pathology as ALLOW FILTERING, just more obvious.

The fix is the same as for other multi-partition anti-patterns: model the data so the sort key lives inside a single partition, or use a dedicated analytics system for queries that truly span the whole dataset.

### What "Acceptable" Looks Like

In-memory sorting is only acceptable when:

- The result set is **small and bounded** (e.g. sorting 20 rows for display)
- The sort key is **derived at read time** from data that isn't known at write time (rare — usually a sign you should store the derived value)
- You're doing a **one-off ad-hoc query**, not production code

If the sort happens on every request, in hot-path code, on an unbounded result set — it's the anti-pattern.

---

## Examples

### Anti-pattern: sort after a full partition read

```python
# ANTI-PATTERN: clustering order is wrong, sorting in app
rows = session.execute("SELECT * FROM events WHERE user_id = ?", [user_id]).all()
rows.sort(key=lambda r: r.event_time, reverse=True)
for row in rows[:20]:
    display(row)
```

### Correct: fix the clustering order

```sql
CREATE TABLE events (
    user_id    uuid,
    event_time timestamp,
    kind       text,
    data       text,
    PRIMARY KEY (user_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```

```python
# Now the disk order is correct — no sort, LIMIT 20 reads only 20 rows
rows = session.execute(
    "SELECT * FROM events WHERE user_id = ? LIMIT 20",
    [user_id]
).all()
```

### Anti-pattern: sorting results from multiple partitions

```python
# ANTI-PATTERN: IN query returns rows grouped by partition, then sorted in app
rows = session.execute(
    "SELECT * FROM events WHERE user_id IN (?, ?, ?)",
    [u1, u2, u3]
).all()
rows.sort(key=lambda r: r.event_time, reverse=True)
```

### Correct: denormalize into a partition that matches the query

```sql
-- A second table keyed to answer "newest events across a group of users"
CREATE TABLE events_by_team (
    team_id    uuid,
    event_time timestamp,
    user_id    uuid,
    kind       text,
    data       text,
    PRIMARY KEY (team_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```

```python
rows = session.execute(
    "SELECT * FROM events_by_team WHERE team_id = ? LIMIT 20",
    [team_id]
).all()
```

### Acceptable: small bounded sort on display

```python
# Fine — result set is small and bounded, no schema redesign needed
recent = session.execute(get_recent_orders, [customer_id]).all()  # ~20 rows
recent.sort(key=lambda r: r.priority)  # re-sort for display only
```

---

## Pulse Check

> An application calls this query on every page load and sorts the results in Python by `created_at` descending before rendering:
>
> ```sql
> SELECT * FROM notifications WHERE user_id = ?;
> ```
>
> The table is defined as:
>
> ```sql
> CREATE TABLE notifications (
>     user_id    uuid,
>     notification_id uuid,
>     created_at timestamp,
>     message    text,
>     PRIMARY KEY (user_id, notification_id)
> );
> ```
>
> **What's wrong, and how would you fix it?**

*(Expected answer: The table's clustering column is `notification_id`, not `created_at` — so rows come back in UUID order, which is why the application has to re-sort. The fix is a schema change: either make `created_at` a clustering column (`PRIMARY KEY (user_id, created_at, notification_id)` with `CLUSTERING ORDER BY (created_at DESC, notification_id ASC)`), or create a second denormalized table keyed for the "newest notifications" access pattern. Sorting in the application on every page load is paying for work the database should be doing at write time.)*

---

## See Also

**In this session:**
- [ALLOW FILTERING](./02-allow-filtering.md)
- [In-Memory Joins on Large Datasets](./09-in-memory-joins.md)
- [Aggregation Queries](./04-aggregations.md)

**From other sessions:**
- [Pattern: Ordered Map](../01-fundamentals/18-pattern-ordered-map.md)
- [Pattern: Time Series](../01-fundamentals/19-pattern-time-series.md)
- [Denormalization](../01-fundamentals/20-denormalization.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Large Partitions](../../general/large-partitions.md)
