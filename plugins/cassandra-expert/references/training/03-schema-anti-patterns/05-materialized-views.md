# Topic: Materialized Views

## Objective
Understand why Materialized Views must not be used in production and how to replace them with manually maintained denormalized tables.

## Why This Matters
Materialized Views seem like an elegant solution — define a view once, and Cassandra automatically keeps it in sync. In practice, they have a history of correctness bugs, they cannot be repaired with standard repair tools, and they add significant write overhead. Using them in production is a reliability risk. The correct alternative — manually maintained denormalized tables — is more work up front but predictable and repairable.

---

## Concept

### What Materialized Views Promise

A Materialized View (MV) automatically maintains a denormalized copy of a table with a different primary key, updated synchronously on every write to the base table.

```sql
-- Base table
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email   text,
    name    text
);

-- Materialized view — Cassandra auto-maintains this
CREATE MATERIALIZED VIEW users_by_email AS
    SELECT * FROM users
    WHERE email IS NOT NULL
    PRIMARY KEY (email, user_id);
```

### Why They Fail in Production

**1. Cannot be repaired.** Standard `nodetool repair` does not repair Materialized Views. If a node fails and comes back, the view can be permanently out of sync with the base table. There is no reliable way to re-sync it short of dropping and rebuilding it — which is expensive and requires downtime.

**2. Correctness bugs.** MVs have a history of consistency issues where the view diverges from the base table under concurrent writes, node failures, or network partitions.

**3. Write overhead.** Every write to the base table triggers a read-before-write to maintain the view (to detect deletes and updates), plus writes to the view's replicas. This doubles or triples write latency and I/O.

**4. Operational complexity.** MVs are an additional failure mode — one more thing that can go wrong and is hard to debug.

### The Fix: Manual Denormalization

Maintain the lookup table yourself. Use a logged batch to ensure both tables are eventually consistent:

```sql
-- Base table
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email   text,
    name    text
);

-- Manually maintained lookup table
CREATE TABLE users_by_email (
    email   text PRIMARY KEY,
    user_id uuid
);
```

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
```

This is repairable (standard repair works on both tables), debuggable, and has no hidden read-before-write overhead.

---

## Examples

### Identifying existing MVs
```sql
-- Find all materialized views in a keyspace
SELECT view_name, base_table_name
FROM system_schema.views
WHERE keyspace_name = 'my_keyspace';
```

### Migrating away from a MV

Order matters — if you backfill before updating the write path, you lose any writes that land between backfill completion and the write-path update. The correct sequence is: create the table, dual-write, backfill, switch reads, drop the view.

```sql
-- Step 1: create the replacement table
CREATE TABLE users_by_email (
    email   text PRIMARY KEY,
    user_id uuid
);

-- Step 2: update write paths to write to BOTH the base table and users_by_email
--         (use a logged batch to keep them in sync). Deploy this first so that
--         from this point forward, no write is missed.

-- Step 3: backfill from the base table (application loop or Spark).
--         Because step 2 is already live, anything written during the backfill
--         is already captured in the new table.

-- Step 4: update read paths to use the new table

-- Step 5: drop the materialized view
DROP MATERIALIZED VIEW users_by_email_mv;
```

See [No-Downtime Database Migrations](https://rustyrazorblade.com/post/2014/no-downtime-database-migrations-tutorial/) for the full pattern and why this ordering matters.

---

## Pulse Check

> A teammate proposes using a Materialized View to maintain a `products_by_category` lookup. They argue it's simpler than writing to two tables on every product insert.
>
> **What are the two most important reasons to reject this, and what do you propose instead?**

*(Expected answer: (1) Materialized Views cannot be repaired — if a node fails, the view can permanently diverge from the base table with no reliable fix. (2) They add hidden read-before-write overhead on every write to the base table, hurting write performance. Alternative: manually maintain a `products_by_category` table using a logged batch on every product insert. More explicit, fully repairable, and no hidden overhead.)*

---

## See Also

**In this session:**
- [Hot Partitions](./02-hot-partitions.md)
- [Secondary Indexes Without Partition Keys](./08-secondary-indexes.md)

**Reference:**
- [Repair](../../general/repair.md)
- [Batches](../../general/batches.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [No-Downtime Database Migrations](https://rustyrazorblade.com/post/2014/no-downtime-database-migrations-tutorial/) — the dual-write-then-backfill ordering used above
