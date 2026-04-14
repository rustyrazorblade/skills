# Topic: Counters

## Objective
Understand how Cassandra counters work, why they can be inaccurate under failure conditions, and when they are and aren't the right choice.

## Why This Matters
Counters seem like a natural fit for tracking counts, scores, and totals. But Cassandra's counter implementation has specific failure modes that can produce inaccurate counts. Understanding these limitations helps you decide when counters are acceptable and when you need a different approach.

---

## Concept

### How Counters Work

Cassandra counters use a distributed counter mechanism where each replica maintains a shard of the count. Incrementing a counter requires a read-before-write to retrieve the current value and add the delta. The final count is the sum of all replica shards.

```sql
CREATE TABLE page_views (
    page_id   text PRIMARY KEY,
    views     counter
);

-- Increment
UPDATE page_views SET views = views + 1 WHERE page_id = ?;

-- Read
SELECT views FROM page_views WHERE page_id = ?;
```

### Why Counters Can Be Inaccurate

**Double-counting on failure.** Counter increments are not idempotent. If a coordinator sends an increment to a replica, the replica applies it, but the acknowledgement is lost (network failure), the coordinator retries — applying the increment twice. The counter is now off by one.

At high throughput, under normal network conditions, these errors are rare but not zero. Over time and at scale, the accumulated error can be significant.

**No read-before-write is truly safe.** The read-before-write at the heart of counter updates creates a window for races under concurrent increments.

### When Counters Are Acceptable

Counters are the right tool when:
- **Small deviations are acceptable**: page views, approximate engagement metrics, "likes" counts
- **The exact value doesn't matter**: you want a rough order of magnitude, not a precise total
- **Simplicity matters more than precision**: counters are easy to use and require no external coordination

### When Counters Are NOT Acceptable

- **Financial totals**: any counter used in accounting, billing, or money movement must be exact
- **Inventory tracking**: off-by-one errors in inventory can cause overselling
- **Security or compliance contexts**: access counts, audit logs

### Alternatives for Exact Counts

**Application-level idempotency**: assign a unique ID to each increment event. Track which events have been applied. Only count each event once.

**Track individual events**: If you require exact numbers on something such as a "like", you'll be tracking the individual like events in tables similar to this:

```sql
-- Table 1: Track who liked each photo (one row per like)
CREATE TABLE photo_likes (
    photo_id uuid,
    user_id  uuid,
    liked_at timestamp,
    PRIMARY KEY (photo_id, user_id)
);

-- "Did this user like this photo?" → single partition lookup
-- "Who liked this photo?" → partition scan
-- "How many likes?" → COUNT(*) on a single partition (exact)

-- Table 2: Track which photos a user has liked
CREATE TABLE user_liked_photos (
    user_id  uuid,
    photo_id uuid,
    liked_at timestamp,
    PRIMARY KEY (user_id, photo_id)
);

-- "Which photos has this user liked?" → partition scan
```

Both tables are written together when a user likes a photo. This gives you exact counts and the ability to check for duplicates — something counters cannot do.

For fastest reads, track the like count on the photo table as an int, or use a dedicated counter table that's reconciled periodically.  Sometimes eventually consistent / correct is an acceptable tradeoff.

---

## Examples

### Correct use: approximate page view counter
```sql
CREATE TABLE page_views (
    page_id text PRIMARY KEY,
    views   counter
) WITH compression = {
    'class': 'LZ4Compressor',
    'chunk_length_in_kb': 4   -- small chunks minimize decompression overhead per read
}
AND compaction = {
    'class': 'UnifiedCompactionStrategy',  -- UCS on 5.0+; LCS on older versions. Never STCS or TWCS.
    'scaling_parameters': 'L12' -- minimize SSTables per read.
};

-- Increment on each page view
UPDATE page_views SET views = views + 1 WHERE page_id = ?;

-- Display the count — approximate is fine for "1.2M views"
SELECT views FROM page_views WHERE page_id = ?;
```

**Why LZ4 with 4KB chunks?** Every counter write requires a read-before-write. LZ4 is the fastest decompressor, and 4KB chunks mean only 4KB is decompressed per counter read — vs. 16KB with the default chunk size, or 64KB in older versions. This reduces per-write CPU overhead by up to 10-15x on counter-heavy tables.

### Incorrect use: inventory counter
```sql
-- ANTI-PATTERN: inventory must be exact
CREATE TABLE inventory (
    product_id text PRIMARY KEY,
    quantity   counter  -- never do this for inventory
);
```

```sql
-- CORRECT: use LWT for inventory (strong consistency, exact)
UPDATE inventory SET quantity = ?
WHERE product_id = ?
IF quantity >= ?;
-- Or use a proper transactional system for inventory management
```

### Counter table restrictions

Counter tables have special restrictions:
```sql
-- Counter tables can ONLY have counter columns and primary key columns
-- You cannot mix counter and non-counter columns
CREATE TABLE stats (
    entity_id text PRIMARY KEY,
    views     counter,
    likes     counter,
    shares    counter
    -- name text  ← ILLEGAL: can't mix counter and non-counter
);
```

---

## Pulse Check

> A teammate proposes using a Cassandra counter to track the number of items remaining in stock for an e-commerce platform. When stock hits 0, purchases are rejected.
>
> **Is this appropriate? What could go wrong?**

*(Expected answer: No — inventory requires exact counts. Cassandra counters can double-count under failure conditions (network retries applying increments twice). If inventory shows 1 item remaining but the counter is off by 1 due to a retry, a customer could purchase an item that isn't actually in stock. Inventory management needs exact, consistent counts — use a transactional system, LWT-based compare-and-set, or a purpose-built inventory service. Cassandra counters are for approximate metrics where small errors are acceptable.)*

---

## See Also

**In this session:**
- [BATCH Misuse](./05-batch-misuse.md)
- [Lightweight Transactions (LWT)](./06-lightweight-transactions.md)

**Reference:**
- [Counters](../../general/counters.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Lightweight Transactions (LWT)](../../general/lwt.md)
- [Compression](../../general/compression.md)
