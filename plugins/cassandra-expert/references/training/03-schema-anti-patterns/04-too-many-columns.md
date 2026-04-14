# Topic: Too Many Columns

## Objective
Recognize when a table has too many sparse or dynamic columns, and know when to use a serialized blob or a map instead.

## Why This Matters
Cassandra tables with hundreds of columns — especially when most rows only populate a few of them — are inefficient and hard to evolve. Wide sparse schemas waste storage, complicate schema migrations, and can cause read performance issues. When columns are truly dynamic (different per row), storing them as a serialized blob or a map is cleaner and more efficient.

---

## Concept

### The Problem: Sparse Wide Rows

A table with hundreds of columns where each row only fills in a handful of them is called a **sparse wide row**. The unfilled columns don't consume storage (Cassandra only stores non-null values), but the schema itself becomes a maintenance problem:

- Schema changes (`ALTER TABLE ADD COLUMN`) require coordination across all nodes
- Hundreds of columns in `system_schema.columns` makes the schema hard to reason about
- Application code that reads `SELECT *` and maps columns to objects becomes fragile as columns are added

### Common Cause: Attribute-Value Anti-Pattern

Teams trying to store arbitrary key-value metadata on an entity often end up with one column per attribute:

```sql
-- ANTI-PATTERN: one column per user attribute
CREATE TABLE user_profiles (
    user_id    uuid PRIMARY KEY,
    attr_color text,
    attr_size  text,
    attr_weight text,
    attr_material text,
    -- ... 200 more columns
);
```

### Fix Option 1: Map Column

When the keys are dynamic and the values are the same type, use a `map<text, text>`:

```sql
CREATE TABLE user_profiles (
    user_id    uuid PRIMARY KEY,
    attributes map<text, text>
);

-- Write
UPDATE user_profiles SET attributes['color'] = 'blue' WHERE user_id = ?;

-- Read all attributes
SELECT attributes FROM user_profiles WHERE user_id = ?;

-- Read one attribute
SELECT attributes['color'] FROM user_profiles WHERE user_id = ?;
```

**Caveat**: maps are still a collection — don't let them grow unbounded. If you need to query by attribute value, an SAI index on map entries works (SAI — Storage-Attached Index — is covered in depth in a dedicated session), but a dedicated table is better for high-throughput paths.

### Fix Option 2: Serialized Blob

When the schema is truly dynamic (variable keys and value types), serialize the entire object as JSON or another format and store it as a `text` or `blob` column:

```sql
CREATE TABLE user_profiles (
    user_id    uuid PRIMARY KEY,
    attributes text   -- JSON-serialized
);
```

**Trade-offs**:
- No ability to filter or index individual attributes within Cassandra
- Application owns serialization/deserialization
- Schema evolution is handled in application code, not DDL
- Works well when you always read the full object and don't need attribute-level filtering

### Fix Option 3: Keyed Attribute Table (usually the best choice)

When each user has an open-ended set of attributes/preferences, use a table with a composite primary key — the entity id as the partition key and the attribute name as the clustering column. Each attribute is its own row.

```sql
CREATE TABLE user_preferences (
    user_id    uuid,
    preference text,
    value      text,
    PRIMARY KEY (user_id, preference)
);

-- Write one preference
UPDATE user_preferences SET value = 'dark' WHERE user_id = ? AND preference = 'theme';

-- Read one preference
SELECT value FROM user_preferences WHERE user_id = ? AND preference = 'theme';

-- Read all preferences for a user (single-partition scan)
SELECT preference, value FROM user_preferences WHERE user_id = ?;

-- Delete one preference
DELETE FROM user_preferences WHERE user_id = ? AND preference = 'theme';
```

This is almost always the right answer when preferences are per-user and the set is open-ended. All of a user's preferences live in one partition, so reading them all is a single fast partition scan, and individual reads/writes hit a single row. Scales well (each user's set is independent), performs well (no collection deserialization cost, no JSON parsing), and evolves well (adding a new preference is just a write, not a schema change).

Use the map or blob options only when this table design doesn't fit — e.g. when the attributes are not per-entity or you need to always read/write the whole set atomically.

---

## Examples

### Before: 200-column sparse table
```sql
CREATE TABLE product_metadata (
    product_id uuid PRIMARY KEY,
    color      text,
    size       text,
    weight     decimal,
    material   text,
    brand      text,
    -- 195 more columns, most null for any given product
);
```

### After: map for dynamic attributes
```sql
CREATE TABLE product_metadata (
    product_id uuid PRIMARY KEY,
    attributes map<text, text>  -- {'color': 'blue', 'size': 'M', 'material': 'cotton'}
);
```

### After: blob for fully dynamic schema
```sql
CREATE TABLE product_metadata (
    product_id uuid PRIMARY KEY,
    metadata   text  -- '{"color":"blue","size":"M","weight_kg":0.3}'
);
```

```python
import json

save_metadata = session.prepare(
    "UPDATE product_metadata SET metadata = ? WHERE product_id = ?"
)
get_metadata = session.prepare(
    "SELECT metadata FROM product_metadata WHERE product_id = ?"
)

def save_product_metadata(product_id, attrs: dict):
    session.execute(save_metadata, [json.dumps(attrs), product_id])

def get_product_metadata(product_id) -> dict:
    row = session.execute(get_metadata, [product_id]).one()
    return json.loads(row.metadata) if row else {}
```

---

## Pulse Check

> A table stores user preferences with 150 columns — one per possible preference setting. Most users have only 5-10 preferences set; the rest are null.
>
> **What's the problem with this design, and what are your two options for fixing it?**

*(Expected answer: 150 sparse columns is a maintenance nightmare — hard to evolve, hard to reason about, and most storage is wasted on nulls. Usually the best fix is a keyed attribute table: `PRIMARY KEY (user_id, preference)` with one row per preference. Each user's preferences live in one partition, individual reads/writes hit a single row, and adding a new preference requires no schema change. A `map<text, text>` column works when preferences are simple key-value pairs and the set is small and bounded. A serialized JSON blob works when preferences are deeply nested and always read as a whole.)*

---

## See Also

**In this session:**
- [Too Many Tables](./03-too-many-tables.md)
- [Unbounded Collections](./06-unbounded-collections.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [SSTable Components](../../general/sstable-components.md)
- [Compression](../../general/compression.md)
- [Impacts of Many Columns in a Cassandra Table (TLP)](https://thelastpickle.com/blog/2020/12/17/impacts-of-many-columns-in-cassandra-table.html)
