# Topic: Table Options

## Objective
Know the table-level properties you'll set when creating or altering tables, what each one does, and when to override the defaults.

## Why This Matters
Every `CREATE TABLE` statement accepts a `WITH` clause that configures how the table behaves — how it's compacted, how long tombstones linger, how it's cached, how rows are compressed, and more. Most of these defaults are reasonable, but several are worth knowing about explicitly because they directly affect data modeling decisions, disk usage, and read/write behavior. You also need to understand table options to know what you can and can't change after a table is created.

---

## Concept

Table options go after `WITH` in a `CREATE TABLE` or `ALTER TABLE` statement, joined by `AND`:

```sql
CREATE TABLE events (
    event_id uuid PRIMARY KEY,
    data text
) WITH default_time_to_live = 86400
  AND gc_grace_seconds = 86400
  AND comment = 'Short-lived event log';
```

Here are the options you'll actually touch.

### `default_time_to_live`

Sets a default TTL (in seconds) for all writes to the table. Individual writes can override it with `USING TTL`. Covered in the TTL topic; listed here as the most important table option to know.

Default: `0` (no default TTL).

### `gc_grace_seconds`

The number of seconds tombstones are kept before compaction can purge them. Default: `864000` (10 days).

This value exists to give repair enough time to propagate deletions across all replicas. **Do not lower `gc_grace_seconds` below your repair interval** — if a replica misses a delete and the tombstone is purged before repair runs, the deleted row can resurrect from that replica.

> **Note:** Repair isn't covered in detail in this training yet. The essential idea: repair is a periodic operation (triggered with `nodetool repair`) that reconciles data between replicas by finding and streaming the differences. It's what guarantees that a delete eventually reaches every replica, even ones that were down or missed the original write. Your "repair interval" is how often you run it — commonly every few days to once a week. `gc_grace_seconds` must be longer than that interval, or deleted rows can resurrect. See [Repair](../../general/repair.md) for the full reference on full, subrange, and incremental repair.

When to adjust:
- **Lower it** (carefully) on tables with lots of deletes or short TTLs, if you run repair frequently enough to stay ahead of the new value.
- **Raise it** if you repair less often than every 10 days.
- If in doubt, leave it alone.

### `comment`

A human-readable description of the table. Shows up in `DESCRIBE TABLE`. Free documentation — use it.

```sql
ALTER TABLE events WITH comment = 'Per-user event log, bucketed by day';
```

### `compaction`

Controls how SSTables are merged. Covered in depth in the compaction topic later in this session; the summary:

```sql
-- Cassandra 5.0+: use UCS for everything
WITH compaction = { 'class': 'UnifiedCompactionStrategy' };

-- Older versions: LCS for read-heavy, TWCS for time-series
WITH compaction = { 'class': 'LeveledCompactionStrategy' };
```

The strategy names (UCS, LCS, TWCS, STCS) are different approaches to deciding *which* SSTables to merge and *when*. Each makes different tradeoffs between read performance, write amplification, and disk usage. Don't worry about picking one yet — the compaction topic covers them in detail.

### `compression`

Controls block-level compression of SSTable data. Defaults to LZ4 with a 16KB chunk length, which is reasonable for most workloads.

```sql
-- Change the chunk size for tables with large rows
WITH compression = { 'class': 'LZ4Compressor', 'chunk_length_in_kb': 64 };

-- Disable compression (rarely a good idea)
WITH compression = { 'enabled': false };
```

### `caching`

Controls what Cassandra caches in memory.

```sql
WITH caching = { 'keys': 'ALL', 'rows_per_partition': 'NONE' };  -- default
```

- `keys`: `ALL` or `NONE` — whether to cache the partition index (keep as `ALL`).
- `rows_per_partition`: `NONE`, `ALL`, or a number. Enables the **row cache** — an on-heap cache of entire partitions, separate from the OS page cache Cassandra normally relies on. **Row cache is rarely worth enabling** — it's memory-hungry, has narrow use cases (hot, small partitions), and usually just regrows the OS page cache. See the [Row Cache](../../general/row-cache.md) reference for detail.

### `speculative_retry`

Controls when a coordinator issues a duplicate read request to a second replica if the first is slow. Default `99p` is fine for most workloads.

```sql
WITH speculative_retry = '99p';     -- duplicate at the 99th percentile latency
WITH speculative_retry = 'ALWAYS';  -- always duplicate
WITH speculative_retry = 'NONE';    -- never duplicate
```

