# Cassandra 5.0 cassandra.yaml Recommendations

This document is the set of **opinionated recommendations** that should be applied on top of the default Cassandra 5.0 config. The unmodified default config file that Cassandra 5.0 ships with is alongside this document as [`cassandra.yaml`](./cassandra.yaml) — use it to see every setting and its shipped default. The recommendations below intentionally override several of those shipped defaults (notably `num_tokens`, the UCS scaling parameters, `storage_compatibility_mode`, and `commitlog_sync_period`).

## Quick Start: cassandra_latest.yaml

Cassandra 5.0 ships with `cassandra_latest.yaml` - a new config file with optimized defaults for new clusters.  This is a good reference to see the settings that enabled the newest features, all of which are opt-in.

## Critical Settings

### num_tokens

```yaml
num_tokens: 1  # or 4
```

**Use 1 token when possible, never more than 4.**

- More tokens = more data movement during scaling
- More tokens = more overhead in token calculations
- More tokens = worse Zero-Copy Streaming eligibility

For detailed explanation of why vnode count matters and the math behind neighbor calculations, see `../general/vnodes.md`.

### Storage Compatibility Mode

```yaml
# Set to NONE to enable all 5.0 features (BTI SSTable format, extended TTL
# beyond 2038, UUID-based SSTable generation).
#
# CRITICAL: the out-of-box default is CASSANDRA_4, which triggers a data loss
# bug with Cassandra Sidecar (CASSANDRA-21197:
# https://issues.apache.org/jira/browse/CASSANDRA-21197). Explicitly set NONE
# before running Sidecar against a 5.0 cluster — the default is not safe.
storage_compatibility_mode: NONE
```

### BTI

```yaml
sstable:
  selected_format: bti
```

