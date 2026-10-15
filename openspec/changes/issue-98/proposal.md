## Why

The lab report does not serve its readers: customers, JIRA reviewers (Cassandra committers), and the owner later on.  A check of 8 real workspaces (`~/dev/cassandra/clusters/*/docs`) found these failures:

- 3 of 8 uploaded an empty `results.md` scaffold.  The run skill writes results only at Completion step 1, so early stops, explorations, and gated teardowns upload a blank page.
- No report puts the verdict first.  The A/B reports show no noise floor.
- In `metrics21667`, the prose says the opposite of its own table.  The prose says the canary "allocates 17.2% less".  The table shows the canary at 32.72 MB/s, and stock at 26.92 and 27.27 MB/s.
- Only 1 of 8 has graphs.
- Tool friction appears on the customer-facing page.
- Each report has different table columns.  Wiki markup and zip files are made by hand.  The theme is the mdbook default, and the title is the cluster slug.

A reader cannot trust or reuse the result without reading the journal.  This change gives the report a fixed, tiered shape, a mechanical check of its claims, downloaded graphs, and generated exports.  It writes the summary at every exit, so no upload is blank.

## What Changes

All paths are under `plugins/easy-db-lab/` unless stated.

- **Scaffold (new templates, old files deleted).**  `scaffold/` holds `1-summary.md.template`, `2-evidence.md.template` (with `## Threats to validity`), `3-plan.md.template`, `4-journal.md.template`, `5-issues.md.template`, `SUMMARY.md.template`, `book.toml.template` (static, with `additional-css`), `lab.css.template` (house theme), and `Makefile.template`.  **BREAKING:** `scaffold/results.md`, `journal.md`, `issues.md`, `SUMMARY.md`, and `Makefile` are deleted.  Redirect 2 also deletes `scaffold/lab.mplstyle.template`, which an earlier step of this change added.  Old workspaces are not supported.
- **`bin/setup-cluster.sh` (modified).**  It copies each template to its destination, creates `docs/images/` and `docs/data/`, and copies `--plan` to `docs/3-plan.md`.  The `book.toml` heredoc goes away.  New flags: `--arm <arm>=<plan.md>` (cross-cluster arms layout, writes the `<test-dir>/arms` marker, excludes `--dc`) and `--docs-only` (scaffold only, no binary, no wrapper).  It never rewrites an existing wrapper.  It refuses a binary whose real path is a wrapper it would write, and it refuses a directory that is an easy-db-lab source checkout.
- **`bin/detect-cluster-layout.sh` (modified).**  It reports `LAYOUT=arms`, `ARMS`, `EDB_<ARM>`, and `STATE_<ARM>` when the `arms` marker exists.  It skips `bin` like `docs`.
- **`bin/configure-multi-dc-seeds.sh` (modified).**  It exits 1 when `<cluster-dir>/arms` exists.
- **`bin/report-graph.py` (new, PEP 723).**  `fetch` queries Mimir `query_range` and writes `docs/data/<name>.csv` and `.json`.  `render` downloads a Grafana panel render (`/render/d-solo/<uid>/`, through the grafana-image-renderer sidecar on every cluster) to `docs/images/<name>.png`, and fails with no image on an unreachable Grafana, a non-200 status, or a body that is not a PNG.  `block` prints the evidence block from the CSVs and the rendered images; it draws nothing.  `--arm-windows` gives one Window line per arm.  The script does not use matplotlib (redirect 2: the owner rejected custom rendering).
- **`bin/report-check.py` (new, PEP 723).**  It checks summary claims against evidence blocks and CSVs (sign, size, unit, noise floor, verdict), the evidence block format, the Reasoning review line, Grafana links, and secrets.  `--gate` writes the "⚠ Unchecked: <reasons>" Caveats line.  Exit 3 means a secret in the customer tiers or `data/` (redirect 7).  An S3 bucket name there is a WARN.  IP addresses, AWS resource IDs, account IDs, paths, and other infrastructure identifiers are not findings.
- **`bin/report-export.py` (new, PEP 723).**  `jira` writes `export/jira.txt` (summary tier in Atlassian wiki markup through pandoc).  `zip` writes `export/report.zip`: the themed HTML book of every page, the appendix included, with every image (redirect 4).  It is built from a staged copy in which secrets and S3 bucket names are replaced by kind placeholders, and `$EDB`, `${EDB}`, and `$EDB_<ARM>` become `easy-db-lab`.  Redaction is best effort: a leftover is a warning that names the kind, the file, and the line, and does not fail the build (redirect 7).
- **Cross-cluster images (redirect 2).**  A metric with an overlay panel in a comparison dashboard (`ab-comparison`, Cassandra Cluster Comparison, `system-ab-comparison`) gets one combined render from the last arm still up.  The coordinator holds that arm by not relaunching it for teardown until the overlay renders are on disk, then relaunches it.  A metric with no overlay panel gets one render per arm, from a regular dashboard, labelled by arm.  The stats table stays combined from both CSVs.
- **`references/report.md` (new).**  One shared reference that the run and explore skills load.  It holds the tier contents, the fixed summary layout, the Noise floor rule, the evidence block format, the prose rules, redaction, the exit rule, the check step, file roles, and the arms rules.
- **`skills/run/SKILL.md` (modified).**  Reporting rules move out of the execution loop, Completion, and Team Agents into `report.md`.  The stale "step 66 above" at line 135 is fixed.  The pause exit writes a Partial summary.  New modes: `run <test-dir> --arm <arm>` and `run <cluster-dir> --finalize`.  "Parallel arms" (lines 369-375) is rewritten to one test directory and one report.  The calibration rule at line 374 is unchanged.
- **`skills/explore/SKILL.md` (modified).**  It loads `report.md`.  At Step 1 it runs `setup-cluster.sh "$PWD" --docs-only --name "$(basename "$PWD")"` when `docs/SUMMARY.md` is absent.  It refuses a source checkout.  At Teardown it writes `1-summary.md` with a verdict and a Findings table first.
- **`skills/plan/SKILL.md` (modified).**  It describes the tiered report and points to `report.md`.  `--previous` reads `1-summary.md`, `4-journal.md`, and `5-issues.md`.
- **`references/report-upload.md` (modified).**  The run skill uploads the five tier files.  The scaffold-only exclusion covers every tier file.  The support check also detects image and CSV support.  The teardown gate runs Finalize first.  An Arms section holds the arm gate and the final upload.
- **`references/journal.md`, `references/issues.md` (modified).**  They use file roles (`<journal>`, `<issues>`).  The Grafana screenshot section is replaced: measurements go to the evidence tier through `report-graph.py`.  Tool friction lives only in `<issues>`.
- **`references/cassandra.md` (modified).**  Multi-DC Setup states that it applies to `LAYOUT=multi` only.
- **Repo `README.md` (modified).**  Line 165 stops advertising the "easy-db-lab operator" agent, which the plugin does not ship.
- **Version.**  `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` go from 0.13.0 to 0.14.0.
- **`tests/test-report.sh` and `tests/fixtures/` (new).**  A local harness that runs every no-cluster acceptance criterion.

