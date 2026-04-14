# Gossip

Gossip is Cassandra's peer-to-peer protocol for sharing cluster state — node liveness, schema versions, token ownership. Gossip pauses are a serious cluster health issue.

**Note:** Cassandra 6.0 introduces Transactional Cluster Metadata (TCM), which moves most cluster coordination away from gossip. Gossip pauses become less impactful on 6.0+.

## Gossip Pauses

A gossip pause means the gossip thread was blocked long enough that the node couldn't participate in cluster state exchange. This can cause nodes to be incorrectly marked down, delayed failure detection, and blocked schema propagation.

```bash
# Check for gossip warnings
grep "Gossip stage" /var/log/cassandra/system.log
# "Gossip stage has N pending tasks"
# "Not marking nodes down due to local pause"
```

### Causes

1. **GC pauses** — long GC stops the world, blocking gossip. Most common cause.
2. **CPU saturation** — no cycles available for gossip thread
3. **Disk I/O starvation** — blocking operations on the gossip thread path
4. **Network issues** — packet loss or high inter-node latency

### Resolution

- Fix GC first — keep pauses under 100ms (see `jvm.md`)
- Check CPU and I/O with `top` and `iostat -x 1`
- Verify network connectivity between nodes
- If the node is overloaded, add capacity

## Gossip Info

```bash
# View gossip state for all nodes
nodetool gossipinfo

# Check for:
# - STATUS: NORMAL (healthy) vs LEAVING/JOINING/etc
# - SCHEMA: should match across all nodes
# - LOAD: data size per node
```

## See Also

- `jvm.md` — GC tuning to prevent gossip pauses
- `cluster-configuration.md` — schema agreement issues
