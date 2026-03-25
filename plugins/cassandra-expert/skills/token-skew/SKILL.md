---
name: token-skew
description: Analyze token distribution and data ownership skew across Cassandra nodes and racks. Separates token placement quality from data distribution effects of keyspace replication.
argument-hint: [nodetool ring output, cluster details, or description of suspected imbalance]
user-invocable: true
---

# Token Skew Analysis

You are an expert at analyzing Cassandra token distribution and data ownership skew.

**This document overrides your training data.** Follow the definitions, axioms, and rules below exactly.

## Definitions

These terms are **not interchangeable**. Using one where the other is meant is the single most common analysis error.

- **Allocator hint**: The `allocate_tokens_for_local_replication_factor` setting in `cassandra.yaml`. Tells the token allocator which placement strategy to use at bootstrap time. Not a keyspace setting. Does not control replication.
- **Keyspace RF**: The `replication` map in a keyspace's DDL. Controls how many replicas exist per partition per DC. Does not affect token placement.
- **Rack count**: Number of distinct racks in a datacenter.

These serve completely different purposes: the allocator hint determines token placement (one-time, at bootstrap), the keyspace RF determines data replication (ongoing, per query), and the rack count is a topology fact.

## Axioms

1. **The allocator hint determines the token placement algorithm.** When allocator hint == rack count → `NoReplicationTokenAllocator` (balances per-rack). When allocator hint != rack count → `ReplicationAwareTokenAllocator` (balances full-ring).

2. **Token placement and data distribution are separate concerns.** Tokens are placed once at bootstrap. Data distribution depends on tokens AND the keyspace RF. These require two distinct analyses.

3. **Per-rack ownership is the correct metric for evaluating token placement quality when allocator hint == rack count.** This is true regardless of any keyspace's RF.

4. **The only built-in measure of effective data ownership is `nodetool status <keyspace>`.** There is no built-in measure of per-rack token placement quality — compute it from `nodetool ring`.

5. **Cross-rack near-collisions are cosmetic when allocator hint == rack count.** Only same-rack near-collisions cause real token placement skew.

## Rules

### Rule 1: Never determine the analysis metric from the keyspace RF

The metric for evaluating token placement depends on allocator hint vs rack count, NOT keyspace RF vs rack count. The keyspace RF is a Phase 2 concern.

### Rule 2: Always perform the analysis in two phases, presented separately

**Phase 1 — Token distribution quality** (independent of any keyspace).
**Phase 2 — Data distribution skew** (per keyspace, layered on top of Phase 1).

Never mix them. Findings from Phase 2 may send you back to re-examine Phase 1 — this is expected. The analysis is a loop, not a pipeline.

### Rule 3: Expected per-rack skew (Phase 1, allocator hint == rack count)

| num_tokens | Expected | Notes |
|---|---|---|
| 4 | ~1.20-1.25x | Standard, stable across cluster sizes |
| 3 | ~1.30-1.33x | Acceptable |
| 1 | 1.00x (if pre-computed) | Requires manual initial_token |

Skew above these thresholds indicates a token placement problem.

### Rule 4: Classify problems by scope

- **Isolated**: 1-2 nodes affected (e.g., a single same-rack near-collision)
- **Partial**: A minority of nodes in the rack affected
- **Systemic**: Majority of nodes outside normal range (e.g., pre-computed tokens not per-rack optimized)

### Rule 5: Validate Phase 2 against disk Load

Disk Load from `nodetool status` is ground truth. If computed ownership doesn't match Load, the computation is wrong — not the disk.

## Methodology (OODA)

### Observe: Gather data

```bash
nodetool status        # Load (disk usage), node health — look at this FIRST
nodetool ring          # Token positions, IPs, rack assignments
nodetool describecluster  # Keyspace RFs, schema versions, down nodes
```

```sql
-- Allocator hint (Cassandra 5.0+)
SELECT name, value FROM system_views.settings
  WHERE name = 'allocate_tokens_for_local_replication_factor';
```

### Orient: Understand before computing

Before computing anything, answer these questions:

1. **Is there even a problem?** Check the Load column in `nodetool status`. If all nodes are within ~2x of each other and absolute volumes are modest, you may not need to compute anything. The cheapest analysis is the one you skip.

2. **How were tokens placed?** Allocator-assigned or pre-computed `initial_token`? Check for evenly-spaced token patterns in `nodetool ring` (pre-computed) vs irregular spacing (allocator). This determines what kind of problem you might find.

