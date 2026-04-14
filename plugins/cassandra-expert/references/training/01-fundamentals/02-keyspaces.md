# Topic: Keyspaces

## Objective
Understand what a keyspace is and how to create one for local development.

## Why This Matters
Every table in Cassandra lives inside a keyspace. The keyspace controls how the tables inside it are replicated across the cluster. You can't create a table without first creating (or selecting) a keyspace, so this is the starting point for any schema work.

---

## Concept

A **keyspace** is the top-level container for tables. It's roughly analogous to a database in PostgreSQL or MySQL. Each keyspace defines:

- **Replication strategy** — how many copies of each row exist, and across which datacenters
- **Replication factor** — how many replicas per partition

Tables inherit their replication settings from the keyspace they live in.

### Creating a Keyspace

For local development, a simple one-datacenter keyspace with `SimpleStrategy` is fine:

```sql
CREATE KEYSPACE myapp
WITH replication = {
    'class': 'SimpleStrategy',
    'replication_factor': 1
};
```

This creates a keyspace named `myapp` where every partition is stored on exactly one node. For a single-node local cluster, that's all you need.

**For production, use `NetworkTopologyStrategy` instead.** `SimpleStrategy` doesn't understand datacenters or racks and is unsuitable for anything real. We cover production replication strategies separately.

### Using a Keyspace

Once a keyspace exists, tables can be referenced in two ways: by their fully-qualified `keyspace.table` name, or by selecting a keyspace first with `USE` and then referencing the table unqualified.

**Best practice: always use fully-qualified names in application code.**

```sql
CREATE TABLE myapp.users (
    user_id uuid PRIMARY KEY,
    name text
);
```

`USE` changes state on the session (the "current keyspace"). Driver sessions are normally shared across many threads and request handlers, so if any caller runs `USE a_different_keyspace`, every other query on that session that relies on unqualified names will silently start hitting the wrong keyspace — or fail outright. This is a nasty class of bug: it depends on execution order, it won't show up in unit tests, and it can corrupt data in production.

Fully-qualified names are stateless, thread-safe, and explicit about intent. Use them everywhere in application code and in every prepared statement.

`USE` is fine for interactive `cqlsh` sessions and one-off schema scripts where you're the only caller, but it should not appear in application code.

```sql
-- Fine in cqlsh, avoid in application code:
USE myapp;
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text
);
```

---

## Examples

### Create a keyspace for local testing
```sql
CREATE KEYSPACE dev
WITH replication = {
    'class': 'SimpleStrategy',
    'replication_factor': 1
};
```

### Dropping a keyspace (careful — deletes everything)
```sql
DROP KEYSPACE dev;
```

---

## Pulse Check

> You run `CREATE KEYSPACE myapp WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};` on a 3-node local cluster.
>
> **How many copies of each row will be stored in this keyspace?**

*(Expected answer: One copy. The replication factor is 1, so each partition is stored on exactly one node. This is fine for local testing but means losing a node means losing data.)*

---

## See Also

**In this session:**
- [Data Distribution](./01-data-distribution.md)
- [Basic Types](./03-types.md)
- [Tables and the Primary Key](./04-tables-primary-key.md)

**Reference:**
- [Replication Strategies](../../general/replication.md)
- [Cluster Topology](../../general/topology.md)
- [Cluster Configuration](../../general/cluster-configuration.md)
