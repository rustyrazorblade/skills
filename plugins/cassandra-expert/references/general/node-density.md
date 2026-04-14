# Node Density

How much data a Cassandra node can handle depends heavily on the version. Denser nodes reduce infrastructure costs but increase repair times, streaming duration, and recovery complexity.

## Version-Specific Limits

| Version | Practical Limit | Notes |
|---------|----------------|-------|
| 3.x | ~3TB | Repairs and streaming become slow and failure-prone above this |
| 4.x | ~5TB | Better compaction and streaming than 3.x, incremental repair safe |
| 5.0+ | Well beyond 5TB | CASSANDRA-15452, BTI, trie memtables, and Shenandoah GC change the equation |

These are soft limits, not hard errors. The signs you've exceeded a practical density limit are: repairs taking too long to complete within `gc_grace_seconds`, streaming failures during bootstrap/decommission, and compaction permanently falling behind.

## What Enables Higher Density in 5.0

- **CASSANDRA-15452**: 2–3x compaction throughput improvement, especially on cloud storage
- **BTI (Big Trie-Indexed)**: More efficient partition index, lower memory overhead
- **Trie memtables**: Reduced GC pressure, better write throughput
- **Java 17 + Shenandoah GC**: Ultra-low pause GC reduces stop-the-world impact at scale
- **Off-heap memtables**: Keeps heap smaller, reduces GC frequency

If you're running 3.x or 4.x with nodes approaching their limits, upgrading to 5.0 is often more cost-effective than adding nodes.

## Operational Trade-offs at High Density

Even on 5.0, denser nodes mean:
- **Longer bootstraps**: More data to stream when adding a node
- **Longer repairs**: More data to compare per node
- **Slower recovery**: A failed node takes longer to replace
- **Larger backups**: More data to snapshot and transfer

The right density depends on your operational tolerance. A cluster that needs fast recovery from node failure should stay leaner. A stable analytics cluster with infrequent topology changes can run much denser.

## Addressing Density Issues

**Immediate**: Add nodes and let the cluster rebalance.

**Long-term**: Upgrade to 5.0 and enable:
```yaml
# Trie memtables
memtable:
  configurations:
    default:
      inherits: trie

# Java 17 + Shenandoah (in jvm.options)
-XX:+UseShenandoahGC
```

## See Also

- `sstable-components.md` — BTI format details
- `memtables.md` — trie memtables configuration
- `compaction.md` — CASSANDRA-15452 throughput improvements
- `repair.md` — repair frequency and gc_grace_seconds
