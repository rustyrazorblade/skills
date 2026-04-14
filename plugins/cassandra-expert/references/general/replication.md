# Replication

## Strategy

**Always use `NetworkTopologyStrategy` in production.** Even single-DC clusters should use NTS — it makes adding a datacenter later straightforward.

```cql
CREATE KEYSPACE my_keyspace WITH REPLICATION = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3,
  'dc2': 3
};
```

`SimpleStrategy` is only acceptable for local development on a single node. It is not rack-aware or datacenter-aware — it breaks failure isolation and prevents DC-local operations.

### Migrating from SimpleStrategy

```cql
ALTER KEYSPACE my_keyspace WITH REPLICATION = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3
};
```

Then run repair to redistribute data:
```bash
nodetool repair -pr my_keyspace
```

## Replication Factor

**RF=3 is standard for production.** It tolerates 1 node failure with `LOCAL_QUORUM` consistency.

| RF | Failures tolerated (QUORUM) | Use case |
|----|----------------------------|----------|
| 1 | 0 | Local development only |
| 3 | 1 | Standard production |
| 5 | 2 | High availability requirements |

**RF must be <= node count in each datacenter.** An RF=3 keyspace on a 2-node datacenter still only has 2 copies — the third replica has nowhere to go.

### Multi-DC Replication

Each datacenter can have a different RF:

```cql
CREATE KEYSPACE my_keyspace WITH REPLICATION = {
  'class': 'NetworkTopologyStrategy',
  'us_east': 3,
  'us_west': 3,
  'analytics': 1
};
```

## Consistency and Replication

With RF=3 and `LOCAL_QUORUM`:
- Writes go to 2 of 3 replicas before acknowledging
- Reads require 2 of 3 replicas to respond
- Tolerates 1 node failure per DC

See [Consistency Levels](./consistency-levels.md) for full guidance.

## See Also

- [Consistency Levels](./consistency-levels.md) — LOCAL_QUORUM, QUORUM, and the quorum math
- [Topology](./topology.md) — rack configuration and minimum nodes per DC
- [Repair](./repair.md) — repair ensures replicas stay in sync
