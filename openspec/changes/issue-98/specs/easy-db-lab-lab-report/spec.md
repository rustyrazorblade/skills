## ADDED Requirements

### Requirement: The scaffold holds five tier files and the report support files

`bin/setup-cluster.sh` SHALL create `docs/` with `1-summary.md`, `2-evidence.md`, `3-plan.md`, `4-journal.md`, `5-issues.md`, `SUMMARY.md`, `Makefile`, `book.toml`, `lab.css`, `images/`, and `data/`.  It SHALL NOT create `results.md`, `plan.md`, `journal.md`, `issues.md`, or `lab.mplstyle`.  Each file SHALL come from `scaffold/<destination>.template`.  `book.toml` SHALL come from a static `book.toml.template`, not from a heredoc in the script.  The script SHALL copy a tier file only when it is absent.  When `--plan` is given, the script SHALL copy the plan to `docs/3-plan.md`; otherwise `3-plan.md` holds the placeholder from its template.  `2-evidence.md.template` SHALL hold a `## Threats to validity` section.  Each tier template SHALL hold only headings and `<!-- -->` comments, so the scaffold-only test works.

#### Scenario: A new workspace gets the tier scaffold

- **WHEN** `bin/setup-cluster.sh` scaffolds a new workspace
- **THEN** `docs/` holds the five tier files, `SUMMARY.md`, `Makefile`, `book.toml`, `lab.css`, `images/`, and `data/`
- **AND** `docs/` does not hold `results.md` or `lab.mplstyle`

#### Scenario: The plan is copied to the plan tier

- **WHEN** `setup-cluster.sh` runs with `--plan <file>`
- **THEN** the plan is copied to `docs/3-plan.md`

#### Scenario: Templates follow the destination naming rule

- **WHEN** a reader lists `plugins/easy-db-lab/scaffold/`
- **THEN** every file is named `<destination-filename>.template`, including `book.toml.template`
- **AND** `setup-cluster.sh` contains no `book.toml` heredoc

#### Scenario: An existing tier file is kept

- **WHEN** `setup-cluster.sh` runs on a `docs/` that already holds `4-journal.md`
- **THEN** the script does not overwrite `4-journal.md`

### Requirement: SUMMARY.md makes the summary the landing page and puts the plan, journal, and issues in an Appendix

`SUMMARY.md.template` SHALL list `1-summary.md` as a prefix chapter, then an Evidence chapter for `2-evidence.md` with any extra evidence pages nested under it from `evidence/`, then a `# Appendix` part with Plan, Journal, and Issues.  The numeric prefixes SHALL make the Grafana Tests index, which sorts by name, show the tiers in the order 1 to 5.

#### Scenario: The built book opens on the summary

- **WHEN** `make` runs on a scaffolded docs tree
- **THEN** `report/index.html` is the summary page
- **AND** the sidebar shows Evidence, with any nested pages, and then an Appendix part with Plan, Journal, and Issues

#### Scenario: Nested evidence pages sit under Evidence

- **WHEN** the writer adds `evidence/latency.md` nested under Evidence in `SUMMARY.md`
- **THEN** the built sidebar shows it under Evidence and above the Appendix

### Requirement: The book title comes from the summary title at make time

`book.toml.template` SHALL hold `title = "@CLUSTER_NAME@"` as a fallback only.  The Makefile SHALL export `MDBOOK_BOOK__TITLE` from the first `# ` line of `1-summary.md` when that line is not empty.  The checker SHALL fail a non-scaffold summary that still holds the template placeholder title.

#### Scenario: The title is the plain-words title

- **WHEN** `make` builds the book and `1-summary.md` starts with `# Scrape allocation drops with the fix`
- **THEN** the book title is "Scrape allocation drops with the fix", not the cluster slug

#### Scenario: An empty title falls back to the cluster name

- **WHEN** `make` builds a book whose `1-summary.md` H1 is empty
- **THEN** the Makefile does not export `MDBOOK_BOOK__TITLE`
- **AND** the book title is the fallback from `book.toml`

#### Scenario: A placeholder title fails the check

- **WHEN** a non-scaffold `1-summary.md` still holds the template placeholder title
- **THEN** `report-check.py` reports FAIL

### Requirement: The house theme styles tables, verdicts, width, and print

`book.toml` SHALL reference `lab.css` through `[output.html] additional-css`.  `lab.css` SHALL give sticky table headers, zebra rows, verdict badge colours for `.verdict-confirmed`, `.verdict-refuted`, `.verdict-inconclusive`, and `.verdict-partial`, a wider content column, and `@media print` styles.  The scripts SHALL emit `--:` alignment for every numeric column, so numeric columns are right-aligned.  A verdict value SHALL be written as `<span class="verdict verdict-<value>">Value</span>`, and the checker SHALL check that the class and the text agree.

#### Scenario: book.toml wires the house CSS

- **WHEN** `book.toml` is read
- **THEN** it references `lab.css` through `additional-css`

#### Scenario: Stats tables are readable

- **WHEN** a built evidence page with a stats table is opened
- **THEN** the numeric columns are right-aligned, the headers stay visible on scroll, and the rows alternate in colour

#### Scenario: A verdict renders as a badge

- **WHEN** a verdict value is rendered
- **THEN** it shows as a badge in that value's colour

#### Scenario: Printing uses the print styles

- **WHEN** the page is printed
- **THEN** it uses the `@media print` styles from `lab.css`

#### Scenario: Verdict class and text disagree

- **WHEN** a summary holds `<span class="verdict verdict-confirmed">Refuted</span>`
- **THEN** `report-check.py` reports FAIL

### Requirement: One shared reference defines the report rules for run and explore

The plugin SHALL ship `references/report.md`.  The run skill and the explore skill SHALL load it.  It SHALL define the tier contents, the fixed summary layout, the Noise floor rule, the evidence block format, Threats to validity, the prose rules, redaction, the exit rule, the check step, the file roles `<plan>`, `<journal>`, and `<issues>`, and the arms rules.  The run skill SHALL NOT keep reporting rules in its execution loop, Completion, or Team Agents sections; it SHALL point to `report.md`.  The stale "step 66 above" at `run/SKILL.md:135` SHALL be fixed.

#### Scenario: Both skills load the reference

- **WHEN** a reader opens `run/SKILL.md` and `explore/SKILL.md`
- **THEN** each points to `../../references/report.md` for the report rules

#### Scenario: Run SKILL.md holds no reporting rules

