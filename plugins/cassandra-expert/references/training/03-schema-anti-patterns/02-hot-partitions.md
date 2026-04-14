# Topic: Hot Partitions

## Objective
Recognize hot partitions and understand that high-traffic, small data belongs in a cache — not in a single Cassandra partition.

## Why This Matters
A hot partition concentrates all reads and writes for a high-traffic piece of data on a single node. That node becomes a bottleneck regardless of how large your cluster is. Adding more nodes doesn't help — the hot partition stays on the same node. This is one of the few Cassandra problems that can't be fixed by scaling horizontally.

---

## Concept

A hot partition occurs when a disproportionate share of cluster traffic hits a single partition. This happens when:

- The partition key has low cardinality (few distinct values, e.g., `country`, `status`, `type`)
- One partition key value is far more popular than others (celebrity problem, viral content)
- The data model routes a global counter or leaderboard to a single partition

### Why More Nodes Don't Help

Cassandra distributes partitions across nodes by hashing the partition key. A hot partition lives on one node (and its replicas). Adding nodes changes which node owns the hot partition, but one node still owns it exclusively. The bottleneck moves, it doesn't go away.

### The Fix: Cache Frequently Accessed Small Data

If the data is small and read-heavy (e.g., a configuration value, a top leaderboard, a viral post), the right answer is a **cache layer** in front of Cassandra:

- Read from cache (Redis, Memcached, in-process cache)
- On cache miss, read from Cassandra and populate cache
- Writes go to Cassandra and invalidate or update the cache

This shifts the load off Cassandra entirely for the hot read path.

### Other Mitigations

**For write-heavy hot partitions:**
- Add a random shard suffix to the partition key to spread writes across N partitions, then aggregate on read
- This is complex — prefer a different data model if possible

**For low-cardinality partition keys:**
- Redesign the schema. `status` as a partition key (with only 3-5 values) is always wrong
- Add a higher-cardinality component to the partition key (e.g., `(status, user_id)`)
- Use a denormalized table with a more selective partition key

### Identifying Hot Partitions

```bash
# Check for uneven load distribution across nodes
nodetool status
# Look at the "Load" column — significant imbalance suggests hot partitions

# Per-table histogram showing read/write latency outliers
nodetool tablehistograms <keyspace>.<table>
```

---

## Examples

### Anti-pattern: global leaderboard as a single partition
```sql
-- ANTI-PATTERN: one partition for the entire leaderboard
CREATE TABLE leaderboard (
    game_id  text,
    score    int,
    user_id  uuid,
    PRIMARY KEY (game_id, score, user_id)
) WITH CLUSTERING ORDER BY (score DESC);
-- If 'game_id' is the same for all players in a popular game,
-- this is one hot partition handling all leaderboard traffic
```

```sql
-- BETTER: shard the leaderboard, aggregate in the application
CREATE TABLE leaderboard (
    game_id  text,
    shard    int,   -- 0–9, chosen randomly on write
    score    int,
    user_id  uuid,
    PRIMARY KEY ((game_id, shard), score, user_id)
) WITH CLUSTERING ORDER BY (score DESC);
-- Reads query all 10 shards and merge results in the application
-- BEST: cache the top-N leaderboard and refresh periodically
```

### Anti-pattern: config value read millions of times per second
```sql
-- This is one row, one partition, millions of reads/sec → hot partition
SELECT value FROM config WHERE key = 'feature_flags';
```

```python
# CORRECT: cache it
import functools

@functools.lru_cache(maxsize=1)  # simple in-process cache
def get_feature_flags():
    row = session.execute(get_flags_stmt).one()
    return row.value

# Or use Redis with a short TTL for multi-process environments
```

---

## Pulse Check

> A social media platform stores posts with `PRIMARY KEY (post_id)`. A viral post gets 500,000 reads per second. Adding more Cassandra nodes doesn't reduce the latency on that post.
>
> **Why doesn't scaling the cluster help, and what's the correct fix?**

*(Expected answer: The viral post is one partition — it lives on one node regardless of cluster size. Horizontal scaling distributes different partitions across more nodes but doesn't split a single partition. The fix is a cache layer: serve the viral post from Redis or a CDN, read from Cassandra only on cache miss. Cassandra is the source of truth, not the read path for hot data.)*

---

## See Also

**In this session:**
- [Huge Partitions](./01-huge-partitions.md)
- [Materialized Views](./05-materialized-views.md)

**Reference:**
- [Token Skew and Distribution](../../general/token-skew.md)
- [Node Density](../../general/node-density.md)
- [Row Cache](../../general/row-cache.md)
- [Thread Pools](../../general/thread-pools.md)
