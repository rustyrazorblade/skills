# Tombstones

Tombstones are Cassandra's delete markers. When you delete a row or column, Cassandra writes a tombstone rather than immediately removing data. Tombstones are necessary for consistency across replicas but accumulate and degrade read performance.

## Why Tombstones Exist

Cassandra can't just remove data — other replicas may still have the original value and would re-introduce it during read repair or anti-entropy repair. A tombstone tells all replicas "this data was deleted at this timestamp" so the delete wins during conflict resolution.

## What Creates Tombstones

- `DELETE` statements
- Setting a column to `null`
- TTL expiration (expired data becomes a tombstone)
- Replacing collection elements (old elements become tombstones)
- Range deletes

## Performance Impact

Every read must scan tombstones in the query range to determine which data is live. High tombstone counts cause:
- Increased query latency
- Higher memory usage during reads
- Query timeouts when tombstone count exceeds failure threshold

```yaml
# cassandra.yaml
tombstone_warn_threshold: 1000      # log warning
tombstone_failure_threshold: 100000  # abort query
```

```bash
# Check for tombstone warnings
grep "tombstone" /var/log/cassandra/system.log
# "Read N live rows and M tombstone cells"
```

## Tombstone Lifecycle

1. Data is deleted → tombstone written
2. Tombstone replicated to other nodes via repair
3. After `gc_grace_seconds` (default 10 days), tombstone is eligible for removal
4. Compaction removes eligible tombstones

**All replicas must see the tombstone before it can be purged.** This is why repair must complete within `gc_grace_seconds` — if a replica never receives the tombstone and it gets purged from the others, the deleted data reappears (data resurrection).

## Reducing Tombstones

### Use TTL instead of DELETE

```cql
-- Instead of writing + later deleting
INSERT INTO sessions (session_id, data) VALUES (?, ?) USING TTL 3600;
```

Data expires automatically. Still creates tombstones, but avoids explicit delete operations and ensures cleanup is predictable.

### Partition by time and drop tables

```cql
-- Monthly buckets
CREATE TABLE events_2025_04 (...);

-- When no longer needed, drop the entire table
DROP TABLE events_2025_01;
-- Zero tombstones
```

This is the most efficient way to expire old data at scale.

### Avoid patterns that generate tombstones silently

- Replacing entire collections (`UPDATE t SET list_col = [...]`) tombstones old elements
- Setting columns to `null` creates a tombstone per column
- Range deletes (`DELETE FROM t WHERE pk = ? AND ck > ?`) can create many tombstones

## See Also

- [Repair](./repair.md) — repair must complete within `gc_grace_seconds` to prevent data resurrection
- [Compaction](./compaction.md) — compaction removes eligible tombstones
- [Time Series Data Modeling](./time-series.md) — table bucketing as an alternative to TTL/deletes
