# Topic: Unbounded Collections

## Objective
Recognize when a collection will grow without bound and replace it with a dedicated table.

## Why This Matters
Cassandra's collection types (list, set, map) are stored inline within a partition. An unbounded collection is an unbounded partition — the same problem as a huge partition, but hidden inside a single column. Collections that grow over time eventually cause the same read latency, GC pressure, and compaction problems as oversized wide rows.

---

## Concept

### How Collections Become a Problem

Collections seem like a natural fit for one-to-many relationships. A user has multiple tags, a post has multiple comments, an order has multiple events. But if there's no upper bound on how many items can be added, the collection grows indefinitely with the partition.

```sql
-- ANTI-PATTERN: comments stored as a list in the post partition
CREATE TABLE posts (
    post_id  uuid PRIMARY KEY,
    title    text,
    body     text,
    comments list<text>  -- grows without bound as comments are added
);
```

A post with 100,000 comments has a list with 100,000 elements — all stored in one partition. Reading the post requires deserializing the entire list even if you only want the first 10 comments.

### The Additional Problem with Lists

Lists in Cassandra have an extra cost: they use a `read-before-write` pattern to prepend or append items. Every `UPDATE ... SET comments = comments + ['new comment']` reads the existing list first. At scale this is expensive.

### The Fix: Use a Dedicated Table

Replace the collection with a table. This gives you:
- Bounded partition sizes (add a bucket if needed)
- Efficient range queries (clustering columns)
- No read-before-write overhead
- Ability to paginate through large result sets

```sql
-- CORRECT: comments as their own table
CREATE TABLE post_comments (
    post_id    uuid,
    comment_id timeuuid,
    author_id  uuid,
    body       text,
    PRIMARY KEY (post_id, comment_id)
) WITH CLUSTERING ORDER BY (comment_id DESC);

-- Get latest 20 comments for a post
SELECT * FROM post_comments WHERE post_id = ? LIMIT 20;
```

### When Collections Are Fine

Collections are appropriate when:
- The number of items is **small and bounded** (< 100 items, never grows arbitrarily)
- You always read all items (not paginating)
- The data is truly auxiliary metadata, not a core data set

Examples: a set of tags on a document (bounded), a map of feature flags (bounded), a list of the last 5 login IPs (bounded, capped in application code).

---

## Examples

### Anti-pattern: user's followed accounts as a set
```sql
-- ANTI-PATTERN: an active user might follow 50,000 accounts
CREATE TABLE users (
    user_id  uuid PRIMARY KEY,
    following set<uuid>  -- grows without bound
);
```

```sql
-- CORRECT: dedicated table
CREATE TABLE user_following (
    user_id     uuid,
    followed_id uuid,
    followed_at timestamp,
    PRIMARY KEY (user_id, followed_id)
);

-- Get who a user follows (paginated)
SELECT followed_id FROM user_following WHERE user_id = ? LIMIT 100;
```

### Anti-pattern: order events as a list
```sql
-- ANTI-PATTERN: an order's event history grows over its lifetime
CREATE TABLE orders (
    order_id uuid PRIMARY KEY,
    events   list<text>  -- 'created', 'paid', 'shipped', 'delivered', ...
);
```

```sql
-- CORRECT: dedicated event table
CREATE TABLE order_events (
    order_id   uuid,
    event_time timestamp,
    event_type text,
    data       text,
    PRIMARY KEY (order_id, event_time)
) WITH CLUSTERING ORDER BY (event_time ASC);
```

---

## Pulse Check

> A schema stores a user's notification history as a `list<text>` column on the users table. Users can receive thousands of notifications per month.
>
> **What's the problem and what's the correct design?**

*(Expected answer: The list grows without bound — an active user accumulates thousands of entries in a single collection inside the users partition. This causes the same problems as any huge partition: read amplification, GC pressure, slow compaction. Fix: create a dedicated `user_notifications` table with `PRIMARY KEY (user_id, created_at)` and `CLUSTERING ORDER BY (created_at DESC)`. Add a TTL or bucket by month to keep it bounded.)*

---

## See Also

**In this session:**
- [Huge Partitions](./01-huge-partitions.md)
- [Too Many Columns](./04-too-many-columns.md)
- [Lists](./07-lists.md)

**Reference:**
- [Large Partitions](../../general/large-partitions.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Tombstones](../../general/tombstones.md)
