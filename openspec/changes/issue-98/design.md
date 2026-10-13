## Context

The easy-db-lab plugin writes a lab report in each cluster workspace under `docs/`.  Today the scaffold holds `results.md`, `plan.md`, `journal.md`, and `issues.md`, and `setup-cluster.sh` writes `book.toml` from a heredoc with the cluster slug as the title.  The run skill writes `results.md` only at Completion step 1, so every other exit uploads a blank page.  `issue-96` (merged, not yet archived) added `references/report-upload.md`, the teardown gate, and the rule that the run skill uploads "the fixed four" files.  The explore skill has no summary rule and provisions without `setup-cluster.sh`, so its `docs/` can lack `SUMMARY.md`, `book.toml`, and `Makefile`.

`report upload` renders each `.md` to HTML, builds one `index.html` per test sorted by name, and accepts `.md` only.  It needs only `state.json` and AWS credentials, so it works after `down` (easy-db-lab `ReportUpload.kt:12-19`).  Each upload rebuilds the index from every document in the test folder (`TestDocumentService.kt:64,107`), so a later partial upload does not drop earlier documents.  Each workspace uploads to `reports/<tenant>/<name>-<id>/`, so every arm of a cross-cluster test is a separate Grafana test.

The architect prototyped the mechanics against mdbook v0.5.3, uv, and pandoc through uv.

## Goals / Non-Goals

**Goals:**

- A five-tier report (`1-summary.md` to `5-issues.md`) that the Grafana Tests index shows in order.
- A summary with the verdict first, a fixed table, and every number traced to an evidence block.
- A mechanical check that catches the `metrics21667` contradiction before `make`.
- Data downloaded from Mimir as CSV, and images downloaded as Grafana panel renders, never linked.
- `make` produces the HTML book, a JIRA export, and a zip of the customer tiers.
- A summary at every exit, so no upload is blank.
- One report per cross-cluster test.

**Non-Goals:**

