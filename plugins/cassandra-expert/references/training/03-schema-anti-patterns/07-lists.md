# Topic: Lists

## Objective
Understand why Cassandra lists are problematic even when bounded, and when to use sets or maps instead.

## Why This Matters
Lists are the most dangerous collection type in Cassandra. Even for small, bounded use cases — where a collection would otherwise be fine — lists carry operational risks that sets and maps do not. In almost every case where you'd reach for a list, a set or map is the correct choice.

---

## Concept

### Why Lists Are Dangerous

**1. Read-before-write on every mutation.**
Appending to or prepending from a list requires Cassandra to read the existing list to determine positioning. This adds a read to every write operation — expensive at scale, and a source of race conditions.

**2. Duplicate values cause inconsistency.**
Lists allow duplicates. Under concurrent writes from multiple clients, the same item can be appended multiple times, leading to subtle data corruption that is hard to detect and clean up.

**3. Deletion by value is expensive.**
Deleting a specific element from a list requires specifying its position index, or deleting by value (which scans the entire list). This is fragile and error-prone.

**4. Ordering is a false promise.**
Lists seem to provide ordering, but concurrent appends from multiple nodes can produce unpredictable orderings. If you need reliable ordering, use a clustering column.

### The Alternatives

| Use Case | Use Instead |
|----------|-------------|
| Unique items, any order | `set<T>` — deduplicates automatically, no read-before-write |
| Key→value pairs | `map<K, V>` — keyed access, no read-before-write for individual keys |
| Ordered items | Dedicated table with a clustering column |
| Last N items | Dedicated table with `LIMIT N` |

### When Lists Are Acceptable

Lists are acceptable only when:
- The list is **write-once** (populated at insert, never appended to)
- The list is **small and bounded** (a handful of items)
- Duplicates don't matter
- You never need to delete individual items

A list of 3 pre-defined configuration values written once at creation time is fine. A list of user activity events is not.

---

## Examples

### Anti-pattern: tags as a list
```sql
-- ANTI-PATTERN: list allows duplicate tags, read-before-write on append
CREATE TABLE articles (
    article_id uuid PRIMARY KEY,
    tags       list<text>
);

UPDATE articles SET tags = tags + ['cassandra'] WHERE article_id = ?;
-- Reads existing tags, appends 'cassandra', writes back
-- Concurrent appends can duplicate tags
```

```sql
-- CORRECT: set deduplicates automatically, no read-before-write
CREATE TABLE articles (
    article_id uuid PRIMARY KEY,
    tags       set<text>
);

UPDATE articles SET tags = tags + {'cassandra'} WHERE article_id = ?;
-- Atomic add, no read required, no duplicates possible
```

### Anti-pattern: recent login IPs as a list
```sql
-- ANTI-PATTERN: list, read-before-write, potential duplicates
CREATE TABLE users (
    user_id    uuid PRIMARY KEY,
    recent_ips list<text>
);
```

```sql
-- CORRECT: map with timestamp as key, keeps last N naturally
CREATE TABLE users (
    user_id    uuid PRIMARY KEY,
    recent_ips map<timestamp, text>  -- {login_time: ip_address}
);
```

```sql
-- BETTER CORRECT: dedicated table, fully queryable, bounded with TTL
CREATE TABLE user_login_history (
    user_id    uuid,
    login_time timestamp,
    ip_address inet,
    PRIMARY KEY (user_id, login_time)
) WITH CLUSTERING ORDER BY (login_time DESC)
  AND default_time_to_live = 2592000;  -- 30 days
```

---

## Pulse Check

> A developer stores a product's image URLs as a `list<text>`. Products have 3-10 images, set at product creation and occasionally updated (adding or removing individual images).
>
> **Should they use a list, and if not, what should they use instead?**

*(Expected answer: No — even though the list is small and bounded, mutations (adding/removing images) trigger read-before-write and are vulnerable to concurrent write races. Use a `set<text>` instead: it deduplicates, has no read-before-write overhead, and adding/removing individual URLs is atomic. If image ordering matters, use a dedicated `product_images` table with a `position` clustering column.)*

---

## See Also

**In this session:**
- [Unbounded Collections](./06-unbounded-collections.md)
- [Secondary Indexes Without Partition Keys](./08-secondary-indexes.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Large Partitions](../../general/large-partitions.md)
