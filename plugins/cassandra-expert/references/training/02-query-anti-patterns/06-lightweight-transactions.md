# Topic: Lightweight Transactions (LWT)

## Objective
Understand what Lightweight Transactions do, how much they cost, and when they are and aren't the right tool.

## Why This Matters
Lightweight Transactions are one of the most expensive operations in Cassandra — typically 4-10x slower than a regular write. Developers who use them without understanding the cost can turn a fast write path into a slow one, and at scale, LWT-heavy workloads can cause serious cluster performance problems.

---

## Concept

### What LWT Does

LWT provides conditional writes — "write this only if a condition is true":

```sql
-- Insert only if the user doesn't already exist
INSERT INTO users (user_id, email) VALUES (?, ?)
IF NOT EXISTS;

-- Update only if the current value matches
UPDATE accounts SET balance = ? WHERE account_id = ?
IF balance = ?;
```

This is implemented using the **Paxos consensus protocol** (a multi-round protocol requiring coordination between replicas). Each LWT involves:

1. **Prepare phase**: coordinator contacts replicas to obtain a promise
2. **Promise phase**: replicas respond
3. **Propose phase**: coordinator proposes the value
4. **Commit phase**: replicas commit and acknowledge

This is 4 round trips instead of 1. With network latency, replication, and coordinator overhead, LWT typically costs 4-10x a regular write.

### When LWT Is Acceptable

- **Uniqueness enforcement**: registering a username or email that must be unique across the system
- **Compare-and-set**: updating a value only if it hasn't changed (optimistic locking)
- **Low-frequency operations**: operations that happen rarely (user registration, not per-request)

### When LWT Is Not Acceptable

- **High-throughput write paths**: anything that runs thousands of times per second
- **As a general mutex or lock**: repeated LWT-based locks cause heavy Paxos traffic
- **When eventual consistency is acceptable**: if you don't actually need the conditional guarantee, don't pay for it

### The Performance Cliff

LWT operations contend with each other on the same partition. Multiple concurrent LWT operations on the same partition queue up — only one can commit at a time. At high concurrency, this becomes a serialization bottleneck.

---

## Examples

### Acceptable: unique user registration
```sql
-- "Register this email only if it isn't already taken"
INSERT INTO users_by_email (email, user_id)
VALUES (?, ?)
IF NOT EXISTS;

-- Returns: [applied] = true if the insert succeeded, false if email already existed
```

```python
result = session.execute(
    "INSERT INTO users_by_email (email, user_id) VALUES (%s, %s) IF NOT EXISTS",
    [email, user_id]
)
if not result.one().applied:
    raise EmailAlreadyExists(email)
```

### Acceptable: compare-and-set balance update
```sql
UPDATE accounts
SET balance = ?
WHERE account_id = ?
IF balance = ?;
-- Only updates if the balance matches what we read — prevents lost updates
```

### Not acceptable: LWT on every request
```python
# ANTI-PATTERN: LWT on every API request — 4-10x slower than regular write
def record_api_call(user_id, endpoint):
    session.execute(
        "UPDATE api_stats SET calls = calls + 1 WHERE user_id = ? IF EXISTS",
        [user_id]
    )
    # This runs on every API call — LWT overhead accumulates at scale
```

```python
# CORRECT: use a counter (for approximate counts) or regular write (no condition needed)
def record_api_call(user_id, endpoint):
    session.execute(
        "UPDATE api_stats SET calls = calls + 1 WHERE user_id = ?",
        [user_id]
    )
```

---

## Pulse Check

> A developer uses `IF NOT EXISTS` on every INSERT to "be safe" — they want to make sure they never overwrite existing data. The table receives 10,000 inserts per second.
>
> **What's the performance impact, and when is `IF NOT EXISTS` actually necessary?**

*(Expected answer: `IF NOT EXISTS` triggers the Paxos protocol on every insert — approximately 4-10x the cost of a regular write. At 10,000/sec, this puts significant Paxos load on the cluster. In Cassandra, regular inserts are idempotent — inserting the same row twice with the same values is safe (last-write-wins). `IF NOT EXISTS` is only necessary when you genuinely need to know if the row already existed and want to prevent overwriting it — like unique user registration. For regular inserts where idempotency is fine, drop the condition.)*

---

## See Also

**In this session:**
- [BATCH Misuse](./05-batch-misuse.md)
- [Counters](./07-counters.md)

**Reference:**
- [Lightweight Transactions (LWT)](../../general/lwt.md)
- [Consistency Levels](../../general/consistency-levels.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
