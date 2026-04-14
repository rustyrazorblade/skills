# Streaming in Cassandra

## Overview

Streaming is Cassandra's process of transferring data between nodes. It occurs during:
- Adding nodes (bootstrap)
- Removing nodes (decommission)
- Replacing failed nodes (`replace_address_first_boot`)
- Repair operations

Streaming performance directly impacts how fast clusters can scale, recovery time during failures, and operational costs.

## Streaming Methods

### Zero Copy Streaming (ZCS)

The fastest streaming method, available in Cassandra 4.0+. Uses Linux `sendfile()` to stream entire SSTables directly from filesystem to network without JVM heap involvement.

```yaml
stream_entire_sstables: true  # Default in 4.0+
```

**Requirements for ZCS:**
- Entire SSTable must be owned by destination node
- Cannot be used with internode encryption
- SSTable token range must fall entirely within destination's token range

**Performance:** Limited only by disk and network throughput.

### Encrypted Entire SSTable Streaming

When encryption is required, complete SSTables are still sent but must pass through JVM for encryption.

```yaml
# Throttle encrypted streaming (default: 24 MiB/s)
entire_sstable_stream_throughput_outbound: 24MiB/s
entire_sstable_inter_dc_stream_throughput_outbound: 24MiB/s
```

### Slow Fallback Path

Used when neither fast path is available:
- Reads 64KB chunks into buffer
- Sends over network, blocks on every write.

**Performance:** Observed at ~12MB/s in production — significantly slower than fast paths.

## Diagnosing Streaming Issues

### Symptoms of Slow Path Streaming

- Bootstrap/decommission taking hours instead of minutes
- Throughput ~12MB/s instead of disk/network speeds
- New node tokens landing in middle of existing SSTable token ranges

### Verification Commands

```bash
# Check token ranges in SSTables
tools/bin/sstablemetadata path/to/some-Data.db
# Look for: First token / Last token spans

# View node tokens
nodetool ring

# Monitor streaming progress
nodetool netstats
```

### Root Causes

| Cause | Impact | Solution |
|-------|--------|----------|
| `num_tokens` > 4 | Tokens likely split existing SSTables | Use 1 or 4 vnodes (requires new DC) |
| STCS/TWCS | Large SSTables with wide token ranges | Use UCS (5.0+) or LCS |
| `stream_entire_sstables: false` | Forces slow path | Set to true |
| Internode encryption | Cannot use sendfile() | Tune throttling, accept slower speed |




## Impact on Operations

### Node Replacement Vulnerability Window

During node replacement via `replace_address_first_boot`:
- Data isn't fully replicated until streaming completes
- `LOCAL_QUORUM` with `RF=3`: another failure causes unavailability
- Incremental repair unavailable on affected ranges
- Hints accumulate on remaining nodes

### Scaling Operations

Fast streaming enables:
- Quick scaling for dynamic workloads
- Less lead time for capacity additions
- Faster decommissioning when scaling down
- Reduced operational risk windows

## Configuration Checklist

1. **vnodes**: Use 1 or 4 only (see `vnodes.md`)
2. **Compaction**: Use UCS (5.0+) or LCS for bounded SSTable sizes
3. **stream_entire_sstables**: Ensure set to `true`
4. **Encryption throttling**: Tune if using internode encryption

## Compaction Strategy Impact

| Strategy | SSTable Behavior | ZCS Eligibility |
|----------|------------------|-----------------|
| UCS | Bounded ~1GB SSTables | High |
| LCS | Bounded ~160MB SSTables | High |
| STCS | Unbounded, can grow to 100s of GB | Low |
| TWCS | One large SSTable per window | Low |

## Throughput and Timeout Settings

```yaml
# cassandra.yaml (Cassandra 5.0)
stream_throughput_outbound: 24MiB/s              # default — good for most clusters
inter_dc_stream_throughput_outbound: 24MiB/s     # default — cross-DC throttle
streaming_keep_alive_period: 300s                # default — leave alone
```

Note: in Cassandra 5.0 the setting was renamed from `stream_throughput_outbound_megabits_per_sec` to `stream_throughput_outbound`, and the unit changed from Mbps to MiB/s. The default of `24MiB/s` is equivalent to the historical 200 Mbps.

**Throughput:** Keep the default `24MiB/s`. Increasing it can overwhelm target nodes and cause repair or bootstrap failures. If streaming is slow, the root cause is usually the slow fallback path (see above), not insufficient throughput.

**Keep-alive period:** Keep the default `300s` (5 minutes). Stalled streams are detected within 10 minutes. Setting this to `0` disables stall detection — don't.

## Summary

For optimal streaming performance:
- Use 1-4 vnodes
- Use UCS (5.0+) or LCS for compaction
- Monitor streaming with `nodetool netstats`
- Plan for vulnerability windows during replacements
- Test streaming performance before production scaling

## See Also

- [Virtual Nodes (vnodes)](./vnodes.md) — vnode count directly drives streaming parallelism
- [Compaction](./compaction.md) — compaction strategy determines ZCS eligibility
- [Repair](./repair.md) — repair streams data during reconciliation
- [How Cassandra Streaming, Performance, Node Density, and Cost Are All Related](https://rustyrazorblade.com/post/2025/03-streaming/)