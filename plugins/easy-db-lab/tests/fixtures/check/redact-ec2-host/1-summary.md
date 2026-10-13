# Scrape allocation rises with the canary

Verdict: <span class="verdict verdict-refuted">Refuted</span>.  The canary allocates more on the scrape path, although its reads are faster.

| Metric | Baseline | Candidate | Delta | Noise floor | Verdict |
|:--|--:|--:|--:|--:|:--|
| [Scrape allocation mean (MB/s)](2-evidence.md#scrape-allocation-mbs) | 27.1 | 32.72 | +20.8% | not measured | <span class="verdict verdict-refuted">Refuted</span> |
| [Read latency p99 (ms)](evidence/latency.md#read-latency-ms) | 14.4 | 10.6 | -26.4% | [0.7%](evidence/latency.md#noise-floor-read-latency-ms) | <span class="verdict verdict-confirmed">Confirmed</span> |

## What this means

The canary does not cut scrape allocation.  It raises it on every node, so the change has a cost.  Reads are faster on the canary.

## Caveats

- The baseline ran on ip-10-0-1-15.  The scrape allocation row has no noise floor measurement.
