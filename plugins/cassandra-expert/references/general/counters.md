# Counters

## Accuracy

Counter increments are **not idempotent**. Every increment is a read-before-write: the replica reads the current value, adds the delta, and writes the result. If the acknowledgement is lost and the coordinator retries, the increment is applied twice. Under normal conditions these errors are rare; at scale, the accumulated error is not zero.

**Use counters only when small deviations are acceptable** — page views, approximate engagement metrics, rough order-of-magnitude totals. Never for money, inventory, audit counts, or anything where exact values matter. Track individual events in regular tables when you need exact counts.

## Compression: 4 KB chunks

Every counter increment performs a read-before-write, so decompression cost per read dominates. Configure counter tables with LZ4 and a 4 KB chunk length:

```sql
ALTER TABLE my_counters
WITH compression = {
    'class': 'LZ4Compressor',
    'chunk_length_in_kb': 4
};
```

vs. the default 16 KB (or 64 KB on older versions), 4 KB chunks decompress 4–16× less data per counter read. On counter-heavy tables this reduces per-write CPU overhead by up to 10–15×.

## Counter cache

The counter cache stores the most recently read counter values on each replica, letting increments skip the on-disk read entirely. A high hit rate is the single biggest throughput lever for counter workloads.

**Enable and size it generously in `cassandra.yaml`:**

```yaml
counter_cache_size_in_mb: 256     # default is auto (typically small)
counter_cache_save_period: 7200   # persist across restarts
```

**Target a hit rate as close to 100% as possible.** Monitor with `nodetool info` or the `system_views` virtual tables. If the hit rate is low, increase `counter_cache_size_in_mb` — the cache is off-heap, so a larger cache does not pressure GC.

The counter cache is far more valuable than the row or key cache for counter workloads. If you're running a counter-heavy table and haven't tuned it, this is the first thing to fix.

## See Also

- [Compression](./compression.md)
- [Thread Pools](./thread-pools.md) — `concurrent_counter_writes` tuning
- [Lightweight Transactions (LWT)](./lwt.md) — the right tool when you need exact counts