- **WHEN** a reader opens the run skill's execution loop, Completion, and Team Agents sections
- **THEN** they point to `report.md` and do not restate the summary layout, the evidence format, or the reasoning-review rule
- **AND** the text "step 66 above" does not appear

#### Scenario: File roles resolve per layout

- **WHEN** a reader looks up `<journal>` in `report.md`
- **THEN** it is `4-journal.md` in a single layout and `4-journal-<arm>.md` for an arm agent

### Requirement: The summary has a fixed layout

`1-summary.md` SHALL hold, in order: a plain-words title; a Verdict line with one of Confirmed, Refuted, Inconclusive, or "Partial: stopped after step N", plus one sentence; a table; for a Cassandra run, a line "Reasoning review: done" or "Reasoning review: not run (cassandra-expert not installed)"; a `## What this means` section of 2 to 4 sentences for a customer; and a `## Caveats` section.  An A/B run SHALL use a comparison table with the columns Metric (with unit), Baseline, Candidate, Delta, Noise floor, and Verdict.  Any other run SHALL use a Findings table with the columns Finding, Evidence, and Severity.  Each comparison Metric cell SHALL link to an evidence anchor and name the statistic and the unit.

#### Scenario: An A/B summary uses the comparison table

- **WHEN** an A/B run writes `1-summary.md`
- **THEN** the table has the columns Metric (with unit), Baseline, Candidate, Delta, Noise floor, and Verdict
- **AND** each Metric cell links to an anchor in the evidence tier

#### Scenario: Any other run uses the Findings table

- **WHEN** a run that is not A/B, or an explore session, writes `1-summary.md`
- **THEN** the table has the columns Finding, Evidence, and Severity

#### Scenario: A verdict outside the four values fails

- **WHEN** the Verdict line holds a value other than Confirmed, Refuted, Inconclusive, or "Partial: stopped after step N"
- **THEN** `report-check.py` reports FAIL

#### Scenario: Cassandra reasoning review is done

- **WHEN** a Cassandra run's summary is written and `cassandra-expert` reviewed the reasoning
- **THEN** the summary reads "Reasoning review: done"

#### Scenario: Cassandra expert is not installed

- **WHEN** the run is a Cassandra run and `cassandra-expert` is not installed
- **THEN** the summary reads "Reasoning review: not run (cassandra-expert not installed)"

#### Scenario: A Cassandra summary without the line fails

- **WHEN** a Cassandra summary has no "Reasoning review" line
- **THEN** the check fails

### Requirement: The Noise floor cell links to its evidence or reads "not measured"

When the run measured noise, the Noise floor cell SHALL hold the value as a link to the evidence block it came from, and the checker SHALL recompute the value from that block's CSV.  When the run did not measure noise, the cell SHALL read "not measured", and the checker SHALL accept it.  A verdict of Confirmed or Refuted SHALL need |delta| > noise floor only when a value is present.  This change SHALL NOT change how or when a run measures noise.

#### Scenario: Every Noise floor cell is a link or "not measured"

- **WHEN** an A/B summary is produced
- **THEN** every Noise floor cell either links to the evidence block its value came from, or reads "not measured"

#### Scenario: Confirmed inside the noise floor fails

- **WHEN** a row holds a noise floor value and a Confirmed or Refuted verdict with |delta| <= that value
- **THEN** `report-check.py` reports FAIL

#### Scenario: Not measured allows a verdict

- **WHEN** a row reads "not measured" and holds a Confirmed verdict
- **THEN** `report-check.py` does not fail that row for the noise floor

#### Scenario: A missing or non-numeric noise floor fails

- **WHEN** an A/B row has an empty Noise floor cell, or a value that is neither numeric nor "not measured"
- **THEN** `report-check.py` reports FAIL

### Requirement: Every claim traces to an evidence block with a downloaded image and data

Each evidence block SHALL hold, in order: a heading, one or more images from `images/`, a stats table, the Window (UTC start and end, duration, step), the Query text, and a Data link to one or more CSVs in `data/`.  Each image SHALL be a Grafana panel render that `report-graph.py render` downloaded.  The default stats columns SHALL be Node, Arm, Samples, Min, p50, Mean, p99, and Max, with Unit.  The writer MAY swap the statistic columns when a metric needs others, for example a total and a rate for a counter.  Images SHALL be downloaded, never linked.  The summary and evidence tiers SHALL hold no link to a Grafana graph.

#### Scenario: A summary claim maps to a full evidence block

- **WHEN** any claim in the summary is traced
- **THEN** it maps to an evidence block with a downloaded Grafana render, a stats table, the Window, the Query, and a Data link to a CSV

#### Scenario: An incomplete evidence block fails

- **WHEN** an evidence block lacks its image, stats table, Window, Query, or Data link
- **THEN** `report-check.py` reports FAIL

#### Scenario: No Grafana links in the customer tiers

- **WHEN** the summary and evidence tiers are searched for links to Grafana graphs
- **THEN** none are found

#### Scenario: Swapped statistic columns for a counter

- **WHEN** the writer runs `block --stats samples,total,rate` for a counter
- **THEN** the stats table has the Node, Arm, Samples, Total, Rate, and Unit columns

### Requirement: Result-affecting issues go to Threats to validity and tool friction stays in the issues file

An issue that affects the result SHALL appear under `## Threats to validity` in the evidence tier.  Tool friction SHALL appear only in `<issues>`, and the summary and evidence tiers SHALL NOT mention it.

#### Scenario: A result-affecting issue

- **WHEN** an issue affects the result
- **THEN** it appears under "Threats to validity" in the evidence tier

#### Scenario: Tool friction stays out of the customer tiers

- **WHEN** `5-issues.md` holds tool friction
- **THEN** the summary and evidence tiers do not mention it

### Requirement: Report prose follows the STE rules

Report prose SHALL have no hard wrap and short sentences.  Each number SHALL be stated once, in its evidence block; the summary table SHALL be the only repeat.  Nodes SHALL be named by role, for example "db2 (fix)".  The checker SHALL warn on a numeral in summary prose outside the table, the Partial token, and the Unchecked line.

#### Scenario: A number in summary prose

- **WHEN** `## What this means` holds a numeral
- **THEN** `report-check.py` reports WARN for it

#### Scenario: Nodes are named by role

- **WHEN** a stats table names a node in an arm
- **THEN** it shows the node with its role, for example "db0 (baseline)"

### Requirement: Infrastructure identifiers never appear in the customer tiers