User-visible behavior: every upload holds a summary with a verdict first.  Every summary claim traces to a downloaded Grafana panel render, a stats table, and a CSV.  `make` produces `report/index.html`, `export/jira.txt`, and `export/report.zip`.  A cross-cluster A/B produces one report.

## Capabilities

### New Capabilities

- `easy-db-lab-lab-report`: the tiered report scaffold and layout, the book title and theme, the summary layout, the Noise floor rule, the evidence block, prose and redaction rules, the exit rule, the graph, check, and export scripts, the `make` targets, the explore scaffold, and the cross-cluster arms layout.

### Modified Capabilities

- `easy-db-lab-report-upload` (in-flight delta from `issue-96`, not yet archived): the upload file list (five tier files, file roles), the scaffold-only exclusion for every tier file, Finalize before every gated upload, check-failure and redaction handling at the gate, image and CSV detection, and arms uploads.

## Impact

- New Python scripts run through `uv` with PEP 723 metadata.  The first `make` needs network access to fetch pypandoc-binary.
- Existing workspaces with `results.md` break on resume.  This is accepted.  Tests are ephemeral.
- `report upload` accepts `.md` only today, so images and CSV are not uploaded until the CLI supports them (separate easy-db-lab issue).
- The arms marker is a new contract shared by `setup-cluster.sh`, `detect-cluster-layout.sh`, and `configure-multi-dc-seeds.sh`.
- `issue-96` must be archived before this change, because this change modifies its requirements.
