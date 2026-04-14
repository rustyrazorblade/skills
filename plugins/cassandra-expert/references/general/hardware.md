# Hardware

## Recommended Specifications

| Size | CPU | RAM | Storage | Network |
|------|-----|-----|---------|---------|
| Small | 8–16 cores | 32–64GB | SSD/NVMe | 10Gbps |
| Medium | 16 cores | 64GB | NVMe | 10Gbps |
| Large | 16–32 cores | 64–128GB | NVMe | 25Gbps |

**AWS i3 instances** are a common choice:
- `i3.2xlarge` — 8 vCPU, 61GB RAM, local NVMe
- `i3.4xlarge` — 16 vCPU, 122GB RAM, local NVMe
- `i3.8xlarge` — 32 vCPU, 244GB RAM, local NVMe

## CPU

**Minimum: 8 cores.** Cassandra's thread pool architecture requires concurrency — fewer than 8 cores causes resource contention across reads, writes, compaction, and flushes simultaneously.

**Maximum: 32 cores** for Apache Cassandra. Returns diminish significantly beyond 32 cores. If you're on larger instances, consider splitting into more nodes — better fault tolerance, better token distribution, cheaper per node.

## Memory

**Minimum: 32GB. Recommended: 64GB+.**

Memory allocation guidance:
- 32GB node: 8GB heap, remainder for OS page cache and off-heap
- 64GB node: 16GB heap, remainder for OS page cache and off-heap
- 128GB+ node: Consider Shenandoah GC with larger heap sizing

OS page cache is critical for read performance — don't size heap so large that it starves the page cache.

## Storage

Always use **local SSD or NVMe**. Spinning disks are not suitable for production Cassandra.

For cloud deployments on EBS or other network-attached storage:
- **Cassandra 5.0+**: CASSANDRA-15452 provides 2–3x compaction throughput improvement and 3x IOPS reduction — denser nodes are viable
- **Pre-5.0 on EBS**: Lower density per node; you'll hit IOPS limits earlier

Never mix storage types within a datacenter — nodes with spinning disks will become bottlenecks.

## Hardware Consistency

**All nodes within a datacenter must be identical or very close in spec.**

Mixed hardware causes:
- Uneven performance — slower nodes become hotspots
- Broken load balancing assumptions
- Unpredictable capacity planning
- Much harder troubleshooting

This applies to cloud deployments too — use a single instance type per datacenter. Different datacenters can use different types (e.g., NVMe for transactional, high-memory for analytics).

## Scaling

Scale **horizontally** (more nodes) rather than vertically (bigger nodes). More nodes means:
- Better fault tolerance
- Better token distribution
- More options for rack/AZ placement
- Easier capacity planning

When replacing undersized nodes, the cleanest approach is to add a new datacenter with the correct spec, migrate traffic, then decommission the old one.

## See Also

- `node-density.md` — how much data per node by version
- `os-settings.md` — OS-level configuration for each node
- `compaction.md` — CASSANDRA-15452 throughput improvements on cloud storage
