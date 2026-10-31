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

## Where the Cost Goes

Each Paxos round reads the Paxos state of the partition and makes three writes to `system.paxos` (promise, proposal, commit), on every replica. On local NVMe, Paxos v2 is CPU-bound: at the throughput ceiling the nodes run at 96–97% CPU, NVMe stays 3–4% busy, and the commit log does not wait.

On slower disks, such as EBS gp2, the limit can be the disk instead. This was not measured. The Paxos state reads that miss the caches go to disk, and every round adds commit log writes. Check disk latency and utilization (`iostat -x`) before you treat the node as CPU-bound. On a disk-bound node, the caches below matter more.

The settings below each remove part of that CPU cost. They were measured together with Paxos v2 on 3 × 8 vCPU nodes, RF 3, with 1M LWT keys. The changes raised the ceiling from about 14.7k to about 19.5k CAS writes/s (+32%) and cut CPU per write by 24%.

### Paxos v1 and v2

Paxos v1 does the same replica work: its rounds run on `MutationStage`, read the Paxos state, and make the same three `system.paxos` writes. So most of these settings also apply to v1. All numbers in this file come from v2; v1 was not measured.

| Setting | v1 | v2 |
|---|---|---|
| `concurrent_writes`, `native_transport_max_threads` | yes | yes |
| `paxos_cache_size` | yes (4.1+) | yes |
| Chunk cache (`file_cache_*`) | yes | yes |
| Memtable shard count | yes (5.0+) | yes (5.0+) |
| `paxos_contention_*` back-off | **no** | yes |

On v1, a contended coordinator always sleeps a random 0–100ms, and no setting changes it. If contention is the problem on v1, move to v2.

## Thread Pool Sizing

LWTs hold `MutationStage` threads much longer than normal writes due to Paxos round trips. The coordinator also holds a native transport thread for the whole Paxos round. The default `concurrent_writes` of 32 is too low on any modern hardware. Start at 64, then raise it from the metrics.

Raise `concurrent_writes` only when both of these are true:

- **CPU is available.** CPU utilization is well below 90% (`top`, `mpstat`, or node_exporter `node_cpu_seconds_total`).
- **Writes are waiting for a thread.** In `nodetool tpstats`, `MutationStage` `Active` equals `concurrent_writes` and `Pending` stays above 0. The JMX metrics are `org.apache.cassandra.metrics:type=ThreadPools,path=request,scope=MutationStage,name=ActiveTasks` and `name=PendingTasks`.

`MutationStage` has an unbounded queue, so its `Blocked` and `All time blocked` columns stay at 0. Waiting writes show up as `Pending`.

```yaml
# cassandra.yaml
concurrent_writes: 64               # starting point; raise from the metrics above
native_transport_max_threads: 128   # default
```

Do not raise it when CPU is saturated. If CPU is above 90% and `Pending` is high, more threads only wait on the `system.paxos` memtable locks and add scheduling cost. On 8 vCPU nodes with local NVMe, 512 threads cut the LWT ceiling 12.5% and raised the p99 10× compared with 128. If CPU is idle and the disk is saturated, the node is disk-bound; more threads do not help, so fix the disk or the cache hit rate.

Leave `native_transport_max_threads` at the default of 128; raising it to 512 made LWT worse, and lowering it to 96 made it worse too.

## Paxos State Cache (Cassandra 4.1+, v1 and v2)

Each Paxos round reads the Paxos state of the partition. On a cache miss, the read goes to the `system.paxos` SSTables. The default cache is min(1% of heap, 50 MiB), which is too small for most LWT workloads.

```yaml
# cassandra.yaml
paxos_cache_size: 1GiB
```

Size it at about 0.5 KB per partition that gets LWTs often. It is on-heap. With 1M LWT keys, `paxos_cache_size: 1GiB` raised the ceiling 15%, cut CPU per write 13%, and cut the p50 near the ceiling from 25ms to 10.5ms. With billions of LWT keys, size it to the keys that get LWTs often, not to all keys.

Also enable the chunk cache. It removes the disk read and decompression for the Paxos state reads that still miss the Paxos cache:

```yaml
# cassandra.yaml
file_cache_enabled: true
file_cache_size: 1GiB
```

On top of the Paxos cache, the chunk cache raised the ceiling another 6% and cut CPU per write 8%. It is on-heap; include it in heap sizing.

## Memtable Shards (Cassandra 5.0+, v1 and v2)

The three `system.paxos` writes per round go through the sharded memtable, which takes a lock per shard. The default shard count is the number of CPU cores. Under LWT load, most thread waiting is on these locks. Raise the count with a JVM option:

```
# jvm-server.options
# 4 × CPU cores; 32 on an 8-core node
-Dcassandra.memtable.shard.count=32
```

On 8 vCPU, 32 shards (4 × cores) raised the ceiling 4% and cut the p99 near the ceiling from 50ms to 37ms. On larger nodes, start at 4 × cores and measure. This option changes every table that uses the default memtable configuration, not only `system.paxos`.

**Do not reduce `system.paxos` flushes.** `memtable_cleanup_threshold: 0.3` cut the LWT ceiling by 46%. The `system.paxos` memtable grew, and every Paxos state read slowed down.

## Contention Back-off (Cassandra 4.1+, v2 only)

When two coordinators compete for the same partition, the loser waits before it tries again. The default wait is random between 0 and 100ms. These settings apply to Paxos v2 only; v1 always uses the fixed 0–100ms wait. With a hundred contended keys, that single wait sets the p99 at about 88ms, while the replica work is only 0.4ms.

Cap the wait:

```yaml
# cassandra.yaml
paxos_contention_max_wait: "p95(rw)*1.8^attempts <= 50ms"
paxos_contention_min_delta: "10ms"
```

Measured effect:

- With 100 contended keys, the p99 fell from 88ms to 11ms.
- With 10 contended keys, throughput rose 4% and the p99 fell from 546ms to 295ms.
- The cost is about 2× the timeouts on very hot keys.

Do not cap the wait at 20ms. Competing coordinators collide again, and throughput on 10 contended keys falls 35%.

## Contended Partitions

A partition that gets frequent concurrent LWTs is a hot spot. Treat it like a large partition: design it out of the data model.

- **Per-partition limit.** With v2, one partition does at most about 950 Paxos rounds/s (about 1ms per round, three round trips). Timeouts pass 0.1% at about 7.6 LWT/s per partition. v1 uses more round trips per round, so expect a lower limit; it was not measured.
- **It affects the whole node.** With v2, coordinators wait on a per-partition lock while they hold a native transport thread. With v1, a contended coordinator holds its native transport thread through the 0–100ms sleep. Two hot partitions held 510 of 512 native transport threads. Regular writes to an unrelated table saw their p99 rise 3.2–3.8× and their rate fall up to 20%.

Fixes:

- Spread the LWTs over more partitions. For example, split a global counter or sequence into buckets.
- Send all LWTs for a partition to one coordinator: token-aware routing with no replica shuffle. This removes ballot conflicts between coordinators.
- Tune the contention back-off (above).

Signals:

- `ClientRequest` `CASWrite` `ContentionHistogram` and `UnfinishedCommit` rise.
- `CASWrite` timeouts rise while `CASWrite` p50 stays low.
- With v2, a thread dump shows native transport threads in `Object.wait` on `PaxosState`.

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
- `memtables.md` — memtable shard count
- `batches.md` — batching LWT operations for a single Paxos round
