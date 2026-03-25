# Token Ownership Skew — Technical Reference

## Terminology

Throughout this document, these terms have precise, distinct meanings:

- **Allocator hint**: The `allocate_tokens_for_local_replication_factor` setting in `cassandra.yaml`. Controls which token placement algorithm is used at bootstrap. Not a keyspace setting.
- **Keyspace RF**: The replication factor in a keyspace's DDL. Controls how many replicas exist per partition per DC. Not an allocator setting.
- **Rack count**: Number of distinct racks in a datacenter.

These three values are independent. A cluster can have allocator hint=3, keyspace RF=2, and rack count=3 — all at the same time, each serving a different purpose.

## Allocator Code Path

### Selection Logic

Cassandra's `TokenAllocation.createStrategy()` selects between two allocator implementations based on whether the **allocator hint** equals the **rack count**:

```java
// TokenAllocation.createStrategy() — from cassandra-all 5.0.2:
if (numRacks == allocator_hint) {
    return createStrategy(snitch, dc, joiningNodeRack, replicas=1, groupByRack=false);
    // Creates NoReplicationTokenAllocator
    // Filters the ring to same-rack tokens only
    // Places new tokens to balance gaps within that rack
} else {
    // Creates ReplicationAwareTokenAllocator
    // Sees ALL tokens across all racks
    // Optimizes for full-ring primary range balance
}
```

The keyspace RF plays no role in this selection. A node being bootstrapped does not consult any keyspace to decide where to place its tokens.

Source files:
- `org.apache.cassandra.dht.tokenallocator.TokenAllocation` — allocator selection
- `org.apache.cassandra.dht.tokenallocator.NoReplicationTokenAllocator` — per-rack balancing
- `org.apache.cassandra.dht.tokenallocator.ReplicationAwareTokenAllocator` — full-ring balancing
- `org.apache.cassandra.locator.NetworkTopologyStrategy` — replica placement (walks clockwise, picks one node per rack)

### NoReplicationTokenAllocator Behavior

When allocator hint == rack count:
1. Filters the token ring to only tokens belonging to nodes in the joining node's rack
2. Identifies the largest gap between same-rack tokens
3. Places the new token at the midpoint of that gap
4. Repeats for each vnode (`num_tokens` times)

This produces optimal **per-rack** balance because it only cares about same-rack spacing. The resulting full-ring primary ranges can look highly unbalanced because new tokens may land right next to tokens from other racks.

### ReplicationAwareTokenAllocator Behavior

When allocator hint != rack count:
1. Sees ALL tokens from all racks
2. Computes replica ownership considering the full replication strategy
3. Places tokens to minimize full-ring ownership variance

This produces better full-ring balance but can place same-rack nodes unevenly around the ring, leading to worse per-rack balance.

## Two-Phase Analysis Framework

Token skew analysis must separate two independent concerns:

### Phase 1: Token Distribution Quality

**Question**: Did the allocator place tokens well?

**Metric selection**: Based on allocator hint vs rack count (NOT keyspace RF vs rack count).

| Condition | Metric | Why |
|---|---|---|
| Allocator hint == rack count | Per-rack ownership | NoReplicationTokenAllocator was used; it optimized per-rack balance |
| Allocator hint != rack count | Full-ring ownership | ReplicationAwareTokenAllocator was used; it optimized full-ring balance |

**Expected results** (allocator hint == rack count, num_tokens=4): ~1.20-1.25x per-rack skew, stable across cluster sizes.

### Phase 2: Data Distribution Skew

**Question**: How much data does each node actually store for a given keyspace?

This depends on both the token positions (from Phase 1) AND the keyspace RF. Different keyspaces on the same cluster can have different data skew.

**Method**: Simulate NTS replica placement at the keyspace's RF. For each primary range, walk clockwise picking one node per rack until RF replicas are collected. Sum per-node across all ranges where the node holds a replica.

**Validation**: Compare computed ownership against actual disk Load from `nodetool status`.

### Why Separation Matters

A cluster can have:
- Perfect token placement (1.20x per-rack) but significant data skew (1.85x) because the keyspace RF differs from the allocator hint
- Terrible token placement (4.67x per-rack in one rack) but dampened data skew (3.31x at RF=2) because NTS replica flow smooths the imbalance across racks

Mixing these two analyses leads to incorrect conclusions about root cause and incorrect remediation.

## The Per-Rack vs Full-Ring Distinction

### Mathematical Foundation

With NTS, when a keyspace has RF == rack count (e.g., RF=3 with 3 racks), every partition is replicated to all 3 racks. A node's data within its rack is determined by the gap between it and the next same-rack node — cross-rack tokens in between are irrelevant.

When a keyspace has RF != rack count (e.g., RF=2 with 3 racks), each partition only hits 2 of 3 racks. The data each node stores depends on a more complex calculation involving both its primary ranges and replica ranges inherited from other-rack primaries.

