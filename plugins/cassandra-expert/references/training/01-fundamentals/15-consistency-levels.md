# Topic: Consistency Levels

## Objective
Choose the right consistency level for reads and writes, understanding the relationship between consistency level, replication factor, and the availability vs. correctness trade-off.

## Why This Matters
Consistency level is the dial that controls whether Cassandra behaves as a consistent database or an eventually consistent one — and it's configurable per query. Using the wrong level means either accepting stale reads (too low) or making your application unavailable when nodes go down (too high). Understanding this trade-off is essential to designing reliable Cassandra applications.

---

## Concept

When Cassandra writes or reads data, it must decide how many replicas need to respond before the operation is considered successful. That's the **consistency level (CL)**.

With RF=3, there are 3 copies of every partition. The consistency level determines how many of those 3 must confirm each operation.

### The Fundamental Formula

```
Read CL + Write CL > RF → Strong Consistency (guaranteed to read your writes)
```

If the combined acknowledgement count exceeds the replication factor, there must be at least one replica that has both the most recent write and participates in the read — so you always read the latest value.

### Common Consistency Levels

| Level | Replicas Required | Typical Use Case |
|-------|------------------|-----------------|
| `ONE` | 1 | Maximum performance, stale reads acceptable |
| `QUORUM` | RF/2 + 1 (majority) | Strong consistency, single datacenter |
| `LOCAL_QUORUM` | Majority in local DC | Strong consistency, multi-datacenter |
| `EACH_QUORUM` | Majority in every DC | Synchronous cross-DC consistency (rarely needed) |
| `ALL` | All replicas | Maximum consistency — any failure = outage |
| `LOCAL_ONE` | 1 in local DC | Fast multi-DC reads, stale OK |

### Strong Consistency with RF=3

The most common strong consistency setup:

```
Write CL = QUORUM (2 of 3 replicas acknowledge)
Read CL  = QUORUM (2 of 3 replicas consulted)
2 + 2 > 3 → Strong consistency guaranteed
```

### The Multi-DC Case: Use LOCAL_QUORUM

In a multi-datacenter cluster, `QUORUM` means quorum across ALL datacenters — it waits for replicas in remote DCs, adding latency and creating a dependency on inter-DC connectivity.

**Use `LOCAL_QUORUM` instead:**
- Strong consistency within the local datacenter
- Low latency (no inter-DC wait)
- Survives complete failure of remote datacenters
- Replication to other DCs happens asynchronously in the background

```
Multi-DC recommendation:
Write CL = LOCAL_QUORUM
Read CL  = LOCAL_QUORUM
```

### Availability vs. Consistency

Higher consistency = less tolerance for node failures:

| Consistency Level | Nodes That Can Be Down (RF=3) |
|------------------|-------------------------------|
| `ONE` | 2 of 3 |
| `QUORUM` | 1 of 3 |
| `ALL` | 0 — any failure blocks operations |

Choose based on your application's requirements:
- Financial transactions → QUORUM/QUORUM (correctness first)
- User sessions → LOCAL_QUORUM/LOCAL_QUORUM (multi-DC)
- Analytics reads → ONE/QUORUM (stale reads acceptable)
- Cached data → ONE/ONE (maximum availability)

### Tunable Per Operation

You should set a **default consistency level** in the driver at initialization — this applies to all queries. You can then override it per query for operations that need different guarantees.

**Java — setting the default at driver initialization:**
```java
CqlSession session = CqlSession.builder()
    .withConfigLoader(
        DriverConfigLoader.programmaticBuilder()
            .withString(DefaultDriverOption.REQUEST_CONSISTENCY, consistencyLevel.toString())
            .build()
    )
    .build();
```

**Overriding per query when needed:**
```python
from cassandra import ConsistencyLevel
from cassandra.query import SimpleStatement

# Most queries use the driver default (e.g. LOCAL_QUORUM)
session.execute(read_query, [user_id])

# Override for analytics where stale reads are acceptable
session.execute(
    SimpleStatement(analytics_query, consistency_level=ConsistencyLevel.ONE),
    [user_id]
)
```

---

## Examples

### Setting consistency level in Python
```python
from cassandra import ConsistencyLevel
from cassandra.query import SimpleStatement

# Or set on a prepared statement's bound statement
stmt = session.prepare("SELECT * FROM accounts WHERE account_id = ?")
bound = stmt.bind([account_id])
bound.consistency_level = ConsistencyLevel.LOCAL_QUORUM
result = session.execute(bound)
```

### Setting consistency level in Java
```java
// On a bound statement
BoundStatement bound = preparedStmt.bind(accountId)
    .setConsistencyLevel(ConsistencyLevel.LOCAL_QUORUM);
session.execute(bound);

// Or at session level (applies to all queries without an explicit CL)
CqlSession session = CqlSession.builder()
    .withConfigLoader(DriverConfigLoader.programmaticBuilder()
        .withString(DefaultDriverOption.REQUEST_CONSISTENCY, "LOCAL_QUORUM")
        .build())
    .build();
```

### Setting consistency level in Go (gocql)
```go
// Per query
session.Query("SELECT * FROM accounts WHERE account_id = ?", accountId).
    Consistency(gocql.LocalQuorum).
    Scan(&account)

// Session default
cluster := gocql.NewCluster("localhost")
cluster.Consistency = gocql.LocalQuorum
session, _ := cluster.CreateSession()
```

### Checking what consistency level a query used
```bash
# Enable tracing to see CL details
cqlsh> TRACING ON;
cqlsh> SELECT * FROM users WHERE user_id = some-uuid;
# Look for "consistency_level" in the trace output
```

---

## Pulse Check

> Your application runs in two datacenters. You're storing financial transaction records. The business requires that a transaction written in DC1 is always readable in DC1, even if DC2 is down.
>
> **Which read and write consistency levels should you use? What would happen if you used QUORUM instead?**

*(Expected answer: Use LOCAL_QUORUM for both reads and writes. This gives strong consistency within DC1 and keeps working if DC2 is down. Using QUORUM would wait for acknowledgements across both DCs — if DC2 is unreachable, writes and reads fail. EACH_QUORUM would be even worse. LOCAL_QUORUM is the right default for multi-DC strong consistency.)*

---

## See Also

**In this session:**
- [The Read and Write Paths](./10-read-write-paths.md)
- [DML Basics — INSERT, UPDATE, DELETE, SELECT](./09-dml-basics.md)
- [Lightweight Transactions (LWT)](./22-lwt.md)

**Reference:**
- [Consistency Levels](../../general/consistency-levels.md)
- [Lightweight Transactions (LWT)](../../general/lwt.md)
- [Replication Strategies](../../general/replication.md)
- [Hinted Handoff](../../general/hinted-handoff.md)
- [Repair](../../general/repair.md)
