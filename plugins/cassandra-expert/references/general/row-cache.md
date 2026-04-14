# Row Cache

**Disable row cache. Set `row_cache_size_in_mb: 0`.**

```yaml
# cassandra.yaml
row_cache_size_in_mb: 0
```

Row cache stores entire partitions in JVM heap. This increases GC pressure significantly and rarely provides a net benefit. The OS page cache is more effective — it is managed by the kernel with no GC overhead, operates at the block level, and automatically adjusts to available memory.

If you see `row_cache_size_in_mb > 0` in a cluster, it is almost certainly legacy configuration from outdated advice. Disable it.

## See Also

- [Memtables](memtables.md)
- [JVM](jvm.md)
- [OS Settings](os-settings.md)
