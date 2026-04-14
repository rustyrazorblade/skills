# Thread Pools

Cassandra uses a staged event-driven architecture (SEDA) where each operation type has its own thread pool. Pending task accumulation in any pool is the primary signal that a bottleneck exists.

## Key Thread Pools

| Pool | Operation | Setting |
|------|-----------|---------|
| `ReadStage` | Local reads | `concurrent_reads` |
| `MutationStage` | Writes and LWTs | `concurrent_writes` |
| `CounterMutationStage` | Counter writes | `concurrent_counter_writes` |
| `CompactionExecutor` | Compaction | `concurrent_compactors` |

## Starting Point Formulas

These are starting points — always tune based on monitoring, not formulas alone.

```yaml
# cassandra.yaml

# 16 × number of data drives
concurrent_reads: 32

# 8 × number of CPU cores
concurrent_writes: 64

# Same as concurrent_writes initially; tune independently
concurrent_counter_writes: 64
```

**LWT workloads**: Double `concurrent_writes` at minimum. LWTs involve multiple network round trips and hold threads much longer than normal writes — the standard formula creates an artificial bottleneck.

## Monitoring

```bash
# Full thread pool stats
nodetool tpstats

# Key columns:
# Active   — currently executing tasks
# Pending  — queued, waiting for a thread (this is your signal)
# Blocked  — tasks that couldn't be queued (should always be 0)
```

**Tuning signal**: If `Pending` is accumulating in a pool AND CPU/disk capacity is available, increase the corresponding concurrency setting incrementally. If resources are already saturated, adding threads makes things worse.

## Interactions

- **Compaction vs reads**: High compaction throughput competes with reads for disk I/O. If `ReadStage` is pending and disk is saturated, check compaction first before raising `concurrent_reads`.
- **Writes vs memtables**: Raising `concurrent_writes` increases memtable pressure — watch GC and flush behavior.
- **Counter writes**: `CounterMutationStage` should be monitored and tuned independently from `MutationStage`.

## Warning Signs

**Over-tuned (too many threads):**
- GC pauses increase
- Memory pressure rises
- Latency increases despite higher concurrency

**Under-tuned (too few threads):**
- Persistent pending tasks
- CPU or disk sitting idle
- Throughput plateaus below hardware capacity

## Commands

```bash
# Thread pool stats
nodetool tpstats

# CPU utilization
top -b -n 1 | grep Cpu

# Disk I/O
iostat -x 1 5
```

## See Also

- [Compaction](./compaction.md) — compaction throughput and its interaction with read concurrency
- [Counters](./counters.md) — counter cache sizing and `concurrent_counter_writes` guidance
