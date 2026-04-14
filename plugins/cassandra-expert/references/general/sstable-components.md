# SSTable Components

An SSTable (Sorted String Table) is Cassandra's immutable on-disk storage format. Each flush from the memtable produces a new SSTable. Understanding the components helps diagnose read performance, memory usage, and compaction behavior.

## File Components

Each SSTable is a set of files written together. The exact set varies by format (see Formats below), but the logical components are consistent:

| Component | Purpose |
|-----------|---------|
| **Data** (`*-Data.db`) | The actual row data, compressed in chunks |
| **Partition Index** (`*-Index.db` / `*-Partition.db`) | Maps partition keys to byte offsets in the Data file |
| **Index Summary** (`*-Summary.db`) | Sampled subset of the partition index, held in heap memory |
| **Bloom Filter** (`*-Filter.db`) | Probabilistic structure: tells you a key is definitely NOT here |
| **Compression Info** (`*-CompressionInfo.db`) | Chunk offsets for the compressed Data file |
| **Statistics** (`*-Statistics.db`) | Metadata: min/max tokens, tombstone counts, column stats |
| **TOC** (`*-TOC.txt`) | List of all files belonging to this SSTable |

## Bloom Filters

Before touching disk, Cassandra checks the bloom filter for each SSTable. If the filter says the partition is not present, the SSTable is skipped entirely.

- **Default `fp_chance`: 0.01** for most strategies, **0.1** for LCS (LCS reads already touch few SSTables, so a bigger filter isn't worth the memory)
- False positives cause unnecessary disk reads; false negatives are impossible by design
- Lower `fp_chance` = larger filter in memory, fewer wasted reads
- Higher `fp_chance` = smaller filter, more wasted reads

```cql
-- Lower to reduce wasted I/O (uses more off-heap memory)
ALTER TABLE keyspace.table WITH bloom_filter_fp_chance = 0.001;

-- Higher for tables rarely queried by partition key
ALTER TABLE keyspace.table WITH bloom_filter_fp_chance = 0.1;
```

**When FP rate exceeds configured value:**
The most common cause is too many SSTables from compaction falling behind. Fix compaction first before adjusting `fp_chance`. Check:

```bash
nodetool compactionstats          # pending compactions
nodetool tablehistograms ks.tbl   # SSTables per read
```

After changing `fp_chance`, rebuild bloom filters without rewriting data:
```bash
nodetool upgradesstables -a keyspace table
```

## SSTables Per Read

Every SSTable that might contain a partition must be checked during a read. Bloom filters reduce unnecessary checks, but compaction is what reduces SSTable count.

```bash
nodetool tablehistograms keyspace.table
# Look at the "SSTables" histogram — p99 > 5 warrants investigation
```

**Target: p99 < 5 SSTables per read** for most workloads.

| Cause | Fix |
|-------|-----|
| Compaction falling behind | Increase `compaction_throughput_mb_per_sec` or switch to UCS (5.0+) |
| Infrequent incremental repair | Repaired/unrepaired groups are read separately — run repair more often |
| TWCS (time-series) | High SSTable count is expected and acceptable if read latency is within SLA |

**Incremental repair note:** When using incremental repair, Cassandra maintains separate repaired and unrepaired SSTable groups. Both are consulted during reads, effectively doubling SSTable count. Running repair frequently keeps the unrepaired group small.

## Index Summary

The index summary is a sampled in-memory subset of the partition index, used to locate a partition's approximate position in the index file before doing a final disk seek.

- Stored in JVM heap
- Controlled by `index_summary_capacity_in_mb` (default: 256MB)
- If the summary is too small, it will be sampled more aggressively, increasing the number of disk seeks per read

```yaml
# cassandra.yaml
index_summary_capacity_in_mb: 256  # Increase on high-density nodes
```

## Compression Info

The compression offset map tracks where each compressed chunk starts in the Data file. This is held **off-heap**.

- With 4KB chunks, a 20TB node can use 4–5GB of off-heap memory for compression metadata
- Account for this when sizing JVM off-heap memory limits

See `compression.md` for chunk size guidance.

## SSTable Formats

### Big (Classic) Format — Cassandra 3.x / 4.x
Uses a B-tree style partition index and a sampled index summary. Default format for pre-5.0 clusters.

### BTI (Big Trie-Indexed) Format — Cassandra 5.0+
Replaces the partition index with a trie-based structure. Benefits:
- Smaller index files
- Faster partition lookups, especially at high partition counts
- Lower index summary memory requirements
- Opt-in in Cassandra 5.0 — requires both `storage_compatibility_mode: NONE` and `sstable: selected_format: bti` (see [bti.md](./bti.md))

The BTI format is one of several reasons Cassandra 5.0 enables higher node density.

## Monitoring

```bash
# Per-table SSTable stats and compression ratio
nodetool tablestats keyspace.table

# Read latency histogram and SSTables per read
nodetool tablehistograms keyspace.table

# Off-heap memory usage (compression metadata, bloom filters, index summaries)
nodetool tablestats keyspace.table | grep -i "off heap"
```

## See Also

- [BTI SSTable Format](./bti.md) — the trie-indexed format for Cassandra 5.0+
- [Compaction](./compaction.md) — how compaction reduces SSTable count
- [Compression](./compression.md) — chunk size trade-offs and off-heap memory impact
- [Repair](./repair.md) — how incremental repair interacts with SSTable groups
