# Virtual Nodes (vnodes) in Cassandra

## Recommendation

**Use 1 token when possible, never more than 4.**

There are only two valid settings for `num_tokens`:

```yaml
num_tokens: 1
```

This is the simplest view of the ring with the fewest neighbors. Best for availability, but rings can be imbalanced if the ring isn't doubled or tokens aren't manually adjusted.

```yaml
num_tokens: 4
```

4 tokens uses more neighbors during streaming but is better balanced as the ring grows. You can expand by roughly 25% and see a balanced increase, which is the sweet spot for adding capacity.

**Everything else is a ticking time bomb.**

## Why Higher vnode Counts Are Dangerous

### The Neighbor Problem

You can calculate the maximum number of neighbors a node will have with the following math:

```
Neighbors = (RF - 1) * 2 * num_tokens
```

For example, with 30 nodes, RF=3, and 4 tokens, each node will have a maximum of:

```
Neighbors = (3 - 1) * 2 * 4 = 16
```

If you're using 3 racks/availability zones, that means each node in each rack will have 16 neighbors - almost every other node in the cluster.

### Availability Impact

At higher vnode counts, clusters are more likely to have availability issues as cluster size increases:

- More neighbors = more nodes involved in each operation
- A single slow or failing node affects more of the cluster
- Recovery and streaming operations involve more nodes
- It's a difficult situation to escape once you're in trouble

### The Historical Default Problem

The historical default of `num_tokens: 256` was chosen for automatic ring balancing but creates severe operational problems:

- With RF=3 and 256 tokens: up to 1024 neighbors per node
- Makes scaling extremely difficult
- Streaming during bootstrap/decommission touches nearly every node
- Cannot be changed on existing clusters without full rebuild

## Impact on Operations

### More tokens means:

- **More data movement during scaling** - bootstrap and decommission operations touch more nodes
- **More overhead in token calculations** - every read/write requires more token math
- **Worse Zero-Copy Streaming eligibility** - SSTables are less likely to have complete token ranges owned by a single destination node

### With bounded SSTable sizes (UCS/LCS):

Low vnode counts combined with bounded SSTable sizes from UCS (version 5.0+) or LCS maximize Zero-Copy Streaming eligibility, enabling:

- 5x faster streaming
- Faster cluster expansion
- More reliable operations

## Changing num_tokens

**num_tokens cannot be safely changed on existing datacenters.**

Options for clusters stuck with high vnode counts:

1. Create a new DC with the new token count.  Rebuild, switch, decommission old DC.
2. Build a new cluster with proper settings and migrate.  [ZDM Proxy](https://github.com/datastax/zdm-proxy) can help with this.

This is why getting it right from the start is critical.  Both operations require copying a lot of data, and the negative impacts of both moving data and high vnode counts have a bigger impact on bigger clusters.  Migrating data is an O(n) process relative to data.

## Summary

| num_tokens | Use Case | Risk Level |
|------------|----------|------------|
| 1 | Best availability, manual balancing | Low |
| 4 | Good balance, automatic distribution | Low |
| 16 | Legacy clusters only | High, increasing with cluster size |
| 256 | Never use | Critical |

## Token Skew with vnodes

With `num_tokens: 4` and 3 racks, the token allocator produces a per-rack ownership skew of ~1.25x. This is real but not critical. See `token-skew.md` for detailed analysis of how the allocator places tokens and why full-ring metrics are misleading.
