# JVM Configuration

## GC Algorithm Selection

| Scenario | GC | Notes |
|----------|-----|-------|
| Cassandra 5.0 + Java 17 (default) | **G1GC** | Works well for most workloads |
| Cassandra 5.0 + Java 17, latency-sensitive with moderate write rates | **Shenandoah** | Ultra-low pause times; wasteful on compaction-heavy workloads — prefer G1GC for those |
| Heap >= 16GB | G1GC | Better than CMS for large heaps |
| Heap < 16GB | CMS + ParNew | Legacy; Java ≤ 11 only — removed in Java 14 ([JEP 363](https://openjdk.org/jeps/363)) |

### Shenandoah (Cassandra 5.0 + Java 17+)

```bash
# jvm17-server.options
-Xms16G
-Xmx16G
-XX:+UseShenandoahGC
-XX:ShenandoahGCMode=iu
```

### G1GC (heap >= 16GB)

```bash
# jvm-server.options
-Xms16G
-Xmx16G
-XX:+UseG1GC
-XX:G1RSetUpdatingPauseTimePercent=5
-XX:MaxGCPauseMillis=500
```

### CMS + ParNew (heap < 16GB)

```bash
# jvm-server.options
-Xms8G
-Xmx8G
-Xmn6G  # 50-75% of heap for new generation
-XX:MaxTenuringThreshold=2
-XX:+UseParNewGC
-XX:+UseConcMarkSweepGC
```

## Heap Sizing

**Always set min and max heap equal:** `-Xms` = `-Xmx`. This prevents heap resizing during operation.

Heap is required scratch space for allocations. Smaller heaps pause more frequently. The trade-off is between page cache (read performance) and GC pause times — balance both.

| Node RAM | Heap | Notes |
|----------|------|-------|
| 32GB | 12–16GB | 12GB for read-heavy (more page cache), 16GB for write-heavy (fewer GC pauses) |
| 64GB | 16GB | Good balance for most workloads |
| 128GB+ | 16–31GB with Shenandoah | Large page cache, Shenandoah handles big heaps well |

Don't over-allocate heap — OS page cache is critical for read performance. But don't under-allocate either — a too-small heap causes frequent GC pauses that hurt latency.

## New Generation Sizing (CMS only)

Allocate **50–75% of total heap** to new generation (`-Xmn`). Most Cassandra objects are short-lived (query results, buffers). Old generation primarily holds memtables waiting to flush.

Always set `MaxTenuringThreshold=2` — prevents short-lived objects from being promoted to old gen unnecessarily.

## JVM Consistency Across Nodes

All nodes in a cluster must use identical JVM settings. Different heap sizes or GC algorithms cause:
- Uneven GC pause patterns across nodes
- Some nodes handling load well while others degrade
- Capacity planning and troubleshooting become unreliable

Manage `jvm-server.options` (or `jvm17-server.options` on 5.0) with configuration management and version control — same as `cassandra.yaml`.

## Monitoring and Profiling

```bash
# GC log location (check jvm-server.options for exact path)
# Look for:
# - Young GC frequency and duration
# - Old GC / full GC frequency (should be rare)
# - Pause times > 100ms (concerning), > 500ms (will cause drops)

# Heap utilization
nodetool info | grep Heap
```

### Allocation Profiling

Use **async-profiler** with `-e alloc` to track JVM memory allocations and identify allocation hot spots:

```bash
# Attach to running Cassandra process
./asprof -e alloc -d 30 -f alloc-profile.html <pid>
```

Use **Swiss Java Knife (sjk) ttop** to monitor per-thread CPU and allocation rates in real time:

```bash
# Show top threads by allocation rate
sjk ttop -p <pid> -o ALLOC
```

Key signals:
- Frequent old gen GC → heap too small or not using trie memtables on 5.0
- Long GC pauses → wrong GC algorithm for heap size
- Heap consistently > 75% used → increase heap or reduce pressure

## See Also

- [Hardware](./hardware.md) — memory sizing per node
- [Memtables](./memtables.md) — trie memtables reduce GC pressure on 5.0
- [Cluster Configuration](./cluster-configuration.md) — JVM settings must be consistent
- [OS Settings](./os-settings.md) — swap and THP settings that affect GC behavior
- [Thread Pools](./thread-pools.md) — pool sizing determines heap allocation rates
