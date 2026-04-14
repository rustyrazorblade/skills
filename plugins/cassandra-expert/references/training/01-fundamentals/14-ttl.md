# Topic: TTL (Time-To-Live)

## Objective
Understand how Cassandra's TTL feature expires data automatically, where TTL creates tombstones, and how to use it correctly for time-bounded data.

## Why This Matters
TTL is one of Cassandra's most useful data modeling tools — it lets you bound the size of your data without ever running a delete query. Time-series tables, session stores, event logs, and caches all rely on TTL to stay healthy over time. But TTL also creates tombstones when it expires, so using it wrong can flood a table with tombstones and degrade reads. Understanding TTL is essential for any time-bounded workload.

---

## Concept

**TTL (time-to-live)** is a per-cell expiration time measured in seconds. When a cell's TTL elapses, Cassandra treats the cell as deleted. TTL is set at write time and applies to individual cells, not rows.

Critically: **an expired cell becomes a tombstone**. It is logically gone from query results, but the tombstone sits on disk until compaction can purge it after `gc_grace_seconds` has passed. TTL does not make data "free" — it still creates work for compaction and still counts toward tombstone scan limits until fully purged.

### Setting TTL

You can set TTL on an INSERT or UPDATE using `USING TTL <seconds>`:

```sql
-- Expire this row in 90 days
INSERT INTO sessions (session_id, user_id, created_at)
VALUES (?, ?, ?)
USING TTL 7776000;
```

```sql
-- Update with TTL — only the updated cells get the new TTL
UPDATE users USING TTL 3600
SET last_active = ?
WHERE user_id = ?;
```

### Column-Level vs Row-Level TTL

TTL applies to cells, not to "the row." That means:

- If you INSERT a row with `USING TTL 60`, every cell in that row gets a 60-second TTL.
- If you then UPDATE one column without a TTL, that column's cell will have **no** TTL and will outlive the rest of the row.
- If you UPDATE one column with a **different** TTL, that column's cell expires independently of the others.

This is a common source of confusion: after partial updates, "the row" may have cells with different TTLs, and only some of them will be visible at a given time.

### Table-Level Default TTL

You can set a default TTL at the table level using `default_time_to_live`:

```sql
CREATE TABLE events (
    event_id uuid,
    event_time timestamp,
    data text,
    PRIMARY KEY (event_id)
) WITH default_time_to_live = 604800;  -- 7 days
```

Any write that doesn't specify its own TTL inherits this default. Writes with an explicit `USING TTL` override it.

Setting `default_time_to_live = 0` means no default expiration (the normal behavior).

### TTL and Tombstones

When a TTL expires, the cell becomes a tombstone. It remains on disk until:
1. `gc_grace_seconds` has passed since the TTL expiration
2. A compaction runs that can fully purge the tombstone

This means that even with TTL, a heavily-updated table can accumulate tombstones and suffer from tombstone scan issues if reads span large ranges of expired data. The usual defenses apply: bucket your partitions so old, tombstone-heavy partitions are read rarely or not at all.

### Common Use Cases

- **Session tokens** — set TTL to session lifetime; no cleanup job needed
- **Time-series data with a retention window** — combine TTL with time-based bucketing so whole partitions age out at once
- **Caches** — Cassandra can serve as a durable cache with automatic expiration
- **Verification codes, password reset tokens** — short TTL, no leak

### Checking TTL on Existing Data

```sql
SELECT ttl(column_name) FROM table WHERE partition_key = ?;
```

This returns the remaining TTL in seconds for that cell, or `null` if no TTL is set.

---

## Examples

### Session store with automatic expiration
```sql
CREATE TABLE sessions (
    session_id uuid PRIMARY KEY,
    user_id uuid,
    created_at timestamp
) WITH default_time_to_live = 86400;  -- 24 hours

-- Write doesn't need to specify TTL; table default applies
INSERT INTO sessions (session_id, user_id, created_at)
VALUES (?, ?, ?);
```

### Time-series with TTL and bucketing
```sql
CREATE TABLE sensor_readings (
    sensor_id uuid,
    day date,
    ts timestamp,
    value double,
    PRIMARY KEY ((sensor_id, day), ts)
) WITH default_time_to_live = 2592000;  -- 30 days

INSERT INTO sensor_readings (sensor_id, day, ts, value)
VALUES (?, ?, ?, ?);
```

### Override default TTL for an individual write
```sql
-- Table default is 30 days, but this row should live 1 year
INSERT INTO sensor_readings (sensor_id, day, ts, value)
VALUES (?, ?, ?, ?)
USING TTL 31536000;
```

### Checking the TTL of a cell
```sql
SELECT ttl(value) FROM sensor_readings
WHERE sensor_id = ? AND day = ? AND ts = ?;
```

---

## Pulse Check

> You're building a password reset feature. The reset token should be usable for 15 minutes, after which it should be gone. A colleague suggests running a periodic cleanup job that deletes expired tokens.
>
> **What's a better approach, and why?**

*(Expected answer: Use TTL. Insert the token with `USING TTL 900` (15 minutes) and Cassandra handles expiration automatically — no cleanup job needed. This is less code, and more importantly it removes a failure mode: if the cleanup job breaks or falls behind, expired tokens linger. With TTL, expiration is guaranteed by the database.)*

> A team is using TTL heavily on a single partition that collects events. Every row has a 7-day TTL, and they write thousands of events per day to the same partition key. After a few weeks, reads on the partition are becoming slow — even though only ~7 days of rows are live at any time.
>
> **What's going on?**

*(Expected answer: The partition is accumulating tombstones from expired rows. Each TTL expiration creates a tombstone that lingers until `gc_grace_seconds` has elapsed and a compaction can purge it. Thousands of expired rows per day produce thousands of tombstones per day, and every read on the partition has to scan through all of them — even though only the handful of live rows are returned. The key insight: TTL doesn't make data "free." Expired cells still cost read effort until they're fully purged.)*

> A colleague runs `INSERT INTO users (user_id, name, email) VALUES (?, 'Alice', 'alice@example.com') USING TTL 3600;` — then one minute later runs `UPDATE users SET email = 'alice@new.com' WHERE user_id = ?;` (no TTL specified).
>
> **What will the row look like in an hour?**

*(Expected answer: The `name` cell will have expired (it had a 1-hour TTL from the original INSERT and an hour has passed). The `email` cell will still be present because the UPDATE overwrote it without specifying a TTL — so that cell has no expiration at all. The row effectively loses its name while keeping the new email. This is a common gotcha: TTLs are per-cell, not per-row.)*

---

## See Also

**In this session:**
- [Tombstones](./11-tombstones.md)
- [Table Options](./12-table-options.md)
- [Pattern: Time Series](./19-pattern-time-series.md)

**Reference:**
- [Tombstones](../../general/tombstones.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Time Series Data Modeling](../../general/time-series.md)
- [Cassandra 5.0 cassandra.yaml](../../cassandra-5.0/cassandra-yaml.md)
