# Topic: Table Pattern — Single Key

## Objective
Recognize when to use the single key pattern and implement it correctly for direct, constant-time lookups.

## Why This Matters
The single key pattern is the simplest Cassandra table structure — one row per partition key, no clustering columns. It's the right default for any entity you look up by a unique identifier. Understanding it clearly establishes the baseline before learning more complex patterns.

---

## Concept

A single key table has one row per partition. The PRIMARY KEY is just the partition key — no clustering columns. Every read retrieves exactly one row from exactly one partition, which makes it extremely fast and predictable.

```sql
PRIMARY KEY (entity_id)
-- one row per entity_id
-- one node per entity_id
-- O(1) lookup, always
```

### When to Use It

- **Entity lookup by unique ID**: users, products, accounts, sessions
- **Key-value storage**: configuration values, feature flags, cached objects
- **No range queries needed**: you always look up by exact key

### When NOT to Use It

- You need to query multiple rows for one entity (use clustering columns)
- You need to list or range-scan entities (needs a separate table or index)
- The "key" isn't truly unique (e.g., email — needs its own lookup table)

### Common Mistake: Querying Without the Partition Key

```sql
-- This requires ALLOW FILTERING — never acceptable in production
SELECT * FROM users WHERE email = 'alice@example.com' ALLOW FILTERING;

-- The right answer: a separate lookup table
CREATE TABLE users_by_email (
    email text PRIMARY KEY,
    user_id uuid
);
```

If you need to look up users by email AND by user_id, you maintain two tables. That's denormalization — covered in a later topic.

---

## Examples

### User profile table
```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    email text,
    created_at timestamp,
    preferences map<text, text>
);

-- Write
INSERT INTO users (user_id, name, email, created_at)
VALUES (uuid(), 'Alice', 'alice@example.com', toTimestamp(now()));

-- Read — O(1), direct partition lookup
SELECT * FROM users WHERE user_id = ?;

-- Update a single column
UPDATE users SET name = 'Alice Smith' WHERE user_id = ?;
```

### Session store
```sql
CREATE TABLE sessions (
    session_id text PRIMARY KEY,
    user_id uuid,
    created_at timestamp,
    expires_at timestamp,
    metadata map<text, text>
) WITH default_time_to_live = 86400;  -- auto-expire after 24 hours
```

### Feature flags (key-value)
```sql
CREATE TABLE feature_flags (
    flag_name text PRIMARY KEY,
    enabled boolean,
    rollout_pct int,
    updated_at timestamp
);

SELECT enabled FROM feature_flags WHERE flag_name = 'new_checkout_flow';
```

### Python example

> **Note:** The examples below use **prepared statements** (`session.prepare(...)`), which are covered in depth in a later topic in this session. For now, the key rule is: call `session.prepare()` once at application startup and reuse the returned statement for every query. Never call `prepare()` inside a request handler.

```python
# Prepare at startup — not inside the request handler
get_user = session.prepare("SELECT * FROM users WHERE user_id = ?")

def get_user_profile(user_id):
    row = session.execute(get_user, [user_id]).one()
    return row
```

### Java example
```java
// Prepare once at application startup
PreparedStatement getUser = session.prepare(
    "SELECT * FROM users WHERE user_id = ?"
);

public User getUser(UUID userId) {
    Row row = session.execute(getUser.bind(userId)).one();
    return mapToUser(row);
}
```

---

## Pulse Check

> You're building a product catalog. Products are looked up by SKU (a unique string). Occasionally, products need to be updated (price changes, description edits).
>
> **Write the CREATE TABLE statement for this single-key table. What column would make a good partition key, and why?**

*(Expected answer: `sku text PRIMARY KEY`. SKU is unique per product, high cardinality (many distinct values → good distribution), and all product lookups are by SKU. Something like `category` as the partition key would be wrong — low cardinality, huge partitions.)*

---

## See Also

**In this session:**
- [Tables and the Primary Key](./04-tables-primary-key.md)
- [Pattern: Ordered Map](./18-pattern-ordered-map.md)
- [Denormalization](./20-denormalization.md)
- [Prepared Statements](./16-prepared-statements.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Row Cache](../../general/row-cache.md)
- [Prepared Statements](../../general/prepared-statements.md)
