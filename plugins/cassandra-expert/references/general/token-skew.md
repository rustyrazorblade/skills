# Token Ownership Skew — Technical Reference

## Overview

This document provides the full technical detail behind token ownership skew analysis in Apache Cassandra. It covers the allocator code paths, the distinction between full-ring and per-rack ownership metrics, and tested skew ratios across configurations.

## Allocator Code Path

### Selection Logic

Cassandra's `TokenAllocation.createStrategy()` selects between two allocator implementations based on whether `allocate_tokens_for_local_replication_factor` equals the number of racks in the datacenter:

```java
// TokenAllocation.createStrategy() — from cassandra-all 5.0.2:
if (numRacks == rf) {
    return createStrategy(snitch, dc, joiningNodeRack, replicas=1, groupByRack=false);
    // Creates NoReplicationTokenAllocator
    // This allocator filters the ring to same-rack tokens only
    // and places new tokens to balance gaps within that rack
} else {
    // Creates ReplicationAwareTokenAllocator
    // This allocator sees ALL tokens across all racks
    // and optimizes for full-ring primary range balance
}
```

Source files:
- `org.apache.cassandra.dht.tokenallocator.TokenAllocation` — allocator selection
- `org.apache.cassandra.dht.tokenallocator.NoReplicationTokenAllocator` — per-rack balancing
- `org.apache.cassandra.dht.tokenallocator.ReplicationAwareTokenAllocator` — full-ring balancing
- `org.apache.cassandra.locator.NetworkTopologyStrategy` — replica placement (walks clockwise, picks one node per rack)

### NoReplicationTokenAllocator Behavior

When `numRacks == rf`:
1. Filters the token ring to only tokens belonging to nodes in the joining node's rack
2. Identifies the largest gap between same-rack tokens
3. Places the new token at the midpoint of that gap
4. Repeats for each vnode (`num_tokens` times)

This produces optimal **per-rack** balance because it only cares about same-rack spacing. However, the resulting full-ring primary ranges can look highly unbalanced because new tokens may land right next to tokens from other racks.

### ReplicationAwareTokenAllocator Behavior

When `numRacks != rf`:
1. Sees ALL tokens from all racks
2. Computes replica ownership considering the full replication strategy
3. Places tokens to minimize full-ring ownership variance

This produces better full-ring balance but can place same-rack nodes unevenly around the ring, leading to worse per-rack balance.

## The Per-Rack vs Full-Ring Distinction

### Mathematical Foundation

With NetworkTopologyStrategy (NTS), RF=3, and 3 racks, every partition is replicated to all 3 racks. The replica placement algorithm walks clockwise from the partition's token and selects the first node encountered from each rack.

For a given rack (say rack-a), a partition is stored on whichever rack-a node is the first rack-a node clockwise from the partition's token. This means a rack-a node's data ownership equals the total of all gaps between it and the preceding rack-a node(s) — cross-rack tokens in between are irrelevant.

### Traced Example: Why Near-Collisions are Cosmetic

6 nodes, 2 per rack, RF=3, with a near-collision:

```text
Ring positions:
  a0: 0      (rack-a)
  b0: 17     (rack-b)
  a1: 18     (rack-a)  <-- near-collision with b0
  c0: 33     (rack-c)
  b1: 67     (rack-b)
  c1: 83     (rack-c)
```

**Full-ring primary ranges:**

| Node | Gap | Full-ring % |
|------|-----|-------------|
| a0   | c1(83) to a0(0) = 17 | 17% |
| b0   | a0(0) to b0(17) = 17 | 17% |
| a1   | b0(17) to a1(18) = 1 | 1% |
| c0   | a1(18) to c0(33) = 15 | 15% |
| b1   | c0(33) to b1(67) = 34 | 34% |
| c1   | b1(67) to c1(83) = 16 | 16% |

Full-ring ratio: 34/1 = 34x. Looks catastrophic.

**Per-rack ownership (tracing NTS replica placement):**

Rack-a tokens: a0 at 0, a1 at 18. Gap a0->a1 = 18, gap a1->a0 = 82.

| Partition token | Walk clockwise for rack-a | Rack-a node |
|-----------------|---------------------------|-------------|
| 1-18            | a1 is first rack-a node   | a1          |
| 19-100 (wrapping to 0) | a0 is first rack-a node | a0 |

Per-rack ownership:
- a1: 18% of all data
- a0: 82% of all data
- Per-rack ratio: 82/18 = 4.6x (in this simplified 1-token example)

With `num_tokens: 4`, each node has 4 tokens and the bad placements average out, producing a stable ~1.25x ratio.

