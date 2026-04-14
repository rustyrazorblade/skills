# Memtables in Cassandra

## Overview

Memtables are in-memory structures where Cassandra buffers writes before flushing to SSTables. In Cassandra 5.0+, Trie memtables provide significant performance improvements.

Combined with offheap memtables, trie memtables can deliver significant write throughput improvements — up to ~250% in latency-sensitive workloads. Results vary by hardware and workload.

## Trie Memtables (Cassandra 5.0+)

### Why Trie Memtables Matter

Trie memtables replace the traditional SkipList implementation with a more efficient trie-based structure:

- Significantly reduced allocations
- Lower GC pause frequency
- Shorter GC pause duration
- Improved write throughput under load
- Better memory efficiency

### Enabling Trie Memtables

Trie memtables require explicit configuration in `cassandra.yaml`:

```yaml
memtable:
  configurations:
    skiplist:
      class_name: SkipListMemtable
    trie:
      class_name: TrieMemtable
    default:
      inherits: trie
```

**Important:** This is not enabled by default. You must add this configuration.

### Per-Table Override

You can use different memtable types per table:

```cql
-- Use SkipList for specific table
CREATE TABLE keyspace.table (...)
WITH memtable = 'skiplist';

-- Use Trie (if default is skiplist)
CREATE TABLE keyspace.table (...)
WITH memtable = 'trie';
```

## Monitoring Memtables

### Check Memtable Statistics

```bash
nodetool tablestats keyspace.table
# Look for memtable-related metrics
```

### Monitor Flush Activity

```bash
nodetool tpstats | grep MemtableFlushWriter
# Watch for pending/blocked tasks
```

### Warning Signs

| Symptom | Likely Cause |
|---------|--------------|
| Flush storms (many rapid flushes) | Memtable space too small for workload |
| Frequent old gen GC | Not using Trie memtables on 5.0+ |
| Blocked MemtableFlushWriter | Disk I/O bottleneck or too many tables |
| Many small SSTables | Memtable space fragmented across too many tables |

## Many Tables Consideration

With many tables (50+), memtable memory fragments across all active tables:

- Each table gets smaller portion of total space
- Results in smaller, more frequent flushes
- Creates more SSTables
- Increases compaction overhead

**Solutions:**
- Consolidate tables where data model allows
- Drop unused tables
- Ensure adequate memtable space for table count

## Interaction with Other Features

### With Off-Heap Storage

Use `offheap_objects` for memtable allocation — reduces GC pressure and improves write throughput compared to `heap_buffers`.

```yaml
# cassandra.yaml
memtable_allocation_type: offheap_objects
```

Trie memtables work optimally with off-heap storage, reducing heap pressure further. Account for off-heap memory in total memory planning — this memory comes from native memory, not JVM heap.

### With Compaction

Larger memtable flushes create fewer, larger SSTables, reducing compaction overhead.

### With GC

Trie memtables significantly reduce allocation rate, which:
- Reduces young gen GC frequency
- Reduces promotion to old gen
- Shortens GC pause times

## Blocked Flush Writers

Blocked `MemtableFlushWriter` threads mean the node cannot flush memtables to disk fast enough. This is always a disk I/O problem.

**Check:**
```bash
nodetool tpstats | grep MemtableFlushWriter
# Non-zero "Blocked" count requires immediate investigation

iostat -x 1
# Look for %util near 100%, high await times on data drives
```

**Common causes:**
- Disk I/O saturated — compaction competing with flushes
- Slow or failing storage (check `dmesg | grep -i error` and `smartctl -a /dev/sdX`)
- Network-attached storage with insufficient IOPS
- Too many tables fragmenting flush I/O

**Fixes:**
1. Reduce compaction throughput to free I/O for flushes: lower `compaction_throughput_mb_per_sec`
2. Place commit log on a separate disk from data directories
3. Move to faster local NVMe storage
4. Add nodes to reduce per-node write pressure

Alert on any non-zero blocked flush writer count — it precedes write rejections and OOM conditions.

## Migration to Trie Memtables

When upgrading to Cassandra 5.0+:

1. Add the memtable configuration to `cassandra.yaml`
2. Perform rolling restart
3. Monitor GC behavior
4. Monitor write latency and throughput

## See Also

- [Commit Log](commitlog.md)
- [SSTable Components](sstable-components.md)
- [Compaction](compaction.md)
- [Tombstones](tombstones.md)
- [JVM](jvm.md)
- [Thread Pools](thread-pools.md)
