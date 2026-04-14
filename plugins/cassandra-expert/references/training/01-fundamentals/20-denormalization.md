# Topic: Denormalization

## Objective
Understand why Cassandra requires denormalized data models and how to design multiple tables to support different query patterns on the same data.

## Why This Matters
In a relational database, you normalize data into one canonical table and then query it flexibly with JOINs and indexes. In Cassandra, there are no JOINs. If you try to apply relational thinking, you'll end up with `ALLOW FILTERING`, secondary indexes on high-cardinality columns, and queries that scan entire nodes. The correct approach is to design one table per query pattern — duplicate the data, and make each table fast for its specific access pattern.

---

## Concept

**Denormalization** means storing the same data in multiple tables, each structured to answer a different query.

In relational databases, denormalization is a performance optimization applied reluctantly. In Cassandra, it's the **primary design technique** — not optional, not an optimization. It's how the data model works.

### The Query-First Design Process

In Cassandra, always start with the query, not the entity:

1. **List all queries** your application needs to make
2. **Design one table per query** with the partition key and clustering columns that make that query efficient
3. **Accept the duplication** — disk is cheap, slow reads are not

### What This Means in Practice

- A user can be stored in `users` (by user_id) AND `users_by_email` (by email)
- An order can be stored in `orders` (by order_id) AND `orders_by_customer` (by customer_id)
- When you write, you write to all relevant tables (usually in a logged batch if consistency matters)
- Each table is optimized for exactly one read pattern

### Write Consistency Across Denormalized Tables

Writing to multiple tables raises the question: what if one write fails? For writes that **must** eventually end up in all tables, use a **logged batch**:

```sql
BEGIN LOGGED BATCH
    INSERT INTO users (user_id, email, name) VALUES (?, ?, ?);
    INSERT INTO users_by_email (email, user_id) VALUES (?, ?);
APPLY BATCH;
```

**Logged batches are not free.** They write to a batchlog table on two coordinator replicas before the writes fan out, which adds latency and coordinator CPU. Use them when you genuinely need atomic multi-table writes for correctness — not as a convenience or a perceived performance optimization. The query anti-patterns session covers batch misuse in depth.

**Also important**: logged batches guarantee eventual consistency (all writes will eventually succeed), but NOT isolation — a reader may see partial state. For many use cases where occasional inconsistency is acceptable, firing the writes as independent concurrent async operations (without a batch) is faster and simpler.

### Materialized Views (Avoid)

Cassandra has a feature called **Materialized Views** that automatically maintains denormalized tables for you. Avoid them in production. They have a history of consistency bugs and significant write overhead. Maintain your own denormalized tables explicitly.

---

## Examples

### User lookup by ID and by email
```sql
-- Primary table: lookup by user_id
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    name text,
    created_at timestamp
);

-- Lookup table: lookup by email → get user_id
CREATE TABLE users_by_email (
    email text PRIMARY KEY,
    user_id uuid
);

-- Write path: always write to both
BEGIN LOGGED BATCH
    INSERT INTO users (user_id, email, name, created_at)
    VALUES (?, ?, ?, toTimestamp(now()));

    INSERT INTO users_by_email (email, user_id)
    VALUES (?, ?);
APPLY BATCH;

-- Read path:
-- Login (by email):
SELECT user_id FROM users_by_email WHERE email = ?;
-- Then:
SELECT * FROM users WHERE user_id = ?;

-- Profile page (by user_id):
SELECT * FROM users WHERE user_id = ?;
```

### Orders by order ID and by customer
```sql
-- Lookup a specific order
CREATE TABLE orders (
    order_id uuid PRIMARY KEY,
    customer_id uuid,
    status text,
    total decimal,
    created_at timestamp
);

-- List all orders for a customer, newest first
CREATE TABLE orders_by_customer (
    customer_id uuid,
    created_at timestamp,
    order_id uuid,
    status text,
    total decimal,
    PRIMARY KEY (customer_id, created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);

-- Write to both on order creation
BEGIN LOGGED BATCH
    INSERT INTO orders (order_id, customer_id, status, total, created_at)
    VALUES (?, ?, 'pending', ?, toTimestamp(now()));

    INSERT INTO orders_by_customer (customer_id, created_at, order_id, status, total)
    VALUES (?, toTimestamp(now()), ?, 'pending', ?);
APPLY BATCH;
```

### Python write pattern
```python
insert_user = session.prepare(
    "INSERT INTO users (user_id, email, name, created_at) VALUES (?, ?, ?, toTimestamp(now()))"
)
insert_user_by_email = session.prepare(
    "INSERT INTO users_by_email (email, user_id) VALUES (?, ?)"
)

def create_user(user_id, email, name):
    batch = BatchStatement(batch_type=BatchType.LOGGED)
    batch.add(insert_user, [user_id, email, name])
    batch.add(insert_user_by_email, [email, user_id])
    session.execute(batch)
```

### Java write pattern
```java
PreparedStatement insertUser = session.prepare(
    "INSERT INTO users (user_id, email, name, created_at) VALUES (?, ?, ?, toTimestamp(now()))"
);
PreparedStatement insertByEmail = session.prepare(
    "INSERT INTO users_by_email (email, user_id) VALUES (?, ?)"
);

public void createUser(UUID userId, String email, String name) {
    BatchStatement batch = BatchStatement.newInstance(BatchType.LOGGED)
        .add(insertUser.bind(userId, email, name))
        .add(insertByEmail.bind(email, userId));
    session.execute(batch);
}
```

> **Coming up next:** you may be wondering how to keep these denormalized tables in sync without losing writes partway through. That's exactly what the next topic — [Batches](./21-batches.md) — is for: logged batches are the tool built to atomically apply multiple writes across tables so they either all land or none do.

---

## Pulse Check

> You have a messaging app. Messages need to support two queries:
> 1. "Get a specific message by message_id"
> 2. "Get all messages in a conversation, newest first"
>
> **How many tables do you need? Sketch the PRIMARY KEY for each.**

*(Expected answer: Two tables. Table 1: `messages` with `PRIMARY KEY (message_id)` for direct lookup. Table 2: `messages_by_conversation` with `PRIMARY KEY (conversation_id, sent_at)` and `CLUSTERING ORDER BY (sent_at DESC)` for listing by conversation. When a message is written, it's inserted into both tables — ideally in a logged batch.)*

**[TRAINER NOTE: Once the learner answers correctly, offer the following simplification.]**

> If `conversation_id` is always available in your application when looking up a message, you can simplify to a single table using a **Storage-Attached Index (SAI)** on `message_id` instead of maintaining two tables. SAI is available in Cassandra 5.0+.
>
> See: `../04-sai/01-sai-overview.md` for how this works and when it's the right trade-off.

---

## See Also

**In this session:**
- [Tables and the Primary Key](./04-tables-primary-key.md)
- [Pattern: Single Key](./17-pattern-single-key.md)
- [Pattern: Ordered Map](./18-pattern-ordered-map.md)
- [Batches](./21-batches.md)

**Reference:**
- [Batches](../../general/batches.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