**Use the BTI (Big Trie-Indexed) SSTable format.** It replaces the legacy BIG format with a trie-based index that is more memory-efficient and performs better at scale. This is the recommended format for all new Cassandra 5.0 deployments — unless you rely on token range scans (see [CASSANDRA-20976](https://issues.apache.org/jira/browse/CASSANDRA-20976)).

### Memtable Configuration

Use trie memtables (Cassandra 5.0+) for lower GC pressure and better write throughput. Configure and set as default:

```yaml
memtable:
  configurations:
    skiplist:
      class_name: SkipListMemtable
    trie:
      class_name: TrieMemtable
    default:
      inherits: trie

memtable_allocation_type: offheap_objects
memtable_heap_space: 4GiB
memtable_offheap_space: 8GiB

```

**Use trie memtables with off-heap allocation.**

- Reduces GC pressure significantly
- Better write performance
- Off-heap keeps data out of the Java heap
- The `default: inherits: trie` applies trie memtables to all tables

### Key Cache

```yaml
key_cache_size: 0
```

With BTI format, key cache provides no benefit. The trie-based index is efficient enough without caching.

Only keep key cache enabled if you have legacy BIG format SSTables.

### Compaction Throughput

Cassandra 5.0.4+ includes significant compaction throughput improvements (CASSANDRA-15452):
- 2-3x improvement in throughput
- 3x reduction in IOPS on cloud storage
- Uses efficient 256KB off-heap read buffer

```yaml
compaction_throughput: 64MiB/s  # or higher
```

**Upgrade to at least 5.0.4+ for these benefits.**

Reference: [Compaction Throughput](https://rustyrazorblade.com/post/2025/04-compaction-throughput/)

### Default Compaction Strategy

```yaml
default_compaction:
  class_name: UnifiedCompactionStrategy
  parameters:
    scaling_parameters: L10
    max_sstables_to_compact: 10
    target_sstable_size: 1GiB
    sstable_growth: 0.3333333333333333
    min_sstable_size: 100MiB
```

Sets UCS as the default for all new tables.

> **Note on the defaults (`L10` / `max_sstables_to_compact: 10`):** This is a deliberate, opinionated choice — **not** the Cassandra project defaults. `L10` configures UCS to behave like a Leveled strategy with a fan factor of 10, which keeps the number of SSTables consulted per read small and produces predictable read latency. `max_sstables_to_compact: 10` caps how many SSTables a single compaction operation will merge at once, preventing runaway compactions on dense nodes.
>
> The upstream project defaults (`T4` / `max_sstables_to_compact: 32`) emulate STCS-style tiering and are better suited to write-heavy workloads where read latency matters less than write amplification. If your cluster is overwhelmingly write-heavy, `T4` is a reasonable fallback — but for most workloads, the leveled-style defaults above are the right starting point.

### Concurrent Compactors

```yaml
concurrent_compactors: 8
```

Enables parallel compaction operations. Adjust based on available CPU cores and I/O capacity.

## Compression Settings

```yaml
# Default compression for new tables
compression:
  class: ZstdCompressor
  chunk_length_in_kb: 16
```

**Avoid the legacy 64KB chunk size.**

- Larger chunks = more data decoded per read
- 16KB is a good balance for most workloads
- Consider 4KB for counter tables (read-before-write pattern) and tables using LWT to minimize the overhead of decompression on single row reads.  

## Commitlog Settings

The default here hasn't kept up with modern hardware.  Use 1 second sync period to minimize the data loss window.

```yaml
commitlog_sync_period: 1s
commitlog_disk_access_mode: auto
```

- `commitlog_sync_period`: 10s is outdated. 1s reduces data loss window on modern hardware.
- `commitlog_disk_access_mode`: `auto` selects optimal mode based on hardware.

### Trickle Fsync

```yaml
trickle_fsync: true
trickle_fsync_interval: 10MiB
```

Avoids sudden large I/O bursts by syncing incrementally.

## Streaming Settings

```yaml
stream_entire_sstables: true
```

Enables Zero-Copy Streaming. This is the default but verify it's enabled.

**Note**: Automatically disabled with internode encryption.

## Thread Pool Settings

```yaml
concurrent_reads: 64
concurrent_writes: 256
```

Defaults are often reasonable, but monitor for saturation:
- Increase if threads are consistently saturated with low CPU usage
- Watch for blocked threads in `nodetool tpstats`

## Cache Settings

```yaml
row_cache_size: 0
```

**Keep row cache disabled.** It's rarely beneficial and often harmful:
- High memory overhead
- Cache invalidation overhead
- Better to rely on OS page cache


## Guardrails

Cassandra 5.0 adds guardrails to prevent problematic configurations:

```yaml
# Example guardrails
tables_warn_threshold: 150
tables_fail_threshold: 200
columns_per_table_warn_threshold: 25
columns_per_table_fail_threshold: 50
```

Review and tune guardrails based on your operational requirements.

## Settings to Avoid

### Row Cache

Never enable `row_cache_size` unless you have a very specific, validated use case.  I haven't found any.

### Auto Bootstrap False

Don't set `auto_bootstrap: false` unless you know exactly what you're doing (e.g., restoring from backup).

### Large num_tokens

Never use `num_tokens` > 4. The historical default of 256 is harmful.

### Materialized Views

Keep them disabled.  Materialized views are a half-baked feature that should never have been merged in.

```
materialized_views_enabled: false
```

# Compaction

```yaml
default_compaction:
  class_name: UnifiedCompactionStrategy
  parameters:
    scaling_parameters: L10 # or use T4 if you're using mostly write heavy tables
    max_sstables_to_compact: 10
    target_sstable_size: 1GiB
    sstable_growth: 0.3333333333333333
    min_sstable_size: 100MiB
```

## Migration Notes

When upgrading from Cassandra 4.x:

1. **Don't change storage_compatibility_mode immediately** - wait until all nodes are upgraded
2. **Key cache**: Keep enabled until all SSTables are rewritten to BTI format
3. **num_tokens**: Cannot be changed on existing clusters without full rebuild
4. **Memtable settings**: Can be changed with rolling restart

## See Also

- [Cassandra 5.0 Notable Features](./notable-features.md)
- [JVM Options (5.0-specific flags)](./jvm-options.md)
- [Compaction](../general/compaction.md)
- [Memtables](../general/memtables.md)
- [Virtual Nodes (vnodes)](../general/vnodes.md)
- [OS Settings](../general/os-settings.md)
- [JVM (general heap & GC tuning)](../general/jvm.md)
