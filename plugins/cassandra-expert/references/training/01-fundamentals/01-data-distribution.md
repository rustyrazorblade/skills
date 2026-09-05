# Topic: Distribution of Data in a Cluster

## Objective
Understand how Cassandra decides which node stores which data, and why that decision is entirely determined by the partition key.

## Why This Matters
Every performance problem in Cassandra eventually traces back to data distribution. If you don't understand how data is placed, you can't reason about hot spots, replication, consistency, or query performance. This is the core mental model for everything else.

## Why We Start Here (Not With Tables)

If you're coming from a relational database, you're probably used to designing tables first and thinking about infrastructure later. Cassandra inverts this: the way data is physically distributed across nodes directly shapes how you design your tables. Your partition key — the most important decision in any table design — exists to control *where data lands in the cluster*. If you don't understand the distribution model first, partition key choices will feel arbitrary. Once you do understand it, table design becomes a natural consequence of the physical reality underneath.

We'll get to table design soon. But when we do, every decision will trace back to what you learn here.

---

## Concept

Cassandra arranges nodes in a logical **ring**. Each node owns ranges of values on that ring, called **token ranges**. When data is written, Cassandra hashes the partition key to produce a token, which determines which nodes own the data.

```
Partition Key → Hash Function → Token → Replica set
```

This is **consistent hashing** — adding or removing nodes only affects neighboring ranges, not the entire ring.

### Replication

Data isn't stored on just one node. The **replication factor (RF)** controls how many nodes hold a copy of each partition. With RF=3, every partition is stored on 3 nodes. These nodes are called **replicas**, and they are all equal — there is no primary, no secondary, no leader. All replicas are peers.

### Coordinators

Any node can act as a **coordinator** for any request. When a client sends a write, it picks a node and that node becomes the coordinator for the request. The coordinator's job is to forward the write to *all* replicas for that partition in parallel — it does not write to a "primary" first and then replicate.

In practice, modern Cassandra drivers use **token-aware routing**: given the partition key of the request, the driver computes the token and picks a replica for that token as the coordinator. This avoids an extra network hop — the coordinator and one of the replicas are the same node — which meaningfully reduces read and write latency. Any node could technically coordinate any request, but token-aware routing is the default and you should not fight it.

All replicas receive the write at the same time, each with the same timestamp. When replicas disagree (due to a missed write, network partition, or dropped mutation), Cassandra reconciles using **last-write-wins based on the write's timestamp**. There is no leader to resolve conflicts — the timestamp does.

For example, suppose a row has a column `foo` and two replicas temporarily disagree:

```
Replica A:  foo = 'bar'   (timestamp 100)
Replica B:  foo = 'baz'   (timestamp 101)
```

When a read touches both replicas, Cassandra compares timestamps and returns `foo = 'baz'` because timestamp 101 > 100. Replica A is then repaired in the background to match. The highest timestamp always wins.

> **We'll come back to this.** Whether a read actually *sees* both replicas (and therefore whether the conflict gets resolved at all) depends on the **consistency level** of the query. We'll dig into consistency levels in a later topic — for now, just hold onto the idea that timestamp-based last-write-wins is the mechanism, and consistency levels decide how many replicas get consulted.

This means:
- **No single point of failure** — any replica can serve a read, any node can coordinate
- **No master, no leader** — every node is a peer
- **Writes go to all replicas in parallel** — the coordinator doesn't wait for all of them to acknowledge (that depends on consistency level, covered later)
- **Conflicts resolve by timestamp** — the write with the highest timestamp wins

### What the Partition Key Controls

The partition key is hashed to determine token placement. A good partition key:
- **Distributes writes evenly** across all nodes (high cardinality, no hot values)
- **Co-locates related data** that will be queried together
- **Doesn't change** — the partition key is immutable once written

A bad partition key concentrates all traffic on one node (a "hot partition") or creates huge partitions on a single node.

---

## Cassandra Query Language (CQL)

Cassandra uses **CQL (Cassandra Query Language)**, which is intentionally designed to look like SQL. If you've worked with any relational database, CQL will feel familiar — `CREATE TABLE`, `INSERT`, `SELECT`, and `WHERE` all work roughly the way you'd expect. But don't let the syntax fool you: the semantics underneath are very different. CQL looks like SQL so that the learning curve is gentle, but the data model, query restrictions, and performance characteristics are all driven by the distributed architecture you just learned about.

Here's a simple table definition in CQL:

```sql
CREATE TABLE user_profiles (
    user_id uuid PRIMARY KEY,
    name text,
    email text
);
```

This looks exactly like what you'd write in PostgreSQL or MySQL. The difference is what `PRIMARY KEY` means.

### Primary Key and Partition Key

In a relational database, the primary key is about uniqueness and indexing. In Cassandra, the primary key controls **where data is physically stored in the cluster**.

The **first component** of the `PRIMARY KEY` definition is always the **partition key**. It's the value that gets hashed to determine which nodes own the data. In the example above, `user_id` is the partition key — every row with a different `user_id` may land on a different set of nodes.

When the primary key is a single column (like `user_id uuid PRIMARY KEY`), that column is the partition key. We'll cover compound primary keys — where the primary key includes both a partition key and clustering columns — in a later topic. For now, the important thing is: **the partition key is always the first part of the primary key, and it determines data placement**.

## Examples

### Good: user_id as partition key
Each user's data lands on a different set of nodes. 1M users → well-distributed load.

```sql
CREATE TABLE user_profiles (
    user_id uuid PRIMARY KEY,
    name text,
    email text
);
```

### Bad: status as partition key
Only a handful of distinct statuses. All "active" users pile up on one node.

```sql
-- ANTI-PATTERN: low cardinality partition key
CREATE TABLE users_by_status (
    status text PRIMARY KEY,  -- "active", "inactive", "banned" — only 3 values!
    user_id uuid
);
```

### Seeing token placement
```bash
# Which node owns a given partition key?
nodetool getendpoints <keyspace> <table> <partition_key_value>

# Ring overview showing token ranges per node
nodetool ring
```

---

## Pulse Check

> You have a 6-node cluster with RF=3. You write a row with partition key `user_id = abc123`.
>
> **How many nodes store a copy of that row? Which node does the client talk to?**

*(Expected answer: 3 nodes store it. The client talks to any node — the coordinator — which routes the write to the correct replicas. The client doesn't need to know which node owns the data.)*

---

## See Also

**In this session:**
- [Keyspaces](./02-keyspaces.md)
- [Tables and the Primary Key](./04-tables-primary-key.md)
- [Partition Keys and Clustering Columns](./06-partition-key-clustering.md)

**Reference:**
- [Replication Strategies](../../general/replication.md)
- [Cluster Topology and Snitches](../../general/topology.md)
- [Virtual Nodes (vnodes)](../../general/vnodes.md)
- [Token Skew and Distribution](../../general/token-skew.md)
- [Gossip Protocol](../../general/gossip.md)
