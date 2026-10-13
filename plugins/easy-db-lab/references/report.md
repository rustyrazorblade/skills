# report.md: The Lab Report

The lab report is the record of a run for three readers: a customer, a JIRA reviewer (a Cassandra committer), and the owner later on.  This reference holds every rule for the report: the tiers, the summary layout, the evidence blocks, the prose and redaction rules, the exit rule, the check, the graph steps, and the arms rules.  The run skill and the explore skill both load it.  The upload procedure and the teardown gate are in `report-upload.md`.

`setup-cluster.sh` writes the scaffold in `<cluster-dir>/docs/`.  The scripts are in this plugin's `bin/`: `report-graph.py`, `report-check.py`, and `report-export.py`.  Each one is a uv script, so `uv` must be on `PATH`.

## File Roles

Other references name the plan, the journal, and the issues file by role.  The role resolves to a file name per layout.

| Role | Single layout and multi-DC | Arm agent (`--arm <arm>`) | Arms coordinator |
|:--|:--|:--|:--|
| `<plan>` | `3-plan.md` | `3-plan-<arm>.md` | `3-plan.md` |
| `<journal>` | `4-journal.md` | `4-journal-<arm>.md` | `4-journal.md` |
| `<issues>` | `5-issues.md` | `5-issues-<arm>.md` | `5-issues.md` |

All paths are under `<cluster-dir>/docs/`.  For an arms test, `<cluster-dir>` is the test directory.

## The Tiers

The report has five tier files.  The number prefix sets the order in the Grafana Tests index, which sorts by name.

| File | Tier | Holds |
|:--|:--|:--|
| `1-summary.md` | Summary | The verdict, the result table, and what the result means.  The landing page of the book. |
| `2-evidence.md` | Evidence | One evidence block per measured claim, then `## Threats to validity`. |
| `3-plan.md` | Appendix | The plan as executed. |
| `4-journal.md` | Appendix | Every command and every finding, in order. |
| `5-issues.md` | Appendix | Every issue, including tool friction. |

The summary and the evidence are the customer tiers.  The plan, the journal, and the issues file are the appendix.  `SUMMARY.md` puts the appendix under `# Appendix`, so the book shows it last.

To add an evidence page, write it under `evidence/`, for example `evidence/latency.md`.  Then nest it under Evidence in `SUMMARY.md`:

```markdown
- [Evidence](2-evidence.md)
  - [Latency](evidence/latency.md)
```

A nested page is in the book and in `export/report.zip`.  It is not in the upload, because the upload names only top-level files.

## The Summary Layout

`1-summary.md` holds these parts, in this order.  Do not add other parts.

1. **Title.**  An H1 that states the result in plain words, for example `# Scrape allocation drops with the fix`.  `make` uses it as the book title.  Never leave the template placeholder; the check fails it.
2. **Verdict line.**  `Verdict: ` plus one verdict badge, then one sentence.
3. **Table.**  The comparison table for an A/B run.  The Findings table for any other run, for every explore session, and for a Partial summary with no measured evidence.
4. **Reasoning review line.**  For a Cassandra run only: `Reasoning review: done`, or `Reasoning review: not run (cassandra-expert not installed)`.  See "The Check" below.
5. **`## What this means`.**  Two to four sentences for a customer.  State no number here.
6. **`## Caveats`.**  The limits of the result, as a list.  The check writes its Unchecked line here.

### Verdicts

A verdict has one of four values:

| Value | Use it when |
|:--|:--|
| Confirmed | The evidence supports the hypothesis. |
| Refuted | The evidence contradicts the hypothesis. |
| Inconclusive | The evidence does not decide the hypothesis. |
| Partial: stopped after step N | The summary was written before every plan step finished.  N is the last finished step. |

Write each verdict as a badge, on the Verdict line and in each table cell:

```markdown
Verdict: <span class="verdict verdict-confirmed">Confirmed</span>.  The fix cuts scrape allocation on every node.
```

The class is `verdict-` plus the first word of the value in lower case: `verdict-confirmed`, `verdict-refuted`, `verdict-inconclusive`, or `verdict-partial`.  The check fails a badge whose class and text do not agree.

### The comparison table (A/B runs)

