# Topic: Lightweight Transactions (LWT)

## Objective
Understand what a lightweight transaction (LWT) is, what it guarantees, the performance cost involved, and when it's the right choice over alternative patterns.

## Why This Matters
Cassandra's writes are normally last-write-wins with no read-before-write — that's what makes them fast. LWTs break that model: they provide compare-and-set (CAS) semantics using a Paxos protocol that requires multiple round trips between replicas. They're the only way to make certain classes of decisions safely, but they're also much slower than regular writes, and developers who don't understand the cost tend to use them everywhere. Knowing when LWTs are genuinely required — and when they're not — is critical.

---

## Concept

A **lightweight transaction** is a conditional write. The statement includes an `IF` clause, and Cassandra will execute the write only if the condition holds:

```sql
INSERT INTO users (user_id, email, name)
VALUES (?, ?, ?)
IF NOT EXISTS;

UPDATE accounts
SET balance = ?
WHERE account_id = ?
IF balance = ?;
```

In both cases, Cassandra must **read the existing state, decide whether the condition is met, and write only if it is** — all atomically, across replicas. This is the compare-and-set primitive you'd use in a concurrent system, brought to a distributed database.

### How LWTs Work (Paxos)

LWTs are implemented using a Paxos-based protocol. Every LWT goes through roughly four phases between the coordinator and the replicas:

1. **Prepare** — the coordinator asks the replicas to agree on a proposal number
2. **Read** — replicas return their current value and the highest proposal they've seen
3. **Propose** — the coordinator sends the new value with its proposal number
4. **Commit** — if accepted, replicas commit the value

This requires **four round trips** under normal conditions (compared to **one** for a regular write). Under contention — when multiple clients try to LWT the same row concurrently — the cost goes up further because proposals can be rejected and retried.

**Rough rule of thumb: LWTs are 4–10x slower than regular writes in the uncontended case and much worse under contention.** They are not free, and they are not "just a conditional write."

### Consistency Level for LWTs

LWTs use a special **serial consistency level** for the Paxos phase. There are two:

- **`SERIAL`** — quorum of all replicas across all datacenters
- **`LOCAL_SERIAL`** — quorum of replicas in the local datacenter only (strongly preferred for multi-DC)

You set this via the driver (Java/Python/Go) in addition to the regular consistency level. In multi-datacenter setups, **use `LOCAL_SERIAL`** to avoid cross-DC latency on every LWT.

### Valid Use Cases for LWTs

LWTs are the right tool when a decision must be **atomic across concurrent writers** and there is no workaround via schema design:

- **Unique constraint enforcement**: "Create this user account only if the email is not already taken" — `INSERT ... IF NOT EXISTS`
- **State machines**: "Transition this order from 'pending' to 'shipped' only if it's currently 'pending'" — `UPDATE ... IF status = 'pending'`
- **Optimistic concurrency / CAS**: "Update this row only if its version number matches what I last read"
- **Leader election / leasing**: Token-based mutual exclusion, with a TTL on the lease row

In all of these cases, the alternative — read then write — has a race condition window where two clients can read the same state and both write, corrupting the invariant.

### What LWTs Are NOT For

