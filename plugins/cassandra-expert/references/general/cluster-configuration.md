# Cluster Configuration

All nodes in a Cassandra cluster should run identical `cassandra.yaml` configurations. Nodes with different settings behave differently under load, violate each other's assumptions, and produce failures that can be difficult to diagnose.

## Settings That Cause the Most Problems When Inconsistent

- **Timeouts** (`read_request_timeout_in_ms`, `write_request_timeout_in_ms`) — some nodes fail operations that others succeed, causing phantom errors
- **Compaction** (`compaction_throughput_mb_per_sec`, `concurrent_compactors`) — uneven resource usage across the ring
- **Memory** (memtable sizes, cache sizes) — unpredictable GC behavior on some nodes
- **Failure policies** (`disk_failure_policy`, `commit_failure_policy`) — different failure responses per node make cluster behavior unpredictable
- **Network** (`internode_compression`, streaming timeouts)

## Best Practices

- Version control `cassandra.yaml` and deploy it with configuration management (Ansible, Chef, Puppet, K8ssandra)
- Treat any manual edit to a single node as technical debt — propagate it to all nodes immediately
- Document intentional per-node differences (e.g., different hardware tiers) explicitly
- Audit for configuration drift after rolling restarts or manual interventions
- Include config consistency checks in operational runbooks

## Schema Agreement

All nodes must agree on the same schema. Multiple schema versions is a dangerous condition — different table definitions across nodes causes silent data corruption.

```bash
# Check schema agreement
nodetool describecluster
# Should show a single schema UUID for all nodes
```

**Causes:** Concurrent DDL operations, network partitions during schema changes, mixed Cassandra versions.

**Fix:** Verify all nodes are on the same Cassandra version, then run `nodetool resetlocalschema` on disagreeing nodes one at a time, followed by a rolling restart.

**Prevention:** One DDL operation at a time. Wait for `nodetool describecluster` to show agreement before the next DDL.

## Version Consistency

All nodes must run the same Cassandra version. Mixed versions can have incompatible data formats and protocol differences that cause communication failures.

```bash
nodetool version  # Run on each node — must all match
```

Complete rolling upgrades fully before performing any other cluster operations.

## Table Count and Unused Tables

**Alert at > 100 tables.** High table counts increase memory overhead, complicate monitoring, and fragment memtable memory across too many tables (see `memtables.md`).

Audit for unused tables regularly:
```bash
# Check for zero read/write activity
nodetool tablestats keyspace.table
# Look for Read Count: 0 and Write Count: 0 over 30+ days
```

Drop unused tables after confirming with application teams. Snapshot first:
```bash
nodetool snapshot keyspace -t before_drop
DROP TABLE keyspace.unused_table;
```

If table count is growing past 100, consider splitting into separate clusters by business domain or workload pattern rather than running everything in one cluster.

## Workload Consistency

Generally speaking, avoid mixing transactional and analytics workloads within the same datacenter. Analytics queries (full table scans, large aggregations) compete for resources with latency-sensitive transactional traffic.  The exception to this is when using Cassandra Analytics, as it consumes very few resources in comparison.

Use separate datacenters or separate clusters for analytics workloads. If using Spark with cassandra-analytics, the bulk reader reads SSTables via the sidecar and has minimal impact on the coordinator path.

## See Also

- `os-settings.md` — OS-level settings that must also be consistent cluster-wide
- `commitlog.md` — `commit_failure_policy` details
- `seed-nodes.md` — seed list consistency