- Calibration methodology.  This change reports only a noise floor that a run already measured.  The calibration rule at `run/SKILL.md:374` is unchanged.
- easy-db-lab CLI changes: image and CSV upload, explicit document order, `commands --json`.
- A plan-command parse script (separate skills issue).
- The Grafana notebook plugin (rustyrazorblade/easy-db-lab#1012).
- Old workspaces: no migration and no compatibility code.
- CI for plugin tests (filed as issue 100).
- `bin/export-workload-metrics` reading `state.json` (filed as issue 99).

## Decisions

The owner accepted D1 to D8 as the architect recommended (decision 1), the minor fixes m1 to m8 (decision 6), and the architect addendum in full (decision 10).  Two owner redirects at Seam 1 changed the graph design after that.  Redirect 1: a query difference in the `cluster` label matcher only is not a mismatch.  Redirect 2: Grafana panel renders replace local plotting (see "Redirect 2" below).  Where an earlier entry here disagrees with a redirect, the redirect wins.

### Pipeline

```
skill (run/explore) --writes--> docs/1-summary.md, 2-evidence.md (rules: references/report.md)
     | after each measuring step, while the cluster is up:
     |                             report-graph.py fetch  (Mimir -> data/<n>.csv + data/<n>.json)
     |                             report-graph.py render (Grafana panel render -> images/<n>.png)
     | then:                       report-graph.py block  (CSV + image -> evidence block on stdout)
     | at every exit:  write summary -> check (report-check.py + subagent + cassandra-expert) -> make -> upload
make (docs/Makefile):  check -> mdbook build (title from 1-summary.md H1) -> export/jira.txt, export/report.zip
```

Three uv scripts, a static scaffold, and one shared reference hold the mechanics.  The skills hold the policy: when to write, check, and upload.  No plugin agent file, no mdbook preprocessor, and no shared Python library are added.

### D1: book title at make time

The Makefile exports `MDBOOK_BOOK__TITLE` from the first `# ` line of `1-summary.md`, only when that H1 is not empty (m1).  `book.toml.template` keeps `title = "@CLUSTER_NAME@"` as the fallback.  The checker fails a non-scaffold summary that still has the placeholder title.

### D2a: JIRA export through pandoc

`report-export.py jira` uses the pandoc jira writer through uv `pypandoc-binary`.  A small Lua filter or post-pass maps `!images/x.png!` to `!x.png!`, turns `.md` links into text, and maps the verdict span to `{color:..}*X*{color}`.

### D2b: zip contents from SUMMARY.md

`report-export.py zip` parses `SUMMARY.md` for the pages before `# Appendix`, scans them for `![](...)` and `(data/...)` references, and zips those pages and files.  A missing referenced file fails the build.

### D3a, D3b, D3c: graph script

One PEP 723 file.  Redirect 2 changed its subcommands to `fetch`, `render`, and `block`; the `fetch` contract below is unchanged.  `fetch` takes `--mimir-url`, `--tenant`, `--query`, `--start`, `--end`, `[--step 30s]`, `--node-label`, `[--node VALUE=db0]...`, `--arm`, `--unit`, `[--scale]`, `--name`, `--docs`, and an optional `--proxy socks5h://...` (m6).  It writes `data/<name>.csv` (long form: `timestamp_utc,node,arm,value`) and `data/<name>.json` (`query, start, end, step, unit, scale, arms`).  It never stores the URL or the tenant.  It fails on a connection error, a non-success status, zero series, or an IPv4-looking node value with no `--node` mapping.  The skill derives the Mimir URL and tenant from `$EDB help observability` and `$EDB status`, per DC wrapper, and never reads `state.json`.

~~`plot` takes one or more `--csv`, `--style`, `--title`, `[--stats ...]`, `[--align elapsed]`, and `--docs`.  It writes `images/<name>.png`.  Role colours come from an explicit map keyed by arm name (m5).  Nodes in an arm differ by line style.~~ (superseded by redirect 2)

`block` keeps the rest of the old `plot` contract.  It prints the full evidence block.  The stats table has one row per node plus one rollup row per arm (Node = all), from pooled samples.  The stat menu is samples, min, p50, mean, p95, p99, max, total, and rate.

### D4, D4b: check

`report-check.py` is the mechanical gate and also `make check`.  A general-purpose subagent, with its prompt in the `report.md` "Check" section, reviews the prose.  For a Cassandra run, `cassandra-expert` reviews the reasoning.  When `cassandra-expert` is not installed, the summary carries "Reasoning review: not run (cassandra-expert not installed)" (m8).  `make all` is `check build export`; `make build` stays for debugging.

The comparison row contract: the Metric cell links to an evidence anchor and names the statistic and the unit, for example `[Scrape allocation mean (MB/s)](2-evidence.md#scrape-allocation)`.  The checker follows the anchor to the Data link, then to the CSV and the JSON, recomputes the arm rollups, and recomputes the delta as `(cand - base) / base` in percent.  It uses mdbook's slug rule (lowercase, strip punctuation, spaces to hyphens) and resolves nested `evidence/` paths (m4).  It scans the Query line and the JSON for IPs (m2).

### D5: verdict badge

The verdict is inline HTML, `<span class="verdict verdict-confirmed">Confirmed</span>`, on the Verdict line and in cells.  `lab.css` styles `.verdict` and `.verdict-{confirmed,refuted,inconclusive,partial}`.  `report upload` passes the span through as plain text in Grafana.  The jira filter maps it to a colour.  The checker checks that class and text agree.

### D6: script location

`setup-cluster.sh` writes `EDB_LAB_BIN ?= <absolute plugin bin>` into the Makefile, with `PATH` as the fallback.

### D7: image and CSV upload detection

The `$EDB commands` support check is extended.  Support exists when the `report upload <FILE>` line lists both `.png` and `.csv`.  This needs a wording contract on the unfiled easy-db-lab CLI issue.

### D8a, D8b: tests

A local bash harness, `plugins/easy-db-lab/tests/test-report.sh`, with fixtures under `plugins/easy-db-lab/tests/fixtures/`.  The plugin-level `tests/` is tracked; the repo `.gitignore` ignores only the root `/tests`.  Coverage: scaffold through a stub binary; `make` on the scaffold and on a fixture tree (title, index is the summary, Appendix in the table of contents, `lab.css` link and rules, `unzip -l`, jira grep); ~~a plot pixel check for grey and blue~~ (superseded by redirect 2: `render` against a stub Grafana HTTP server that returns a PNG, an error status, an empty body, and a body that is not a PNG, and against `127.0.0.1:1`; `block` with a CSV and an image); `fetch` against `127.0.0.1:1` and an empty-result stub; check fixtures for agree, wrong sign, wrong size, wrong unit, and redaction.  The wrong-sign fixture uses the `metrics21667` numbers: candidate 32.72 MB/s, baseline 26.92 and 27.27 MB/s, claim -17.2%.  Upload detection uses a stub `$EDB`.  The CSS criteria are checked by rule presence plus one manual visual check.

### Exit rule and check failures (owner decision 2)

The check runs in full at every exit.  There are no relaxed Partial rules.  At a teardown gate a check failure never blocks: the report uploads with a "⚠ Unchecked: <reasons>" Caveats line, the failure goes to `<issues>`, and `down` proceeds.  An interactive run gets one chance to fix first; an unattended run proceeds and reports to the launcher.  At Completion without teardown, a failure blocks the build until it is fixed.  A pause leaves the cluster up, so it needs no special handling.  Partial means the summary was written before every plan step finished.  Explore is never Partial.

### Gate mechanics (addendum F4, F13)

`report-check.py [--gate [--reason TEXT]...] <docs>`.  Exit 0: no failure.  Exit 1: failure.  Exit 2: usage or I/O error.  Exit 3: redaction failure, in either mode.  Without `--gate` it never edits files.  With `--gate`, a non-redaction failure writes or replaces the one "⚠ Unchecked: <reasons>" line under `## Caveats`, merges `--reason` from the subagent and `cassandra-expert`, and exits 0.  A clean `--gate` run removes a stale Unchecked line.  The numeral-in-prose warning ignores the Unchecked line.  The Makefile has `gate: ; $(CHECK) --gate $(REASONS) . && $(MAKE) build export`; `all` is unchanged.

Interactive gate order: write the summary; check (script, subagent, expert); on failure, show the reasons and offer one choice (fix now and re-check once, or proceed unchecked); `make gate`; upload; on upload failure, the existing menu (a retry re-uploads only, with no re-check).  The unattended gate skips the choice.  Unattended Completion with no teardown: on failure, no build and no upload; log; report the reasons to the launcher; the cluster stays up; the later gated teardown applies the Unchecked rule.

### Redaction failure (owner decision B, option a)

A redaction failure (exit 3) blocks the upload but not the `down`.  The report stays local and the failure is logged.  The owner fixes it and uploads later with `run <cluster-dir> --finalize`, which writes, checks, makes, and uploads, with no `down`.  It works for single layouts too.  Unattended runs report "report not uploaded: redaction" to the launcher.

### Noise floor (owner decision 3, column option a)

The Noise floor column stays.  When the run measured noise, the cell holds the value as a link to its evidence block, and the checker recomputes it from that CSV.  Otherwise the cell reads "not measured", and the checker accepts it.  The rule "Confirmed or Refuted needs |delta| > noise floor" applies only when a value is present.

### Cross-cluster arms (owner decision 4 option a, decision A, addendum F1 to F12)

A cross-cluster test has exactly one report.  `setup-cluster.sh <test-dir> <binary> --name <title> --plan <template> --arm <arm>=<plan.md>...` makes a multi-DC-shaped test directory with an `arms` marker (one arm per line).  `--arm` excludes `--dc`.  `<test-dir>/docs/` holds the one report.  `<test-dir>/<arm>/` holds each arm's wrapper.  Each arm's `cluster_name` comes from its plan; `--name` is only the fallback title.  The coordinator runs `setup-cluster.sh` once; arm agents never run it.  `--plan` goes to `docs/3-plan.md`; each `--arm a=p` goes to `docs/3-plan-<a>.md`.  `SUMMARY.md` is generated with an Appendix of Plan, Coordinator journal, Coordinator issues, and then per arm Plan, Journal, and Issues.

`detect-cluster-layout.sh` checks the marker before the wrapper scan and reports `LAYOUT=arms`, `ARMS`, `EDB_<ARM>`, `STATE_<ARM>`, and `STATE` (provisioned if any arm is).  `configure-multi-dc-seeds.sh` exits 1 when the marker exists.

An arm agent runs as `run <test-dir> --arm <arm> [step N]` and binds `$EDB` to `EDB_<ARM>` only.  It writes only `4-journal-<arm>.md`, `5-issues-<arm>.md`, `data/*-<arm>.*`, and (since redirect 2) `images/*-<arm>.png`.  It fetches its own data after each measuring step while its Mimir is up (F2 option a).  Its arm gate uploads `3-plan-<arm>.md`, `4-journal-<arm>.md`, and `5-issues-<arm>.md` through its own wrapper, then runs `down` on its own arm; no summary, check, or make.  Without `--arm`, the skill refuses teardown in arms mode.

The coordinator owns `1-summary.md`, `2-evidence.md`, `4-journal.md`, and `5-issues.md`.  After the last arm reports and the coordinator has rendered the overlay images (see "Redirect 2"), it runs `run <test-dir> --finalize` once, with arms up or down.  Final Finalize builds each evidence block from the CSVs and the images on disk with `block --arm-windows`, writes the summary and evidence, checks with the teardown-gate rules, makes, and uploads through every arm's wrapper.  The upload list is every top-level `.md` that `docs/SUMMARY.md` links, minus scaffold-only files.  Arms still up afterwards are torn down when the coordinator relaunches each arm at Completion / teardown.

`block --arm-windows` (formerly `plot --align elapsed`) keeps each CSV's window and writes one Window line per arm.  The unit and the step must still match, and the queries must match apart from the `cluster` matcher (redirect 1); when they differ there, the block writes one Query line per arm.  Without `--arm-windows`, mismatched windows are an error.  Stats rows are keyed by (arm, node), with labels such as "db0 (baseline)".  A Data line may hold several CSV links; the checker follows all, merges them, and keys by (Node, Arm).

### Redirect 2: Grafana panel renders replace local plotting (owner override of Q8 and the plot half of Q18)

The owner reversed Q8 (plot locally from the CSV) and the matplotlib half of Q18 (a shared `lab.mplstyle` and fixed role colours) at Seam 1: "Let's use the images from Grafana exporter, we don't need to over complicate this.  It'll be consistent with what people see in the UI."  Then: "No more custom rendering, that was a stupid, over complicated idea."  This is an owner override of the architect.  The `lab.css` half of Q18 stays.

Fact: every easy-db-lab cluster's Grafana pod runs a grafana-image-renderer v5.12.4 sidecar (easy-db-lab `GrafanaManifestBuilder.kt:49,199-207,269-271`), so the render API `/render/d-solo/<uid>/` works on every cluster.  Anonymous access worked in a past run (`~/dev/cassandra/clusters/smoke-test/docs/journal.md:61`).  The operator reaches Grafana over Tailscale or the SOCKS tunnel.

The shape the owner settled:

- **Q1 (a).**  Keep `fetch` (Mimir to CSV), the stats table from that CSV, and the checker's recompute.  Remove only matplotlib plotting, `lab.mplstyle`, and the fixed role colours.  The image is a Grafana render of a panel for the same metric and window.
- **Q2 (b).**  A cross-cluster metric gets one combined image.  The last arm stays up until the coordinator renders the overlay panel of a comparison dashboard from that arm's Grafana.  That Grafana reads both clusters from the shared Mimir.  Then that arm tears down.
- **Q3 (a).**  When no overlay panel exists for the metric, each arm renders its own panel from a regular dashboard while it is up.  Each image is labelled by arm.  The stats table stays combined.

The interface:

- `render --grafana-url URL --dashboard UID --panel ID --from TIME --to TIME [--var NAME=VALUE]... [--width 1200] [--height 600] --name NAME --docs DOCS [--proxy socks5h://...] [--timeout 60]` sends one GET to `/render/d-solo/<UID>/?panelId=..&from=..&to=..&var-..=..&width=..&height=..&tz=UTC`.  An ISO time goes out as epoch milliseconds; a Grafana relative time such as `now-93600s` goes out unchanged.  It writes `images/<name>.png` only for a status 200 and a non-empty body with the PNG signature.  Any other result exits non-zero, names the cause, and leaves `images/<name>.png` as it was.  It stores no URL.  It uses `requests[socks]`, the same as `fetch`.
- `block --csv ... --image [ARM=]PATH ... --title .. [--stats ..] [--arm-windows] [--page ..] --docs ..` prints the evidence block from the CSVs and the image paths.  It draws nothing and writes no file.  It checks that each image is a non-empty PNG under `images/`.  `ARM=PATH` puts the arm in the alt text.  `plot` and the matplotlib dependency are removed.
- Timing: `fetch` and `render` run at the same point, after each measuring step, while the cluster is up.  Grafana and Mimir stop with the cluster.  `block` reads files only, so the coordinator can run it at Final Finalize with every arm down.
- Overlay panels: `ab-comparison` and Cassandra Cluster Comparison (`c09599ec-8d87-4fe5-9346-9e85c41d33af`) hold 1001 Throughput, 1002 Read p99, 1003 Write p99, 1004 Error rate, 1005 CPU busy, 1006 Disk I/O, and 1007 GC pause.  `system-ab-comparison` holds 1001 CPU busy, 1002 Memory used, 1003 Disk I/O, and 1004 Network.  Each takes `var-baseline_cluster` and `var-candidate_cluster`.  Each overlay panel sets its own range (`timeFrom` from `max_len`), and shifts each run with a PromQL offset (`base_offset`, `cand_offset`) to a common start.  The panel description says an absolute dashboard range turns the panel's own range off, so the coordinator renders an overlay with a relative range, `--from now-<N>s --to now`, where N runs from the earlier arm's measured start to the render time.  There is no fixed range anywhere (redirect 3, owner: "if it's a 24 hour test, a 1hr time window is useless").  A single-cluster render uses the block's measured window as absolute times.  For an overlay to show the measured windows, the comparison dashboards need optional `base_from`, `base_to`, `cand_from`, and `cand_to` variables (rustyrazorblade/easy-db-lab#1015).  The coordinator detects them in the dashboard JSON (`/api/dashboards/uid/<UID>`) and sets them from each arm's `data/<name>.json`.  Without them, the overlay covers each cluster's whole run, and the summary's Caveats say so.

Hold and release.  The existing rules already give the mechanism.  No agent decides teardown on its own, and an arm runs its gate and `down` only when the coordinator relaunches `run <test-dir> --arm <arm>` at Completion / teardown.  So the coordinator holds the render arm (the last arm still up) by not relaunching it.  After it has rendered every overlay image to `docs/images/`, it relaunches that arm; the relaunch is the release.  It may relaunch the other arms at any time after they report completion.  No new shared state file is needed.  A failed overlay render is logged, gets one retry when interactive, and then the arm is released; the block with no image fails the check, and the teardown-gate rule adds the Unchecked line.

Per-arm fallback.  For a metric with no overlay panel, each arm agent renders its own regular dashboard panel to `images/<metric>-<arm>.png` at the same point as its fetch.  Arm agents now also write `images/*-<arm>.png`; the `-<arm>` suffix keeps the no-two-writers rule.  The coordinator passes those images as `--image <arm>=<path>`.

The check is unchanged.  Its evidence-block rule already needs an image file under `images/` and refuses a linked image, so a Grafana render that was not downloaded fails it.

### File roles (addendum F6)

`report.md` defines `<plan>`, `<journal>`, and `<issues>`.  In a single layout they are `3-plan.md`, `4-journal.md`, and `5-issues.md`.  For an arm agent they are the `-<arm>` names.  `journal.md`, `issues.md`, and `report-upload.md` use the roles.

### Explore scaffold (owner decision 5 option a, addendum F8 to F10)

`setup-cluster.sh <cluster-dir> --docs-only --name <n>` takes no binary and creates no wrapper.  Without `--docs-only`, it never rewrites an existing wrapper, and it refuses a binary whose real path equals a wrapper path it would write.  It exits 1 when `<cluster-dir>/bin/easy-db-lab` exists next to `settings.gradle.kts` or `build.gradle.kts`.  Explore scaffolds at Step 1, after it resolves the binary and passes the guard, and before its first journal write, with `--name "$(basename "$PWD")"`.  Under `--docs-only`, `--dc` per DC is redundant.  `detect-cluster-layout.sh` skips `bin`, which removes the `DCS=bin` special case at `explore/SKILL.md:31`.

### Folded-in debt (owner decision 7)

Scaffold files follow the `<destination>.template` rule.  `book.toml` becomes a static template.  Reporting rules move from `run/SKILL.md` into `references/report.md`, and the stale "step 66 above" at `run/SKILL.md:135` is fixed.  The README stops advertising the unshipped operator agent.

## Risks / Trade-offs

- [The teardown gate now runs Finalize (write, check, make, upload) at every exit.] → The owner settled the failure rule in decision 2: a check failure never blocks the `down`.
- [Nested evidence pages are not uploaded by the single-layout run skill, and images are broken in Grafana until the CLI supports them.] → The support check (D7) adds images and CSV when the CLI supports them.  The full report stays in `report/` and `export/report.zip`.
- [Cross-cluster: which workspace holds the comparison summary was unstated.] → Owner decision 4: one test directory; the coordinator writes the summary.
- [Explore provisions without `setup-cluster.sh`, so `docs/` may lack the scaffold.] → Owner decision 5: explore runs `setup-cluster.sh --docs-only` when `docs/SUMMARY.md` is absent.
- [The first `make` needs network access for uv to fetch pypandoc-binary.  The graph script needs `requests[socks]` the first time it runs.] → Accepted.  uv caches the packages after the first run.
- [An overlay panel covers each cluster's whole `up` period within the dashboard's Lookback, not only the measured window of the block.] → Redirect 3, owner decision (a): the comparison dashboards get optional window variables (rustyrazorblade/easy-db-lab#1015), and the coordinator sets them to the measured windows.  Until that ships, the overlay falls back to the whole run, and a Caveats line says so.  Rejected: (b) override the existing computed variables (`base_start`, `base_end`) through `var-` URL parameters, because Grafana may recompute query variables on load and ignore the override; (c) keep the whole-run overlay with no fix.
- [The render arm stays up a little longer, for the overlay renders.] → Accepted by Q2 (b).  A failed render releases the arm after one retry, so a render problem never keeps a cluster up.
- [A render needs Grafana anonymous access and the renderer sidecar.] → Both exist on every cluster today.  A failure is logged and the missing image fails the check, the same as a failed fetch.
- [The image and the stats table come from different code paths, so they can disagree if the writer picks the wrong panel.] → The writer picks the panel per `report.md`, and the block holds the Query next to the image.  The numbers that the checker trusts come from the CSV only.
- [`src = "."` copies `data/`, `export/`, the Makefile, and the style into `report/`.] → Accepted; verified harmless.
- [A pause writes a Partial summary, which makes it non-scaffold, so it uploads later.] → Intended.
- [No migration; old workspaces break on resume.] → Accepted by scope.
- [An arm must fetch before its own `down`; a missed fetch is permanent.] → The missing evidence fails the check, and the teardown-gate rule adds an Unchecked line.
- [An arm's teardown upload after the coordinator's full upload replaces only that arm's appendix files; the coordinator's copy of the arm journals is stale until then.] → The index keeps the rest (verified).
- [`--gate` edits `1-summary.md` after the check subagent reviewed it.] → The edit is limited to the one Unchecked line under Caveats, and the numeral-in-prose warning ignores it.
- [The arms marker is a new contract shared by three scripts.] → The test harness covers all three.
- [The D7 wording contract depends on an unfiled CLI change.] → Stub-only tests until then.

## Alternatives Considered

Each entry gives the option and why it was rejected.  "Owner override" marks a place where the owner did not take the architect's recommendation, or set a rule the architect did not propose.

### Architect options (design)

- **D1 alt: sed rewrites `book.toml` before the build.**  Rejected: it leaves a dirty tree.
- **D1 alt: the skill writes the title into `book.toml`.**  Rejected: it depends on the agent, and the criterion says the title comes "at make time".
- **D2a alt: a markdown-it-py converter of about 150 lines.**  Rejected: no download, but the plugin owns every edge case.  The architect noted it is the pick if offline builds matter more.
- **D2a alt: require system pandoc.**  Rejected: it needs a system install; pypandoc-binary needs none.
- **D2b alt: zip all of `images/` and `data/`.**  Rejected: it leaks appendix Grafana renders.
- **D2b alt: an `images/appendix/` convention.**  Rejected: fragile.
- **D3a alt: two scripts.**  Rejected: they duplicate the contract.
- **D3a alt: one all-in-one command.**  Rejected: not testable without a cluster.
- **D3b alt: shell out to `$EDB` and parse `status`.**  Rejected: fragile.
- **D3b alt: copy the `env.sh` / `state.json` approach.**  Rejected: it violates the never-read-`state.json` rule.
- **D3c alt: arm rollups as the mean of node means.**  Rejected: it differs from pooled samples for percentiles.
- **D4 alt: a new `agents/report-checker.md`.**  Rejected: the Codex manifest ships only skills; YAGNI.
- **D4 alt: subagent only, no script.**  Rejected: the sign, size, and unit criteria are not reliably testable.
- **D4b alt: the skill runs the check, and `make` only builds.**  Rejected: the owner accepted the recommendation (`all: check build export`) in decision 1.  The inputs state no further reason.
- **D5 alt: `additional-js` that adds classes.**  Rejected: it needs a headless browser to test, and print depends on JS.
- **D5 alt: an mdbook preprocessor.**  Rejected: the architect added no preprocessor; the inputs state no further reason.  CSS alone cannot select on text, so a CSS-only option does not exist.
- **D6 alt: `PATH` only.**  Rejected: it breaks a human who runs `make` outside Claude.
- **D6 alt: copy the scripts into `docs/`.**  Rejected: mdbook copies them into `report/`.
- **D7 alt: probe with an image-only upload and parse the rejection.**  Rejected: hard to tell from an SSO failure.
- **D7 alt: wait for `commands --json`.**  Rejected: that CLI change is out of scope.
- **D8a alt: also a GitHub Actions workflow.**  Rejected: no test CI exists today; filed separately as issue 100 (owner decision 7).
- **D8b alt: headless Chrome for the CSS criteria.**  Rejected: the owner accepted rule presence plus one manual visual check (decision 1).

### Architect options (addendum)

- **Final Finalize check rule (b): Completion rules, where a failure blocks the build.**  Rejected: it risks never uploading.  The owner chose (a), teardown-gate rules, because evidence cannot be re-measured (decision 10).
- **Arm gate alt: the arm uploads nothing at its gate.**  Rejected: the journals are not in S3 if the coordinator dies, and it weakens "every down is gated" (`run/SKILL.md:90`).
- **Explore title prompt: ask the user for a title.**  Rejected: the architect did not recommend it, and the owner chose the directory basename as the fallback title (decision 10).
- **Redaction blocks the `down` (keep the cluster up and report).**  Rejected: the owner chose decision B option (a); the report stays local, and upload works after `down`.

### Owner decisions

- **Decision 2 (M1), check failure at a teardown gate.**  The owner chose (b): the check runs in full at every exit, and at a gate a failure never blocks.  Rejected:
  - (a) A check failure at the gate keeps the cluster up until it is fixed.  This is the architect's original proposal (an unattended gate treats a check failure like an upload failure).  Rejected because a writing problem must not keep a cluster up and costing money.  Owner override of the architect.
  - An earlier form of (b) relaxed some check rules for a Partial verdict.  Rejected once the owner asked what a partial exit is: a Partial run with no measured rows passes the check anyway, so no special rules are needed.
  - (c) The gate behaviour of (b) with no relaxed rules, so a Partial report always shows an Unchecked caveat.  Superseded by the same finding.
- **Decision 3 (M2), the noise-floor source.**  The owner removed calibration from this issue: "we are not doing calibration here; that will be added later."  Rejected: making every A/B calibrate; using the window-to-window spread of the measured run; a writer-supplied value with a source note.  Owner override: the run skill and the issue's first criterion tied the column to a calibration spread.  For the column itself the owner chose (a), keep it, with "not measured" as a valid value.  Rejected:
  - (b) "not measured" caps the verdict at Inconclusive.  Rejected because almost every single-cluster A/B would be Inconclusive until the calibration work lands.
  - (c) Drop the column until the calibration work lands.  Rejected because it changes the summary layout the owner chose.
- **Decision 4 (M3), the cross-cluster report.**  The owner set the rule that a cross-cluster test has exactly one report.  Owner override.  This ruled out a per-arm report for each arm with the comparison left to a later issue.  The owner chose (a), a multi-DC-shaped test directory.  Rejected:
  - (b) Separate workspaces per arm plus a coordinator workspace that copies the arms' CSVs in.  Rejected: more copying, and the arms' trees would hold journals that are never uploaded as reports.
  - (c) Arm A's workspace holds the report, and the coordinator copies arm B's data into it.  Rejected: it breaks the "never write a sibling's workspace" rule.
- **Decision 5 (M4), the explore scaffold.**  The owner chose (a): explore runs `setup-cluster.sh` when `docs/SUMMARY.md` is absent.  Rejected:
  - (b) Explore writes markdown tier files with no mdbook, check, or exports.  Rejected: it breaks the check rule for every explore session.
  - (c) Drop the explore criteria from this issue.  Rejected: the owner wants explore to write the same report.
- **Decision A, split the cross-cluster report into its own issue.**  Recommended by the issue-manager, because it roughly doubles the issue.  Rejected: the owner kept it in this issue (option a).  Owner override of the recommendation.  The spec resolves critic findings 1, 2, 5, 6, 7, 11, and 12.
- **Decision B, redaction at a teardown gate.**  The owner chose (a): a redaction failure blocks the upload but not the `down`.  Rejected:
  - (b) A redaction failure blocks both the upload and the `down`.  Rejected: a writing problem must not keep a cluster up, and the upload works after `down`.
  - (c) No exemption, so the report uploads with the identifier in it.  Rejected: it breaks the redaction criterion.

### Redirect 2 (Grafana panel renders)

- **The original design: plot the CSV locally with matplotlib, a shared `lab.mplstyle`, and fixed role colours (Q8, plot half of Q18).**  Rejected by the owner at Seam 1 as over-complicated custom rendering.  A Grafana render is also what readers see in the UI.  Owner override of the architect.
- **Q1 (b): take the stats from the Grafana panel data instead of the Mimir CSV.**  Rejected: the checker's recompute needs a CSV it can read with no network, and the panel data has no stable format to recompute from.
- **Q1 (c): the writer copies the numbers by hand from the Grafana panel.**  Rejected: this brings back the `metrics21667` failure, where the prose and the numbers disagreed, and the checker has nothing to recompute.
- **Q2 (a): one render per arm always, and no combined image.**  Rejected: the reader must compare two images by eye, and the comparison dashboards already put both runs on one axis from a common start.
- **Q3 (b): restrict cross-cluster claims to metrics that have an overlay panel.**  Rejected: it limits what a test can measure to the panels that exist today.
- **Q3 (c): add an overlay panel to a dashboard during the run.**  Rejected: it changes a shared dashboard during a test, and a hand-made panel is custom rendering again.

## Migration Plan

No migration.  Old workspaces are not supported.  The change requires `issue-96` to be archived first, because it modifies `issue-96`'s `easy-db-lab-report-upload` requirements.  Rollback is a revert of the change.

## Open Questions

None.  The owner settled decisions 1 to 10.
