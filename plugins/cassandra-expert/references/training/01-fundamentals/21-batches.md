# Topic: BATCH — Logged, Unlogged, and When to Use Each

## Objective
Understand what Cassandra's `BATCH` statement does, the difference between logged and unlogged batches, and when each is the right tool.

## Why This Matters
BATCH is one of the most misunderstood features in Cassandra. Developers coming from relational databases assume BATCH is a performance feature — a way to bundle many inserts into fewer network round-trips, like a SQL bulk insert or a transaction. **It isn't, and treating it that way will slow your cluster down.** Batches in Cassandra are for atomicity (logged) or for same-partition write efficiency (unlogged), and using them anywhere else hurts performance instead of helping it.

---

## Concept

A `BATCH` groups multiple INSERT, UPDATE, and DELETE statements into a single CQL operation. It comes in three flavors:

- **`LOGGED BATCH`** — the default. Provides eventual atomicity across statements.
- **`UNLOGGED BATCH`** — no atomicity guarantee. Used as an optimization in one specific case.
- **`COUNTER BATCH`** — for batched counter updates; counters can't mix with non-counter writes.

### Logged Batches: What They're For

A logged batch guarantees that **all statements in the batch will eventually complete, or none will**. Cassandra achieves this by writing the batch to a **batchlog** (a replicated system table) on two coordinator replicas before executing. If the coordinator dies mid-batch, another node will replay the batchlog and finish the work.

```sql
BEGIN BATCH
    INSERT INTO users (user_id, email, name) VALUES (?, ?, ?);
    INSERT INTO users_by_email (email, user_id) VALUES (?, ?);
APPLY BATCH;
```

This is the right tool when writing to **multiple tables that must stay in sync** — the classic **denormalization** case from the previous topic, where the same logical write needs to land in two or three tables to support different query patterns. If one write lands and the other doesn't, your reads can return inconsistent state. The logged batch prevents that.

**What logged batches do NOT provide:**
- **Not isolation.** Other readers can see a partially-applied batch while it's in progress.
- **Not a transaction.** There is no rollback if one statement has a logical error. "Atomic" here only means "eventually all complete."
- **Not a performance optimization.** The batchlog adds latency and coordinator work. A logged batch is **slower** than firing the same statements as independent concurrent async writes.

### Unlogged Batches: The Single-Partition Optimization

An unlogged batch skips the batchlog entirely — there's no atomicity guarantee. A failed batch can leave partial state permanently.

There is exactly one case where an unlogged batch is a genuine performance win:

> **When every statement in the batch writes to the same partition key**, on the same table.

In that case, the coordinator can send one combined mutation to the replicas instead of N separate ones, saving network and coordinator overhead. Cassandra even automatically converts a single-partition logged batch into an unlogged one as an optimization.

```sql
-- Same user_id for every write → unlogged batch is a real optimization
BEGIN UNLOGGED BATCH
    INSERT INTO user_events (user_id, event_time, type) VALUES (?, ?, 'login');
    INSERT INTO user_events (user_id, event_time, type) VALUES (?, ?, 'page_view');
    INSERT INTO user_events (user_id, event_time, type) VALUES (?, ?, 'click');
APPLY BATCH;
```

If your statements span multiple partitions or tables, an unlogged batch actively hurts performance — see the anti-pattern section below.

### Counter Batches

Counter columns must be batched separately from other writes. Use `BEGIN COUNTER BATCH`:

```sql
BEGIN COUNTER BATCH
    UPDATE page_views SET views = views + 1 WHERE page_id = ?;
    UPDATE daily_views SET views = views + 1 WHERE day = ? AND page_id = ?;
APPLY BATCH;
```

The same caveats apply: counter updates are not idempotent, and a failed retry can double-count.

### The Big Anti-Pattern: BATCH as "Bulk Insert"

The most common misuse:

```sql
-- WRONG: 100 unrelated rows in one batch
BEGIN BATCH
    INSERT INTO users (user_id, name) VALUES (uuid1, ?);
    INSERT INTO users (user_id, name) VALUES (uuid2, ?);
    -- ... 98 more inserts
APPLY BATCH;
```

This looks like an optimization — fewer network round-trips, right? It's actually **slower and more harmful** than firing 100 independent writes. Here's why:

1. **The coordinator becomes a bottleneck.** All 100 inserts hit one node, which then has to forward them to the various partition owners. Without a batch, the driver's token-aware routing would send each write directly to its own replica.
2. **Coordinator memory and CPU pressure.** The batch has to be held in memory while it's being processed.
3. **Batch size warnings and failures.** Cassandra warns at 5KB of batch size by default and can fail the batch at 50KB. Large unrelated batches hit these limits.

**The correct answer for "many writes" is concurrent async operations**, typically with a semaphore to bound concurrency. That's covered in the query anti-patterns session.

### When To Use Each

| Situation | Use |
|-----------|-----|
| Many unrelated inserts/updates | **Concurrent async writes**, no batch |
| Multi-table atomic write (denormalized tables) | **Logged batch** (atomicity required) |
| Multiple writes to the same partition | **Unlogged batch** (real optimization) |
| Counter updates | **Counter batch** (required) |
| Single statement | No batch at all |