Account IDs, VPC, subnet, and security group IDs, IPs, and tunnel details SHALL NOT appear in the summary or evidence tiers, or in their CSV and JSON files.  They SHALL stay in the appendix journal.  `report.md` SHALL tell the writer to select nodes by host name (for example `instance=~"db.*"`), never by IP.  `report-graph.py fetch` SHALL refuse an IPv4-looking node value with no `--node` mapping.  Branch names and unreleased bug details SHALL be the owner's call for each report.  A redaction failure SHALL make `report-check.py` exit 3.

#### Scenario: Customer tiers hold no infrastructure identifiers

- **WHEN** the summary and evidence tiers are searched for account IDs, VPC IDs, IPs, and tunnel details
- **THEN** none are found

#### Scenario: An IP in the Query line or JSON fails

- **WHEN** an evidence Query line or a `data/*.json` file holds an IPv4 address
- **THEN** `report-check.py` exits 3

#### Scenario: Fetch refuses an unmapped IP node label

- **WHEN** `report-graph.py fetch` gets a series whose node label looks like an IPv4 address and no `--node` mapping covers it
- **THEN** it exits non-zero with a clear message and writes no CSV

### Requirement: Both skills write the evidence after each measuring step and the summary at every exit

The run and explore skills SHALL update the evidence tier after each step that measures something, through `report-graph.py fetch`, `render`, and `block`.  They SHALL run `fetch` and `render` at the same point, while the cluster is up, because Mimir and Grafana stop with the cluster.  `block` reads only files on disk, so it MAY run later.  They SHALL write `1-summary.md` at every exit: Completion, before every gated teardown, and on pause.  A partial exit is any exit before every plan step has finished: a pause, or a teardown gate before the plan ends.  A partial summary SHALL hold the verdict "Partial: stopped after step N" and one sentence.  Explore SHALL never be Partial.  A failed fetch or a failed render SHALL be logged to `<journal>` and `<issues>`, and the run SHALL continue.

#### Scenario: Stop after step 2 at the teardown gate

- **WHEN** a run stops after step 2 and goes through the teardown gate
- **THEN** the uploaded `1-summary.md` holds the verdict "Partial: stopped after step 2" and one sentence

#### Scenario: Pause writes a Partial summary

- **WHEN** the user pauses a run
- **THEN** `1-summary.md` is written with a Partial verdict before the session stops

#### Scenario: Explore writes a summary at teardown

- **WHEN** an explore session reaches teardown
- **THEN** it has written `1-summary.md` with a verdict and a Findings table (Finding, Evidence, Severity)
- **AND** the verdict is not Partial

#### Scenario: A measuring step adds an evidence block

- **WHEN** a plan step measures a metric
- **THEN** the skill runs `report-graph.py fetch` and `render` before the next step, while the cluster is up
- **AND** it runs `block` and appends the evidence block to the evidence tier

#### Scenario: A failed fetch does not stop the run

- **WHEN** `report-graph.py fetch` fails during a run
- **THEN** the skill logs the failure to `<journal>` and `<issues>` and continues
- **AND** the missing evidence fails the check at the next exit

#### Scenario: A failed render does not stop the run

- **WHEN** `report-graph.py render` fails during a run
- **THEN** the skill logs the failure to `<journal>` and `<issues>` and continues
- **AND** the evidence block with no image fails the check at the next exit

#### Scenario: A full A/B run on a real cluster

- **WHEN** a short A/B plan from the root `tests/plans/` runs to Completion on a real cluster
- **THEN** the workspace holds a summary with a verdict and a filled comparison table, at least one evidence block whose PNG is a Grafana panel render and whose CSV came from Mimir, a passing check, and a good `make` with all three outputs
- **AND** the upload of the five files shows in the Grafana Tests dashboard index in the order 1 to 5

#### Scenario: A single-cluster A/B renders from a regular dashboard

- **WHEN** a single-cluster A/B run on a real cluster reaches the upload
- **THEN** each image in the uploaded evidence tier is a Grafana render of a regular dashboard panel for the metric and the window of its block

### Requirement: The graph script fetches from Mimir to CSV

`bin/report-graph.py` SHALL be a uv-runnable PEP 723 script.  Its `fetch` subcommand SHALL query Mimir `query_range` with an explicit `--mimir-url` and `--tenant`, and an optional `--proxy socks5h://...`.  It SHALL write `docs/data/<name>.csv` in long form (`timestamp_utc,node,arm,value`) and `docs/data/<name>.json` with the query, start, end, step, unit, scale, and arms.  It SHALL NOT store the URL or the tenant.  The skill SHALL derive the URL and the tenant from `$EDB help observability` and `$EDB status` for each wrapper, and SHALL NOT read `state.json`.

#### Scenario: Mimir is unreachable

- **WHEN** `fetch` runs against an unreachable Mimir, for example `127.0.0.1:1`
- **THEN** it exits non-zero with a clear message
- **AND** it writes no CSV

#### Scenario: The query returns no series

- **WHEN** `fetch` gets a success response with zero series
- **THEN** it exits non-zero with a clear message
- **AND** it writes no CSV

#### Scenario: Fetch output holds no connection details

- **WHEN** `fetch` succeeds
- **THEN** `data/<name>.json` holds the query, window, step, unit, scale, and arms
- **AND** neither the CSV nor the JSON holds the Mimir URL or the tenant

### Requirement: The graph script renders a Grafana panel to a PNG

The `render` subcommand of `bin/report-graph.py` SHALL download one Grafana panel render and write it to `docs/images/<name>.png`.  It SHALL draw nothing itself.  Its interface SHALL be `render --grafana-url URL --dashboard UID --panel ID --from TIME --to TIME [--var NAME=VALUE]... [--width 1200] [--height 600] --name NAME --docs DOCS [--proxy socks5h://...] [--timeout 60] [--theme dark|light]`.  It SHALL send one GET to `<grafana-url>/render/d-solo/<UID>/?panelId=<ID>&from=<from>&to=<to>&var-<NAME>=<VALUE>...&width=<width>&height=<height>&tz=UTC&theme=<theme>`, with each value URL-encoded.  `--theme` SHALL default to `dark`, to match the report's dark theme.  `--from` and `--to` SHALL take an ISO 8601 UTC time, which the script sends as epoch milliseconds, or a Grafana relative time such as `now-93600s` or `now`, which the script sends unchanged.  `--name` SHALL follow the `fetch` rule: letters, digits, `_`, `.`, and `-`, and no path.  The script SHALL write the PNG only when the response status is 200 and the body is not empty and starts with the PNG signature.  On a connection error, a timeout, another status, an empty body, or a body that is not a PNG, it SHALL exit non-zero with a message that names the cause, and it SHALL NOT write or replace `images/<name>.png`.  It SHALL NOT store the Grafana URL anywhere.  The skill SHALL derive the Grafana URL for each wrapper from `$EDB help observability` and `$EDB status`, SHALL pass `--proxy` when it reaches Grafana through the SOCKS tunnel, and SHALL NOT read `state.json`.  The writer SHALL choose a panel that shows the same metric as the block's query, and SHALL render it over the block's window, with the dashboard's cluster variable set to the run's cluster.  The image window SHALL be the block's measured window: the `start` and `end` in the block's `data/<name>.json`, passed as absolute ISO times.  The writer SHALL NOT use a fixed or default range.  A relative time SHALL be used only for an overlay render, as the overlay requirement states.

