# Batches in Cassandra

Batches exist primarily to ensure all writes eventually succeed. They are not a bulk loading mechanism, but they can improve performance in specific scenarios.

## When to Use Batches

**Valid: writing denormalized data to multiple tables atomically**
```cql
BEGIN BATCH
  INSERT INTO users (user_id, name) VALUES (?, ?);
  INSERT INTO users_by_email (email, user_id) VALUES (?, ?);
APPLY BATCH;
```

**Invalid: bulk loading multiple rows**
```cql
-- NEVER DO THIS
BEGIN BATCH
  INSERT INTO users (user_id, name) VALUES (1, 'Alice');
  INSERT INTO users (user_id, name) VALUES (2, 'Bob');
  -- ... 1000 more inserts
APPLY BATCH;
```

For bulk loading, use `sstableloader`, `COPY`, application-level async writes, or [Cassandra Analytics](https://github.com/apache/cassandra-analytics) for Spark-based bulk writes.

## Batch Types

**LOGGED** (default): Cassandra writes a batch log entry first, then replays if any part fails. Guarantees all writes eventually go through. Use when writing denormalized data across multiple tables.

**UNLOGGED**: No replay guarantee. Lower overhead. Use only for grouping writes within the same partition.

**COUNTER**: Only for counter updates. Always unlogged.

## Atomicity vs Isolation

Batches provide **atomicity** — all writes eventually succeed or all fail. They do **not** provide **isolation**.

A client paginating through query results can observe a partial batch mid-execution. If a batch writes rows that span a page boundary, the reader may see some rows updated and others not. Do not rely on batches for read-your-writes consistency across multiple tables.

## Size Thresholds

```yaml
# cassandra.yaml
batch_size_warn_threshold_in_kb: 5    # Warning logged at 5KB
batch_size_fail_threshold_in_kb: 50   # Batch rejected at 50KB
```

Keep batches under 5KB. Large batches buffer entirely on the coordinator heap, causing GC pressure and coordinator timeouts. Splitting a large batch into smaller ones does not change correctness — logged batches guarantee completion regardless of size.

## Performance

### Single-Partition Batches

Batching writes to the **same partition** can improve performance. Cassandra optimizes a single-partition batch into one mutation, reducing the number of writes to the commitlog and memtable. This is especially beneficial when the application is remote from the data center — bundling multiple row writes into a single round trip avoids per-statement network latency.

### Multi-Partition Batches on Small Clusters

On small clusters where the replica set is effectively the entire cluster (e.g., RF=3 with 3 nodes), unlogged multi-partition batches can be acceptable. The coordinator contacts the same set of nodes regardless of which partitions are in the batch, so there is no additional fan-out cost.

### Multi-Partition Batches on Large Clusters

On larger clusters, multi-partition batches are **not** a performance optimization. The coordinator must route each statement to its owning replicas, collect acknowledgments, and manage the batch log. This fans out to many nodes, buffers data on the coordinator heap, and can cause longer GC pauses. Unrelated writes batched together will hurt performance compared to sending them individually and letting the driver handle parallelism.

## Identifying Batch Problems

```bash
grep "Batch.*exceeding" /var/log/cassandra/system.log
# "Batch for [ks.table] is of size X, exceeding specified threshold of Y"
```

## Best Practices

- Use LOGGED batches when you need the eventual-delivery guarantee across tables
- Use UNLOGGED batches for same-partition grouping — this is a valid performance optimization
- Single-partition batches reduce round trips and are beneficial, especially over high-latency links
- On large clusters, do not batch across partitions for performance — let the driver parallelize
- Keep batch size under 5KB
- Alert on batch size warnings in logs

## See Also

- [Lightweight Transactions (LWT)](lwt.md)
- [Tombstones](tombstones.md)
- [CQL Anti-Patterns](cql-anti-patterns.md)
- [Prepared Statements](prepared-statements.md)
