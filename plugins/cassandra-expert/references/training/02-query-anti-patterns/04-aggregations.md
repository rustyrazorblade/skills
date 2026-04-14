# Topic: Aggregation Queries

## Objective
Understand why CQL aggregations (COUNT, SUM, AVG, MIN, MAX) are an anti-pattern in production Cassandra, and what to use instead.

## Why This Matters
Cassandra is optimized for fast, key-based lookups — not aggregations. A `SELECT COUNT(*)` on a large table requires reading every row through a single coordinator thread, causes GC pressure from large result sets, and blocks cluster resources for normal queries. What looks like a simple query can bring a production cluster to its knees.

---

## Concept

### What Aggregations Do Internally

CQL supports aggregation functions — `COUNT`, `SUM`, `AVG`, `MIN`, `MAX` — but they are executed on the coordinator, not distributed across nodes. The coordinator must:

1. Read all matching rows (potentially the entire table or partition)
2. Deserialize them into JVM heap
3. Aggregate in memory
4. Return the result

There is no query optimizer, no predicate pushdown, no distributed aggregation. It's a full scan with a single-threaded rollup on one node.

### User-Defined Aggregations (UDAs) are the same anti-pattern

CQL also lets you define your own aggregation functions with `CREATE AGGREGATE`, backed by user-defined functions (UDFs). UDAs feel like an escape hatch — "if the built-ins aren't enough, I'll write my own" — but they execute on the exact same single-coordinator path as the built-in aggregates. You still read every matching row through one node, deserialize onto the heap, and run the rollup in a single thread. All the problems above apply.

On top of that, UDAs add their own hazards:

- **Custom code in the read path.** UDFs/UDAs run inside the Cassandra JVM. A bug, infinite loop, or heap-hungry accumulator directly impacts the coordinator.
- **Security surface.** Running arbitrary user code inside the database is why UDFs are disabled by default in most production deployments (`user_defined_functions_enabled: false`). Turning them on to support a UDA is a security regression.
- **Deprecated / sandbox removed.** Scripted UDFs (JavaScript) were removed, and the Java UDF sandbox has been weakened over releases. Treat UDAs as legacy functionality, not a supported solution.

The rule is simple: **if `COUNT(*)` is wrong, a UDA wrapping the same scan is also wrong.** Use one of the correct alternatives below.

### The Performance Impact

- **High read latency**: aggregations compete with normal reads for disk I/O
- **GC pressure**: large result sets create massive on-heap objects
- **Coordinator bottleneck**: single-threaded aggregation blocks the coordinator
- **Timeouts**: large aggregations frequently exceed client timeout thresholds
- **Cluster instability**: sustained aggregation queries degrade performance for all users

### The Correct Alternatives

**Option 1: Pre-compute with counters**

If you need counts or sums, maintain them at write time with counter tables:

```sql
-- ANTI-PATTERN: counting at read time
SELECT COUNT(*) FROM events WHERE user_id = ?;

-- CORRECT: maintain the count at write time
CREATE TABLE user_event_counts (
    user_id    uuid,
    event_type text,
    count      counter,
    PRIMARY KEY (user_id, event_type)
) WITH compression = {'class': 'LZ4Compressor', 'chunk_length_in_kb': 4}
  AND compaction = {'class': 'UnifiedCompactionStrategy'};

-- Increment on every event write
UPDATE user_event_counts SET count = count + 1
WHERE user_id = ? AND event_type = ?;

-- Read is instant — no scan needed
SELECT count FROM user_event_counts
WHERE user_id = ? AND event_type = 'login';
```

**Option 2: Aggregate in the application**

For small, bounded result sets, fetch the rows and aggregate in application code:

```python
# Acceptable when the partition is small and bounded
rows = session.execute(get_orders, [customer_id]).all()
total = sum(row.amount for row in rows)
```

**Option 3: Use an analytics system**