```markdown
| Metric | Baseline | Candidate | Delta | Noise floor | Verdict |
|:--|--:|--:|--:|--:|:--|
| [Scrape allocation mean (MB/s)](2-evidence.md#scrape-allocation-mbs) | 27.1 | 21.3 | -21.4% | not measured | <span class="verdict verdict-confirmed">Confirmed</span> |
```

The row contract:

- **Metric** links to the evidence block of the measurement.  The link text names the statistic and ends with the unit in parentheses: `Scrape allocation mean (MB/s)`.  The statistic is one of samples, min, p50, mean, p95, p99, max, total, or rate.  The unit must equal the unit in the block's `data/*.json`.
- **Baseline** and **Candidate** are the arm rollup values for that statistic, from the block's stats table.  The arms in the data must be named `baseline` and `candidate`.
- **Delta** is `(candidate - baseline) / baseline`, in percent, with its sign: `+20.8%` or `-17.2%`.
- **Noise floor** follows the Noise Floor rule below.
- **Verdict** is a badge.

The anchor after `#` is the heading id that mdbook makes: lower case, punctuation removed, and spaces changed to hyphens.  `## Scrape allocation (MB/s)` becomes `#scrape-allocation-mbs`.  A link into a nested page names the page: `evidence/latency.md#read-latency-ms`.

### The Findings table (other runs and explore)

```markdown
| Finding | Evidence | Severity |
|:--|:--|:--|
| Read latency rises during compaction | [Read latency (ms)](evidence/latency.md#read-latency-ms) | High |
```

Each Evidence cell links to at least one evidence block.  A table with no findings yet holds the header and the separator row, and no other row.

### Noise Floor

This change does not change how or when a run measures noise.  It reports only a noise floor that the run already measured.

- When the run measured noise, the cell holds the value as a link to the evidence block it came from: `[0.7%](evidence/latency.md#noise-floor-read-latency-ms)`.  That block is an A/A measurement: both arms run the same build, and the arms are still named `baseline` and `candidate`.  The noise floor is |delta| between the two arms for the same statistic as the row.  The check recomputes it from the block's CSV.
- When the run did not measure noise, the cell reads `not measured`.  The check accepts it.
- An empty cell, or a value with no link, fails the check.
- A Confirmed or Refuted row needs |delta| above the noise floor.  This rule applies only when the cell holds a value.

## Evidence Blocks

Each claim in the summary traces to one evidence block.  A block holds, in this order:

1. A heading, for example `## Scrape allocation (MB/s)`.
2. The image, downloaded to `images/`.
3. The stats table.
4. The Window: UTC start and end, the duration, and the step.
5. The Query, as inline code.
6. A Data link to one or more CSVs in `data/`.

`report-graph.py plot` prints the full block.  Paste it into the evidence tier without edits:

```markdown
## Scrape allocation (MB/s)

![Scrape allocation (MB/s)](images/scrape-alloc.png)

| Node | Arm | Samples | Min | p50 | Mean | p99 | Max | Unit |
|:--|:--|--:|--:|--:|--:|--:|--:|:--|
| db0 (baseline) | baseline | 21 | 26.92 | 26.92 | 26.92 | 26.92 | 26.92 | MB/s |
| all | baseline | 21 | 26.92 | 26.92 | 26.92 | 26.92 | 26.92 | MB/s |
| db2 (candidate) | candidate | 21 | 21.30 | 21.30 | 21.30 | 21.30 | 21.30 | MB/s |
| all | candidate | 21 | 21.30 | 21.30 | 21.30 | 21.30 | 21.30 | MB/s |

Window: 2026-10-01T10:00:00Z to 2026-10-01T10:10:00Z (10m 0s), step 30s

Query: `sum by (instance) (rate(jvm_gc_memory_allocated_bytes_total{cluster="lab-ab-1c9bbb2f-aab1-4478-ac8d-35cb6ca31790",instance=~"db.*"}[1m]))`

Data: [scrape-alloc.csv](data/scrape-alloc.csv)
```

The stats table has one row per node and one rollup row per arm (Node = all).  A rollup pools the samples of the arm's nodes.  The default columns are Node, Arm, Samples, Min, p50, Mean, p99, and Max, then Unit.  Every numeric column is right-aligned (`--:`).

When a metric needs other statistics, swap them with `--stats`.  For a counter, use `--stats samples,total,rate`: total is the last value minus the first, and rate is the total divided by the window in seconds.

