# Topic: Advanced Types — Collections, Static Columns, and Counters

## Objective
Understand CQL's specialized types — collections, static columns, and counters — and know which ones have footguns you should avoid.

## Why This Matters
Beyond the basic scalar types, CQL offers a few specialized types that exist to solve specific modeling problems. Some of them (collections, static columns) are useful when applied correctly. Others (lists, counters) have footguns that cause production problems if you don't know what you're getting into. Now that you understand clustering columns, these types can be framed properly: most of them are alternatives to — or supplements for — a table with clustering columns.

---

## Concept

### Collection Types

Collections let a single column hold multiple values. CQL supports three: **set**, **map**, and **list**.

Collections are meant for small amounts of data — think "labels on an email" or "phone numbers for a contact." They are **not** a replacement for a table with clustering columns. If the data can grow unbounded, use a proper table with clustering columns instead. The whole reason Cassandra has clustering columns is to efficiently store many rows within a partition — collections are for the cases where you have a handful of values that are always read together with the rest of the row.

#### Sets

A `set` is an unordered, unique collection of values:

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    tags set<text>
);

INSERT INTO users (user_id, email, tags)
VALUES (uuid(), 'alice@example.com', {'admin', 'beta'});
```

Sets are the default choice when you need a collection.

#### Maps

A `map` is a collection of key-value pairs, sorted by key:

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    preferences map<text, text>
);

INSERT INTO users (user_id, email, preferences)
VALUES (uuid(), 'alice@example.com', {'theme': 'dark', 'lang': 'en'});
```

#### Why Sets and Maps Are Safe: CRDTs

Sets and maps in Cassandra behave as [**Conflict-free Replicated Data Types (CRDTs)**](https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type). Their mutating operations — adding an element to a set, adding or removing a key from a map — are **commutative** and **idempotent**, which means replicas can receive the same updates in any order (or the same update more than once after a retry) and still converge to the same final state. A retried "add `admin` to tags" is indistinguishable from doing it once. That's why sets and maps are safe under Cassandra's eventual-consistency model and under client-side retries. (Eventual consistency and consistency levels are covered in depth later in this session — for now, just know that replicas may briefly disagree and Cassandra needs operations that still produce the correct result when applied more than once.)

Lists are the exception — and that's exactly why they're problematic.

#### Lists — Not Recommended

A `list` is an ordered collection of non-unique values. **Lists have significant footguns** — append/prepend operations are not idempotent, so a retried write after a timeout can cause duplicates. (Cassandra writes can fail with a timeout when the coordinator doesn't hear back from enough replicas in time; clients typically retry these, which is why idempotence matters. Timeouts and retries are covered properly when we get to consistency levels later in this session.) They also require read-before-write for some operations.

**Rule: prefer `set` over `list` whenever possible.** We'll explore why lists are problematic in the Schema Anti-Patterns session.

### Static Columns

A **static column** is a column whose value is shared across all rows in a partition. Normal columns have a different value in every row; a static column has exactly one value per partition.

Static columns only make sense in tables with clustering columns. In a table where the partition key is the entire primary key, each partition has exactly one row — so there's nothing to deduplicate across, and a static column would be identical to a regular column.

Static columns are useful when you have metadata that applies to the whole partition and would otherwise be duplicated on every row:

```sql
CREATE TABLE blog_posts (
    author_id uuid,
    post_id timeuuid,
    author_name text STATIC,   -- one value per author (partition)
    author_bio text STATIC,    -- one value per author (partition)
    title text,
    content text,
    PRIMARY KEY (author_id, post_id)
);
```

Every row for a given `author_id` shares the same `author_name` and `author_bio`. Cassandra stores these values once per partition, not once per row. Updating a static column updates it for the entire partition.

**Rules for static columns:**
- **Only valid in tables with clustering columns.**
- **Can't be part of the primary key.**
- **Updated independently** — you can `UPDATE` a static column without specifying any clustering column values:

```sql
-- Update applies to the whole partition, no clustering column needed
UPDATE blog_posts SET author_bio = 'Updated bio'
WHERE author_id = ?;
```

Static columns save space and write amplification compared to duplicating per-row metadata, but they're a niche tool — use them when the data naturally fits the "one value per partition" shape.

### Counters — Handle With Care

The `counter` type is a special 64-bit integer that supports atomic increment and decrement:

```sql
CREATE TABLE page_views (
    page_id uuid PRIMARY KEY,
    views counter
);

UPDATE page_views SET views = views + 1 WHERE page_id = ?;
```

Counters come with strict limitations:
- A table with a counter column can only contain counters (besides the primary key)
- Counter values can't be directly set — only incremented or decremented
- Counter updates are **not idempotent** — a retried update after a timeout may double-count

**Counters are an anti-pattern for most use cases.** We'll cover when they're appropriate and how to avoid them in the Query & Application Anti-Patterns session.

---

## Examples

### A table using a set
```sql
CREATE TABLE articles (
    article_id uuid PRIMARY KEY,
    title text,
    tags set<text>
);
```

### A table using a map
```sql
CREATE TABLE user_settings (
    user_id uuid PRIMARY KEY,
    settings map<text, text>
);
```

### A table using static columns
```sql
CREATE TABLE conversations (
    conversation_id uuid,
    message_id timeuuid,
    title text STATIC,                -- one per conversation
    participants set<uuid> STATIC,    -- one per conversation
    sender_id uuid,
    body text,
    PRIMARY KEY (conversation_id, message_id)
);
```

---

## Pulse Check

> You need to store the tags applied to each article. You're deciding between `list<text>` and `set<text>`.
>
> **Which should you choose, and why?**

*(Expected answer: `set<text>`. Tags are unique and unordered, which fits a set perfectly. Lists have footguns — append/prepend operations aren't idempotent, so a retried write after a timeout can cause duplicates. Prefer sets over lists unless you truly need ordered, non-unique values.)*

> You have a `messages` table partitioned by `conversation_id`, with `sent_at` as a clustering column. Each conversation has a title and a list of participant IDs that are the same on every message. You don't want to duplicate that metadata on every row.
>
> **What feature solves this, and why is it only valid here (and not in a table with no clustering columns)?**

*(Expected answer: Static columns. Declare `title text STATIC` and `participants set<uuid> STATIC` — they'll be stored once per partition and updated independently of clustering columns. They're only valid in tables with clustering columns because if each partition has one row (no clustering), a static column would be identical to a regular one — there's nothing to deduplicate across.)*

> You have `CREATE TABLE users (user_id uuid PRIMARY KEY, name text, created_at timestamp);` and someone proposes adding `last_login timestamp STATIC`.
>
> **Will Cassandra accept this? Why or why not?**

*(Expected answer: No — Cassandra will reject it. The `users` table has no clustering columns; the partition key `user_id` is the entire primary key, so each partition has exactly one row. A static column only makes sense when a partition contains multiple rows that share a per-partition value. Without clustering columns, STATIC is meaningless and invalid.)*

> Your team wants to use a counter column to track the number of "likes" on posts, and they plan to display an exact count on every page.
>
> **What's the risk, and when is a counter acceptable?**

*(Expected answer: Counter updates are not idempotent — if an update times out and is retried, it may double-count. Under failures, the displayed count can drift from reality. Counters are acceptable when small deviations don't matter (approximate analytics, view counts) but not when exact correctness is required. For accurate counts, write individual events to a regular table and aggregate them.)*

---

## See Also

**In this session:**
- [Basic Types](./03-types.md)
- [User-Defined Types (UDTs)](./08-udts.md)
- [Batches](./21-batches.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Large Partitions](../../general/large-partitions.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
