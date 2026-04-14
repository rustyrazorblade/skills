# Topic: BATCH Misuse

## Objective
Understand what Cassandra batches actually do, why they are not a performance optimization, and when they are the correct tool.

## Why This Matters
Developers coming from relational databases assume batches improve performance by reducing round trips. In Cassandra, batches often make performance worse. They are a correctness tool — not a performance tool. Using them for the wrong reason adds overhead without benefit, and using them across multiple partitions can create significant coordinator pressure.

---

## Concept

### What Batches Actually Do

A Cassandra LOGGED batch:
1. Writes a batch log entry to two nodes before executing any statements
2. Executes all statements in the batch
3. Removes the batch log entry after all statements succeed

The batch log ensures **eventual completion** — if the coordinator fails mid-batch, another node will replay it. This is a durability guarantee, not an atomicity or isolation guarantee.

**Important**: batches do NOT provide isolation. Readers can observe partial batch state between statements executing.

An UNLOGGED batch:
- No batch log — no durability guarantee
- Statements execute without replay protection
- Slightly lower overhead than LOGGED
- Only useful for multiple writes to the **same partition**

### Why Batches Are Not a Performance Optimization

- **LOGGED batches add overhead**: two extra writes to the batch log before any statements execute
- **Multi-partition batches concentrate load**: the coordinator must handle all statements, route to multiple nodes, and track completion — this is more work, not less
- **No parallelism**: statements in a batch execute sequentially through the coordinator

Firing statements concurrently from the application is faster than batching them.

### When Batches Are the Correct Tool

**LOGGED batch: keeping multiple denormalized tables in sync**
```sql
-- If you must ensure all three writes eventually succeed:
BEGIN LOGGED BATCH
    INSERT INTO users (user_id, email) VALUES (?, ?);
    INSERT INTO users_by_email (email, user_id) VALUES (?, ?);
APPLY BATCH;
```

Use when a partial failure would leave your denormalized tables inconsistent and you need eventual convergence.

**UNLOGGED batch: multiple writes to the same partition**
```sql
-- Multiple column updates on the same partition key:
BEGIN UNLOGGED BATCH
    UPDATE user_settings SET value = ? WHERE user_id = ? AND key = 'theme';
    UPDATE user_settings SET value = ? WHERE user_id = ? AND key = 'language';
APPLY BATCH;
-- Same partition key — this is a minor convenience, not a big win
```

### What NOT to Do

```sql
-- ANTI-PATTERN: batching unrelated writes for "performance"
BEGIN LOGGED BATCH
    INSERT INTO orders (...) VALUES (...);
    INSERT INTO inventory (...) VALUES (...);
    INSERT INTO analytics_events (...) VALUES (...);
APPLY BATCH;
-- Three different partitions, possibly different nodes
-- Coordinator serializes all of this — slower than firing concurrently
```

---

## Examples

### Anti-pattern: batch for throughput
```python
# ANTI-PATTERN: assumes batch = faster
batch = BatchStatement(batch_type=BatchType.LOGGED)
for item in items:
    batch.add(insert_stmt, [item.id, item.value])
session.execute(batch)
# One coordinator handles everything serially through the batch log
```

```python
# CORRECT: concurrent async writes
from cassandra.concurrent import execute_concurrent_with_args

execute_concurrent_with_args(
    session,
    insert_stmt,
    [(item.id, item.value) for item in items],
    concurrency=50
)
```

### Correct: logged batch for denormalized table consistency
```python
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
    # If coordinator dies mid-batch, the batch log ensures eventual completion
```

---

## Pulse Check

> A developer is inserting 500 records into Cassandra and wraps them all in a single LOGGED batch, reasoning that "one network call is faster than 500."
>
> **Why is this wrong, and what should they do instead?**

*(Expected answer: A LOGGED batch first writes a batch log entry to two nodes, then executes all 500 statements serially through the coordinator — this is more overhead than individual writes, not less. There's also one network call per batch, but 500 serial operations inside it. The correct approach: fire 500 async queries concurrently with a concurrency limit (e.g., 50 at a time). This leverages the cluster's parallelism instead of bottlenecking through one coordinator.)*

---

## See Also

**In this session:**
- [Lightweight Transactions (LWT)](./06-lightweight-transactions.md)
- [Counters](./07-counters.md)
- [Triggers](./08-triggers.md)

**Reference:**
- [Batches](../../general/batches.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Prepared Statements](../../general/prepared-statements.md)
- [Drivers](../../general/drivers.md)
