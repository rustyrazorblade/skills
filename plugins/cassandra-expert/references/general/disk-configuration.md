# Disk Configuration

## Single Data Directory (Recommended)

Use a single `data_file_directories` path. If you need to combine multiple physical disks, use LVM or RAID rather than listing multiple directories.

```yaml
# cassandra.yaml
data_file_directories:
  - /var/lib/cassandra/data
```

## Multiple Data Directories (JBOD)

### Pre-4.0: Dangerous

Cassandra versions before 4.0 have a critical JBOD bug that can cause data resurrection and partial partition loss. Partition data may be incorrectly placed across multiple disks, leading to silent corruption that is difficult to detect.

If you must use JBOD on pre-4.0, **`disk_failure_policy: stop` is mandatory** — any other setting risks data corruption when a disk fails.

```yaml
# Pre-4.0 JBOD (not recommended, but if you must)
data_file_directories:
  - /mnt/disk1/cassandra/data
  - /mnt/disk2/cassandra/data
disk_failure_policy: stop  # REQUIRED
```

### 4.0+: Safe

Cassandra 4.0 resolved the JBOD data safety issues. Multiple data directories work correctly.

## Alternatives to JBOD

- **LVM** — combine physical disks into a single logical volume
- **RAID** — hardware or software RAID (RAID 0 for performance, RAID 10 for redundancy)
- **Larger cloud volumes** — provision a single EBS/persistent disk with adequate capacity
- **More nodes** — scale horizontally instead of adding disks per node

## Commit Log Separation

Place the commit log on a **separate disk** from data directories when possible. The commit log is sequential and append-only — a dedicated disk prevents I/O contention with the random read/write pattern of data operations and compaction.

See `commitlog.md` for full guidance.

## See Also

- `disk-failure-policy.md` — how the node handles disk errors
- `commitlog.md` — commit log disk placement
- `os-settings.md` — readahead and other disk-level settings
