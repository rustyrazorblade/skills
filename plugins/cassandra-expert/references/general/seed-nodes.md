# Seed Nodes

Seed nodes help new nodes discover the cluster topology during bootstrap. They are not special at runtime — they only matter when a node is joining or restarting.

## Configuration

```yaml
# cassandra.yaml
seed_provider:
  - class_name: org.apache.cassandra.locator.SimpleSeedProvider
    parameters:
      - seeds: "dc1_node1,dc1_node2,dc1_node3,dc2_node1,dc2_node2,dc2_node3"
```

## Rules

**Use at least 3 seed nodes per datacenter** (3 is the standard; 2 for constrained dev DCs). Fewer creates a single point of failure for cluster discovery. Going much higher provides no benefit and adds operational overhead.

**All seed IPs must be active cluster members.** Invalid seed addresses (decommissioned nodes, typos, stale IPs) prevent new nodes from joining and cause bootstrap failures. Audit seed lists whenever you decommission a node or change IPs.

**The same seed list must appear on every node in the cluster.** Inconsistent seed lists cause gossip issues and unreliable topology changes. See `cluster-configuration.md`.

## Selecting Seeds

- Choose stable, reliable nodes that are unlikely to be decommissioned
- Distribute across different racks for fault tolerance
- Include seeds from every datacenter in multi-DC deployments
- Do not make every node a seed — 3 per DC is optimal

## See Also

- `cluster-configuration.md` — seed list consistency across nodes
- `gossip.md` — how gossip uses seeds for cluster discovery