#### Scenario: A render writes the panel PNG

- **WHEN** `render` runs against a stub Grafana that returns status 200 and a PNG body
- **THEN** it writes the body unchanged to `docs/images/<name>.png` and exits 0
- **AND** the stub got a GET on `/render/d-solo/<UID>/` with `panelId`, `from`, `to`, each `var-<NAME>`, `width`, `height`, and `tz=UTC`

#### Scenario: An ISO window becomes epoch milliseconds

- **WHEN** `render` gets `--from 2026-10-01T10:00:00Z --to 2026-10-01T10:10:00Z`
- **THEN** the request holds `from=1790848800000` and `to=1790849400000`

#### Scenario: A relative range passes through

- **WHEN** `render` gets `--from now-93600s --to now`
- **THEN** the request holds `from=now-93600s` and `to=now`

#### Scenario: A single-cluster render uses the measured window

- **WHEN** the writer renders a regular dashboard panel for an evidence block whose `data/<name>.json` holds `start` 2026-10-01T10:00:00Z and `end` 2026-10-02T10:00:00Z
- **THEN** the render request holds `from` and `to` for exactly that window
- **AND** the image covers the whole 24-hour window, not a fixed or default range

#### Scenario: Grafana is unreachable

- **WHEN** `render` runs against an unreachable Grafana, for example `127.0.0.1:1`
- **THEN** it exits non-zero with a clear message
- **AND** it writes no image

#### Scenario: Grafana returns an error status

- **WHEN** the stub Grafana returns a status other than 200
- **THEN** `render` exits non-zero with a message that names the status
- **AND** it writes no image

#### Scenario: Grafana returns a body that is not a PNG

- **WHEN** the stub Grafana returns status 200 with an empty body, or with a body that does not start with the PNG signature
- **THEN** `render` exits non-zero with a clear message
- **AND** it writes no image

#### Scenario: A failed render keeps the old image

- **WHEN** `images/<name>.png` exists and a `render` with the same `--name` fails
- **THEN** `images/<name>.png` is unchanged

### Requirement: The graph script builds the evidence block from CSV and a rendered image

The `block` subcommand of `bin/report-graph.py` SHALL replace `plot`.  `plot` SHALL NOT exist, and the script SHALL NOT depend on matplotlib.  The interface SHALL be `block --csv PATH [--csv PATH]... --image [ARM=]PATH [--image [ARM=]PATH]... --title TEXT [--stats LIST] [--arm-windows] [--page 2-evidence.md] --docs DOCS`.  `block` SHALL read CSVs only from `docs/data/` and images only from `docs/images/`.  It SHALL print the full evidence block to stdout and SHALL write no file.  Each image SHALL be a non-empty PNG; otherwise `block` SHALL exit non-zero and print no block.  An image given as `ARM=PATH` SHALL carry the arm in its alt text, for example `![Throughput (baseline)](images/throughput-baseline.png)`.  The stats table SHALL have one row per node and one rollup row per arm (Node = all) from pooled samples, from every CSV together.  Empty input SHALL exit non-zero and print no block.  CSVs with mismatched query, unit, or step SHALL be an error.  Two queries that differ only in their `cluster` label matcher SHALL NOT count as mismatched, because each arm filters on its own cluster; the block SHALL then hold one Query line per arm.  Without `--arm-windows`, CSVs with mismatched windows SHALL be an error.  With `--arm-windows`, each CSV SHALL keep its window, and the block SHALL hold one Window line per arm.  With `--arm-windows`, one arm in two CSVs with different windows SHALL be an error.

#### Scenario: The block cites the rendered image

- **WHEN** `block` gets a CSV fixture and `--image docs/images/scrape-alloc.png`
- **THEN** it prints the heading, `![<title>](images/scrape-alloc.png)`, the stats table, the Window, the Query, and the Data link, in that order
- **AND** it writes no file

#### Scenario: A missing or non-PNG image

- **WHEN** `block` gets an `--image` path that does not exist, is empty, is outside `docs/images/`, or is not a PNG
- **THEN** it exits non-zero with a clear message
- **AND** it prints no block

#### Scenario: Per-arm images are labelled by arm

- **WHEN** `block` gets one CSV per arm, `--image baseline=<png>`, and `--image candidate=<png>`
- **THEN** the block holds two image lines, each with its arm in the alt text
- **AND** it holds one stats table with the node rows and the rollup rows of both arms

#### Scenario: Empty input prints no block

- **WHEN** `block` gets a CSV with no rows
- **THEN** it exits non-zero with a clear message
- **AND** it prints no block

#### Scenario: Arms with different windows

- **WHEN** `block --arm-windows` gets one CSV per arm with different windows, the same unit and step, and queries that differ only in their `cluster` label matcher
- **THEN** the evidence block holds one Window line per arm, for example "Window (baseline): ..."
- **AND** it holds one Query line per arm

#### Scenario: Mismatched windows without arm windows

- **WHEN** `block` gets CSVs with different windows and no `--arm-windows`
- **THEN** it exits non-zero with a clear message

#### Scenario: The script holds no plotting code

- **WHEN** a reader reads the PEP 723 metadata of `bin/report-graph.py` and runs `report-graph.py --help`
- **THEN** the dependencies hold no matplotlib
- **AND** the subcommands are `fetch`, `render`, and `block`

### Requirement: The check step compares every summary claim with its evidence before make