### RF=3 (NoReplication) vs RF=2 (ReplicationAware): Side-by-Side

Starting with 3 seed nodes evenly spaced, adding a 4th node to rack-a:

```text
Seed ring: a0 at 0, b0 at 33, c0 at 66

allocate_tokens = 3 (NoReplication):
  Sees only rack-a: [a0 at 0]
  Biggest gap: 0 -> 0 (full ring = 100)
  Places a1 at midpoint: position 50
  Rack-a spacing: a0(0) -> a1(50) = 50, a1(50) -> a0(0) = 50
  Per-rack ratio: 1.0x (perfect!)

allocate_tokens = 2 (ReplicationAware):
  Sees all racks: [a0:0, b0:33, c0:66]
  Biggest full-ring gap: c0(66) -> a0(0) = 34
  Places a1 at position 83 (midpoint of biggest gap)
  Rack-a spacing: a0(0) -> a1(83) = 83, a1(83) -> a0(0) = 17
  Per-rack ratio: 83/17 = 4.9x (terrible!)

With num_tokens=4, these average out to:
  NoReplication:    ~1.25x per-rack
  ReplicationAware: ~1.46x to 2.44x per-rack
```

## Tested Skew Ratios

Measured on Cassandra 5.0 clusters across multiple configurations. Results are deterministic across runs. The recommended `num_tokens` values are 1 or 4 (see `vnodes.md`); `num_tokens: 3` is included for comparison only.

### Full Matrix: Full-Ring vs Per-Rack

| num_tokens | RF | Allocator | Metric | 6 nodes | 9 nodes | 12 nodes | 18 nodes |
|---|---|---|---|---|---|---|---|
| 4 | 3 | NoReplication | full-ring | 2.00x | 3.00x | 2.00x | 5.00x |
| 4 | 3 | NoReplication | per-rack | 1.25x | 1.25x | 1.25x | 1.20x |
| 3 | 3 | NoReplication | full-ring | 2.50x | 2.75x | 2.83x | 2.99x |
| 3 | 3 | NoReplication | per-rack | 1.33x | 1.33x | 1.33x | 1.31x |
| 4 | 2 | ReplicationAware | full-ring | 1.33x | 2.00x | 1.50x | 1.60x |
| 4 | 2 | ReplicationAware | per-rack | 1.46x | 1.87x | 2.00x | 1.62x |
| 3 | 2 | ReplicationAware | full-ring | 1.67x | 2.00x | 1.67x | 2.00x |
| 3 | 2 | ReplicationAware | per-rack | 2.43x | 1.54x | 2.00x | 2.44x |

### Effect of Pre-computed Seed Tokens

Some operators (e.g., cass-operator) pre-compute evenly-spaced `initial_token` values for seed nodes. Whether or not seeds are pre-computed, **per-rack skew for RF=3 is the same** (~1.25x with `num_tokens: 4`). Pre-computed seeds only affect full-ring appearance, not per-rack reality.

## Near-Collision Analysis

### Definition

A near-collision occurs when two tokens from different nodes are extremely close on the ring. On the full 2^64 Murmur3 token range, gaps can be extremely small (single digits).

Whether near-collisions occur depends on the seed token starting offset, which varies per cluster. They are not inherent to the allocator algorithm itself.

### Impact Classification

| Type | Example | Impact when RF = rack count |
|------|---------|---------------------------|
| Cross-rack | rack-a and rack-b tokens nearly adjacent | None (cosmetic) |
| Same-rack | Two same-rack tokens nearly adjacent | Real — one node stores almost nothing for that vnode |

With `num_tokens: 4`, even a same-rack near-collision on one vnode is diluted by the other 3 vnodes. The overall per-rack skew remains bounded.

## The num_tokens Averaging Effect

With `num_tokens: 4`, each node has 4 tokens around the ring. If one token lands in a suboptimal position, the other 3 tokens still contribute normal-sized gaps. A node's total data ownership is the sum across all its token ranges.

- With `num_tokens: 1`: A single bad placement is catastrophic — no averaging.
- With `num_tokens: 4`: Bad placements are diluted. Per-rack skew stabilizes at 1.25x for RF=3.
- With `num_tokens: 16+`: More averaging, but the operational costs (streaming, neighbors) far outweigh the marginal balance improvement.

## References

- Cassandra source: `TokenAllocation.java`, `NoReplicationTokenAllocator.java`, `ReplicationAwareTokenAllocator.java`, `NetworkTopologyStrategy.java`
- vnodes reference: `vnodes.md` (in this directory)