**Key distinction**: The per-rack metric evaluates token placement quality (Phase 1). The NTS simulation at a specific RF evaluates data distribution (Phase 2). These answer different questions.

### Traced Example: Why Cross-Rack Near-Collisions are Cosmetic

6 nodes, 2 per rack, allocator hint=3, rack count=3, with a near-collision:

```text
Ring positions:
  a0: 0      (rack-a)
  b0: 17     (rack-b)
  a1: 18     (rack-a)  <-- near-collision with b0 (CROSS-RACK)
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

**Per-rack ownership (correct metric for Phase 1):**

Rack-a tokens: a0 at 0, a1 at 18. Gap a0->a1 = 18, gap a1->a0 = 82.

| Partition token | First rack-a node clockwise | Rack-a node |
|---|---|---|
| 1-18 | a1 | a1 |
| 19-100 (wrapping to 0) | a0 | a0 |

Per-rack ownership: a1 = 18%, a0 = 82%. Per-rack ratio: 4.6x (in this simplified 1-token example). With `num_tokens: 4`, bad placements average out, producing a stable ~1.25x ratio.

The cross-rack near-collision (b0 at 17, a1 at 18) is cosmetic — it makes the full-ring numbers look terrible but has zero effect on per-rack balance.

### Side-by-Side: Allocator Hint = 3 vs 2

Starting with 3 seed nodes evenly spaced, adding a 4th node to rack-a:

```text
Seed ring: a0 at 0, b0 at 33, c0 at 66

allocator hint = 3 (NoReplicationTokenAllocator):
  Sees only rack-a: [a0 at 0]
  Biggest gap: 0 -> 0 (full ring = 100)
  Places a1 at midpoint: position 50
  Rack-a spacing: a0(0)->a1(50) = 50, a1(50)->a0(0) = 50
  Per-rack ratio: 1.0x (perfect)

allocator hint = 2 (ReplicationAwareTokenAllocator):
  Sees all racks: [a0:0, b0:33, c0:66]
  Biggest full-ring gap: c0(66)->a0(0) = 34
  Places a1 at position 83 (midpoint of biggest gap)
  Rack-a spacing: a0(0)->a1(83) = 83, a1(83)->a0(0) = 17
  Per-rack ratio: 83/17 = 4.9x (terrible)

With num_tokens=4, these average out to:
  allocator hint=3: ~1.25x per-rack
  allocator hint=2: ~1.46x to 2.44x per-rack
```

## Tested Skew Ratios

Measured on Cassandra 5.0.6 clusters. The "Hint" column is the allocator hint, NOT a keyspace RF. Results are deterministic across runs.

### Full Matrix: Full-Ring vs Per-Rack

| num_tokens | Hint | Allocator | Metric | 6 nodes | 9 nodes | 12 nodes | 18 nodes |
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

Some operators (e.g., cass-operator) pre-compute evenly-spaced `initial_token` values for seed nodes. Whether or not seeds are pre-computed, **per-rack skew with allocator hint=3 and num_tokens=4 is the same** (~1.25x). Pre-computed seeds only affect full-ring appearance, not per-rack reality.

Note: Pre-computed tokens that evenly divide the full ring without considering per-rack balance can produce high per-rack skew (3-4x) even though the full-ring distribution looks perfect. Token computation must optimize for per-rack balance when the allocator hint == rack count.

## Near-Collision Analysis

### Definition

A near-collision occurs when two tokens from different nodes are extremely close on the ring. On the full 2^64 Murmur3 token range, gaps can be extremely small (single digits).

### Impact Classification

| Type | Description | Impact on token placement (Phase 1) |
|---|---|---|
| Cross-rack | Tokens from different racks nearly adjacent | Cosmetic when allocator hint == rack count |
| Same-rack | Tokens from same rack nearly adjacent | Real problem — causes per-rack imbalance |

**Cascading effect**: A same-rack near-collision doesn't just affect the 2 colliding nodes. It displaces ownership across the entire rack, potentially pushing many nodes outside the normal range.

## The num_tokens Averaging Effect

With `num_tokens: 4`, each node has 4 tokens around the ring. If one token lands in a suboptimal position, the other 3 tokens still contribute normal-sized gaps. A node's total ownership is the sum across all its token ranges.

- With `num_tokens: 1`: A single bad placement is catastrophic — no averaging.
- With `num_tokens: 4`: Bad placements are diluted. Per-rack skew stabilizes at 1.25x.
- With `num_tokens: 16+`: More averaging, but the operational costs (streaming, neighbors) far outweigh the marginal balance improvement.

## References

- Cassandra source: `TokenAllocation.java`, `NoReplicationTokenAllocator.java`, `ReplicationAwareTokenAllocator.java`, `NetworkTopologyStrategy.java`
- vnodes reference: `vnodes.md` (in this directory)
