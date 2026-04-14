# Hinted Handoff

## Overview

Hinted handoff is Cassandra's mechanism for maintaining eventual consistency when a replica node is temporarily unavailable. When a coordinator cannot write to a replica, it stores the write as a "hint" locally and replays it to the replica when it comes back online.

Hinted handoff is **not a replacement for repair** — it only covers the window during which a node is down. For long outages or data that predates the hint window, repair is required.

## How It Works

1. Coordinator attempts to write to all replicas
2. If a replica is unavailable, coordinator stores the write as a hint
3. When the replica comes back online, the coordinator replays the hint
4. If the replica is down longer than `max_hint_window` (default 3 hours), hints are discarded

## Configuration

```yaml
# cassandra.yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000  # 3 hours — increase for clusters with longer maintenance windows
max_hints_delivery_threads: 2
hints_flush_period_in_ms: 10000
```

## Aborted Hints

Aborted hints indicate that hints could not be delivered within the hint window. This is a signal that something is wrong — either a node was down too long, or there is a persistent network or health issue.

### Common Causes

- Node down longer than `max_hint_window` (default 3 hours)
- Network instability between nodes
- Target node consistently slow or overloaded
- Excessive hint accumulation overwhelming the coordinator
- Disk space issues on the coordinator node

### Investigation

```bash
# Check for down nodes
nodetool status

# Check hint metrics
nodetool sjk mxdump -b org.apache.cassandra.metrics:type=Storage,name=TotalHints

# Check logs for hint-related errors
grep -i "hint" /var/log/cassandra/system.log

# Check network connectivity
nodetool gossipinfo
```

### Resolution

1. Identify which nodes are generating and receiving aborted hints
2. Check node health: CPU, memory, disk I/O, network latency
3. Resolve the underlying node or network issue
4. Run repair to fill in any consistency gaps caused by discarded hints:

```bash
nodetool repair -pr --full
```

## Monitoring

Track these metrics to catch hint problems early:

- **Total hints per node** — accumulation indicates a node is frequently unavailable
- **Aborted hint count** — should be zero; any value is a signal to investigate
- **Hint replay latency** — slow replay indicates a stressed receiving node

## Best Practices

- Alert on any aborted hints — they should not occur in a healthy cluster
- If a node will be down longer than 3 hours, consider increasing `max_hint_window_in_ms` or running repair on the node when it returns
- Run incremental repair regularly — hints cover short outages, repair covers everything else
- Monitor disk space on coordinator nodes — hint accumulation consumes local disk

## See Also

- [Repair](repair.md)
- [Consistency Levels](consistency-levels.md)
- [Dropped Messages](dropped-messages.md)
- [Gossip](gossip.md)