### `read_repair`

Controls asynchronous read repair behavior. Default: `BLOCKING`. Rarely worth changing.

### Clustering Order

Technically not a "WITH" option in the same way, but it's part of table options and important:

```sql
CREATE TABLE events (
    user_id uuid,
    event_time timestamp,
    data text,
    PRIMARY KEY (user_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```

This fixes the on-disk sort order of clustering columns and is the primary way to get "newest first" reads without the application doing a reverse.

---

## ALTER TABLE — What You Can and Can't Change

After a table is created, you can change some things but not others.

**You can:**
- Add a column: `ALTER TABLE users ADD phone text;`
- Drop a column: `ALTER TABLE users DROP phone;`
- Rename a column (with restrictions around primary key columns)
- Change table options: `ALTER TABLE users WITH gc_grace_seconds = 3600;`

**You can't:**
- Change a column's type (except in very narrow cases)
- Change the primary key of a table
- Change a column between static and regular
- Change clustering order

**Rule of thumb:** schema evolution in Cassandra is mostly additive. If you need to change something that isn't additive, the answer is usually a new table plus a migration.

---

## Examples

### Table with several options
```sql
CREATE TABLE sessions (
    session_id uuid PRIMARY KEY,
    user_id uuid,
    created_at timestamp
) WITH default_time_to_live = 86400
  AND gc_grace_seconds = 86400
  AND compaction = { 'class': 'UnifiedCompactionStrategy' }
  AND comment = 'User sessions, 24-hour TTL';
```

### Altering an existing table
```sql
-- Add a column
ALTER TABLE sessions ADD ip_address inet;

-- Change gc_grace_seconds
ALTER TABLE sessions WITH gc_grace_seconds = 3600;

-- Update the comment
ALTER TABLE sessions WITH comment = 'User sessions, 1-hour gc_grace';
```

### Inspecting a table's options
```sql
DESCRIBE TABLE sessions;
```

---

## Pulse Check

> A team is running repair every 14 days. Someone suggests lowering `gc_grace_seconds` to `86400` (1 day) to clear tombstones faster on a table with lots of deletes.
>
> **What's the risk, and what should they do instead?**

*(Expected answer: Zombie rows. If `gc_grace_seconds` is shorter than the repair interval, a tombstone can be purged on one replica before repair has propagated the delete to another replica. When the replicas reconcile, the non-deleted version "wins" and the deleted row resurrects. The fix: either run repair more often than `gc_grace_seconds`, or leave `gc_grace_seconds` at a safe value. Never lower it below your actual repair cadence.)*

> A team wants to change a column from `int` to `bigint` because their values are starting to exceed 32-bit range. They propose `ALTER TABLE stats ALTER count TYPE bigint`.
>
> **Will this work? If not, what are their options?**

*(Expected answer: In modern Cassandra, changing a column's type is generally not allowed (it was restricted in 3.10+ and mostly removed). Their options are: (1) add a new column `count_big bigint`, backfill values, then drop the old column; or (2) create a new table with the correct schema and migrate data. Schema evolution in Cassandra is mostly additive.)*

> You're creating a table for a short-lived cache where every row has a TTL of 5 minutes. You're choosing between `gc_grace_seconds = 864000` (default, 10 days) and `gc_grace_seconds = 3600` (1 hour).
>
> **What do you need to know before making this decision?**

*(Expected answer: You need to know the repair cadence for this cluster. If repair runs at least once an hour (or faster than the lower value), the 1-hour setting is safe. If repair only runs weekly, the 1-hour setting will cause zombie rows. For a short-lived cache, you can often lower `gc_grace_seconds` safely to prevent tombstone buildup — but only when you've confirmed your repair cadence supports it.)*

---

## See Also

**In this session:**
- [Tombstones](./11-tombstones.md)
- [TTL (Time-To-Live)](./14-ttl.md)
- [Compaction Overview](./13-compaction-overview.md)

**Reference:**
- [Tombstones](../../general/tombstones.md)
- [Compaction](../../general/compaction.md)
- [Compression](../../general/compression.md)
- [Row Cache](../../general/row-cache.md)
- [Repair](../../general/repair.md)
- [Cassandra 5.0 cassandra.yaml](../../cassandra-5.0/cassandra-yaml.md)
