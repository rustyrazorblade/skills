# Topic: SAI vs. Denormalization — Choosing the Right Tool

## Objective
Make a principled decision between an SAI index and a dedicated denormalized table for a given query pattern.

## Why This Matters
Both SAI and denormalization solve the same problem — querying data by a column that isn't the partition key. But they make opposite trade-offs. Choosing the wrong one means either unpredictable read performance (SAI on a hot path) or unnecessary write complexity (denormalization for a rarely-used lookup). Knowing when to use each is a core Cassandra design skill.

---

## Concept

### The Trade-offs

| | SAI Index | Denormalized Table |
|---|---|---|
| **Read performance** | Good with partition key; degrades without it | Always O(1) — direct partition lookup |
| **Write overhead** | Index maintained automatically | You maintain both tables explicitly |
| **Query flexibility** | Range queries, filtering, collections | Fixed to the table's PRIMARY KEY |
| **Best for** | Infrequent, flexible queries | High-throughput, predictable queries |
| **Risk** | Missing partition key → cluster-wide scan | Write to one table fails → inconsistency |

### Decision Framework

**Use SAI when:**
- The partition key is always present in the query
- The query runs infrequently (not on the critical path)
- The alternative would be a second table that's rarely written to
- You need range queries or collection filtering that can't be modeled with clustering columns

**Use a denormalized table when:**
- The query is high-throughput or latency-sensitive
- You can't guarantee the partition key is present in every query
- The access pattern is fixed and well-known
- You need the fastest possible read performance

### The Key Question

> *"Is this query on the critical path?"*

If yes → denormalize. If no, and the partition key is always present → SAI is fine.

---

## Examples

### Scenario 1: User lookup — denormalize

A login flow runs millions of times per day. Users log in by email, but the primary key is `user_id`.

```sql
-- High-traffic path: use a dedicated table
CREATE TABLE users_by_email (
    email   text PRIMARY KEY,
    user_id uuid
);

-- Login: two fast partition lookups
SELECT user_id FROM users_by_email WHERE email = ?;
SELECT * FROM users WHERE user_id = ?;
```

An SAI index on `email` could work, but login is on the critical path — denormalization is more predictable and faster.

### Scenario 2: Admin order search — use SAI

An internal admin tool lets support staff search a customer's orders by status. This runs a few hundred times per day, and `customer_id` is always known.

```sql
CREATE INDEX orders_by_status ON orders (status) USING 'sai';

-- Admin query: partition key present, low traffic — SAI is fine
SELECT * FROM orders WHERE customer_id = ? AND status = 'refunded';
```

A second table (`orders_by_status`) would work but adds write complexity for a low-volume use case. SAI is the right trade-off here.

### Scenario 3: Denormalize when the partition key is unknown

A messaging app needs:
1. List messages in a conversation (high-traffic)
2. Look up a specific message by ID from admin tools (occasional, and the `conversation_id` is usually not known)

The second query looks like a case for SAI — but it isn't. **The SAI partition-key rule applies regardless of query frequency.** A query that can't be scoped to a partition should not be an SAI query, even if it runs rarely. The right pattern here is a dedicated lookup table:

```sql
-- Primary table: optimized for listing (high-traffic path)
CREATE TABLE messages (
    conversation_id uuid,
    message_id      timeuuid,
    body            text,
    PRIMARY KEY (conversation_id, message_id)
) WITH CLUSTERING ORDER BY (message_id DESC);

-- Dedicated lookup table for admin tools that only have message_id
CREATE TABLE messages_by_id (
    message_id      timeuuid PRIMARY KEY,
    conversation_id uuid,
    body            text
);

-- High-traffic: fast partition scan, newest first
SELECT * FROM messages WHERE conversation_id = ? LIMIT 50;

-- Extract creation time from the timeuuid — no separate column needed.
-- (Shown here for demonstration; in application code, use your driver's
-- timeuuid utilities to extract the timestamp client-side rather than
-- paying for it in CQL on every read.)
SELECT toTimestamp(message_id), body FROM messages WHERE conversation_id = ? LIMIT 50;

-- Admin lookup: direct partition read on the lookup table
SELECT * FROM messages_by_id WHERE message_id = ?;
```

Writes go to both tables, ideally wrapped in a LOGGED BATCH so the two stay consistent.

`message_id` as a `timeuuid` does triple duty: it's a globally unique identifier, it encodes the creation time (so no separate `sent_at` column), and as the clustering key on `messages` it sorts the partition in chronological order. It also works as the partition key on `messages_by_id` because it's globally unique.

The key takeaway: "infrequent" is not a loophole for the SAI partition-key rule. If you can't scope the query to a partition, denormalize — even if the query runs once a day.

---

## Pulse Check

> You're building a job board. Jobs are stored with `company_id` as the partition key. You need to support two queries:
>
> 1. "Show all jobs posted by a company" — runs constantly, shown on every company profile page
> 2. "Show all jobs tagged 'remote'" — runs when a user applies a filter, moderately frequent
>
> **Which approach would you use for each query, and why?**

*(Expected answer: Query 1 is the primary access pattern — it's already served by the partition key (`company_id`), no index or denormalization needed. Query 2 is a filter on a non-key column (`tags`). If `company_id` is always present in the filter query (e.g., "remote jobs at this company"), SAI on `tags` is appropriate. If users can search "all remote jobs" across all companies without a company context, SAI without a partition key will degrade — and a denormalized table like `jobs_by_tag` with `PRIMARY KEY (tag, job_id)` is the right answer.)*

---

## See Also

**In this session:**
- [SAI Overview — Why This Session Exists](./01-sai-overview.md)
- [What SAI Is and Why the Partition Key Rule Exists](./02-what-is-sai.md)
- [Querying with SAI — Patterns and Anti-Patterns](./04-querying-with-sai.md)

**Reference:**
- [SAI FAQ (Apache Cassandra)](https://cassandra.apache.org/doc/latest/cassandra/developing/cql/indexing/sai/sai-faq.html)
- [Batches](../../general/batches.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [SSTable Components](../../general/sstable-components.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
