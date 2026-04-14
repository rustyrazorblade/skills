# Compaction in Cassandra

## Overview

Compaction merges SSTables, removes deleted and overwritten data, and organizes data for efficient reads. 

Strategy selection directly impacts node density, operational costs, and performance.

## Strategy Selection

### Decision Tree

```
Is your Cassandra version 5.0 or later?
├── YES → Use UCS (for all workloads)
└── NO (4.x or earlier)
    └── Is this a time series workload?
        ├── YES → Is data immutable with TTL?
        │   ├── YES → Use TWCS
        │   └── NO → Use LCS with table bucketing by date
        └── NO → Is this a write-intensive workload with overwrites?
            ├── YES → Consider STCS (rare case)
            └── NO → Use LCS (best general-purpose choice)
```

### Cassandra 5.0+: Use UCS for Everything

**UnifiedCompactionStrategy (UCS)** replaces all legacy strategies:

- Adapts to workload patterns automatically
- Controlled SSTable sizes (default 1GB)
- Better streaming performance (Zero Copy eligible)
- Reduced write amplification

### Cassandra 4.x and 3.x

| Strategy | Use Case | Trade-offs |
|----------|----------|------------|
| **LCS** | General purpose, read-heavy | Higher write amp, consistent reads |
| **TWCS** | Immutable time series with TTL | Large SSTables prevent ZCS |
| **STCS** | Very rare - write-heavy with overwrites | Creates huge SSTables, avoid |

**STCS should almost never be used on modern systems.** It creates unmanageably large SSTables, results in poor streaming performance, and inefficient space reclamation.  It also requires a significant amount of free space, 50% in the worst case.

### Pre-3.0 with Spinning Disks

On very old Cassandra versions (pre-3.0) with spinning disks, STCS may be the only viable option due to LCS write amplification on slow storage.

**However:** If you're running pre-3.0 Cassandra on spinning disks, you should prioritize upgrading to modern Cassandra on SSDs. The performance, operational, and cost benefits far outweigh migration effort.

## Migration to UCS

### From STCS

`T4` provides 4 SSTables per tier, emulating STCS behavior while avoiding massive SSTables.

```cql
ALTER TABLE mykeyspace.foo WITH COMPACTION = {
    'class': 'UnifiedCompactionStrategy',
    'scaling_parameters': 'T4'
};
```


### From LCS

`L10` provides 10 SSTables per level, maintaining LCS-like read performance.

```cql
ALTER TABLE mykeyspace.foo WITH COMPACTION = {
    'class': 'UnifiedCompactionStrategy',
    'scaling_parameters': 'L10'
};
```

### From TWCS

The tiered settings can be used to reduce write amplification at higher levels.  
This provides similar behavior to TWCS without the negative effects of major compaction as the window is closed, 
which negatively impacts streaming performance.  Node density can be significantly increased by switching from TWCS to UCS.

```cql
ALTER TABLE mykeyspace.foo WITH COMPACTION = {
    'class': 'UnifiedCompactionStrategy',
    'scaling_parameters': 'T4,T8',
    'base_shard_count': '8'
};
```

## Scaling Parameters

| Parameter | Behavior | Use Case |
|-----------|----------|----------|
| `T4` | 4 SSTables per tier (tiered) | Write-heavy, STCS replacement |
| `T4,T8` | Tiered first level, fan out second | High-write time series |
| `L10` | 10 SSTables per level (leveled) | Read-heavy, LCS replacement |

## Throughput Tuning

### Key Settings
```yaml
compaction_throughput_mb_per_sec: 64  # Adjust based on workload
concurrent_compactors: 4              # Baseline; increase on NVMe with many cores
```

### Per-Compactor Throughput

Each compactor thread needs at least 8 MB/s or it will be throttled so aggressively that SSTables accumulate. Rule of thumb:

```
compaction_throughput_mb_per_sec / concurrent_compactors >= 8
```

Target range: **32–160 MB/s total**. Setting it too high causes excessive object allocation and GC pressure. Set it as low as possible while keeping pending compactions near zero.

