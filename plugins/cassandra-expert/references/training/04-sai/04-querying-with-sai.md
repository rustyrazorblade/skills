# Topic: Querying with SAI — Patterns and Anti-Patterns

## Objective
Write efficient SAI queries using supported operators, recognize the patterns that work well, and avoid the ones that silently degrade performance.

## Why This Matters
SAI supports a richer set of query operators than plain CQL — range queries, text matching, collection filtering. But every one of these operators must be paired with a partition key to perform well. The flexibility SAI provides is only safe when used correctly.

---

## Concept

### Supported Operators

| Operator | Types | Example |
|----------|-------|---------|
| `=` | All scalar types | `WHERE customer_id = ? AND status = 'active'` |
| `<`, `<=`, `>`, `>=` | Numeric, timestamp, date | `WHERE customer_id = ? AND total > 100` |
| `CONTAINS` | set, list | `WHERE customer_id = ? AND tags CONTAINS 'vip'` |
| `CONTAINS KEY` | map | `WHERE customer_id = ? AND metadata CONTAINS KEY 'source'` |
| `IN` | Scalar types | `WHERE customer_id = ? AND status IN ('pending', 'active')` |

`OR` in the `WHERE` clause is **not supported** by SAI in Apache Cassandra 5.0 — it fails with a syntax error. For same-column multi-value matching use `IN`. For cross-column "A or B" semantics, issue the two queries concurrently from the application and merge client-side. (Verified with `skills/training/scripts/verify-sai-capabilities.py`.)

### The Partition Key Rule (Again)

Every query pattern below assumes the partition key is present. Without it, the query degrades to a cluster-wide SSTable scan. This bears repeating because it's the most common SAI mistake.

### Range Queries

SAI supports range queries on indexed numeric, date, and timestamp columns — something plain clustering columns can also do, but only within a single partition and only in prefix order. SAI can do this across clustering columns in any order, as long as the partition key is present.

```sql
-- Efficient: partition key + range filter via SAI
SELECT * FROM sensor_readings
WHERE device_id = ?         -- partition key
  AND temperature > 80.0;   -- SAI range query

-- Also efficient: multiple SAI filters combined
SELECT * FROM orders
WHERE customer_id = ?       -- partition key
  AND status = 'pending'    -- SAI equality
  AND total >= 50.00;       -- SAI range
```

### Text Matching

SAI supports exact match on text columns. SAI does **not** support `LIKE` in Apache Cassandra 5.0. (Legacy SASI indexes did support `LIKE`, but SASI should not be used in new work — see [SASI: Never Use](./06-sasi-never-use.md).) SAI also does not provide full-text search (no stemming, tokenization, or relevance ranking); use Elasticsearch or OpenSearch for that.

```sql
CREATE INDEX products_by_name ON products (name) USING 'sai';

-- Exact match
SELECT * FROM products WHERE category_id = ? AND name = 'Widget Pro';
```

### Collection Filtering

```sql
-- Filter rows where a set contains a value
SELECT * FROM orders WHERE customer_id = ? AND tags CONTAINS 'priority';

-- Filter rows where a map contains a key
SELECT * FROM events WHERE user_id = ? AND metadata CONTAINS KEY 'campaign';
```

---

## Anti-Patterns

### Missing partition key
```sql
-- ANTI-PATTERN: cluster-wide SSTable scan
SELECT * FROM orders WHERE status = 'pending';

-- FIX: always include the partition key
SELECT * FROM orders WHERE customer_id = ? AND status = 'pending';
```

### Using SAI where a clustering column would do
```sql
-- If you always query by customer_id AND order_date in sequence,
-- order_date should be a clustering column — not an SAI index
-- SAI adds index overhead; clustering columns are free

-- Consider this instead:
CREATE TABLE orders (
    customer_id uuid,
    order_date  date,
    order_id    uuid,
    ...
    PRIMARY KEY (customer_id, order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC, order_id ASC);

-- No SAI needed — efficient range query via clustering column:
SELECT * FROM orders
WHERE customer_id = ?
  AND order_date >= '2025-01-01';
```

