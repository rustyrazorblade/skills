# Topic: Too Many Tables

## Objective
Recognize when a schema has proliferated into too many narrow tables, and understand how to consolidate them into fewer, wider tables.

## Why This Matters
A common Cassandra mistake is creating a separate table for every slight variation in query pattern. This leads to schemas with hundreds of tables, each with only a few columns, maintained across dozens of write paths. It increases operational complexity, makes schema evolution painful, and often performs worse than a well-designed consolidated table.

---

## Concept

### How It Happens

The "one table per query" principle is correct — but it doesn't mean "one table per column combination." Developers new to Cassandra sometimes interpret it too literally and create a new table for every possible filter or projection:

```sql
-- Overfit to individual queries:
CREATE TABLE users_by_id (...);
CREATE TABLE users_by_email (...);
CREATE TABLE users_by_username (...);
CREATE TABLE users_active (...);
CREATE TABLE users_inactive (...);
CREATE TABLE users_premium (...);
-- ...and so on
```

### The Problem

- **Write amplification**: every user record must be written to 6+ tables
- **Consistency risk**: if any write fails, tables diverge
- **Schema sprawl**: hundreds of tables are hard to understand, evolve, and maintain
- **Compaction overhead**: each table has its own compaction workload

### The Fix: Fewer, Wider Tables

Design around your actual access patterns — the distinct query shapes, not every possible column filter. Use SAI (Storage-Attached Index — covered in depth in a dedicated session) for low-traffic filters instead of dedicated tables. Denormalize only for genuinely different partition structures.

```sql
-- Consolidated: one primary table + one lookup table for email
CREATE TABLE users (
    user_id   uuid PRIMARY KEY,
    email     text,
    username  text,
    status    text,
    tier      text,
    created_at timestamp
);

CREATE TABLE users_by_email (
    email   text PRIMARY KEY,
    user_id uuid
);

-- SAI for infrequent filters (status, tier) — no extra tables needed
CREATE INDEX users_by_status ON users (status) USING 'sai';
CREATE INDEX users_by_tier   ON users (tier)   USING 'sai';
```

### When Multiple Tables Are Justified

Multiple tables are the right answer when the **partition structure** genuinely differs — when you need to group data by a different partition key for a different access pattern:

```sql
-- These have fundamentally different partition keys — separate tables are correct
CREATE TABLE orders (PRIMARY KEY (order_id));            -- lookup by order
CREATE TABLE orders_by_customer (PRIMARY KEY (customer_id, created_at)); -- list by customer
```

The signal: if two tables have the same partition key but different column projections, they can probably be one table.

---

## Examples

### Before: over-segmented schema
```sql
CREATE TABLE active_users   (user_id uuid PRIMARY KEY, ...);
CREATE TABLE inactive_users (user_id uuid PRIMARY KEY, ...);
CREATE TABLE premium_users  (user_id uuid PRIMARY KEY, ...);
-- Three write paths for the same entity, must stay in sync
```

### After: single table + SAI
```sql
CREATE TABLE users (
    user_id    uuid PRIMARY KEY,
    status     text,   -- 'active', 'inactive'
    tier       text,   -- 'free', 'premium'
    email      text,
    created_at timestamp
);

CREATE INDEX users_by_status ON users (status) USING 'sai';
CREATE INDEX users_by_tier   ON users (tier)   USING 'sai';

-- Queries:
SELECT * FROM users WHERE user_id = ?;
SELECT * FROM users WHERE user_id = ? AND status = 'active';
SELECT * FROM users WHERE user_id = ? AND tier = 'premium';
```

---

## Pulse Check

> A developer has created these four tables for a product catalog:
> - `products_electronics` — products where category = 'electronics'
> - `products_clothing` — products where category = 'clothing'
> - `products_books` — products where category = 'books'
> - `products_by_id` — all products, looked up by product_id
>
> **What's wrong with this design, and how would you consolidate it?**

*(Expected answer: Three of the four tables duplicate the same data segmented by category — they'll diverge if writes fail, and adding a new category requires a new table. Consolidate to one `products` table with `product_id` as the partition key, keep `category` as a column, and use an SAI index on `category` for category-filtered queries. The category tables can be dropped.)*

---

## See Also

**In this session:**
- [Too Many Columns](./04-too-many-columns.md)
- [Secondary Indexes Without Partition Keys](./08-secondary-indexes.md)

**Reference:**
- [Memtables](../../general/memtables.md)
- [Compaction](../../general/compaction.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
