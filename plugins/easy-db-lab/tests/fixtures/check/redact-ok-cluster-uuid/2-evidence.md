# Evidence

## Scrape allocation (MB/s)

![Scrape allocation (MB/s)](images/scrape-alloc.png)

| Node | Arm | Samples | Min | p50 | Mean | p99 | Max | Unit |
|:--|:--|--:|--:|--:|--:|--:|--:|:--|
| db0 (baseline) | baseline | 21 | 26.92 | 26.92 | 26.92 | 26.92 | 26.92 | MB/s |
| db1 (baseline) | baseline | 21 | 27.27 | 27.27 | 27.27 | 27.27 | 27.27 | MB/s |
| all | baseline | 42 | 26.92 | 27.09 | 27.09 | 27.27 | 27.27 | MB/s |
| db2 (candidate) | candidate | 21 | 32.72 | 32.72 | 32.72 | 32.72 | 32.72 | MB/s |
| all | candidate | 21 | 32.72 | 32.72 | 32.72 | 32.72 | 32.72 | MB/s |

Window: 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s

Query: `sum by (instance) (rate(jvm_gc_memory_allocated_bytes_total{instance=~"db.*"}[1m]))`

Data: [scrape-alloc.csv](data/scrape-alloc.csv)

## Threats to validity

- The run used the cluster label `report-ab-896195de-19a1-43fe-b315-751612345678`.  Each arm ran for ten minutes, so slow drift is not visible.
