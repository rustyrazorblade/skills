# Topic: In-Memory Joins on Large Datasets

## Objective
Recognize when application-level joins on large datasets are a scalability problem, and replace them with denormalized tables.

## Why This Matters
Without JOINs in Cassandra, developers sometimes fetch large datasets from multiple tables and join them in application memory. For small datasets this works. At scale, it means fetching millions of rows across the network, joining them in a single application process, and returning a fraction of the data. This is slow, memory-intensive, and doesn't scale.

---

## Concept

### How It Happens

A developer needs data that spans two tables — say, orders with customer names. Without a JOIN, they fetch all orders, then look up customer names for each order:

```python
# ANTI-PATTERN: in-memory join on large datasets
orders = session.execute("SELECT order_id, customer_id, total FROM orders").all()
customer_cache = {}
result = []
for order in orders:
    if order.customer_id not in customer_cache:
        customer = session.execute(get_customer, [order.customer_id]).one()
        customer_cache[order.customer_id] = customer.name
    result.append({
        'order_id': order.order_id,
        'customer_name': customer_cache[order.customer_id],
        'total': order.total
    })
```

This reads every order into application memory, then does N customer lookups. At 1 million orders with 100K customers, this is:
- 1M rows over the network
- Up to 100K additional lookups
- Joining in a single process

### The Fix: Denormalize

Store the data you need together in the same table. If you need customer names alongside orders, put the customer name in the orders table.

```sql
-- Include customer_name at write time
CREATE TABLE orders (
    customer_id   uuid,
    order_id      uuid,
    customer_name text,    -- denormalized from users table
    total         decimal,
    created_at    timestamp,
    PRIMARY KEY (customer_id, order_id)
);

-- Write: denormalize at insert time
INSERT INTO orders (customer_id, order_id, customer_name, total, created_at)
VALUES (?, ?, ?, ?, toTimestamp(now()));
```

Yes, this means customer_name is duplicated across all their orders. Disk is cheap; in-memory joins at scale are not.

### When Updates Are a Concern

Denormalization raises a valid question: what if the customer changes their name? The answer depends on the use case:

- **Historical records** (orders, invoices): use the name at time of transaction — don't update old records
- **Current state** (active sessions, profiles): maintain the denormalized copy with a background job or at write time
- **Rarely changes**: accept eventual consistency — update denormalized copies asynchronously

### When In-Memory Joins Are Acceptable

In-memory joins on **small, bounded datasets** are fine:
- Joining a list of 20 results with a lookup table
- Enriching a single page of paginated results
- One-time data migrations

The problem is in-memory joins on **large or unbounded datasets**.

---

## Examples

### Anti-pattern: enriching a full dataset in memory
```python
# ANTI-PATTERN: fetches entire table then joins
all_orders = list(session.execute("SELECT * FROM orders"))  # 1M rows
# Now doing 1M customer lookups...
```

### Correct: denormalize at write time
```python
insert_order = session.prepare("""
    INSERT INTO orders (customer_id, order_id, customer_name, total, created_at)
    VALUES (?, ?, ?, ?, toTimestamp(now()))
""")

def place_order(customer_id, customer_name, total):
    order_id = uuid.uuid4()
    session.execute(insert_order, [customer_id, order_id, customer_name, total])
```

### Correct: in-memory join on a small result set (acceptable)
```python
# Fine: joining 20 order results with customer lookups
recent_orders = session.execute(get_recent_orders, [customer_id]).all()
# Only 20 lookups — acceptable
```

### Correct: use Spark for bulk analytics joins
```python
# For analytical joins over large datasets, use Spark
orders_df = spark.read.format("org.apache.cassandra.spark") \
    .option("table", "orders").load()
customers_df = spark.read.format("org.apache.cassandra.spark") \
    .option("table", "users").load()

# Spark handles the distributed join
result = orders_df.join(customers_df, "customer_id")
```

---

## Pulse Check

> An API endpoint returns a list of the 10 most recent orders for a customer, including the product name for each line item. A developer fetches the 10 orders, then queries the `products` table for each line item's product name.
>
> **Is this an in-memory join problem? Why or why not?**

*(Expected answer: No — this is fine. The dataset is small and bounded: 10 orders, each with a handful of line items. A few dozen product lookups is acceptable. The in-memory join anti-pattern applies to large or unbounded datasets — not to small, paginated result sets. The rule is: denormalize when the join dataset is large or when query frequency is high enough that the lookup overhead accumulates.)*

---

## See Also

**In this session:**
- [Synchronous (Blocking) Queries](./10-synchronous-queries.md)
- [Sorting Partitions in Memory](./12-in-memory-sorting.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Drivers](../../general/drivers.md)
