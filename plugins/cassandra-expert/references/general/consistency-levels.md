# Consistency Levels

Consistency levels control how many replicas must respond before a read or write is considered successful. The right level depends on the replication factor, datacenter topology, and the application's tolerance for stale reads.

## Key Formula

**Read CL + Write CL > RF = Strong Consistency**

With RF=3, `QUORUM` reads + `QUORUM` writes means at least one replica in the read set must have the latest write — guaranteeing you always read your own writes.

## Common Levels

| Level | Replicas Required | Use Case |
|-------|------------------|----------|
| **ONE** | 1 replica | Maximum performance, tolerates stale reads |
| **QUORUM** | RF/2 + 1 | Strong consistency, single DC |
| **LOCAL_QUORUM** | Majority in local DC | Strong consistency, multi-DC (recommended) |
| **EACH_QUORUM** | Majority in each DC | Cross-DC strong consistency (rare) |
| **ALL** | All replicas | Maximum consistency, any replica down = failure |
| **LOCAL_ONE** | 1 replica in local DC | Fast local reads, tolerates stale data |

## Multi-Datacenter Recommendations

**Use `LOCAL_QUORUM` for both reads and writes in multi-DC clusters.**

- Strong consistency within the local datacenter
- Low latency — doesn't wait for remote DCs
- Survives complete failure of remote datacenters
- Replication to other DCs happens asynchronously in the background

**Avoid `EACH_QUORUM`** unless you absolutely need synchronous cross-DC consistency and can tolerate operation failures when any DC is unavailable.

## Common Patterns

### Strong consistency (most common)

```
RF=3
Write CL = LOCAL_QUORUM (multi-DC) or QUORUM (single-DC)
Read CL  = LOCAL_QUORUM (multi-DC) or QUORUM (single-DC)
```

### Eventual consistency (high availability)

```
RF=3
Write CL = ONE
Read CL  = ONE
```

Replicas converge over time via anti-entropy repair. Use when the application can tolerate stale reads.

### Write-heavy with strong reads

```
RF=3
Write CL = ONE
Read CL  = ALL
```

Every write is fast (1 replica), but every read checks all replicas. Risky — any replica down blocks reads.

## Availability Trade-offs

Higher consistency = lower availability:

| CL | RF=3 failures tolerated | Impact |
|----|------------------------|--------|
| `ALL` | 0 | Any node down blocks operations |
| `QUORUM` | 1 | Survives minority failure |
| `ONE` | 2 | Only total failure blocks operations |

## Tunable Per Operation

Cassandra's consistency is configurable per query, not cluster-wide. Set a sensible default in the driver at initialization, then override per query where needed:

```python
# Default for the session
cluster = Cluster(...)
session = cluster.connect()
session.default_consistency_level = ConsistencyLevel.LOCAL_QUORUM

# Override for a specific query
stmt = SimpleStatement(query, consistency_level=ConsistencyLevel.ONE)
session.execute(stmt)
```

## Application Guidelines

| Workload | Recommended CL | Why |
|----------|---------------|-----|
| Financial transactions | `LOCAL_QUORUM` / `LOCAL_QUORUM` | Must read own writes |
| User profiles | `ONE` / `ONE` acceptable | Stale reads tolerable |
| Session data (multi-DC) | `LOCAL_QUORUM` / `LOCAL_QUORUM` | DC-local consistency |
| Analytics reads | `ONE` | Availability over consistency |

## See Also

- `replication.md` — replication factor guidelines
- `topology.md` — rack and DC configuration