```yaml
# Example: 4 compactors, 16 MB/s each
compaction_throughput_mb_per_sec: 64
concurrent_compactors: 4
```

Monitor pending compactions over several days before adjusting — STCS workloads show spiky pending counts during large compactions that are normal and not a signal to increase throughput.

### Cassandra 5.0.4+ Optimization

- CASSANDRA-15452 provides 2-3x throughput improvement
- 3x IOPS reduction on cloud storage (EBS)
- Uses 256KB sequential reads for better cloud storage efficiency

## Monitoring

### Key Metrics
1. **Pending compactions**: Should be near zero normally
2. **SSTables per read**: Track via `nodetool tablehistograms`
3. **Compaction throughput**: Completion speed
4. **p99 read latency**: Ensure SLO compliance

### Commands
```bash
nodetool compactionstats
nodetool compactionhistory
nodetool tablehistograms keyspace.table
```

## Disk Space Requirements

Space requirements depend heavily on compaction strategy — the old advice of "keep 50% free" only applies to STCS.

| Strategy | Free Space Needed |
|----------|------------------|
| **STCS** | Up to 50% — major compactions can temporarily require 2x table size. **Never use STCS on disks > 2TB.** |
| **LCS** | Moderate — overlapping SSTables during leveling, more predictable than STCS |
| **TWCS** | Predictable — one SSTable per window, efficient for time series |
| **UCS** | 10–50GB if data is stable; more headroom if growing |

Clusters can run at > 90% disk capacity with UCS, but some operations become high risk (snapshots, node replacements). **Keep at least 100GB free as an absolute minimum.**

**Immediate actions when space is critical:**
```bash
# Clear snapshots (common space hog)
nodetool clearsnapshot

# Check snapshot size
du -sh /var/lib/cassandra/data/*/*/snapshots/
```

Then add nodes or expand volumes — don't just delete data without understanding what it is.

**Alert thresholds (customize for your setup):**
- STCS on small disks (< 1TB): warn at 40% free, critical at 30%
- STCS on medium disks (1–2TB): warn at 30% free, critical at 20%
- UCS on large disks (> 2TB): warn at 200GB free, critical at 50GB

Monitor absolute free space in GB, not just percentages — a 10% threshold on a 10TB disk is 1TB, which is very different from 10% on a 500GB disk.

## Common Issues

### High Pending Compactions

Alert threshold: **> 20 pending compactions sustained** warrants investigation.

```bash
nodetool compactionstats
```

- Increase `compaction_throughput_mb_per_sec` if CPU and I/O are not saturated
- Add `concurrent_compactors` if CPU has headroom
- Upgrade to 5.0.4+ for better throughput on disaggregated storage (EBS)
- Switch from STCS to UCS on 5.0+ — STCS creates large SSTables that take excessive time to compact
- If CPU or disk is saturated, you need to expand capacity

### Read Performance Degradation

- High SSTables per read indicates compaction behind or incorrect strategy / options are set.
- Switch to UCS with leveling parameters (L10) for read heavy or latency heavy workloads. 
- Review data model for large partitions, use `nodetool tablehistograms` to identify p99 and largest partitions.

## OS Settings

Readahead must be set to 4KB on all data drives. The OS default (often 128KB–1MB) causes read amplification for Cassandra's random-access pattern. See `os-settings.md` for configuration details.

## Summary

| Version | Recommendation                           |
|---------|------------------------------------------|
| 5.0+ | UCS for all workloads                    |
| 4.x/3.x | LCS for general, TWCS for time series.   |
| Pre-3.0 + spinning disks | STCS (but upgrade ASAP)                  |

## See Also

- [Tombstones](./tombstones.md)
- [Streaming](./streaming.md)
- [SSTable Components](./sstable-components.md)
- [Compaction Throughput Improvements in Cassandra 5.0.4](https://rustyrazorblade.com/post/2025/04-compaction-throughput/)
- [Compaction Strategies and Performance](https://rustyrazorblade.com/post/2025/07-compaction-strategies-and-performance/)
- [Compaction Nuance](https://thelastpickle.com/blog/2017/03/16/compaction-nuance.html)
