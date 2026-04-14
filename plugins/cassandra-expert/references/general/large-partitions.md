# Large Partitions

Large partitions degrade read performance, increase GC pressure, slow compaction and repair, and can cause streaming failures during node operations.

## Size Guidelines

- **Sweet spot**: Under 10MB
- **Acceptable**: Up to 100MB for partitions that are rarely read in full
- **Problem**: Over 100MB — redesign required

## Detection

```bash
# Table-level stats including max partition size
nodetool tablehistograms keyspace.table

# Warnings in logs
grep "large partition" /var/log/cassandra/system.log

# Per-table stats
nodetool tablestats keyspace.table
```

## Common Causes

1. **Unbounded time series** — continuously appending to the same partition without bucketing
2. **Low-cardinality partition key** — too few distinct values, data concentrates in few partitions
3. **Append-only patterns** — no TTL, no deletion, partition grows forever
4. **Unbounded collections** — lists/sets/maps that grow without limit

## Fixing Large Partitions

### Add bucketing to the partition key

```cql
-- Before: unbounded
CREATE TABLE events (
  user_id uuid,
  event_time timestamp,
  data text,
  PRIMARY KEY (user_id, event_time)
);

-- After: bucketed by day
CREATE TABLE events (
  user_id uuid,
  day text,
  event_time timestamp,
  data text,
  PRIMARY KEY ((user_id, day), event_time)
);
```

Choose bucket granularity based on write rate to keep partitions under 10MB. For high-volume users, daily or hourly buckets. For low-volume, weekly or monthly.

### Increase partition key cardinality

```cql
-- Before: only ~200 countries
CREATE TABLE events (
  country text,
  event_id uuid,
  PRIMARY KEY (country, event_id)
);

-- After: composite partition key
CREATE TABLE events (
  country text,
  user_id uuid,
  event_id uuid,
  PRIMARY KEY ((country, user_id), event_id)
);
```

### Add TTL to prevent unbounded growth

```cql
INSERT INTO events (...) VALUES (...) USING TTL 2592000;  -- 30 days
```

## Why Large Partitions Are Expensive

- Reading any row in the partition requires loading the partition index into memory
- Compaction must read and rewrite the entire partition
- Repair compares partitions by hash — large partitions are expensive to hash and stream
- A single large partition can cause GC pressure when materialized in heap during reads

## See Also

- [SSTable Components](./sstable-components.md) — how partition indexes work
- [Compaction](./compaction.md) — compaction impact of large partitions
- [Time Series Data Modeling](./time-series.md) — bucketing patterns for time series data
