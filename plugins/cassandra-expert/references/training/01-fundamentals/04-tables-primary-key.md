# Topic: Tables and the Primary Key

## Objective
Understand how Cassandra organizes data into tables and how the PRIMARY KEY defines both where a row lives and how rows are identified.

## Why This Matters
Before you can design tables well, you need a clear mental model of what a Cassandra table looks like and what the PRIMARY KEY actually does. Cassandra tables look superficially like relational tables — rows, columns, a primary key — but the PRIMARY KEY works very differently. Understanding this upfront prevents a cascade of confusion later.

---

## Concept

A Cassandra **table** is a collection of rows, where each row is identified by a **primary key**. You define tables using CQL, which looks a lot like SQL:

```sql
CREATE TABLE users (
    user_id uuid,
    name text,
    email text,
    created_at timestamp,
    PRIMARY KEY (user_id)
);
```

A row in Cassandra is a set of columns sharing the same primary key value. Unlike a relational database, there are no joins, no foreign keys, and no secondary indexes that work like you'd expect. Every row is identified — and located — entirely by its primary key.

### The Primary Key Has Two Parts

Every primary key in Cassandra has two components:

```
PRIMARY KEY ( (partition_key), clustering_column_1, clustering_column_2, ... )
```

1. **Partition key** — the *first* component, always required. Determines **which node** stores the row. Can be one column or multiple columns grouped as a tuple using double parentheses.
2. **Clustering columns** — zero or more columns that come after the partition key. Determine the **sort order** of rows within a partition.

### Just a Partition Key (No Clustering Columns)

The simplest case: one column, which is both the partition key and the entire primary key. Each value produces exactly one row.

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,   -- partition key only, no clustering columns
    name text,
    email text
);
```

This is equivalent to writing `PRIMARY KEY (user_id)`.

### Partition Key + Clustering Columns

When you add clustering columns, a single partition can hold many rows, sorted by the clustering columns:

```sql
CREATE TABLE messages (
    conversation_id uuid,   -- partition key
    sent_at timeuuid,       -- clustering column
    sender_id uuid,
    body text,
    PRIMARY KEY (conversation_id, sent_at)
);
```

**Why `timeuuid` and not `timestamp`?** This is the collision problem we discussed in the Basic Types topic. `timestamp` only has millisecond precision, so two messages sent in the same millisecond would produce the same clustering key value — and Cassandra would treat them as the *same row* and overwrite one with the other. `timeuuid` is time-ordered **and** guaranteed unique, which is exactly what a clustering column needs when you want to order by time.

#### How the Data Is Laid Out

All messages with the same `conversation_id` live in the same partition, and within that partition they are physically stored **sorted by `sent_at` ascending** (the default clustering order). Suppose three messages are inserted into conversation `abc` in this order:

```sql
-- Inserted in this order (out of time order):
INSERT INTO messages (conversation_id, sent_at, sender_id, body)
  VALUES (abc, <timeuuid @ 10:02:15.123>, alice, 'Hey');

INSERT INTO messages (conversation_id, sent_at, sender_id, body)
  VALUES (abc, <timeuuid @ 10:02:10.000>, bob,   'Hello');

INSERT INTO messages (conversation_id, sent_at, sender_id, body)
  VALUES (abc, <timeuuid @ 10:02:17.500>, alice, 'How are you?');
```

Even though they arrived out of order, Cassandra stores them within the partition sorted by the clustering column. A `SELECT * FROM messages WHERE conversation_id = abc` returns rows in clustering order:

| conversation_id | sent_at (timeuuid, shown as time) | sender_id | body           |
|-----------------|-----------------------------------|-----------|----------------|
| abc             | 10:02:10.000                      | bob       | `Hello`        |
| abc             | 10:02:15.123                      | alice     | `Hey`          |
| abc             | 10:02:17.500                      | alice     | `How are you?` |

This is **not** a runtime sort — the rows are physically stored on disk in this order inside the partition. That's the defining property of clustering columns: related rows are co-located and pre-sorted, which is what makes range queries like "give me the last 20 messages in this conversation" fast.

### Composite Partition Key

The partition key itself can be multiple columns grouped as a tuple. The **extra parentheses** around the partition key are required to distinguish the partition key from the clustering columns:

```sql
CREATE TABLE events (
    tenant_id uuid,
    event_date date,
    event_time timestamp,
    event_type text,
    data text,
    PRIMARY KEY ((tenant_id, event_date), event_time)
    --          ^^^^^^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^
    --          composite partition key   clustering column
);
```

In this table:
- `(tenant_id, event_date)` together form the partition key — a row's partition is determined by both columns
- `event_time` is the clustering column — rows within a partition are sorted by it

### Reading the PRIMARY KEY Syntax

| Syntax | Partition key | Clustering columns |
|--------|--------------|-------------------|
| `PRIMARY KEY (a)` | `a` | none |
| `PRIMARY KEY (a, b)` | `a` | `b` |
| `PRIMARY KEY (a, b, c)` | `a` | `b, c` |
| `PRIMARY KEY ((a, b))` | `a, b` | none |
| `PRIMARY KEY ((a, b), c)` | `a, b` | `c` |
| `PRIMARY KEY ((a, b), c, d)` | `a, b` | `c, d` |

**The rule:** whatever is inside the *innermost* parentheses is the partition key. Everything else is a clustering column.

---

## Examples

### Simple primary key (one row per user_id)
```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    email text
);
```

### Partition key + one clustering column
```sql
CREATE TABLE orders_by_customer (
    customer_id uuid,    -- partition key
    order_id timeuuid,   -- clustering column
    total decimal,
    status text,
    PRIMARY KEY (customer_id, order_id)
);
```

### Composite partition key
```sql
CREATE TABLE pageviews (
    site_id uuid,
    day date,
    viewed_at timestamp,
    url text,
    user_agent text,
    PRIMARY KEY ((site_id, day), viewed_at)
);
```

---

## Pulse Check

> Given this table definition:
>
> ```sql
> CREATE TABLE readings (
>     device_id uuid,
>     region text,
>     recorded_at timestamp,
>     value double,
>     PRIMARY KEY ((device_id, region), recorded_at)
> );
> ```
>
> **What is the partition key? What are the clustering columns?**

*(Expected answer: The partition key is the tuple `(device_id, region)` — both columns together determine the partition. The clustering column is `recorded_at`, which sorts rows within each partition.)*

---

## See Also

**In this session:**
- [Basic Types](./03-types.md)
- [Partition Storage](./05-partition-storage.md)
- [Partition Keys and Clustering Columns](./06-partition-key-clustering.md)
- [Denormalization](./20-denormalization.md)

**Reference:**
- [Large Partitions](../../general/large-partitions.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [SSTable Components](../../general/sstable-components.md)
