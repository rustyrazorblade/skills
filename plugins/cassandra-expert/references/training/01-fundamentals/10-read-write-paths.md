# Topic: The Read and Write Paths

## Objective
Understand what happens inside Cassandra when a write or read is executed, and why this design makes writes extremely fast and inserts/updates effectively the same operation.

## Why This Matters
Most questions about Cassandra's performance, consistency, and behavior come back to the read and write paths. Once you understand how requests flow through a coordinator to replicas — and how consistency levels shape that flow — you can reason about almost any runtime behavior Cassandra exhibits. It also reveals the underlying reason for one of Cassandra's more surprising properties: inserts and updates are the same thing (most of the time).

---

## Concept

We'll build this up in three stages, starting with the simplest possible setup. If you have Cassandra running on your local machine, you can follow along with the single node examples.

```sql
CREATE KEYSPACE IF NOT EXISTS demo
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

USE demo;

CREATE TABLE users (
    user_id text PRIMARY KEY,
    name text,
    email text
);
```

### Stage 1: Single Node, RF=1

On a single node with `replication_factor: 1`, every row has exactly one copy. There's no distribution, no replicas to coordinate, no consistency level to worry about.

**Write path:**

1. Client sends the write to the node.
2. The node appends the mutation to its **commit log** (an append-only file on disk).
3. The node writes the same mutation to the **memtable** (an in-memory structure).
4. The node acknowledges the write to the client.
5. Later, writes will be bulk flushed to data files on disk called `SSTables`, which have several components (we will cover this in depth later).

The commit log exists for durability: if the node crashes before the memtable is flushed to disk, the commit log is replayed on restart to reconstruct the memtable. By collecting writes in the memtable and writing to disk asynchronously, we can get extremely high throughput with very low latency on our writes.

**Crucial insight: writes do not read first.** Cassandra does not check whether the row already exists. It just appends a mutation with a timestamp. This has several major consequences:

- **Inserts and updates are the same operation** — both just write cells with a timestamp. If the row already exists, new cell values simply overwrite old ones at the per-column level. This is why Cassandra is sometimes described as "upsert-only."
- **Deletes are writes too** — a delete writes a tombstone, the same way any other mutation would be written.
- **Writes are very fast** — no disk seeks, no lookups, no "does this row exist?" check. Just an append to the commit log and an in-memory write.

**Try it yourself:** Insert a row, then go look for it on disk.

```sql
INSERT INTO users (user_id, name, email) VALUES ('abc', 'Alice', 'alice@example.com');
```

Now check the data directory for the `demo.users` table.  If you downloaded the tarball from the Cassandra website, it'll be in the `data` directory.

```bash
ls data/data/demo/users-*/
```

There are no data files — the data only exists in the memtable (in memory). But you can still read it:

```sql
SELECT * FROM users WHERE user_id = 'abc';
```

The node finds the row in the memtable and returns it. Now force the memtable to flush to disk:

```bash
nodetool flush demo users
```

Check the directory again:

```bash
ls data/data/demo/users-*/
```

Now you'll see SSTable files (`*-Data.db`, `*-Index.db`, etc.). The data has been written from the memtable to an immutable SSTable on disk.

**Upsert behavior in action:** Now update a row that doesn't exist. Remember, writes don't read first — there's no "row exists?" check:

```sql
UPDATE users SET name = 'Bob', email = 'bob@example.com' WHERE user_id = 'xyz';
SELECT * FROM users WHERE user_id = 'xyz';
```

The UPDATE created the row, even though we never inserted it. There is no difference between INSERT and UPDATE.

Now re-insert `abc` with different values:

```sql
INSERT INTO users (user_id, name, email) VALUES ('abc', 'Alice Smith', 'asmith@example.com');
SELECT * FROM users WHERE user_id = 'abc';
```

No conflict, no error — the new cells simply overwrite the old ones because they have a newer timestamp. Cassandra doesn't check what was there before.