Rules:

- Download every graph.  Never link to a Grafana graph from the summary or the evidence tier.
- A Grafana render image is optional.  If you keep one, put it in `<journal>`, in the appendix only.  Download it to `images/`; never link it.
- For a block in a nested page, pass `--page evidence/<page>.md` to `plot`, so its links are relative to that page.

### Threats to validity

`2-evidence.md` ends with `## Threats to validity`.  Put every issue that affects the result there, for example a noisy neighbour, a short window, or a node that restarted.  The same issue also goes in `<issues>`.  Tool friction never goes here; it goes in `<issues>` only.

## Graphs

After each plan step that measures something, fetch the data and plot it, before the next step starts.  Then append the evidence block to the evidence tier.

### Fetch

1. Read `$EDB help observability` for the Mimir query endpoint and the tenant header.  Read `$EDB status` for the address that the endpoint uses.  Never read `state.json`.
2. In a multi-DC or arms layout, do this for each wrapper: each DC and each arm has its own Mimir URL.  Do not assume a tenant per DC or per arm; several clusters can share one tenant, such as `default`.
3. Find this cluster's `cluster` label value.  It is the cluster name and the cluster ID from `$EDB status`, for example `lab-ab-1c9bbb2f-aab1-4478-ac8d-35cb6ca31790`.  Confirm it in the list from `api/v1/label/cluster/values`.  Write it in `<journal>`.
4. Filter every fetch query on `cluster="<value>"`.  A tenant holds the series of many clusters, so a query with no `cluster` filter can return another cluster's data.  `fetch` refuses a query with no `cluster` matcher.
5. Select nodes by host name, for example `instance=~"db.*"`.  Never select by IP.  If the node label holds an IP, map each value to a host name with `--node <value>=db0`.  `fetch` refuses an IPv4-looking node value with no mapping.
6. Run `fetch`:

```bash
report-graph.py fetch --mimir-url "$MIMIR_URL" --tenant "$TENANT" \
  --query 'sum by (instance) (rate(jvm_gc_memory_allocated_bytes_total{cluster="lab-ab-1c9bbb2f-aab1-4478-ac8d-35cb6ca31790",instance=~"db.*"}[1m]))' \
  --start 2026-10-01T10:00:00Z --end 2026-10-01T10:10:00Z --step 30s \
  --node-label instance --arm baseline=db0,db1 --arm candidate=db2 \
  --unit "MB/s" --scale 1e-6 --name scrape-alloc --docs <cluster-dir>/docs
```

If Mimir is reachable only through a SOCKS proxy, add `--proxy socks5h://<host>:<port>`.  `fetch` writes `data/<name>.csv` and `data/<name>.json`.  It never stores the URL or the tenant.

If `fetch` fails, write the command and the error to `<journal>` and `<issues>`, and continue the run.  The missing evidence then fails the check at the next exit.

### Plot

```bash
report-graph.py plot --csv <cluster-dir>/docs/data/scrape-alloc.csv \
  --title "Scrape allocation (MB/s)" --docs <cluster-dir>/docs
```

`plot` reads CSVs only from `docs/data/`.  It writes `images/<name>.png` with `lab.mplstyle` and prints the evidence block.  The baseline arm is grey and the candidate arm is blue; nodes in one arm differ by line style.  CSVs with a different unit or step are an error.  CSVs whose queries differ are an error, unless they differ only in the `cluster` matcher.  Then the block has one Query line per arm, for example `Query (baseline): ...`.  CSVs with different windows are an error, except with `--align elapsed` (see "Arms" below).

## Prose Rules

Write report prose in ASD-STE100 Simplified Technical English:

- Use short sentences, in the active voice.
- Do not hard-wrap lines.
- State each number once, in its evidence block.  The summary table is the only repeat.  The check warns on a numeral in summary prose.
- Name nodes by role, for example "db2 (fix)" or "db0 (baseline)".
- Keep tool friction out of the summary and the evidence tier.  It goes in `<issues>` only.

## Redaction

These identifiers never appear in the summary, the evidence tier, or their CSV and JSON files:

- account IDs (12 digits);
- VPC, subnet, and security group IDs (`vpc-`, `subnet-`, `sg-`);
- IP addresses, and EC2 host names that hold one (`ip-10-0-1-15`, `ip-10-0-1-15.ec2.internal`);
- tunnel details (SOCKS, Tailscale, SSH port forwards).

