# Lightweight Transactions (LWT)

LWTs provide linearizable consistency (compare-and-set semantics) using the Paxos consensus protocol. They are significantly more expensive than regular operations — multiple round trips between nodes, higher latency, lower throughput.

## When to Use

**Valid use cases:**
- Account/user creation with uniqueness guarantee (`IF NOT EXISTS`)
- Leader election and distributed locks
- Compare-and-set operations where race conditions must be prevented

**Do not use for:**
- High-throughput hot paths
- Operations that can tolerate eventual consistency
- Anything that can be handled with application-level coordination

Question every LWT — most apparent "I need linearizable consistency" cases can be redesigned away.

## CQL Syntax

```cql
-- Insert only if partition doesn't exist
INSERT INTO users (id, name) VALUES (123, 'John') IF NOT EXISTS;

-- Conditional update (compare-and-set)
UPDATE users SET balance = 100 WHERE id = 123 IF balance = 50;
```

The response includes an `[applied]` boolean — always check it. A `false` response means the condition failed and the write was not applied.

## Paxos v2 (Cassandra 4.1+)

Enable Paxos v2 for meaningfully better LWT performance:

```yaml
# cassandra.yaml
paxos_variant: v2
```

V1 and V2 are compatible during rolling rollout — restart nodes one at a time. V2 reduces round trips and improves latency significantly over V1.

## Paxos State Purging

Enable repair-based purging of Paxos state:

```yaml
# cassandra.yaml
paxos_state_purging: repaired
```

This ties cleanup of the `system.paxos` table to incremental repair rather than to a time-based TTL. It's the right setting for any cluster that uses LWTs — it keeps `system.paxos` from accumulating stale rows between repair cycles and avoids the correctness edge cases that TTL-based purging can hit.

## Thread Pool Impact

LWTs hold `MutationStage` threads much longer than normal writes due to Paxos round trips. The standard `concurrent_writes` formula (8 × cores) creates an artificial bottleneck for LWT-heavy workloads.

**For LWT-heavy clusters: at least double `concurrent_writes`.**

```yaml
concurrent_writes: 128  # Instead of the formula-based 64
```

Monitor `MutationStage` pending tasks — if they accumulate and CPU is available, increase further.

## Detecting Heavy LWT Usage

```bash
# system.paxos appearing in top tables by read activity is a signal
nodetool tablestats system.paxos

# Search application code/logs for conditional writes
grep -r "IF NOT EXISTS\|IF EXISTS" .
```

## Reducing LWT Usage

**Redesign the data model:** If uniqueness is needed, make the unique value the partition key — writes to the same partition key are idempotent by nature.

**Accept eventual consistency:** Many use cases don't actually require linearizable consistency. Application-level conflict resolution is often sufficient.

**External coordination:** For distributed locking, tools like ZooKeeper or etcd are purpose-built and more performant.

## See Also

- `thread-pools.md` — `concurrent_writes` tuning for LWT workloads
- `batches.md` — batching LWT operations for a single Paxos round
