# Topic: ALLOW FILTERING

## Objective
Understand why ALLOW FILTERING is never acceptable in production and what the correct alternatives are.

## Why This Matters
ALLOW FILTERING is Cassandra's way of saying "I can't execute this query efficiently, but I'll do it anyway by scanning data I don't need." In a small development cluster it appears to work fine. In production, it causes full partition or full table scans that saturate I/O, increase latency, and degrade the entire cluster — not just the query in question.

---

## Concept

### What ALLOW FILTERING Does

When a query can't be satisfied using the PRIMARY KEY structure, Cassandra refuses to execute it by default. `ALLOW FILTERING` overrides this refusal and forces Cassandra to:

1. Read more data than needed (potentially the entire table or partition)
2. Filter out non-matching rows in memory
3. Return only the matching rows

The cost scales with the amount of data scanned, not the amount of data returned.

```sql
-- Cassandra refuses this without ALLOW FILTERING
SELECT * FROM orders WHERE total > 100;

-- ALLOW FILTERING forces a full table scan
SELECT * FROM orders WHERE total > 100 ALLOW FILTERING;
-- Reads every row in the table, discards non-matching ones
-- At 100M rows, this reads 100M rows to return a few thousand
```

### Why It Appears to Work in Development

Development clusters have small datasets. A full scan of 10,000 rows is fast. A full scan of 100,000,000 rows in production is not. ALLOW FILTERING queries that pass QA can cause production outages.

### The Correct Fixes

**Option 1: Fix the data model**
Design the table so the query can be served by the PRIMARY KEY structure. This is almost always the right answer.

```sql
-- Instead of filtering by total, model for the query:
CREATE TABLE large_orders (
    customer_id uuid,
    order_id    uuid,
    total       decimal,
    PRIMARY KEY (customer_id, order_id)
);
-- Now filter by total is within a single partition — acceptable with SAI
```

**Option 2: Use SAI with the partition key**
SAI can filter on non-primary-key columns without a full table scan — but only when the partition key is included.

```sql
CREATE INDEX orders_by_total ON orders (total) USING 'sai';
-- Must include partition key:
SELECT * FROM orders WHERE customer_id = ? AND total > 100;
```

This is covered in depth in a dedicated training.

**Option 3: Use an external search system**

For full-text search, complex multi-field filtering, or ad-hoc analytics queries, use a dedicated search system:

- **OpenSearch / Elasticsearch**: full-text search, complex filters, faceted search
- **Apache Spark + cassandra-analytics**: bulk analytics over the entire dataset

---

## Examples

### Identifying ALLOW FILTERING in existing code

```sql
-- Original table: products keyed by product_id
CREATE TABLE products (
    product_id uuid PRIMARY KEY,
    name       text,
    category_id uuid,
    price      decimal
);
```

```python
# Code review red flag: any query containing ALLOW FILTERING
session.execute("SELECT * FROM products WHERE category_id = ? ALLOW FILTERING", [category_id])
# category_id is not the partition key — this scans every product in the cluster
```

### Correct: model for the query

```sql
-- Query: "get all products in a category"
-- Fix: create a table where category_id is the partition key

CREATE TABLE products_by_category (
    category_id uuid,
    product_id  uuid,
    name        text,
    price       decimal,
    PRIMARY KEY (category_id, product_id)
);

-- Now the query is efficient — reads a single partition:
SELECT * FROM products_by_category WHERE category_id = ?;
```

### Correct: use OpenSearch for complex filtering
```python
# For ad-hoc multi-field filtering without knowing the query shape upfront,
# sync data to OpenSearch and query there
from opensearchpy import OpenSearch

client = OpenSearch([{'host': 'localhost', 'port': 9200}])

response = client.search(
    index='orders',
    body={
        'query': {
            'bool': {
                'must': [
                    {'range': {'total': {'gt': 100}}},
                    {'term': {'status': 'pending'}}
                ]
            }
        }
    }
)
```

---

## Pulse Check

> A teammate adds this query to the codebase to power a reporting dashboard:
> ```sql
> SELECT * FROM transactions
> WHERE amount > 1000
>   AND currency = 'USD'
> ALLOW FILTERING;
> ```
>
> **Why is this dangerous?**

*(Expected answer: This is a full table scan — it reads every row in the transactions table to find those matching the filter. In production with millions of rows, this saturates I/O and degrades the whole cluster. The correct fix is a data-model change: create a purpose-built table whose partition or clustering keys match the query's filter predicates, or use an SAI index with the partition key always present in the query.)*

---

## See Also

**In this session:**
- [IN() Queries](./01-in-queries.md)
- [Token Range Queries](./03-token-range-queries.md)
- [Aggregation Queries](./04-aggregations.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Large Partitions](../../general/large-partitions.md)
- [Dropped Messages](../../general/dropped-messages.md)
