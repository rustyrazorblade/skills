# Cassandra 5.0 Notable Features

## Recommended Configuration Checklist

Enable all of these on new Cassandra 5.0 clusters:

- **UnifiedCompactionStrategy** — replace STCS, LCS, and TWCS for all workloads
- **Trie memtables** — lower GC pressure, better write throughput
- **BTI format** — unless using token range scans (see CASSANDRA-20976)
- **Java 17 + Shenandoah GC** — ultra-low pause times at scale
- **Off-heap memtables** — reduce heap pressure
- **Compaction throughput** — 64 MiB/s default; tune toward 128 MiB/s for write-heavy clusters, avoid excessive values that cause GC pressure
- **Zstd compression** — when compression ratio matters more than CPU overhead

Details on each below.

## Unified Compaction Strategy (UCS)

**Recommendation: Replace 100% of STCS workloads with UCS immediately.**

UCS fundamentally improves upon STCS through a density-based approach. While STCS merges similarly-sized SSTables into larger ones (eventually creating unwieldy files), UCS maintains fine-grained control over SSTable sizing with a default of 1GB per file.

**STCS should never be used with Cassandra 5.0.** There are exactly zero cases where STCS is the right choice now that UCS exists.

### Key Advantages Over STCS

- Controlled file sizes preventing excessive growth
- Enhanced read efficiency through better organization
- Minimized write amplification
- Superior temporary space handling
- Dramatically better streaming performance

### Why UCS Enables Faster Cluster Expansion

UCS produces smaller, bounded SSTables. This is critical because Zero-Copy Streaming (ZCS) only works when the destination node owns the complete token range of an SSTable. Smaller SSTables mean:

- New nodes are more likely to own complete SSTable token ranges
- More SSTables qualify for the fast Zero-Copy path
- Cluster expansions complete faster and more reliably

Combined with limited virtual nodes (1-4) and ZCS enabled, UCS maximizes streaming efficiency and enables denser nodes with reduced infrastructure costs.

For details on Zero-Copy Streaming (introduced in 4.0), see [Cassandra 4.0 Notable Features](../cassandra-4.0/notable-features.md).

### Migration Configuration

**From STCS:**

```cql
ALTER TABLE mykeyspace.mytable WITH COMPACTION = {
  'class': 'UnifiedCompactionStrategy',
  'scaling_parameters': 'T4'
};
```
The `T4` setting emulates STCS behavior while avoiding massive SSTables.

**From LCS:**
```cql
ALTER TABLE mykeyspace.mytable WITH COMPACTION = {
  'class': 'UnifiedCompactionStrategy',
  'scaling_parameters': 'L10'
};
```

**Time-Series Workloads:**
- `scaling_parameters`: Tiering levels (e.g., `'T4,T8'`)
- `base_shard_count`: Enables parallel compactions for write-heavy scenarios
- `unsafe_aggressive_sstable_expiration`: Allows dropping fully expired files without safety verification

Reference: [Compaction Strategies and Performance](https://rustyrazorblade.com/post/2025/07-compaction-strategies-and-performance/)

## Storage Attached Indexes (SAI)

SAI provides efficient indexing without the problems of legacy secondary indexes:

- Query complex data types efficiently
- Better performance than legacy secondary indexes at moderate scale
- Supports vector similarity search (though see Vector section below)

### Critical Performance Guidance

**Always include the partition key in SAI queries.**

SAI scales linearly with the total number of SSTables in the cluster. Without a partition key:
- Small clusters: Acceptable performance
- Large clusters: Performance degrades significantly

With a partition key in the query, SAI only needs to search SSTables that could contain that partition, dramatically reducing the search space.

### When to Use SAI
- Queries that include the partition key plus additional filtering
- Moderate cardinality columns
- When you need more flexibility than partition/clustering keys alone

### When NOT to Use SAI
- High-cardinality columns at scale without partition key filtering
- As a replacement for proper data modeling
- High-throughput queries that could be served by denormalization

## Trie Memtables and SSTables

New trie-based data structures for both in-memory and on-disk storage.

### Trie Memtables

**Recommendation: Use trie memtables with off-heap memory.**

Trie memtables store keys by shared prefixes instead of full keys, reducing object count and improving CPU cache locality.

Benefits:
- Reduced memory overhead
- Better write performance
- Improved flush efficiency
- Lower GC pressure with off-heap configuration

### BTI SSTable Format (Trie-Indexed SSTables)

BTI (Big Trie-Indexed) is a new SSTable format that replaces the partition index with a trie-based structure.

**Enable in cassandra.yaml** (both settings are required — `storage_compatibility_mode: NONE` unlocks 5.0 features, `selected_format: bti` selects BTI as the active format):
```yaml
storage_compatibility_mode: NONE
sstable:
  selected_format: bti
```

Benefits:
- Removes redundant key material in indexes
- Reduces number of key comparisons during lookups
- Faster data access for large datasets
- Key cache is not used (index is efficient enough without it)

Note: Cassandra can read both BTI and legacy BIG format SSTables, so migration is seamless.

## JDK 17 Support

Cassandra 5.0 requires Java 17+.

### Shenandoah GC Option

Java 17 supports Shenandoah GC, which can deliver lower latencies more consistently than G1.

**However, use with caution:**

Shenandoah can result in significant wasted CPU time with compaction-heavy workloads. This is common with:
- Spark jobs doing large bulk writes
- Any analytics workload with heavy write amplification

For analytics workloads, consider the Cassandra Analytics project to offload bulk operations.

### GC Recommendation
- **G1GC**: Default choice, works well for most workloads
- **Shenandoah**: Consider for latency-sensitive workloads with moderate write rates

## Vector Data Type

Cassandra 5.0 includes a native vector data type and similarity search via SAI.

**Recommendation: Do not use Cassandra for vector search.**

The current implementation has performance issues. For vector search workloads, consider:
- Qdrant
- Milvus

These have proven reliable in production use cases.

## Other Notable Features

### Dynamic Data Masking
Automatic redaction of sensitive data based on user permissions.

### Enhanced Guardrails
Additional safety mechanisms to prevent problematic configurations.

### TTL and Writetime on Collections/UDTs
Extended TTL and writetime tracking to complex data structures.

### Mathematical CQL Functions
New functions: `abs`, `exp`, `log`, `log10`, `round`

### SSTablePartitions Tool
Offline utility for identifying oversized partitions.

### Extended TTL Maximum
Increased expiration date limits beyond the previous 20-year cap.

## See Also

- [cassandra.yaml](./cassandra-yaml.md)
- [JVM Options](./jvm-options.md)
- [Compaction](../general/compaction.md)
- [Memtables](../general/memtables.md)
- [BTI SSTable Format](../general/bti.md)
- [SSTable Components](../general/sstable-components.md)
- [Streaming](../general/streaming.md)
- [What's New in Cassandra 5.0](https://cassandra.apache.org/doc/latest/cassandra/new/index.html)