LWTs are **not** a general solution to "I want to be sure my write applied":
- They are not a replacement for `LOCAL_QUORUM` writes
- They are not a transaction mechanism for multi-row or multi-table updates (they're single-row only)
- They are not an optimization for read-then-write patterns that don't have a race condition

If you're using LWTs because "it feels safer," you're paying a large performance cost for nothing. Use them when you need them, and only then.

### Caveats and Pitfalls

- **Not cross-row or cross-table.** An LWT applies to one row. If you need atomicity across multiple rows or tables, that's what logged batches are for (and even those are only "eventual" atomicity, not ACID).
- **Retries are tricky.** LWT writes are not idempotent in the same way regular writes are — if you retry after a timeout, you need to check whether the write applied using the response, not blindly re-issue.
- **Contention is expensive.** If many clients LWT the same row concurrently, Paxos proposals collide and retry. Under heavy contention, LWT throughput can collapse.
- **Counter updates can't use LWTs.** Counters are a separate operation type and have their own atomicity model.

### Understanding the Return Value

LWT statements return a result row indicating whether the condition was met:

```sql
cqlsh> INSERT INTO users (user_id, email) VALUES (uuid(), 'alice@example.com') IF NOT EXISTS;

 [applied]
-----------
      True
```

If the condition fails, the return includes the current values of the columns involved so you can decide what to do next:

```sql
cqlsh> INSERT INTO users (user_id, email) VALUES (uuid(), 'alice@example.com') IF NOT EXISTS;

 [applied] | user_id  | email
-----------+----------+------------------
     False | some-uid | alice@example.com
```

Your application code must check `[applied]` — a "failed" LWT is not an error, it's a normal outcome meaning the condition wasn't met.

---

## Examples

### Unique account creation (IF NOT EXISTS)
```sql
-- Create the user only if this user_id hasn't been taken
INSERT INTO users (user_id, email, name)
VALUES (?, ?, ?)
IF NOT EXISTS;
```

### State machine transition
```sql
-- Only ship the order if it's still pending
UPDATE orders
SET status = 'shipped', shipped_at = toTimestamp(now())
WHERE order_id = ?
IF status = 'pending';
```

### Optimistic concurrency with version column
```sql
-- Update only if the version matches what we last read
UPDATE documents
SET content = ?, version = ?
WHERE doc_id = ?
IF version = ?;
```

### Python — checking the applied result
```python
insert_user = session.prepare("""
    INSERT INTO users (user_id, email, name) VALUES (?, ?, ?)
    IF NOT EXISTS
""")

def create_user(email, name):
    user_id = uuid.uuid4()
    result = session.execute(insert_user, [user_id, email, name]).one()
    if not result.applied:
        # The user_id was already taken — extremely rare with uuid4
        raise ValueError("collision, retry")
    return user_id
```

### Java — using LOCAL_SERIAL for multi-DC
```java
PreparedStatement updateStatus = session.prepare(
    "UPDATE orders SET status = ? WHERE order_id = ? IF status = ?"
);

// Use LOCAL_SERIAL to avoid cross-DC Paxos latency
BoundStatement bound = updateStatus.bind("shipped", orderId, "pending")
    .setSerialConsistencyLevel(DefaultConsistencyLevel.LOCAL_SERIAL);

ResultSet rs = session.execute(bound);
Row row = rs.one();
if (!row.getBoolean("[applied]")) {
    // Order was already shipped (or in some other state) — not an error
    log.info("Order {} could not be shipped: {}", orderId, row.getString("status"));
}
```

### Go — checking the result
```go
applied, err := session.Query(
    `UPDATE orders SET status = ? WHERE order_id = ? IF status = ?`,
    "shipped", orderID, "pending",
).SerialConsistency(gocql.LocalSerial).ScanCAS()

if err != nil {
    return err
}
if !applied {
    // Condition wasn't met — log and move on
    log.Printf("order %s already in a non-pending state", orderID)
}
```

---

## Pulse Check

> A team is using LWTs on every write to a user profile table "to be safe." They're seeing high p99 latencies and their cluster is CPU-bound under modest load.
>
> **What's happening, and what would you suggest?**

*(Expected answer: LWTs require a Paxos round — roughly 4x the work of a regular write, plus contention penalties. Using LWTs for writes that don't actually need compare-and-set semantics is wasted cost. For normal profile updates, `LOCAL_QUORUM` gives strong consistency (write + read at LOCAL_QUORUM is read-your-writes safe) without Paxos. Reserve LWTs for the cases that genuinely need atomic decisions — uniqueness, state transitions, CAS — and use LOCAL_QUORUM for everything else.)*

> You're building user signup. Email must be unique. A colleague proposes: first `SELECT ... FROM users_by_email WHERE email = ?`, then if no row exists, INSERT. Another colleague suggests `INSERT ... IF NOT EXISTS`.
>
> **Which is correct, and why is the other wrong?**

*(Expected answer: Use `INSERT ... IF NOT EXISTS` (an LWT). The SELECT-then-INSERT pattern has a race: two signups with the same email can both read "no existing row" at the same time and both proceed to INSERT, creating duplicate accounts. LWTs close this window because the check and the write happen atomically via Paxos. This is one of the canonical valid use cases for an LWT, and the performance cost is worth it because signup is low-volume and correctness matters.)*

> You need to transition an order through states: pending → paid → shipped → delivered. Two instances of a worker might simultaneously try to advance the same order.
>
> **How would you prevent double-processing, and what's the LWT statement you'd write?**

*(Expected answer: `UPDATE orders SET status = 'paid' WHERE order_id = ? IF status = 'pending';` — and check `[applied]`. Only one worker will succeed; the other will see the condition as false and know another worker already advanced the state. This is a classic state machine use of LWTs — no race condition, no locking needed, just compare-and-set on the state column.)*

---

## See Also

**In this session:**
- [DML Basics — INSERT, UPDATE, DELETE, SELECT](./09-dml-basics.md)
- [Batches](./21-batches.md)
- [Consistency Levels](./15-consistency-levels.md)

**Reference:**
- [Lightweight Transactions (LWT)](../../general/lwt.md)
- [Consistency Levels](../../general/consistency-levels.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
