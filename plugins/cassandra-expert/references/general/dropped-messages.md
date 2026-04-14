# Dropped Messages

Dropped messages mean the cluster cannot process requests fast enough. Any non-zero dropped `MUTATION` count is a data consistency emergency.

## How to Check

```bash
nodetool tpstats
# Look for non-zero values in the "Dropped" column
```

## Message Types

| Type | Severity | Meaning |
|------|----------|---------|
| `MUTATION` | **Critical** | Writes dropped — data loss risk |
| `READ` | **Critical** | Reads timing out — clients seeing errors |
| `REQUEST_RESPONSE` | **Critical** | Cross-node communication failing |
| `READ_REPAIR` | Less critical | Read repair delayed, will retry |
| `HINT` | Less critical | Hint delivery delayed, will retry |

Alert on any dropped `MUTATION`, `READ`, or `REQUEST_RESPONSE`. Dropped `MUTATION` in particular requires immediate investigation — those writes are gone.

## Common Causes

1. **Cluster overload** — request rate exceeds capacity
2. **Thread pool saturation** — pending tasks backing up, no free threads
3. **GC pauses** — long GC stops the world, requests expire in queue
4. **Disk saturation** — I/O bottleneck slowing reads or flushes
5. **Slow or expensive queries** — blocking threads that other requests need
6. **Network issues** — packet loss or high inter-node latency

## Investigation

```bash
# Thread pool saturation
nodetool tpstats
# Look for: Active at maximum, Pending > 0, Blocked > 0

# GC pauses
grep "GC" /var/log/cassandra/gc.log
# Pauses > 100ms are concerning; > 500ms will cause drops

# Slow queries
grep "operations were slow" /var/log/cassandra/system.log

# Disk I/O
iostat -x 1 5

# Network drops
netstat -s | grep -i drop
```

## Resolution

**Short-term (stabilize):**
- Throttle application traffic to reduce load
- Identify and kill expensive queries
- Increase timeouts as a temporary measure only — this buys time, it does not fix the problem

**Root cause fixes:**
- Thread pool saturation → see `thread-pools.md`
- GC pauses → review heap sizing and GC settings in JVM options
- Disk saturation → check compaction throughput, consider adding nodes
- Expensive queries → fix data model or add appropriate indexes
- Sustained overload → add capacity

## Monitoring

Alert on:
- Any dropped `MUTATION` (zero tolerance)
- Any dropped `READ` or `REQUEST_RESPONSE` sustained over time
- Thread pool pending tasks > 0 for more than a few seconds

## See Also

- `thread-pools.md` — thread pool sizing and pending task analysis
- `compaction.md` — compaction competing for disk I/O