They stay in `<journal>`, in the appendix.  Select nodes by host name, never by IP.  Branch names and details of unreleased bugs are the owner's call for each report; ask the owner before you put them in a customer tier.  `report-check.py` exits 3 on a redaction failure.

## The Exit Rule

Write `1-summary.md` at every exit:

- at Completion;
- before every gated teardown;
- on pause.

A partial exit is any exit before every plan step has finished: a pause, or a teardown gate before the plan ends.  A partial summary has the verdict `Partial: stopped after step N` and one sentence.  A partial summary with no measured evidence holds the Findings table, because there is no comparison to state.  With no findings yet, the table has a header and no rows.  The check runs in full at every exit; there are no relaxed rules for a Partial summary.  An explore session is never Partial: at teardown it writes a verdict and a Findings table.

## The Check

Run the check after you write the summary, and before `make`.  It has three parts.

1. **The script.**  `report-check.py <cluster-dir>/docs`.  `make check` runs the same command.  It prints PASS, FAIL, or WARN per check.  Exit 0 means no FAIL, 1 a FAIL, 2 a usage or I/O error, and 3 a redaction FAIL.  Malformed evidence data, such as a CSV value that is not a number, is a FAIL that names the data file.  It treats a run as a Cassandra run when `<plan>` or a journal names `cassandra use` or `cassandra start`.
2. **The check subagent.**  Run a general-purpose subagent with the prompt below.
3. **The reasoning review.**  For a Cassandra run only.  Ask `cassandra-expert` to review the reasoning: confounds, the choice of metric, and whether the noise floor supports the verdict.  When it has run, write `Reasoning review: done`.  `cassandra-expert` ships as a separate plugin.  When it is not installed, write `Reasoning review: not run (cassandra-expert not installed)`, and tell the user or the launcher plainly.

Each concern from the subagent or the review is a reason.  Fix it, or pass it to the gate as `--reason`.

### The check subagent prompt

```
You review the lab report in <cluster-dir>/docs.  Read 1-summary.md, 2-evidence.md, every evidence page listed in SUMMARY.md before "# Appendix", and <issues>.  Check:
1. The Verdict line and each row verdict agree with the numbers in the tables.
2. The prose says the same as the tables; no sentence states the opposite of a row.
3. "What this means" is two to four sentences for a customer, with no number.
4. No tool friction from <issues> appears in the summary or the evidence tier.
5. Every issue in <issues> that affects the result is under "Threats to validity".
6. Nodes are named by role, for example "db2 (fix)".
7. The prose is short, active STE sentences with no hard wrap.
Reply "OK" if every check passes.  Otherwise reply with one line per problem, each a short reason that names the file and the problem.  Do not edit any file.
```

### Finalize

Finalize is the report part of every exit, in this order:

1. Write `1-summary.md`, and update the evidence tier.
2. Run the check: the script, the subagent, and, for a Cassandra run, the reasoning review.
3. Apply the check-failure rule for this exit, below.
4. Build with `make`, or with `make gate` at a teardown gate.
5. Upload per `report-upload.md`.

`make` (the `all` target) runs `check`, then `build` (the book in `report/`), then `export` (`export/jira.txt` and `export/report.zip`).  `make gate` runs `report-check.py --gate` with the reasons, then `build` and `export`.  Pass the reasons like this:

```bash
make -C <cluster-dir>/docs gate REASONS='--reason "the noise floor does not support the verdict"'
```

### The check-failure rule

**At a teardown gate**, a check failure never blocks the build, the upload, or the `down`:

1. Interactive: show the reasons.  Offer one choice: fix now and re-check once, or proceed unchecked.
2. Unattended: skip the choice.
3. Run `make gate`.  For a non-redaction failure, `--gate` writes or replaces one `⚠ Unchecked: <reasons>` line under `## Caveats`, and exits 0.  A clean `--gate` run removes a stale Unchecked line.
4. Write the failure to `<issues>`.
5. Upload, then run the `down` per `report-upload.md`.  On an upload failure, use the existing failure menu.  A retry re-uploads only; it does not re-run the check.
6. Unattended: report the failure to the launcher.