Now flush again so this update lands in a second SSTable:

```bash
nodetool flush demo users
```

At this point, `abc` exists in two SSTables: the original insert and the re-insert. You can see this directly by turning on tracing:

```sql
TRACING ON;
SELECT * FROM users WHERE user_id = 'abc';
```

In the tracing output, look for lines mentioning `sstables` — you'll see the read touched 2 SSTables. The node had to read from both and merge the results by timestamp to return the latest values. This is the read path in action: more SSTables means more work per read.

```sql
TRACING OFF;
```

**Deletes are writes too:** Delete the row and see what happens:

```sql
DELETE FROM users WHERE user_id = 'xyz';
SELECT * FROM users WHERE user_id = 'xyz';
```

The row is gone. But Cassandra didn't "remove" anything — it wrote a **tombstone**, a marker that says "this row is deleted as of this timestamp." You can verify this by flushing and looking at the SSTable count:

```bash
nodetool flush demo users
ls data/data/demo/users-*/
```

There's a new SSTable — the one containing the tombstone. The old SSTable with the original data is still there. Use `sstabledump` to see exactly what's in each SSTable:

```bash
tools/bin/sstabledump data/data/demo/users-*/*-Data.db
```

In the output, you'll see the live rows with their cell values and timestamps — and the tombstone for `xyz` showing a `"deletion_info"` entry with a `"marked_deleted"` timestamp. This is what a delete actually looks like on disk: not an absence of data, but a write that says "deleted at time T."

**Read path:**

1. Client sends the read to the node.
2. The node looks up the partition in its memtable and on-disk SSTables.
3. The node merges results across all sources, resolving conflicts by the cell's timestamp (last-write-wins), and returns the row.

**Compaction preview:** At this point we have multiple SSTables on disk. Each flush creates a new one, and they accumulate over time. Every read has to check all of them and merge results — the more SSTables, the more work each read does.

**Compaction** is the background process that solves this. It merges multiple SSTables into one, keeping only the latest version of each cell and discarding tombstones that are old enough to be safely removed. You don't need to understand the details yet (we'll cover compaction strategies later), but the key idea is simple: many small files get merged into fewer large files, dead data gets thrown away, and reads get faster.

You can trigger compaction manually to see it in action:

```bash
ls data/data/demo/users-*/
nodetool compact demo users
ls data/data/demo/users-*/
```

Before compaction you had multiple SSTables. After, you have one. The tombstoned row for `xyz` is gone (purged during the merge), and `abc` appears once with its latest values. Run `sstabledump` again to confirm:

```bash
tools/bin/sstabledump data/data/demo/users-*/*-Data.db
```

Only the live data remains.

### Stage 2: 3-Node Cluster, LOCAL_ONE

Now scale to a 3-node cluster with `replication_factor: 3`, meaning every partition is stored on all 3 nodes. Here we need a **consistency level** — a per-query setting that tells the coordinator how many replicas must respond before the request is considered successful. We'll cover consistency levels in detail later; for now, let's use **LOCAL_ONE**, which means "wait for one replica to acknowledge."

**Write path:**

1. Client sends the write to any node. That node becomes the **coordinator** for this request.
2. The coordinator forwards the write to **all 3 replicas in parallel**.
3. Each replica independently writes to its own commit log and memtable.
4. As soon as **one replica** acknowledges (because the consistency level is LOCAL_ONE), the coordinator returns success to the client.
5. The remaining two replicas continue processing in the background.

Note: replication does not depend on consistency level. The coordinator always forwards the write to all replicas. Consistency level only controls how many acknowledgments the coordinator waits for before responding to the client.

**Read path:**

1. Client sends the read to any node (the coordinator).
2. The coordinator picks **one replica** and asks it for the row.
3. The replica returns its version of the row.
4. The coordinator returns it to the client.

