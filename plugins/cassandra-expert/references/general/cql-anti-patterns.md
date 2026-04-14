# CQL Anti-Patterns

## Query Anti-Patterns

### ALLOW FILTERING

Never acceptable in production. Forces Cassandra to scan all partitions and filter in memory. Acceptable only in cqlsh for ad-hoc investigation on small datasets.

### Missing Partition Key

Every CQL query must include the full partition key in the WHERE clause. Without it, the query becomes a full table scan (or requires `ALLOW FILTERING`).

```cql
-- BAD: no partition key
SELECT * FROM orders WHERE status = 'pending';

-- GOOD: partition key included
SELECT * FROM orders WHERE user_id = ? AND status = 'pending';
```

### Large IN Clauses

Each value in an `IN()` clause is a separate internal query to a potentially different coordinator. Large `IN()` lists cause fan-out, increased latency, and coordinator pressure.

```cql
-- BAD: 100 values = 100 internal queries
SELECT * FROM users WHERE user_id IN (?, ?, ?, ... );

-- BETTER: execute individual queries concurrently from the application
```

### SELECT *

Retrieve only the columns you need. `SELECT *` reads all columns from disk, including large blobs or collections you may not use — wasting I/O and network bandwidth.

### Read-Modify-Write

Reading a value, modifying it in the application, then writing it back is a race condition. Multiple clients can read the same value, modify independently, and overwrite each other. Use LWTs if you truly need compare-and-set semantics (see `lwt.md`), or redesign the data model to avoid the pattern.

## Schema Anti-Patterns

### Unbounded Partition Growth

Partitions that grow without limit eventually degrade performance. Use bucketing (time-based or hash-based composite keys) to bound partition size. See `large-partitions.md`.

### Using Cassandra as a Queue

Cassandra is not designed for queue workloads. Deleting consumed messages creates tombstones that accumulate and degrade read performance. Use a purpose-built queue (Kafka, RabbitMQ, Pulsar).

### Secondary Indexes on High-Cardinality Columns

Legacy secondary indexes (not SAI) on high-cardinality columns create a hidden table per node that grows with the data. Performance degrades with cluster size. Use SAI (5.0+) or denormalize instead.

### Excessive Tombstone Generation

Frequent deletes, null writes, and collection replacements generate tombstones. Design the data model to minimize deletes — use TTL, table bucketing, or append-only patterns. See `tombstones.md`.

## See Also

- `large-partitions.md` — partition size guidelines and bucketing
- `tombstones.md` — tombstone lifecycle and reduction
- `lwt.md` — when compare-and-set is actually needed
- `batches.md` — batch misuse patterns