### Using SAI on a high-write, high-read hot path
```sql
-- If this query runs millions of times per second, SAI adds
-- index maintenance overhead on every write AND read latency.
-- A dedicated denormalized table is faster.
```

---

## Examples

### E-commerce order filtering
```sql
CREATE TABLE orders (
    customer_id uuid,
    order_id    uuid,
    status      text,
    total       decimal,
    created_at  timestamp,
    PRIMARY KEY (customer_id, order_id)
);

CREATE INDEX orders_by_status  ON orders (status)     USING 'sai';
CREATE INDEX orders_by_total   ON orders (total)      USING 'sai';
CREATE INDEX orders_by_created ON orders (created_at) USING 'sai';

-- "Show me this customer's pending orders over $100, newest first"
SELECT * FROM orders
WHERE customer_id = ?
  AND status = 'pending'
  AND total > 100.00
ORDER BY order_id DESC;   -- clustering column ordering still applies
```

### Python
```python
get_pending_orders = session.prepare("""
    SELECT order_id, status, total, created_at
    FROM orders
    WHERE customer_id = ?
      AND status = 'pending'
      AND total > ?
""")

def get_large_pending_orders(customer_id, min_total):
    return session.execute(get_pending_orders, [customer_id, min_total]).all()
```

### Java
```java
PreparedStatement getPendingOrders = session.prepare(
    "SELECT order_id, status, total, created_at FROM orders " +
    "WHERE customer_id = ? AND status = 'pending' AND total > ?"
);

public List<Row> getLargePendingOrders(UUID customerId, BigDecimal minTotal) {
    return session.execute(getPendingOrders.bind(customerId, minTotal)).all();
}
```

### Go
```go
func getLargePendingOrders(ctx context.Context, session *gocql.Session, customerID gocql.UUID, minTotal float64) ([]Order, error) {
    iter := session.Query(
        "SELECT order_id, status, total, created_at FROM orders WHERE customer_id = ? AND status = 'pending' AND total > ?",
        customerID, minTotal,
    ).WithContext(ctx).Iter()

    var orders []Order
    var o Order
    for iter.Scan(&o.OrderID, &o.Status, &o.Total, &o.CreatedAt) {
        orders = append(orders, o)
    }
    return orders, iter.Close()
}
```

---

## Pulse Check

> You have this table and index:
>
> ```sql
> CREATE TABLE user_events (
>     user_id    uuid,
>     event_id   uuid,
>     event_type text,
>     created_at timestamp,
>     PRIMARY KEY (user_id, event_id)
> );
> CREATE INDEX user_events_by_type ON user_events (event_type) USING 'sai';
> ```
>
> A developer writes this query:
> ```sql
> SELECT * FROM user_events
> WHERE event_type = 'purchase'
>   AND created_at > '2025-01-01';
> ```
>
> **What's wrong, and how do you fix it?**

*(Expected answer: The query is missing the partition key (`user_id`). Without it, SAI scans all SSTables cluster-wide. Also, `created_at` is not indexed — this would require ALLOW FILTERING or an additional SAI index. Fix: add `user_id = ?` to the query. If `created_at` filtering is needed, add a SAI index on `created_at` too, or make it a clustering column if the access pattern always goes user → time.)*

---

## See Also

**In this session:**
- [SAI Overview — Why This Session Exists](./01-sai-overview.md)
- [What SAI Is and Why the Partition Key Rule Exists](./02-what-is-sai.md)
- [Creating and Managing SAI Indexes](./03-creating-managing-indexes.md)
- [SAI vs. Denormalization](./05-sai-vs-denormalization.md)

**Reference:**
- [SAI FAQ (Apache Cassandra)](https://cassandra.apache.org/doc/latest/cassandra/developing/cql/indexing/sai/sai-faq.html)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Prepared Statements](../../general/prepared-statements.md)
- [SSTable Components](../../general/sstable-components.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