With LOCAL_ONE, you're trusting whatever that one replica says. If another replica has a newer version that hasn't propagated yet, the client may see stale data.

### Stage 3: 3-Node Cluster, LOCAL_QUORUM — Reconciliation

Now use **LOCAL_QUORUM** with RF=3, which means "wait for 2 out of 3 replicas." This is the standard consistency level for most production applications.

**Write path:**

1. Client sends the write to the coordinator.
2. Coordinator forwards the write to all 3 replicas in parallel.
3. Coordinator waits for **2 out of 3** acknowledgments, then returns success to the client.
4. The third replica processes in the background.

**Read path with reconciliation:**

1. Client sends the read to the coordinator.
2. Coordinator sends the read to **2 of the 3 replicas** (enough to satisfy quorum).
3. Both replicas return their version of the row.
4. The coordinator compares the two responses:
   - **If they agree**, it returns the row to the client.
   - **If they disagree**, the coordinator reconciles using **last-write-wins by timestamp**. The cell with the latest timestamp wins, and the coordinator issues a **read repair** in the background to update the stale replica.
5. Coordinator returns the reconciled row to the client.

This is where the "all replicas are equal peers" property matters: there is no leader to arbitrate conflicts. Cassandra reconciles by timestamp alone. Any replica that has seen the latest write provides the authoritative value.

**Why LOCAL_QUORUM + LOCAL_QUORUM is the recommended default:** if you write at LOCAL_QUORUM and read at LOCAL_QUORUM, then at least one replica involved in any read is guaranteed to have received any successful prior write (because 2 + 2 > 3). This gives strong consistency without requiring all replicas to participate.

---

## Examples

### Demonstrating upsert behavior

These two statements are functionally identical:

```sql
-- "Insert"
INSERT INTO users (user_id, name) VALUES ('abc', 'Alice');

-- "Update"
UPDATE users SET name = 'Alice' WHERE user_id = 'abc';
```

Both just write the cell `name = 'Alice'` with the current timestamp. If the row doesn't exist, it's effectively created. If it exists, the value is overwritten. There is no "row exists?" check.

### Writing and reading at LOCAL_QUORUM

```sql
CONSISTENCY LOCAL_QUORUM;
INSERT INTO users (user_id, name, email) VALUES (?, ?, ?);
SELECT * FROM users WHERE user_id = ?;
```

### Setting consistency level in a driver (Python)

```python
from cassandra import ConsistencyLevel
from cassandra.query import SimpleStatement

stmt = SimpleStatement(
    "SELECT * FROM users WHERE user_id = ?",
    consistency_level=ConsistencyLevel.LOCAL_QUORUM,
)
rows = session.execute(stmt, [user_id])
```

---

## Pulse Check

> You have a 3-node cluster with RF=3. An application writes a row at LOCAL_QUORUM, then immediately reads that same row at LOCAL_ONE. The read happens to go to a replica that hasn't yet received the write.
>
> **What might the client see, and how would you fix it?**

*(Expected answer: The client may see stale data or nothing at all. LOCAL_ONE talks to only one replica, and that replica may not yet have the write. To guarantee read-your-own-writes, read at LOCAL_QUORUM. Then at least one of the two replicas the coordinator contacts is guaranteed to have received the prior quorum write, so the client always sees the latest value.)*

---

## See Also

**In this session:**
- [DML Basics — INSERT, UPDATE, DELETE, SELECT](./09-dml-basics.md)
- [Tombstones](./11-tombstones.md)
- [Compaction Overview](./13-compaction-overview.md)
- [Consistency Levels](./15-consistency-levels.md)

**Reference:**
- [Commit Log](../../general/commitlog.md)
- [Memtables](../../general/memtables.md)
- [Consistency Levels](../../general/consistency-levels.md)
- [Hinted Handoff](../../general/hinted-handoff.md)
- [Dropped Messages](../../general/dropped-messages.md)