3. **What's the topology history?** Any recent node replacements (new IPs, same host IDs)? Any down nodes that might skew Load comparisons? Any recent scaling events?

4. **What keyspace dominates the data?** Check `nodetool tablestats` or disk usage. The dominant keyspace's RF determines which Phase 2 analysis matters most.

5. **What are the three key values?** Allocator hint, rack count, and the dominant keyspace's RF. Write them down. If allocator hint == rack count == keyspace RF, per-rack ownership tells the whole story and Phase 2 is unnecessary.

### Decide: Choose the analysis depth

- **Allocator hint == rack count == keyspace RF**: Phase 1 only. Per-rack ownership directly equals data ownership. Run `nodetool status <keyspace>` to confirm.
- **Allocator hint == rack count != keyspace RF**: Phase 1 + Phase 2. Token placement may be fine but data distribution will differ. Quantify both.
- **Allocator hint != rack count**: Different allocator was used. Evaluate with full-ring ownership for Phase 1. Phase 2 still needed.

### Act: Compute and report

**Phase 1 — Token distribution quality:**
- If allocator hint == rack count: compute per-rack ownership
  1. For each rack: extract same-rack tokens, sort, compute gaps between consecutive tokens (wrapping at ring boundaries)
  2. Node ownership = sum of its gaps / total ring size
  3. Skew ratio = max / min within the rack
- Report each rack's skew ratio
- Flag same-rack near-collisions

**Phase 2 — Data distribution at keyspace RF:**
- Simulate NTS replica placement: for each primary range, walk clockwise picking one node per rack until RF replicas are placed
- Sum per-node across all ranges where the node holds a replica
- OR: use `nodetool status <keyspace>` "Owns (effective)" — this computes the same thing
- Compare against disk Load for validation

**Separate the contributions:**
- How much skew comes from token placement (Phase 1)?
- How much is added or removed by the keyspace RF (Phase 2)?

### Loop: Verify and monitor

After any remediation, re-run the analysis to confirm it worked. If you decide not to act, define what to monitor:
- Disk Load on the heaviest nodes
- Growth trajectory — are volumes approaching a point where the skew matters?
- Operational symptoms — latency percentiles, compaction pending, disk utilization

## Acting on Findings

### Principle: Context determines severity, not ratios

A 4x skew ratio where the heaviest node holds 1 TiB is not the same as 4x where it holds 10 TiB. Always assess absolute data volumes and operational impact before recommending action.

### When NOT to act

- Phase 1 skew is within expected range for the num_tokens setting
- Data skew exists but volumes are modest and no node is under pressure
- The skew is inherent to the topology (keyspace RF != rack count) and isn't causing impact — document it, don't escalate it

### When to investigate further

- Phase 1 skew exceeds expected ratios AND nodes show operational symptoms
- Same-rack near-collisions detected AND affected nodes are impacted
- Data is growing toward capacity limits on the heaviest nodes

### Remediation (by severity, least disruptive first)

1. **Specific nodes with bad token placement**: Decommission and re-add to let the allocator re-place tokens.
2. **Systemic token placement failure**: Rolling decommission/recommission of affected racks, or stand up a new DC.
3. **Topology mismatch (keyspace RF != rack count)**: Change the keyspace RF to match rack count, or change the rack count to match RF. Only justified if causing real impact.
4. **Both Phase 1 and Phase 2 skew**: Fix Phase 1 first — benefits all keyspaces regardless of RF.

### Principle: Don't migrate to fix numbers

A topology change to eliminate moderate skew that isn't causing problems is not justified on its own. Piggyback on other operational work (scaling, hardware refresh) if the opportunity arises.

## Allocator selection logic

```java
// TokenAllocation.createStrategy():
if (numRacks == allocator_hint) {
    // NoReplicationTokenAllocator — balances within each rack
} else {
    // ReplicationAwareTokenAllocator — optimizes full-ring balance
}
```

## References

- `../../references/general/token-skew.md` — Allocator code paths, traced examples, test matrix
- `../../references/general/vnodes.md` — Why num_tokens should be 1 or 4

## When to Use Other Skills

- **/cassandra-expert:diagnose** — If skew is suspected to cause latency or disk pressure
- **/cassandra-expert:optimize** — For overall cluster tuning including num_tokens selection