`bin/report-check.py <docs>` SHALL be a uv-runnable PEP 723 script that reads files only and uses no network.  It SHALL print PASS, FAIL, or WARN per check.  It SHALL exit 0 with no FAIL, 1 with a FAIL, 2 on a usage or I/O error, and 3 on a redaction FAIL.  For each comparison row it SHALL follow the Metric anchor (by mdbook's slug rule, including nested `evidence/` pages) to the Data links, merge the CSVs, key the rows by (Node, Arm), recompute the arm rollups and the delta `(cand - base) / base` in percent, and compare sign, size, and unit with the row.  A size mismatch is a difference beyond the displayed precision, or a delta off by more than 0.1 percentage points.  A unit mismatch is a unit that differs from the JSON.  Before `make`, the skill SHALL also run a check subagent with the prompt in `report.md`, and, for a Cassandra run, `cassandra-expert` for a reasoning review of confounds, the choice of metric, and whether the noise floor supports the verdict.  When `cassandra-expert` is not installed, the skill SHALL say so plainly.  The writer SHALL fix every mismatch before the build, except where the gate rule applies.

#### Scenario: Wrong sign (the metrics21667 pattern)

- **WHEN** a sample summary claims a -17.2% delta and its CSV holds the candidate at 32.72 MB/s against baselines at 26.92 and 27.27 MB/s
- **THEN** the check step flags the sign mismatch before `make`

#### Scenario: Wrong size

- **WHEN** a sample summary states a delta whose size differs from the CSV by more than 0.1 percentage points
- **THEN** the check step flags it before `make`

#### Scenario: Wrong unit

- **WHEN** a sample summary states a metric in a unit that differs from the evidence JSON
- **THEN** the check step flags it before `make`

#### Scenario: Summary and evidence agree

- **WHEN** the summary and the evidence agree
- **THEN** the check step passes and `make` proceeds

#### Scenario: A heading with punctuation and a nested page

- **WHEN** a Metric cell links to `evidence/latency.md#read-latency-ms` for the heading "Read latency (ms)"
- **THEN** the checker resolves the anchor and checks the row

### Requirement: A check failure never blocks teardown

At a teardown gate, a non-redaction check failure SHALL NOT block the build, the upload, or the `down`.  The skill SHALL run `make gate`, which runs `report-check.py --gate`; it SHALL write or replace one "⚠ Unchecked: <reasons>" line under `## Caveats`, merge the reasons from the subagent and `cassandra-expert`, and exit 0.  The skill SHALL log the failure to `<issues>`.  An interactive run SHALL first offer one chance to fix the report and re-check once, or to proceed unchecked.  An unattended run SHALL proceed and report the failure to the launcher.  At Completion with no teardown, a failed check SHALL block the build until it is fixed; an unattended run SHALL then not build or upload, SHALL log the failure, SHALL report the reasons to the launcher, and SHALL leave the cluster up.  A clean `--gate` run SHALL remove a stale Unchecked line.  Without `--gate`, the checker SHALL NOT edit any file.

#### Scenario: Check failure at a teardown gate

- **WHEN** a check fails at a teardown gate
- **THEN** the report uploads with a "⚠ Unchecked: <reasons>" Caveats line, the failure is in the issues file, and the `down` runs

#### Scenario: Interactive gate offers one fix

- **WHEN** a check fails at an interactive teardown gate
- **THEN** the skill shows the reasons and offers to fix now and re-check once, or to proceed unchecked

#### Scenario: Unattended gate proceeds

- **WHEN** a check fails at an unattended teardown gate
- **THEN** the skill skips the choice, runs `make gate`, uploads, runs `down`, and reports the failure to the launcher

#### Scenario: Completion with no teardown blocks the build

- **WHEN** a check fails at Completion and no teardown follows
- **THEN** the skill does not build until the failure is fixed

#### Scenario: Unattended Completion with no teardown

- **WHEN** a check fails at an unattended Completion with no teardown intent
- **THEN** the skill does not build or upload, logs the failure, reports the reasons to the launcher, and leaves the cluster up

#### Scenario: A clean gate removes a stale line

- **WHEN** `report-check.py --gate` passes on a summary that holds an old Unchecked line
- **THEN** it removes the Unchecked line

### Requirement: A redaction failure blocks the upload but not the down

When `report-check.py` exits 3 at a teardown gate, the skill SHALL NOT upload, SHALL log the failure to `<journal>` and `<issues>`, and SHALL run the `down`.  An unattended run SHALL report "report not uploaded: redaction" to the launcher.  The run skill SHALL offer `run <cluster-dir> --finalize`, which writes the summary, checks, makes, and uploads, and SHALL NOT run `down`.  The entry point SHALL work after `down` and in every layout.

#### Scenario: Redaction failure at a teardown gate

- **WHEN** the redaction check fails at a teardown gate
- **THEN** nothing is uploaded, the failure is logged, and the `down` runs

#### Scenario: The owner uploads after the fix

- **WHEN** the owner fixes the report and runs `run <cluster-dir> --finalize`
- **THEN** the report uploads with no `down`

#### Scenario: Unattended redaction failure

- **WHEN** the redaction check fails at an unattended teardown gate
- **THEN** the skill reports "report not uploaded: redaction" to the launcher

### Requirement: make builds the book and the exports

`Makefile.template` SHALL define `all: check build export`, plus `build`, `check`, `export`, `gate`, `serve`, and `clean`.  `setup-cluster.sh` SHALL write `EDB_LAB_BIN ?= <absolute plugin bin>` into the Makefile, with `PATH` as the fallback.  `make` SHALL produce `report/index.html`, `export/jira.txt`, and `export/report.zip`.  `bin/report-export.py` SHALL be a uv-runnable PEP 723 script.  `jira` SHALL write the summary tier in Atlassian wiki markup, through pandoc from `pypandoc-binary`, with each image referenced by file name for manual attachment, `.md` links turned into text, and the verdict span mapped to a colour.  `zip` SHALL produce the shareable book: the rendered HTML book of every page that `SUMMARY.md` lists, the appendix included, built with the house theme from a redacted copy.  It SHALL copy every listed page, and every `images/` and `data/` file they reference, into a staging tree under `export/`.  In the staged copy, it SHALL replace each infrastructure identifier (IPv4 addresses, EC2 host names such as `ip-10-0-1-15`, 12-digit account IDs, `vpc-`, `subnet-`, `sg-`, `igw-`, and `i-` IDs, and tunnel and SOCKS details) with a fixed placeholder that names its kind, for example `<private-ip>` or `<vpc-id>`.  The kinds SHALL also cover IPv6 addresses, public EC2 DNS names such as `ec2-54-12-34-56.compute-1.amazonaws.com`, `eni-`, `vol-`, and `ami-` IDs, dashed account IDs, local home and key paths such as `/Users/<name>/…`, AWS profile names, SSO start URLs, email addresses, S3 bucket names and `s3://` URLs, and `host:port` service URLs.  Where matches overlap, the replacement SHALL cover the whole overlapping text with one placeholder.  The replacement SHALL NOT change link fragments, and SHALL NOT change version strings or ordinary prose.  In the same step, it SHALL replace the wrapper variables `$EDB`, `${EDB}`, and `$EDB_<ARM>` with the plain command name `easy-db-lab`.  It SHALL redact every staged file that is text, whatever its extension, and SHALL fail on a referenced file that is neither text nor a known image type.  It SHALL reject mdbook include directives in staged pages.  It SHALL then run the redaction check over the whole staged copy and over every text file of the built HTML, the search index and print page included, and SHALL fail the build if any identifier remains.  It SHALL build the book from the staged copy with mdbook and zip the built HTML as `export/report.zip`, so that opening `index.html` from the extracted zip shows the themed book with working images and links.  The local `report/` book and the uploaded tier files SHALL keep the unredacted record.  A missing referenced file SHALL fail the build.

#### Scenario: make produces the exports

- **WHEN** `make` runs on a sample docs tree with images and CSV
- **THEN** it produces `report/index.html`, `export/jira.txt`, and `export/report.zip`

#### Scenario: jira.txt holds the summary tier

- **WHEN** `jira.txt` is read
- **THEN** it holds the summary tier in Atlassian wiki markup
- **AND** each image is referenced by file name, for example `!scrape-alloc.png!`

#### Scenario: report.zip is the shareable book

- **WHEN** `report.zip` is extracted and its `index.html` is opened
- **THEN** it shows the themed HTML book with every page that `SUMMARY.md` lists, the appendix included
- **AND** every image and data link in it resolves inside the extracted tree

#### Scenario: The shareable book is redacted

- **WHEN** a journal page holds an IPv4 address, an EC2 host name, a VPC ID, and a SOCKS port
- **THEN** the pages in `report.zip` hold the placeholders, for example `<private-ip>` and `<vpc-id>`, and none of the original values
- **AND** the local `report/` book and `4-journal.md` still hold the original values

#### Scenario: The shareable book names the command plainly

- **WHEN** a journal page holds `$EDB status`, `"${EDB}" down --auto-approve`, and `$EDB_BASELINE report upload`
- **THEN** the pages in `report.zip` show `easy-db-lab status`, `"easy-db-lab" down --auto-approve`, and `easy-db-lab report upload`
- **AND** the local `report/` book still holds the variables

#### Scenario: A value the redaction misses fails the export

- **WHEN** the staged copy still holds an infrastructure identifier after the replacement step
- **THEN** `make export` exits non-zero and names the file and the line

#### Scenario: A missing referenced image fails the build

- **WHEN** the evidence tier references `images/missing.png` and the file does not exist
- **THEN** `make` exits non-zero

#### Scenario: make runs the scripts outside Claude

- **WHEN** a human runs `make` in a scaffolded `docs/` with no plugin `bin/` on `PATH`
- **THEN** the Makefile finds the scripts through `EDB_LAB_BIN`

### Requirement: Explore scaffolds the report before its first report write

When `docs/SUMMARY.md` is absent, the explore skill SHALL run `setup-cluster.sh "$PWD" --docs-only --name "$(basename "$PWD")"` at Step 1, after it resolves the binary and passes the source-checkout guard, and before its first journal write.  `--docs-only` SHALL take no binary and SHALL create no wrapper.  The directory basename SHALL be only the fallback title.

#### Scenario: Explore starts with no report scaffold

- **WHEN** an explore session starts in a directory with no `docs/SUMMARY.md`
- **THEN** it runs `setup-cluster.sh` before its first report write
- **AND** any existing wrapper is unchanged

#### Scenario: Explore starts with a scaffold

- **WHEN** an explore session starts in a directory that has `docs/SUMMARY.md`
- **THEN** it does not run `setup-cluster.sh`

### Requirement: The setup script protects wrappers and source checkouts

Without `--docs-only`, `setup-cluster.sh` SHALL NOT rewrite an existing wrapper.  It SHALL refuse a binary whose real path equals a wrapper path it would write.  It SHALL exit 1 when `<cluster-dir>/bin/easy-db-lab` exists next to `settings.gradle.kts` or `build.gradle.kts`.  `detect-cluster-layout.sh` SHALL skip `bin` like `docs`.  The explore skill SHALL refuse to scaffold or provision in a source checkout, and SHALL tell the user to change to a workspace.

#### Scenario: An existing wrapper is kept

- **WHEN** `setup-cluster.sh` runs on a directory that already has a wrapper
- **THEN** the wrapper is unchanged

#### Scenario: A binary that is its own wrapper

- **WHEN** the binary's real path equals a wrapper path the script would write
- **THEN** the script exits non-zero and writes nothing

#### Scenario: A source checkout

- **WHEN** `setup-cluster.sh` runs on a directory with `bin/easy-db-lab` and `settings.gradle.kts`
- **THEN** it exits 1
- **AND** explore tells the user to change to a workspace

#### Scenario: Layout detection skips bin

- **WHEN** `detect-cluster-layout.sh` scans a directory with a `bin/` subdirectory
- **THEN** it does not report `bin` as a DC

### Requirement: A cross-cluster test is one test directory with one report

`setup-cluster.sh <test-dir> <binary> --name <title> --plan <template> --arm <arm>=<plan.md>...` SHALL create one `<test-dir>/<arm>/` wrapper per arm, one shared `<test-dir>/docs/`, and the marker `<test-dir>/arms` with one arm per line.  `--arm` SHALL exclude `--dc`.  `--plan` SHALL go to `docs/3-plan.md`, and each `--arm a=p` SHALL go to `docs/3-plan-<a>.md`.  The script SHALL create `4-journal-<arm>.md` and `5-issues-<arm>.md` for each arm, copy-if-absent, and SHALL generate a `SUMMARY.md` Appendix of Plan, Coordinator journal, Coordinator issues, and then per arm Plan, Journal, and Issues.  The coordinator SHALL run the script once; arm agents SHALL NOT run it.  `detect-cluster-layout.sh` SHALL check the marker first and report `LAYOUT=arms`, `ARMS`, `EDB_<ARM>`, `STATE_<ARM>`, and `STATE`.  `configure-multi-dc-seeds.sh` SHALL exit 1 when the marker exists.  `references/cassandra.md` Multi-DC Setup SHALL state that it applies to `LAYOUT=multi` only.  The run skill's "Parallel arms" section SHALL describe this layout in place of one workspace per arm, and SHALL keep the calibration rule unchanged.

#### Scenario: The arms scaffold

- **WHEN** the coordinator runs `setup-cluster.sh <test-dir> <binary> --name T --plan tpl.md --arm baseline=b.md --arm candidate=c.md`
- **THEN** `<test-dir>/arms` lists baseline and candidate, each arm has a wrapper under `<test-dir>/<arm>/`, and `docs/` holds `3-plan-baseline.md`, `3-plan-candidate.md`, and one journal and one issues file per arm
- **AND** the `SUMMARY.md` Appendix lists the coordinator files and then each arm's Plan, Journal, and Issues

#### Scenario: Arm and DC flags together

- **WHEN** `setup-cluster.sh` gets both `--arm` and `--dc`
- **THEN** it exits non-zero with a usage message

#### Scenario: Layout detection reports arms

- **WHEN** `detect-cluster-layout.sh` runs on a test directory with an `arms` marker
- **THEN** it prints `LAYOUT=arms`, `ARMS="baseline candidate"`, and `EDB_<ARM>` and `STATE_<ARM>` for each arm

#### Scenario: Seeds script refuses arms

- **WHEN** `configure-multi-dc-seeds.sh` runs on a directory with an `arms` marker
- **THEN** it exits 1

#### Scenario: One report per cross-cluster test

- **WHEN** a cross-cluster test finishes
- **THEN** there is one report under `<test-dir>/docs/`, with one journal and one issues file per arm
- **AND** it is uploaded through every arm's wrapper

### Requirement: Arm agents write only their own files and gate their own down

An arm agent SHALL run as `run <test-dir> --arm <arm> [step N]` and SHALL bind `$EDB` to `EDB_<ARM>` only.  In `docs/` it SHALL write only `4-journal-<arm>.md`, `5-issues-<arm>.md`, `data/*-<arm>.*`, and `images/*-<arm>.png`.  It SHALL NOT write another arm's files, `1-summary.md`, or `2-evidence.md`.  It SHALL fetch its own data after each measuring step while its Mimir is up, with `--name <metric>-<arm>`.  For a metric with no overlay panel, it SHALL also render its own panel at the same point, per the overlay requirement.  On resume it SHALL read `docs/3-plan-<arm>.md`.  Its arm gate SHALL upload `3-plan-<arm>.md`, `4-journal-<arm>.md`, and `5-issues-<arm>.md` through its own wrapper, with the existing upload-failure handling, and then run `down` on its own arm only; it SHALL NOT write a summary, check, or make.  In arms mode, the run skill SHALL refuse teardown without `--arm`.  No agent SHALL decide teardown on its own; the coordinator SHALL relaunch `run <test-dir> --arm <arm>` at Completion / teardown.

#### Scenario: No two agents write the same file

- **WHEN** two arm agents run at the same time
- **THEN** each writes only its own `-<arm>` journal, issues, data, and image files

#### Scenario: Arm gate

- **WHEN** an arm agent reaches its teardown gate
- **THEN** it uploads its plan, journal, and issues files through its own wrapper and then runs `down` on its own arm only
- **AND** it does not write `1-summary.md`

#### Scenario: Teardown without an arm

- **WHEN** the run skill is asked to tear down a `LAYOUT=arms` test directory without `--arm`
- **THEN** it refuses

### Requirement: The coordinator runs the Final Finalize once after the last arm

The coordinator SHALL own `1-summary.md`, `2-evidence.md`, `4-journal.md`, and `5-issues.md`.  After the last arm reports completion and the coordinator has rendered the overlay images, it SHALL run `run <test-dir> --finalize` once, with the arms up or down.  Final Finalize SHALL build each evidence block from the CSVs and the images on disk with `block --arm-windows`, and SHALL render nothing.  It SHALL then write the summary and evidence tiers, run the check with the teardown-gate rules, run `make gate`, and upload through every arm's wrapper.  It SHALL NOT run `down`.  Arms still up afterwards SHALL be torn down by the coordinator relaunching each arm at Completion / teardown.

#### Scenario: Final Finalize after the last arm

- **WHEN** the last arm reports completion
- **THEN** the coordinator runs `run <test-dir> --finalize` once and uploads the full report through every arm's wrapper
- **AND** it runs no `down` and no `render`

#### Scenario: Final Finalize with a check failure

- **WHEN** the check fails during Final Finalize
- **THEN** the coordinator applies the teardown-gate rule: one chance to fix when interactive, else the Unchecked line, then the build and the upload

### Requirement: A cross-cluster metric gets one overlay render, and the last arm stays up for it

In `LAYOUT=arms`, when a comparison dashboard has an overlay panel for a metric, the evidence block for that metric SHALL hold one combined image: a render of that overlay panel from one arm's Grafana, which reads both clusters from the shared Mimir.  The overlay panels SHALL be these:

| Dashboard | UID | Overlay panels |
|:--|:--|:--|
| A/B Comparison | `ab-comparison` | 1001 Throughput, 1002 Read p99, 1003 Write p99, 1004 Error rate, 1005 CPU busy, 1006 Disk I/O, 1007 GC pause |
| Cassandra Cluster Comparison | `c09599ec-8d87-4fe5-9346-9e85c41d33af` | the same ids as A/B Comparison |
| System A/B Comparison | `system-ab-comparison` | 1001 CPU busy, 1002 Memory used, 1003 Disk I/O, 1004 Network |

The coordinator SHALL render an overlay with `--var baseline_cluster=<baseline arm cluster_name> --var candidate_cluster=<candidate arm cluster_name>`.  Each overlay panel sets its own range, so the dashboard range SHALL be relative: the coordinator SHALL pass `--from now-<N>s --to now`, where N is the number of seconds from the earlier arm's measured start to the render time.  The coordinator SHALL NOT use a fixed range.  The dashboard moves each run to a common start, so the coordinator SHALL NOT align windows for the image.

The image SHALL show each arm's measured window when the dashboard supports it.  The coordinator SHALL detect support by reading the dashboard JSON through `<grafana-url>/api/dashboards/uid/<UID>` and finding the variables `base_from`, `base_to`, `cand_from`, and `cand_to` (rustyrazorblade/easy-db-lab#1015).  When they exist, the coordinator SHALL set them, as epoch milliseconds, to the `start` and `end` in each arm's `data/<name>.json` for the block's metric.  When they do not exist, the overlay covers each cluster's whole run, from its first `up` sample to its last.  The coordinator SHALL then render it anyway, SHALL note the fallback in `4-journal.md`, and SHALL add a `## Caveats` line to `1-summary.md` that says the overlay image covers each cluster's whole run, not only the measured window.  In a test with more than two arms, the coordinator SHALL render one overlay per arm other than baseline, with that arm as `candidate_cluster`, and SHALL give each image that arm as its label.

The render arm SHALL be the last arm still up.  An arm runs its gate and its `down` only when the coordinator relaunches `run <test-dir> --arm <arm>` at Completion / teardown, so the coordinator holds the render arm by not relaunching it.  The coordinator SHALL relaunch the render arm for teardown only after it has rendered every overlay image to `docs/images/`; that relaunch is the release.  The coordinator MAY relaunch the other arms for teardown at any time after they report completion.  The hold and the release SHALL use no shared state file: the only files in play stay the per-arm files and the `arms` marker.  The coordinator SHALL derive the render arm's Grafana URL from `EDB_<ARM>` through `help observability` and `status`.  When an overlay render fails, the coordinator SHALL log the failure to `4-journal.md` and `5-issues.md`, SHALL offer one retry when interactive, and SHALL then release the arm.  The evidence block with no image then fails the check, and the teardown-gate rule applies.

When no comparison dashboard has an overlay panel for a metric, each arm agent SHALL render its own panel from a regular dashboard while its arm is up, at the same point as its fetch, to `images/<metric>-<arm>.png`, with its own cluster and its own window.  The coordinator's block for that metric SHALL list each image labelled by arm, through `--image <arm>=<path>`, and the stats table SHALL stay one table from both arms' CSVs.

#### Scenario: The last arm holds its down until the overlay render

- **WHEN** every arm has reported completion and a measured metric has an overlay panel
- **THEN** the coordinator renders that overlay panel from the render arm's Grafana, with `baseline_cluster` and `candidate_cluster` set, before it relaunches the render arm for teardown
- **AND** the evidence block for that metric holds one image

#### Scenario: The overlay shows the measured windows

- **WHEN** the comparison dashboard defines `base_from`, `base_to`, `cand_from`, and `cand_to`
- **THEN** the overlay render request sets them to each arm's measured `start` and `end`, in epoch milliseconds
- **AND** the request uses a relative range from the earlier arm's measured start to now, not a fixed range

#### Scenario: The dashboard has no window variables

- **WHEN** the comparison dashboard defines none of the window variables
- **THEN** the coordinator renders the whole-run overlay, notes the fallback in `4-journal.md`, and adds a `## Caveats` line to `1-summary.md` that says the image covers each cluster's whole run

#### Scenario: The coordinator releases the render arm

- **WHEN** the coordinator has rendered every overlay image to `docs/images/`
- **THEN** it relaunches `run <test-dir> --arm <render arm>` at Completion / teardown, and that arm runs its gate and its `down`

#### Scenario: The hold uses no shared state file

- **WHEN** the coordinator holds and releases the render arm
- **THEN** no file outside the per-arm files and the `arms` marker carries the hold or the release

#### Scenario: An overlay render fails

- **WHEN** an overlay render fails
- **THEN** the coordinator logs the failure to `4-journal.md` and `5-issues.md`, offers one retry when interactive, and then releases the render arm
- **AND** the evidence block with no image fails the check under the teardown-gate rule

#### Scenario: A metric with no overlay panel

- **WHEN** a measured metric has no overlay panel in any comparison dashboard
- **THEN** each arm agent renders its own regular dashboard panel to `images/<metric>-<arm>.png` while its arm is up
- **AND** the coordinator's evidence block holds one image per arm, labelled by arm, and one stats table from both arms' CSVs

#### Scenario: A two-arm test on a real cluster

- **WHEN** a two-arm cross-cluster test on a real cluster reaches the final upload
- **THEN** the uploaded evidence tier holds at least one combined overlay image that is a Grafana render from the render arm's Grafana
- **AND** the render arm ran its `down` only after that render

### Requirement: Plan, run, explore, and references hold no stale report structure

`skills/plan/SKILL.md`, `skills/run/SKILL.md`, `skills/explore/SKILL.md`, `references/report-upload.md`, `references/journal.md`, and `references/issues.md` SHALL NOT refer to `results.md` or the old file names.  Each SHALL describe the tiered report or point to `report.md`.  The plan skill SHALL drop "Performance Results" and the screenshot instructions, and its `--previous` handling SHALL read `1-summary.md`, `4-journal.md`, and `5-issues.md`.  `journal.md` SHALL replace the Grafana Screenshots section with the rule that measurements go to the evidence tier through `report-graph.py`.  These files and `references/report.md` SHALL NOT refer to the `plot` subcommand, `lab.mplstyle`, matplotlib, fixed role colours, or a Grafana render as an optional appendix image.  The repo `README.md` SHALL NOT advertise an "easy-db-lab operator" agent.

#### Scenario: No stale results.md reference

- **WHEN** `skills/plan/SKILL.md`, `skills/run/SKILL.md`, `skills/explore/SKILL.md`, `references/report-upload.md`, and `references/journal.md` are searched for `results.md`
- **THEN** no stale reference remains
- **AND** each file describes the tiered report or points to the new shared reference

#### Scenario: No vague screenshot instruction

- **WHEN** `references/journal.md` and `skills/run/SKILL.md` are searched for the Grafana screenshot instruction
- **THEN** it is gone or points to the evidence block rule in `report.md`

#### Scenario: Plan previous reads the tier files

- **WHEN** the plan skill runs with `--previous <cluster-dir>`
- **THEN** it reads `docs/1-summary.md`, `docs/4-journal.md`, and `docs/5-issues.md`

#### Scenario: README advertises no operator agent

- **WHEN** a reader searches the repo `README.md` for "easy-db-lab operator"
- **THEN** no match is found

#### Scenario: No custom plotting instruction

- **WHEN** `references/report.md`, `references/journal.md`, `skills/run/SKILL.md`, and `skills/explore/SKILL.md` are searched for `report-graph.py plot`, `lab.mplstyle`, and matplotlib
- **THEN** no instruction to plot or style an image remains
- **AND** each points to `render` and `block`
