# Commit Log

The commit log is Cassandra's write-ahead log. Every write is appended here before the acknowledgment is sent to the client, providing durability in case of a crash before the memtable is flushed to disk.

## Sync Modes

### Periodic (recommended for most workloads)

```yaml
# cassandra.yaml
commitlog_sync: periodic
commitlog_sync_period_in_ms: 1000   # Local SSD/NVMe
commitlog_sync_period_in_ms: 2000   # Disaggregated storage (EBS, network-attached)
```

Cassandra batches writes and fsyncs at the configured interval. Higher write throughput, lower latency. Risk: up to one interval of writes can be lost on a hard crash.

With RF=3 and `LOCAL_QUORUM` writes, the data is already on multiple nodes — the practical durability risk of 1–2 second periodic sync is very low for most workloads.

### Batch (higher durability, lower throughput)

```yaml
commitlog_sync: batch
commitlog_sync_batch_window_in_ms: 2
```

Cassandra fsyncs after every write batch. Near-zero data loss on crash, but significantly higher write latency. Use only when write durability is more critical than performance — financial systems, compliance audit logs.

## Storage-Specific Guidance

| Storage Type | Recommended Interval |
|---|---|
| Local NVMe/SSD | 1000ms |
| Disaggregated (EBS, network-attached) | 2000ms |
| Spinning disks | 10000ms (upgrade storage if possible) |

The legacy default of 10 seconds is conservative and appropriate only for slow spinning disks.

## Hardware Layout

Place the commit log on a **separate disk** from data directories. Commit log writes are sequential and append-only — a dedicated disk prevents I/O contention with the random read/write pattern of data files and compaction.

On cloud instances with a single volume, this is not always practical, but on bare metal it is a meaningful performance improvement.

## Monitoring

```bash
# Check commit log segment count and size
nodetool commitlog

# Disk utilization on commit log volume
iostat -x 1

# Write latency (batch mode will show higher p99)
nodetool tablehistograms keyspace.table
```

Watch for:
- Commit log disk filling up (blocked writes follow)
- High write latency on clusters using `batch` sync mode
- Commit log disk I/O contention with data directories (sign they share a volume)

## Failure Policy

```yaml
# cassandra.yaml
commit_failure_policy: die  # default — recommended
```

| Option | Behavior |
|--------|----------|
| `die` | JVM exits immediately — enables clean alerting and restart |
| `stop` | Stops CQL/gossip but keeps JVM running |
| `stop_paranoid` | Stops all operations including gossip |
| `ignore` | Logs error and continues — **never use this** |

Use `die`. A commit log failure means the node cannot safely accept writes. Continuing with `ignore` risks silent data loss. Configure systemd or your process supervisor to restart the node and alert on the crash.

Ensure this setting is consistent across all nodes — inconsistent policies make failure behavior unpredictable.

## See Also

- `memtables.md` — flush behavior and blocked flush writers
- `os-settings.md` — disk layout and I/O configuration
