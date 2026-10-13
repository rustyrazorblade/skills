# Reads slow down when compaction runs

Verdict: <span class="verdict verdict-confirmed">Confirmed</span>.  Read latency rises while compaction runs on the same node.

| Finding | Evidence | Severity |
|:--|:--|:--|
| Read latency rises during compaction | [Read latency (ms)](evidence/latency.md#read-latency-ms) | High |
| Scrape allocation differs by build | [Scrape allocation (MB/s)](2-evidence.md#scrape-allocation-mbs) | Low |

## What this means

Schedule compaction away from peak read traffic.

## Caveats

- The session measured one node size only.
