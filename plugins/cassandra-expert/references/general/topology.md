# Topology

## Minimum Nodes Per Datacenter

**Minimum: 3 nodes per datacenter.** With RF=3 and `LOCAL_QUORUM`, fewer than 3 nodes means a single failure takes the DC offline.

## Rack Configuration

**Match rack count to replication factor.** Cassandra distributes replicas across racks for fault tolerance — each replica should be in a separate rack.

| RF | Racks | Result |
|----|-------|--------|
| 3 | 3 | Optimal — one replica per rack, single rack failure loses 1 of 3 replicas |
| 3 | 2 | **Bad** — 2 replicas in one rack, single rack failure loses 2 of 3 replicas |
| 3 | 1 | No rack awareness — all replicas in same failure domain |

**Avoid 2 racks with RF=3.** This is the worst configuration — it defeats the purpose of rack awareness while still having the operational complexity of multiple racks.

### Racks Map to Failure Domains

Racks should represent actual failure boundaries:
- In AWS: racks = availability zones
- On bare metal: racks = physical server racks with independent power/network
- If all nodes share the same failure domain, use a single rack

### Changing Rack Configuration

Rack assignments cannot be changed on running nodes. Requires a datacenter migration:
1. Create new datacenter with correct rack layout
2. Add nodes with proper rack assignments
3. Migrate traffic
4. Decommission old datacenter

## Scaling

Scale in increments that maintain balance. With RF=3 and 3 racks, add nodes in multiples of 3 (one per rack) to keep data evenly distributed.

## See Also

- `replication.md` — replication factor guidelines
- `vnodes.md` — token allocation and distribution
- `seed-nodes.md` — seed node placement across racks
