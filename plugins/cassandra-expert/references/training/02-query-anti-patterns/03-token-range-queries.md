# Topic: Token Range Queries

## Objective

Understand what token range queries are, why they're generally an anti-pattern for application use, and what to use instead for bulk data access.

## Why This Matters
Token range queries scan entire token ranges across the cluster — they are essentially full table scans expressed at the storage level. Using them in application code to iterate over large datasets bypasses Cassandra's strengths entirely and produces the same cluster-wide I/O impact as ALLOW FILTERING. The correct tools for bulk data access are purpose-built analytics systems.

---

## Concept

### What Token Range Queries Are

Cassandra's ring assigns each partition a token. You can query by token range to read all rows whose tokens fall within a range:

```sql
SELECT * FROM users WHERE token(user_id) >= ? AND token(user_id) < ?;
```

Drivers use this internally to implement pagination over the full dataset. It's part of Cassandra's internal machinery — not a feature designed for application queries.

### Why Application Code Shouldn't Use Them

- **Full table scan**: scanning all token ranges reads the entire table. This is expensive and slow.
- **High I/O**: forces every node to do sequential disk reads across all SSTables
- **Cluster impact**: sustained token range scans saturate disk and network on every node simultaneously
- **No predicate pushdown**: you can't filter efficiently within a token range scan — you read everything and discard non-matching rows

### When Token Range Queries Are Used Legitimately

- **Driver pagination** (internal): drivers use token ranges to implement `fetchAll()` style operations
- **Repair** (internal): Cassandra uses token ranges during repair to compare replicas
- **Custom bulk export tools** (expert use): tools like `cassandra-analytics` (Spark) use token ranges carefully and in parallel — but they're purpose-built for this

### The Correct Alternatives

**For analytics and reporting:**
Use **Apache Spark with cassandra-analytics** (https://github.com/apache/cassandra-analytics). It reads token ranges in parallel across the cluster, handles failures gracefully, and is designed for bulk reads.

```python
# Spark + cassandra-analytics: bulk read of an entire table
df = spark.read \
    .format("org.apache.cassandra.spark") \
    .option("keyspace", "my_keyspace") \
    .option("table", "my_table") \
    .load()

result = df.filter(df.status == "pending").groupBy("region").count()
```

**For search and ad-hoc queries:**
Use **OpenSearch** or **Elasticsearch**. Sync Cassandra data to the search index (via CDC or batch sync) and run complex queries there. (CDC — Change Data Capture — is covered later in this session in the Triggers topic.)

**For data exports:**
Use `cassandra-analytics` to export to Parquet, then query with Spark, Athena, or BigQuery.

---

## Examples

### Anti-pattern: iterating the full table in application code
```python
# ANTI-PATTERN: token range scan to "get all users"
# This reads the entire table and saturates the cluster

rows = session.execute("SELECT * FROM users")  # implicit full scan via driver
for row in rows:
    process(row)  # processing 10M users one at a time
```

### Correct: use Spark for bulk processing
```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("user-processing") \
    .config("spark.cassandra.connection.host", "cassandra-host") \
    .getOrCreate()

# Reads the table in parallel across the cluster — no single-node bottleneck
users = spark.read \
    .format("org.apache.cassandra.spark") \
    .option("keyspace", "my_keyspace") \
    .option("table", "users") \
    .load()

# Process in parallel with Spark
users.filter(users.status == "active") \
     .write \
     .parquet("s3://my-bucket/active-users/")
```

### Correct: use OpenSearch for ad-hoc filtering
```python
# Sync data to OpenSearch via CDC or scheduled job
# Then query freely without impacting Cassandra
results = opensearch_client.search(
    index='users',
    body={'query': {'term': {'status': 'active'}}}
)
```

---

## Pulse Check

> A data engineer wants to generate a daily report of all orders placed in the last 24 hours. They propose iterating over all orders using the Cassandra driver's `fetch_all()` method.
>
> **Why is this wrong, and what should they use instead?**

*(Expected answer: `fetch_all()` on a large table performs a full token range scan — it reads every row in the orders table to find the last 24 hours' worth, saturating disk I/O on every node. For a daily report, use Apache Spark with cassandra-analytics to read the data in parallel and filter efficiently, or sync order data to a data warehouse (Redshift, BigQuery) and run the report there. If the query is time-based, consider whether the schema should support it directly with a time-bucketed partition key.)*

---

## See Also

**In this session:**
- [ALLOW FILTERING](./02-allow-filtering.md)
- [Sorting Partitions in Memory](./12-in-memory-sorting.md)
- [Aggregation Queries](./04-aggregations.md)

**Reference:**
- [Token Skew and Distribution](../../general/token-skew.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Virtual Nodes (vnodes)](../../general/vnodes.md)
- [Time Series Data Modeling](../../general/time-series.md)
