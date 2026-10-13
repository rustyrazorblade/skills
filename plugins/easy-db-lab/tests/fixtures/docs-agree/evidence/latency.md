# Latency

## Read latency (ms)

![Read latency (ms)](../images/read-latency.png)

| Node | Arm | Samples | Min | p50 | Mean | p99 | Max | Unit |
|:--|:--|--:|--:|--:|--:|--:|--:|:--|
| db0 | baseline | 21 | 12.00 | 13.00 | 12.95 | 14.00 | 14.00 | ms |
| db1 | baseline | 21 | 12.40 | 13.40 | 13.40 | 14.40 | 14.40 | ms |
| all | baseline | 42 | 12.00 | 13.07 | 13.17 | 14.40 | 14.40 | ms |
| db0 | candidate | 21 | 8.80 | 9.55 | 9.51 | 10.30 | 10.30 | ms |
| db1 | candidate | 21 | 9.10 | 9.85 | 9.88 | 10.60 | 10.60 | ms |
| all | candidate | 42 | 8.80 | 9.60 | 9.69 | 10.60 | 10.60 | ms |

Window (baseline): 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s

Window (candidate): 2026-10-01T11:30:00Z to 2026-10-01T11:40:00Z (10m 0s), step 30s

Query: `histogram_quantile(0.99, sum by (instance, le) (rate(cassandra_read_latency_seconds_bucket{instance=~"db.*"}[1m])))`

Data: [latency-baseline.csv](../data/latency-baseline.csv), [latency-candidate.csv](../data/latency-candidate.csv)

## Noise floor: read latency (ms)

![Noise floor: read latency (ms)](../images/noise-latency.png)

| Node | Arm | Samples | Min | p50 | Mean | p99 | Max | Unit |
|:--|:--|--:|--:|--:|--:|--:|--:|:--|
| all | baseline | 42 | 12.00 | 13.07 | 13.17 | 14.40 | 14.40 | ms |
| all | candidate | 42 | 12.20 | 13.20 | 13.25 | 14.30 | 14.30 | ms |

Window: 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s

Query: `histogram_quantile(0.99, sum by (instance, le) (rate(cassandra_read_latency_seconds_bucket{instance=~"db.*"}[1m])))`

Data: [noise-latency.csv](../data/noise-latency.csv)