**At Completion with no teardown**, a check failure blocks the build until it is fixed.  Fix the summary or the evidence, then run the check again.  An unattended run does not build or upload: it writes the failure to `<journal>` and `<issues>`, reports the reasons to the launcher, and leaves the cluster up.  The later gated teardown applies the Unchecked rule.

**A pause** leaves the cluster up.  Write the Partial summary and run the check; a failure needs no other action.

### A redaction failure

When `report-check.py` exits 3 at a teardown gate:

1. Do not upload.  The report stays local.
2. Write the failure to `<journal>` and `<issues>`.
3. Run the `down`.  A writing problem must not keep a cluster up.
4. Unattended: report "report not uploaded: redaction" to the launcher.
5. Tell the owner to fix the report and then run `run <cluster-dir> --finalize`.

`run <cluster-dir> --finalize` writes the summary, checks, runs `make gate`, and uploads.  It never runs `down`.  `report upload` needs only the workspace and AWS credentials, so it works after `down`, and it works in every layout.  Because the cluster can be gone, it uses the teardown-gate check rules.

## Arms

A cross-cluster A/B is one test directory with one report (`LAYOUT=arms`).  The coordinator scaffolds it once:

```bash
setup-cluster.sh <test-dir> <binary> --name "<title>" --plan <template.md> \
  --arm baseline=<baseline-plan.md> --arm candidate=<candidate-plan.md>
```

This writes the `<test-dir>/arms` marker, one wrapper per arm at `<test-dir>/<arm>/easy-db-lab`, one shared `<test-dir>/docs/`, `docs/3-plan.md` from the template, `docs/3-plan-<arm>.md` per arm, `4-journal-<arm>.md` and `5-issues-<arm>.md` per arm, and a `SUMMARY.md` whose Appendix lists the coordinator files and then each arm's files.  Each arm's cluster name comes from its plan; `--name` is only the fallback title.  Arm agents never run `setup-cluster.sh`.

### Write ownership

No two agents write the same file.

| Writer | Writes in `docs/` |
|:--|:--|
| Coordinator | `1-summary.md`, `2-evidence.md`, `evidence/`, `4-journal.md`, `5-issues.md`, `images/` |
| Arm agent | `4-journal-<arm>.md`, `5-issues-<arm>.md`, `data/*-<arm>.csv`, `data/*-<arm>.json` |

An arm agent never writes another arm's files, `1-summary.md`, or `2-evidence.md`.

### Per-arm fetch

An arm agent runs as `run <test-dir> --arm <arm> [step N]` and binds `$EDB` to `EDB_<ARM>` only.  After each measuring step, while its Mimir is up, it fetches its own data with `--name <metric>-<arm> --arm <arm>=<nodes>`, and a query that filters on its own `cluster` label.  A missed fetch is permanent after that arm's `down`, so fetch before the next step.

### The arm gate

An arm's gate replaces Finalize for that arm.  The arm agent uploads `3-plan-<arm>.md`, `4-journal-<arm>.md`, and `5-issues-<arm>.md` through its own wrapper, with the normal upload-failure handling.  Then it runs `down` on its own arm only.  It writes no summary, and it runs no check and no `make`.

### Final Finalize

After the last arm reports completion, the coordinator runs `run <test-dir> --finalize` once.  The arms can be up or down.  Final Finalize:

1. plots from the CSVs on disk with `plot --align elapsed`;
2. writes the summary and the evidence tier;
3. runs the check with the teardown-gate rules: one chance to fix when interactive, else the Unchecked line;
4. runs `make gate`;
5. uploads through every arm's wrapper, per `report-upload.md`;
6. runs no `down`.

Arms still up afterwards are torn down when the coordinator relaunches `run <test-dir> --arm <arm>` at Completion / teardown.

### Plot with --align elapsed

The arms run at different times, so their windows differ.  `plot --align elapsed` keeps each CSV's window and puts the seconds since that CSV's start on the x-axis.  The block holds one Window line per arm, for example `Window (baseline): ...`.  Each arm's query filters on its own `cluster` label, so the queries can differ in the `cluster` matcher only.  Then the block holds one Query line per arm.  The rest of the query, the unit, and the step must match.  Series are keyed by arm and node, with legends such as "db0 (baseline)".  The Data line links every arm's CSV, and the check merges them, keyed by node and arm.
