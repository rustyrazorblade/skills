# Topic: DML Basics — INSERT, UPDATE, DELETE, SELECT

## Objective
Write the four basic DML statements in CQL and understand the Cassandra-specific rules and surprises compared to SQL.

## Why This Matters
CQL looks like SQL, but the small differences matter. INSERT and UPDATE are effectively the same operation. DELETE writes a marker instead of removing data. SELECT's WHERE clause has rules that a SQL background will not prepare you for. Learning the basics correctly up front avoids a class of mistakes that are easy to make and expensive to unwind. Advanced operations like BATCH and lightweight transactions are covered in the Advanced DML section later.

---

## Concept

DML (Data Manipulation Language) is the set of statements that read and write data — **INSERT**, **UPDATE**, **DELETE**, and **SELECT**. Those four are the bread and butter of application code against Cassandra.

### INSERT

```sql
INSERT INTO users (user_id, email, name, created_at)
VALUES (?, ?, ?, toTimestamp(now()));
```

INSERT writes one row. The statement must include **at least the primary key** and can include any subset of the other columns. Omitted columns are simply not written — they remain null (or whatever the previous value was for an existing row).

INSERT supports `USING TTL` to set an expiration and `USING TIMESTAMP` to override the write timestamp (rarely needed — don't reach for it unless you understand last-write-wins). TTL is covered in its own topic.

### UPDATE

```sql
UPDATE users
SET email = ?, name = ?
WHERE user_id = ?;
```

UPDATE also writes to one row. The WHERE clause must fully specify the primary key.

**INSERT and UPDATE are effectively the same operation.** Both just write cells with a timestamp. If the row doesn't exist yet, UPDATE will create it. If it does exist, INSERT will overwrite the specified columns. There is no "row exists?" check (generally) — this is called **upsert** semantics, and it's covered in depth in the Read and Write Paths topic.

```sql
-- These two statements have the same effect on the database
-- (assume users has user_id text PRIMARY KEY)
INSERT INTO users (user_id, name) VALUES ('abc', 'Alice');
UPDATE users SET name = 'Alice' WHERE user_id = 'abc';
```

The main stylistic reason to prefer one over the other: INSERT is natural when creating new rows; UPDATE is natural when modifying a specific subset of columns on a row you know exists.

### DELETE

```sql
-- Delete a whole row (all its cells, marked as a row tombstone)
DELETE FROM users WHERE user_id = ?;

-- Delete specific columns (cell tombstones)
DELETE email, phone FROM users WHERE user_id = ?;

-- Delete a range of clustering columns (range tombstone)
DELETE FROM messages WHERE conversation_id = ? AND sent_at < ?;
```

DELETE **does not remove data** — it writes a **tombstone**, which is a marker indicating "this data should be treated as deleted at this timestamp." Tombstones are reconciled with live data at read time and purged by compaction after `gc_grace_seconds` (a per-table option, default 10 days — covered in Topic 12). This is covered in the Tombstones topic. Once we cover the read and write paths it'll make a lot more sense why we do it this way.

The WHERE clause for a DELETE must include enough of the primary key to identify the target. You can delete a full row, specific columns within a row, or a range of clustering columns in a partition.

### SELECT: The Basic Shape

```sql
SELECT column_list
FROM keyspace.table
WHERE ...
[ORDER BY ...]
[LIMIT n]
[ALLOW FILTERING];
```

Familiar from SQL. What's different is the set of things you're allowed to put in that WHERE clause — and what happens when you push your luck.

### SELECT: The WHERE Rule

The WHERE clause must **always specify the partition key** for the query to be efficient. This is non-negotiable. Cassandra routes a query to the nodes that own the partition — without the partition key, it has no idea where to look.

Beyond the partition key, you can optionally restrict further using clustering columns:

```sql
-- Table: PRIMARY KEY (user_id, created_at)

-- Point lookup on a partition (all rows for a user)
SELECT * FROM messages WHERE user_id = ?;

-- Range on the clustering column (with partition key)
SELECT * FROM messages
WHERE user_id = ? AND created_at > '2025-01-01';

-- Exact row lookup (partition key + all clustering columns)
SELECT * FROM messages WHERE user_id = ? AND created_at = ?;
```

### SELECT: Clustering Column Rules

Clustering columns must be restricted in order. You cannot skip one:

```sql
-- Table: PRIMARY KEY (user_id, year, month, day)

-- OK — prefix match, range on last
SELECT * FROM events WHERE user_id = ? AND year = ? AND month = ? AND day > ?;

-- NOT OK — can't skip month
SELECT * FROM events WHERE user_id = ? AND year = ? AND day > ?;
```

Range queries (`<`, `>`, `>=`, `<=`) are only allowed on the *last* restricted clustering column.

### SELECT: ORDER BY

You can only `ORDER BY` clustering columns, and only in the same direction they're already sorted on disk (or the exact reverse of all of them). You **cannot** reorder arbitrarily.

```sql
-- Table has CLUSTERING ORDER BY (created_at DESC)

-- OK — default order
SELECT * FROM messages WHERE user_id = ?;

-- OK — explicit reverse (cheap; reads the partition backwards)
SELECT * FROM messages WHERE user_id = ? ORDER BY created_at ASC;

-- NOT OK — created_at is a clustering column, name is not
SELECT * FROM messages WHERE user_id = ? ORDER BY name ASC;
```

If you need data in an order your clustering columns don't support, the answer is a different table — not `ORDER BY`.

### SELECT: LIMIT

`LIMIT` is cheap when the query is partition-bounded, because Cassandra stops reading as soon as it has enough rows. Combined with clustering column sort order, it's the pattern for "give me the N most recent / highest-scored / first alphabetical" queries.

```sql
SELECT * FROM messages WHERE user_id = ? LIMIT 20;
```

### SELECT: ALLOW FILTERING — The Foot-Gun

If you ask Cassandra for data without restricting by the partition key, it rejects the query. You can override this by adding `ALLOW FILTERING`:

```sql
-- Forces a full cluster scan. Do not do this in production.
SELECT * FROM users WHERE email = ? ALLOW FILTERING;
```

**Rule: never use ALLOW FILTERING in production code.** It tells Cassandra to read every partition on every node, filter in memory, and return the matches. It's a full table scan. The right fix is almost always a dedicated lookup table (`users_by_email`) or an SAI index (Storage-Attached Index — covered in Session 4) — either of which is covered in other sessions.

### SELECT: What CQL Does Not Support

Coming from SQL, these are the features that are **absent or severely restricted**:

| SQL Feature | Status in CQL |
|-------------|--------------|
| `JOIN` | Not supported. Ever. Denormalize instead. |
| Subqueries | Not supported. |
| `GROUP BY` | Only on prefixes of the primary key. No arbitrary aggregation. |
| `DISTINCT` | Only on partition keys. |
| `SELECT COUNT(*)` | Supported but very expensive — reads the entire partition (or table). Avoid. |
| Arbitrary `ORDER BY` | Only on clustering columns in their natural or fully-reversed order. |
| `OFFSET` pagination | Not supported. Use the driver's built-in paging cursor instead. |

---

## Examples

### INSERT with TTL
```sql
-- Expire this row in 24 hours
INSERT INTO sessions (session_id, user_id, created_at)
VALUES (?, ?, toTimestamp(now()))
USING TTL 86400;
```

### UPDATE a single column
```sql
UPDATE users SET email = ? WHERE user_id = ?;
```

### DELETE a specific clustering range
```sql
-- Delete all messages in a conversation older than a cutoff
DELETE FROM messages
WHERE conversation_id = ?
  AND sent_at < ?;
```

### Point lookup by partition key
```sql
SELECT user_id, name, email
FROM users
WHERE user_id = ?;
```

### Range query with partition key and clustering column
```sql
SELECT message_id, body, sent_at
FROM messages_by_conversation
WHERE conversation_id = ?
  AND sent_at >= ?
  AND sent_at <  ?
LIMIT 100;
```

### Driver paging (Python)
```python
# The driver streams result pages transparently — don't load everything into memory
stmt = session.prepare("SELECT * FROM messages WHERE conversation_id = ?")
for row in session.execute(stmt, [conv_id]):  # iterates across pages
    handle(row)
```

### Driver paging (Java)
```java
PreparedStatement stmt = session.prepare(
    "SELECT * FROM messages WHERE conversation_id = ?"
);

ResultSet rs = session.execute(stmt.bind(convId));
for (Row row : rs) {       // iterator pages through results automatically
    handle(row);
}
```

### Driver paging (Go)
```go
iter := session.Query(
    "SELECT * FROM messages WHERE conversation_id = ?", convID,
).PageSize(100).Iter()

var msg Message
for iter.Scan(&msg.ID, &msg.Body, &msg.SentAt) {
    handle(msg)
}
if err := iter.Close(); err != nil {
    return err
}
```

---

## Pulse Check

> A colleague runs this against an empty table:
>
> ```sql
> UPDATE users SET name = 'Alice' WHERE user_id = 'abc';
> ```
>
> **What happens? Would the result be different if they had used INSERT instead?**

*(Expected answer: A row is created with `user_id = 'abc'` and `name = 'Alice'` — no error, no "row doesn't exist" check. INSERT would produce the same result. Cassandra writes are upserts: both statements just write a cell with a timestamp, and the row is reconstructed on read from the cells that exist. There is no "does it exist?" lookup on the write path.)*

> You have `CREATE TABLE users (user_id uuid PRIMARY KEY, email text, name text);` and need to look up a user by email. A colleague writes:
>
> ```sql
> SELECT * FROM users WHERE email = ? ALLOW FILTERING;
> ```
>
> **Why is this wrong, and what's the correct alternative?**

*(Expected answer: It's a full cluster scan — Cassandra checks every partition on every node because `email` is not the partition key. This scales linearly with data size. The correct fix is a dedicated lookup table `users_by_email (email PRIMARY KEY, user_id)` written alongside the main table. Denormalization is how Cassandra handles "query by a different key.")*

> You have `CREATE TABLE events (user_id uuid, year int, month int, day int, data text, PRIMARY KEY (user_id, year, month, day));`
>
> Which of these queries work without `ALLOW FILTERING`? For any that fail, explain why.
>
> 1. `SELECT * FROM events WHERE user_id = ? AND year = 2026;`
> 2. `SELECT * FROM events WHERE user_id = ? AND year = 2026 AND day > 1;`
> 3. `SELECT * FROM events WHERE user_id = ? AND year = 2026 AND month = 4 AND day > 1;`
> 4. `SELECT * FROM events WHERE year = 2026;`

*(Expected answer: (1) and (3) work. (2) fails because `month` is a clustering column between `year` and `day` — you can't skip it. (4) fails because it doesn't restrict the partition key. Clustering columns must be restricted in order; partition key must always be present.)*

> You run `DELETE FROM users WHERE user_id = ?;` against a heavily-read table. A few minutes later, reads on that partition are noticeably slower than before.
>
> **What's the likely explanation?**

*(Expected answer: The DELETE wrote a tombstone. On subsequent reads, Cassandra has to scan past the tombstone to determine there's no live data. If enough deletes pile up on the same partition, reads accumulate tombstone scans. For a single delete this is barely noticeable, but the same mechanism is what makes heavy-delete workloads — like using Cassandra as a queue — slow down over time. This is why DELETE is a write, not a subtraction.)*

---

## See Also

**In this session:**
- [The Read and Write Paths](./10-read-write-paths.md)
- [Tombstones](./11-tombstones.md)
- [Prepared Statements](./16-prepared-statements.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Drivers](../../general/drivers.md)
- [Tombstones](../../general/tombstones.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
