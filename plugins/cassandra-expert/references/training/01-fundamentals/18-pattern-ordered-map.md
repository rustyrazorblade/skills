# Topic: Table Pattern — Ordered Map

## Objective
Use clustering columns to build an ordered, range-queryable collection of rows within a single partition — the ordered map pattern.

## Why This Matters
Most real-world entities aren't single rows — they have lists, histories, or grouped sub-records. The ordered map pattern is how Cassandra handles one-to-many relationships efficiently, within a single partition and without a JOIN. Getting this right eliminates the temptation to reach for `ALLOW FILTERING` or secondary indexes.

---

## Concept

An ordered map is a partition with **multiple rows**, sorted by one or more clustering columns. Think of it as a sorted key→value structure where the partition key is the outer key and the clustering column is the inner key.

```
Partition Key (outer key)
  └─ Clustering Col = A → row
  └─ Clustering Col = B → row
  └─ Clustering Col = C → row
```

All rows in the partition live on the same node, stored sorted on disk. This makes range queries on clustering columns extremely efficient — Cassandra reads a contiguous slice.

### What It Enables

- **Range queries**: `WHERE partition_key = ? AND clustering_col > ? AND clustering_col < ?`
- **Prefix queries**: `WHERE partition_key = ? AND clustering_col_1 = ? AND clustering_col_2 > ?`
- **Ordered results without sorting**: data comes back in clustering column order
- **Efficient LIMIT**: `LIMIT 10` reads only 10 rows from the sorted partition

### Anti-Pattern: Secondary Indexes as a Substitute

If you find yourself adding a secondary index to look up rows inside a partition by a non-clustering column, stop. Redesign the table so that column is a clustering column instead. (Secondary indexes and SAI are covered in depth in later sessions — for now, just understand that reaching for an index inside a partition usually means the table structure is wrong.)

---

## Examples

### User settings / preferences
```sql
-- "Get all settings for a user" or "Get a specific setting"
CREATE TABLE user_settings (
    user_id uuid,
    setting_name text,
    setting_value text,
    updated_at timestamp,
    PRIMARY KEY (user_id, setting_name)
);

-- Write individual settings
INSERT INTO user_settings (user_id, setting_name, setting_value, updated_at)
VALUES (?, 'theme', 'dark', toTimestamp(now()));

INSERT INTO user_settings (user_id, setting_name, setting_value, updated_at)
VALUES (?, 'notifications', 'enabled', toTimestamp(now()));

-- Read all settings for a user (full partition scan — fine, small partition)
SELECT * FROM user_settings WHERE user_id = ?;

-- Read a specific setting (single row lookup)
SELECT setting_value FROM user_settings
WHERE user_id = ? AND setting_name = 'theme';
```

### Order line items
```sql
-- "Get all line items for an order"
CREATE TABLE order_items (
    order_id uuid,
    item_id uuid,
    product_sku text,
    quantity int,
    unit_price decimal,
    PRIMARY KEY (order_id, item_id)
);

-- Get all items in an order
SELECT * FROM order_items WHERE order_id = ?;
```

### Multi-column clustering with range query
```sql
-- "Get a user's notifications, newest first, optionally filtered by type"
CREATE TABLE notifications (
    user_id uuid,
    notification_type text,
    created_at timestamp,
    message text,
    read boolean,
    PRIMARY KEY (user_id, notification_type, created_at)
) WITH CLUSTERING ORDER BY (notification_type ASC, created_at DESC);

-- All notifications for a user
SELECT * FROM notifications WHERE user_id = ? LIMIT 50;

-- Notifications of a specific type, newest first
SELECT * FROM notifications
WHERE user_id = ?
  AND notification_type = 'order_update'
LIMIT 20;
```

### Python example
```python
get_settings = session.prepare(
    "SELECT setting_name, setting_value FROM user_settings WHERE user_id = ?"
)
get_one_setting = session.prepare(
    "SELECT setting_value FROM user_settings WHERE user_id = ? AND setting_name = ?"
)

def get_all_settings(user_id):
    return {row.setting_name: row.setting_value
            for row in session.execute(get_settings, [user_id])}

def get_setting(user_id, name):
    row = session.execute(get_one_setting, [user_id, name]).one()
    return row.setting_value if row else None
```

### Java example
```java
PreparedStatement getSettings = session.prepare(
    "SELECT setting_name, setting_value FROM user_settings WHERE user_id = ?"
);

public Map<String, String> getAllSettings(UUID userId) {
    return session.execute(getSettings.bind(userId))
        .all()
        .stream()
        .collect(Collectors.toMap(
            row -> row.getString("setting_name"),
            row -> row.getString("setting_value")
        ));
}
```

---

## Pulse Check

> You're building a leaderboard. You need to store scores for each game, and retrieve **all scores for a given game sorted by score descending**.
>
> **Write the PRIMARY KEY for this table.**

*(Expected answer: `PRIMARY KEY (game_id, score)` with `CLUSTERING ORDER BY (score DESC)`. Partition key = `game_id` (all scores for one game on one node). Clustering column = `score DESC` (results come back sorted by score automatically).)*

**[TRAINER NOTE: Only ask the follow-up below once the learner has correctly answered the question above.]**

> Now a new requirement: **"Get all scores for a specific user in a specific game."**
>
> **Write the PRIMARY KEY for a second table that supports this query.**

*(Expected answer: `PRIMARY KEY ((user_id, game_id), score)`. The composite partition key co-locates all scores for a given user+game on one node. This is a separate denormalized table, written alongside the leaderboard table.)*

---

## See Also

**In this session:**
- [Partition Keys and Clustering Columns](./06-partition-key-clustering.md)
- [Pattern: Single Key](./17-pattern-single-key.md)
- [Pattern: Time Series](./19-pattern-time-series.md)
- [Denormalization](./20-denormalization.md)

**Reference:**
- [Large Partitions](../../general/large-partitions.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [SSTable Components](../../general/sstable-components.md)