---

## Examples

### Logged batch for denormalized writes (atomicity matters)
```sql
-- A user record lives in two tables; they must stay in sync
BEGIN BATCH
    INSERT INTO users (user_id, email, name, created_at)
    VALUES (?, ?, ?, toTimestamp(now()));

    INSERT INTO users_by_email (email, user_id)
    VALUES (?, ?);
APPLY BATCH;
```

### Unlogged batch for same-partition writes (real optimization)
```sql
-- All writes target the same partition (same order_id)
BEGIN UNLOGGED BATCH
    INSERT INTO order_items (order_id, item_id, sku, qty) VALUES (?, ?, ?, ?);
    INSERT INTO order_items (order_id, item_id, sku, qty) VALUES (?, ?, ?, ?);
    INSERT INTO order_items (order_id, item_id, sku, qty) VALUES (?, ?, ?, ?);
APPLY BATCH;
```

### Python — logged batch for multi-table writes
```python
from cassandra.query import BatchStatement, BatchType

insert_user = session.prepare(
    "INSERT INTO users (user_id, email, name) VALUES (?, ?, ?)"
)
insert_by_email = session.prepare(
    "INSERT INTO users_by_email (email, user_id) VALUES (?, ?)"
)

def create_user(user_id, email, name):
    batch = BatchStatement(batch_type=BatchType.LOGGED)
    batch.add(insert_user, [user_id, email, name])
    batch.add(insert_by_email, [email, user_id])
    session.execute(batch)
```

### Java — logged batch for multi-table writes
```java
PreparedStatement insertUser = session.prepare(
    "INSERT INTO users (user_id, email, name) VALUES (?, ?, ?)"
);
PreparedStatement insertByEmail = session.prepare(
    "INSERT INTO users_by_email (email, user_id) VALUES (?, ?)"
);

public void createUser(UUID userId, String email, String name) {
    BatchStatement batch = BatchStatement.newInstance(BatchType.LOGGED)
        .add(insertUser.bind(userId, email, name))
        .add(insertByEmail.bind(email, userId));
    session.execute(batch);
}
```

### Go — logged batch for multi-table writes
```go
batch := session.NewBatch(gocql.LoggedBatch)
batch.Query(
    "INSERT INTO users (user_id, email, name) VALUES (?, ?, ?)",
    userID, email, name,
)
batch.Query(
    "INSERT INTO users_by_email (email, user_id) VALUES (?, ?)",
    email, userID,
)
if err := session.ExecuteBatch(batch); err != nil {
    return err
}
```

### Anti-pattern: batching to "speed up" bulk inserts
```python
# WRONG — 200 unrelated users in one logged batch
batch = BatchStatement(batch_type=BatchType.LOGGED)
for user in users:
    batch.add(insert_user, [user.id, user.email, user.name])
session.execute(batch)  # coordinator bottleneck, warnings, possible failure

# RIGHT — fire them as concurrent async writes with a concurrency limit
from cassandra.concurrent import execute_concurrent_with_args
execute_concurrent_with_args(
    session, insert_user,
    [(u.id, u.email, u.name) for u in users],
    concurrency=50,
)
```

---

## Pulse Check

> Your application needs to insert 500 sensor readings at startup — one row per reading, all different sensor IDs. A colleague writes a logged batch containing all 500 INSERT statements.
>
> **Is this a good idea? What should they do instead?**

*(Expected answer: No — it's an anti-pattern. 500 unrelated partitions in one batch creates coordinator bottleneck, may hit batch size warnings or failures, and is slower than the alternative. The correct pattern is concurrent async writes with a semaphore limiting concurrency to ~50. Logged batches are for atomic multi-table writes, not bulk loading.)*

> You're writing a denormalized `orders` + `orders_by_customer` design. Each order is inserted into both tables and must stay consistent — a reader should never see the order in one table but not the other (eventually).
>
> **Which batch type should you use, and why not just fire both writes concurrently without a batch?**

*(Expected answer: LOGGED BATCH. If you fire the writes independently and the coordinator crashes between them, one table is updated and the other isn't — permanent divergence until someone notices. A logged batch writes to the batchlog first, so even on coordinator failure another node replays and completes the work. You pay some latency for the guarantee, but that's the tradeoff for correctness.)*

> You're inserting 20 line items for the same order into the `order_items` table (all the same `order_id`, so all the same partition).
>
> **Which batch type, if any, should you use?**

*(Expected answer: UNLOGGED BATCH. Because every statement targets the same partition, the coordinator can combine them into a single mutation and send it once to the replicas instead of 20 times. This is the one case where unlogged batches are a real optimization. No atomicity guarantee is needed because it's all one partition — but that's OK because a single-partition logged batch gets auto-converted to unlogged by Cassandra anyway.)*

---

## See Also

**In this session:**
- [DML Basics — INSERT, UPDATE, DELETE, SELECT](./09-dml-basics.md)
- [Lightweight Transactions (LWT)](./22-lwt.md)
- [Denormalization](./20-denormalization.md)

**Reference:**
- [Batches](../../general/batches.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Drivers](../../general/drivers.md)