For large-scale aggregations across many partitions, use a purpose-built system:

- **Apache Spark + cassandra-analytics** — distributed aggregation over full tables using the bulk reader (preferred over the CQL connector)
- **OpenSearch** — aggregations over indexed data
- **Data warehouse** (Redshift, BigQuery, Athena) — sync data via CDC (Change Data Capture, covered in the Triggers topic later in this session) or batch export

When using Spark, always prefer the **cassandra-analytics bulk reader** (`https://github.com/apache/cassandra-analytics`) over the CQL-based Spark connector. The bulk reader uses the Cassandra sidecar to read SSTables directly, bypassing the coordinator entirely — making it far more efficient for large-scale reads and much less disruptive to production traffic.

### When Aggregations Are Acceptable

- **Small, bounded partitions**: `COUNT(*)` on a partition with 20 rows is fine
- **Administrative/troubleshooting queries**: occasional manual queries in non-critical windows
- **Development and testing**: not in production

---

## Examples

### Anti-pattern: counting events at query time
```sql
-- Full partition scan to count — avoid in production
SELECT COUNT(*) FROM user_events WHERE user_id = ?;
```

### Correct: counter table
```sql
CREATE TABLE user_event_counts (
    user_id    uuid,
    event_type text,
    count      counter,
    PRIMARY KEY (user_id, event_type)
);

-- Write path: increment on every event
UPDATE user_event_counts SET count = count + 1
WHERE user_id = ? AND event_type = ?;

-- Read path: instant lookup
SELECT count FROM user_event_counts
WHERE user_id = ? AND event_type = 'purchase';
```

### Correct: Spark + cassandra-analytics bulk reader for cross-partition aggregation

Use the **cassandra-analytics bulk reader** (`https://github.com/apache/cassandra-analytics`), not the CQL-based Spark connector. The bulk reader uses the Cassandra sidecar to read SSTables directly — bypassing the coordinator entirely and avoiding production traffic disruption.

```python
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = SparkSession.builder \
    .appName("daily-aggregation") \
    .getOrCreate()

# Bulk reader reads SSTables directly via the Cassandra sidecar
events = spark.read \
    .format("org.apache.cassandra.spark") \
    .option("sidecar_instances", "cassandra-host-1,cassandra-host-2,cassandra-host-3") \
    .option("keyspace", "my_keyspace") \
    .option("table", "events") \
    .load()

# Distributed aggregation — not hitting Cassandra with COUNT(*)
summary = events.groupBy("event_type").agg(F.count("*").alias("total"))
summary.show()
```

### Identifying aggregation queries in production
```bash
# Check slow query log for aggregation patterns
grep -E "COUNT|SUM|AVG|MIN|MAX" /var/log/cassandra/debug.log

# High read latency on a table is a signal
nodetool tablestats <keyspace>.<table>
# Look for: "Read Latency" — spikes often caused by aggregations
```

---

## Pulse Check

> A reporting dashboard runs this query every 60 seconds to show a live user count:
> ```sql
> SELECT COUNT(*) FROM users;
> ```
> The `users` table has 50 million rows.
>
> **What's wrong and what are the two correct alternatives?**

*(Expected answer: `COUNT(*)` on 50M rows is a full table scan executed on a single coordinator — it will time out, cause GC pressure, and degrade the cluster for all users. Alternative 1: maintain a counter table with a global user count, incremented on every user registration. Alternative 2: export user data to a data warehouse and run the count there. The dashboard should read a pre-computed value, not trigger a live scan.)*

---

## See Also

**In this session:**
- [ALLOW FILTERING](./02-allow-filtering.md)
- [Token Range Queries](./03-token-range-queries.md)
- [Sorting Partitions in Memory](./12-in-memory-sorting.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Dropped Messages](../../general/dropped-messages.md)
- [JVM Tuning](../../general/jvm.md)
- [Large Partitions](../../general/large-partitions.md)
