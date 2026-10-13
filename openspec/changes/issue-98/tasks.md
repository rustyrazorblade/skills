All paths are under `plugins/easy-db-lab/` unless stated.  Write each test before the code it tests.

## 1. Test harness and fixtures (first)

- [x] 1.1 Create `tests/test-report.sh`: a bash harness that runs every case, prints PASS or FAIL per case, and exits 0 only when every case passes.  It needs `mdbook` and `uv` and no cluster.
- [x] 1.2 Add a stub easy-db-lab binary under `tests/fixtures/bin/` for scaffold and upload-detection cases.  Add two stub `commands` outputs: one whose `report upload <FILE>` line lists `.md` only, one that lists `.png` and `.csv`.
- [x] 1.3 Add a fixture docs tree `tests/fixtures/docs-agree/` with an A/B summary, an evidence block, a nested `evidence/` page with a "(MB/s)" heading, a PNG, CSV, and JSON, where every claim agrees.
- [x] 1.4 Add the wrong-sign fixture from `metrics21667`: candidate 32.72 MB/s, baselines 26.92 and 27.27 MB/s, summary claims -17.2%.
- [x] 1.5 Add wrong-size, wrong-unit, "not measured" noise floor, Confirmed-inside-noise, bad verdict value, verdict class/text mismatch, incomplete evidence block, Grafana link, placeholder title, and numeral-in-prose fixtures.
- [x] 1.6 Add Cassandra-run fixtures: "Reasoning review: done", "Reasoning review: not run (cassandra-expert not installed)", and one with no Reasoning review line.
- [x] 1.7 Add redaction fixtures: an IPv4 in the summary, a 12-digit account ID, `vpc-`/`subnet-`/`sg-` IDs, tunnel wording, an IP in a Query line, and an IP in a `data/*.json`.
- [x] 1.8 Add arms fixtures: one CSV per arm with different windows and the same query, unit, and step, and a Data line with several CSV links.
- [x] 1.9 Add graph fixtures: a baseline and candidate CSV, an empty CSV, and CSVs with mismatched metadata.  Add an empty-result Mimir stub (a local HTTP server that returns success with zero series).

## 2. Scaffold templates

- [x] 2.1 Write harness cases for the scaffold: the five tier files, `SUMMARY.md`, `Makefile`, `book.toml`, `lab.css`, `lab.mplstyle`, `images/`, `data/`; no `results.md`; `--plan` to `docs/3-plan.md`; copy-if-absent for tier files; every scaffold file named `<destination>.template`.
- [x] 2.2 Create `scaffold/1-summary.md.template`, `2-evidence.md.template` (with `## Threats to validity`), `3-plan.md.template`, `4-journal.md.template`, and `5-issues.md.template`.  Each holds only headings and `<!-- -->` comments.
- [x] 2.3 Create `scaffold/SUMMARY.md.template`: `[Summary](1-summary.md)`, `- [Evidence](2-evidence.md)`, `# Appendix`, then Plan, Journal, Issues.
- [x] 2.4 Create the static `scaffold/book.toml.template` with `title = "@CLUSTER_NAME@"`, `src = "."`, `build-dir = "report"`, `[output.html] additional-css = ["lab.css"]`, and `no-section-label = true`.
- [x] 2.5 Create `scaffold/lab.css.template`: sticky `thead th`, zebra rows, `.verdict` and `.verdict-{confirmed,refuted,inconclusive,partial}` badges, wider `--content-max-width`, and `@media print`.
- [x] 2.6 Create `scaffold/lab.mplstyle.template`.  Check for the `dataviz` skill palette first; else use Okabe-Ito and name the source in a comment.  Set fonts and sizes.
- [x] 2.7 Create `scaffold/Makefile.template` with `EDB_LAB_BIN ?= @EDB_LAB_BIN@`, the `MDBOOK_BOOK__TITLE` export only when the `1-summary.md` H1 is not empty, and the targets `all: check build export`, `build`, `check`, `export`, `gate`, `serve`, and `clean`.
- [x] 2.8 Delete `scaffold/results.md`, `scaffold/journal.md`, `scaffold/issues.md`, `scaffold/SUMMARY.md`, and `scaffold/Makefile`.

## 3. setup-cluster, detect-layout, seeds

- [ ] 3.1 Write harness cases for `--docs-only` (no binary, no wrapper), an existing wrapper kept, a binary whose real path is a wrapper path, the source-checkout guard (exit 1), `--arm` with `--dc` (usage error), and the arms scaffold (marker, per-arm wrappers, `3-plan-<arm>.md`, per-arm journal and issues, generated `SUMMARY.md` Appendix).
- [x] 3.2 Change `bin/setup-cluster.sh`: copy each `*.template` to its destination (tier files copy-if-absent), sed `@CLUSTER_NAME@` and `@EDB_LAB_BIN@`, create `docs/images` and `docs/data`, copy `--plan` to `docs/3-plan.md`, remove the `book.toml` heredoc, and update the header comment.
- [ ] 3.3 Add `--docs-only`, the never-rewrite-a-wrapper rule, the binary self-check, and the source-checkout guard to `setup-cluster.sh`.
- [ ] 3.4 Add `--arm <arm>=<plan.md>` to `setup-cluster.sh`: the `arms` marker, one wrapper per arm, per-arm plan, journal, and issues files, and the generated Appendix.  Reject `--arm` with `--dc`.
- [ ] 3.5 Write harness cases for `detect-cluster-layout.sh`: `LAYOUT=arms` with `ARMS`, `EDB_<ARM>`, `STATE_<ARM>`, and `STATE`; `bin` skipped like `docs`.  Then change the script.
- [ ] 3.6 Write a harness case for `configure-multi-dc-seeds.sh` exiting 1 with an `arms` marker.  Then add the guard.

## 4. Scripts: graph, check, export

- [ ] 4.1 Write harness cases for `report-graph.py fetch`: `127.0.0.1:1` exits non-zero with a clear message and no CSV; the empty-result stub exits non-zero; an unmapped IPv4 node value is refused; the JSON holds no URL or tenant.
- [ ] 4.2 Write harness cases for `report-graph.py plot`: PNG written with the shared style; a pixel check finds grey `#999999` and blue `#0072B2`; empty input exits non-zero with no PNG; mismatched metadata is an error; mismatched windows without `--align` are an error; `--align elapsed` writes one Window line per arm; the stats table uses `--:` alignment and per-arm rollup rows.
- [ ] 4.3 Implement `bin/report-graph.py` (PEP 723, `fetch` and `plot`) in the pattern of `plugins/cassandra-expert/skills/training/scripts/verify-sai-capabilities.py`, until 4.1 and 4.2 pass.
- [ ] 4.4 Write harness cases for `report-check.py` over every fixture from group 1: exit 0 for agree, 1 for each content FAIL, 3 for each redaction FAIL, 2 for a bad path; WARN for numeral in prose; `--gate` writes one Unchecked line and exits 0; a clean `--gate` removes a stale line; no file edit without `--gate`; nested page and slug resolution; multi-link Data merge keyed by (Node, Arm).
- [ ] 4.5 Implement `bin/report-check.py` (PEP 723, files only, no network) until 4.4 passes.
- [ ] 4.6 Write harness cases for `report-export.py`: `jira` holds the summary tier in wiki markup, images as `!name.png!`, no `.md` links, verdict colour; `zip` lists the summary, evidence, nested pages, and their images and CSV, and no appendix file; a missing referenced file fails.
- [ ] 4.7 Implement `bin/report-export.py` (PEP 723, `pypandoc-binary`, `jira` and `zip`) until 4.6 passes.

## 5. Makefile and book

- [ ] 5.1 Write harness cases for `make` on the scaffold and on `docs-agree`: `report/index.html` is the summary; the sidebar shows Evidence, nested pages, and an Appendix with Plan, Journal, and Issues; the title is the summary H1; an empty H1 falls back; `lab.css` is linked and holds the sticky, zebra, badge, width, and print rules; all three outputs exist; `make` works with `EDB_LAB_BIN` and no plugin `bin/` on `PATH`; `make gate` runs.
- [ ] 5.2 Fix the Makefile template until 5.1 passes.
- [ ] 5.3 Do one manual visual check of a built evidence page (right-aligned numbers, sticky header, zebra rows, verdict badge, print preview) and record the result in the PR.

## 6. Shared reference: references/report.md

- [ ] 6.1 Create `references/report.md` with tier contents, the fixed summary layout, the comparison row contract, the Noise floor rule, the evidence block format and default stats columns, Threats to validity, the STE prose rules, redaction (select nodes by host name, never by IP; branch names and unreleased bugs are the owner's call), file roles, and the exit rule with the Partial definition.
- [ ] 6.2 Add the "Check" section: the script, the check subagent prompt, the `cassandra-expert` reasoning review and the not-installed line, the gate order (F13), the check-failure rule (decision 2), the redaction rule (decision B), and `run <cluster-dir> --finalize`.
- [ ] 6.3 Add the graph section: how to derive the Mimir URL and tenant per wrapper from `$EDB help observability` and `$EDB status`, `--proxy`, and how a failed fetch is logged.
- [ ] 6.4 Add the arms section: write ownership, per-arm fetch, the arm gate, Final Finalize with the teardown-gate check rules, and `plot --align elapsed`.

## 7. Skill edits: run, explore, plan

- [ ] 7.1 `skills/run/SKILL.md`: rename every tier file reference, including resume detection at line 104 (`docs/3-plan.md`).  Fix "step 66 above" at line 135.
- [ ] 7.2 `skills/run/SKILL.md`: replace the screenshot instruction at line 257 with "run `report-graph.py` and append the evidence block per `report.md`".  Replace Completion steps 1-2 (lines 263-291) with "Finalize the report per `report.md`".  Make the pause exit (lines 328-332) write a Partial summary.  Point Team Agents (line 384) to the reasoning review in `report.md`.
- [ ] 7.3 `skills/run/SKILL.md`: add the `--arm <arm>` and `--finalize` modes, the arms resume from `docs/3-plan-<arm>.md`, and the refusal of teardown without `--arm` in arms mode.  Rewrite "Parallel arms" (lines 369-375) per addendum F12.  Keep the calibration rule at line 374 unchanged.
- [ ] 7.4 `skills/explore/SKILL.md`: load `report.md`; at Step 1, after the binary and the source-checkout guard, run `setup-cluster.sh "$PWD" --docs-only --name "$(basename "$PWD")"` when `docs/SUMMARY.md` is absent; remove the `DCS=bin` special case at line 31; at Teardown (line 132), run Finalize first with a verdict and a Findings table, and use the every-tier-file scaffold-only exclusion.
- [ ] 7.5 `skills/plan/SKILL.md`: lines 235-240 describe the tiered report and point to `report.md`; drop "Performance Results" and screenshots; lines 18-23 `--previous` reads `1-summary.md`, `4-journal.md`, and `5-issues.md`.

## 8. References and README

- [ ] 8.1 `references/report-upload.md`: support check adds the `.png`/`.csv` probe (lines 7-19); "the fixed four" becomes the five tier files with the scaffold-only carve-out (lines 25-37); the explore exclusion covers every tier file (lines 39-46); the teardown gate starts with Finalize and `make gate` (lines 60-70); roles replace file names (lines 54-58); add the Arms section.
- [ ] 8.2 `references/journal.md`: use `<journal>`; replace "Grafana Screenshots" (line 64) with the evidence-tier rule; Grafana renders are optional, appendix only, downloaded and never linked.
- [ ] 8.3 `references/issues.md`: use `<issues>`; tool friction lives only here; result-affecting issues also go to Threats to validity.
- [ ] 8.4 `references/cassandra.md`: Multi-DC Setup states that it applies to `LAYOUT=multi` only.
- [ ] 8.5 Repo `README.md` line 165: stop advertising the "easy-db-lab operator" agent.
- [ ] 8.6 Add a harness case that greps `skills/plan/SKILL.md`, `skills/run/SKILL.md`, `skills/explore/SKILL.md`, `references/report-upload.md`, and `references/journal.md` for `results.md` and the old file names, and the README for "easy-db-lab operator".

## 9. Version bump

- [ ] 9.1 Bump the version from 0.13.0 to 0.14.0, as the owner confirmed in the issue's owner-instruction comment.  Update `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` together.

## 10. End-to-end test on a real cluster (under the gitignored root `tests/`)

- [ ] 10.1 Run `tests/test-report.sh` and confirm every case passes.
- [ ] 10.2 Write a short A/B plan at the repo root `tests/plans/report-ab.md`.  Run it with the run skill to Completion in `tests/clusters/<timestamp>/`.  Confirm: a summary with a verdict and a filled comparison table, at least one evidence block whose PNG and CSV came from Mimir, a passing check, a good `make` with all three outputs, and an upload of the five files that the Grafana Tests index shows in the order 1 to 5.
- [ ] 10.3 Run a short plan, stop after step 2, and go through the teardown gate.  Confirm the uploaded `1-summary.md` holds "Partial: stopped after step 2".
- [ ] 10.4 Run an explore session in an empty directory.  Confirm it scaffolds with `--docs-only` before its first report write, and that at teardown `1-summary.md` holds a verdict and a Findings table.
- [ ] 10.5 Run a two-arm cross-cluster test with `--arm`.  Confirm one report under `<test-dir>/docs/`, one journal and one issues file per arm, the arm gates, the coordinator's `--finalize`, and the upload through every arm's wrapper.
- [ ] 10.6 Search the produced summary and evidence tiers for account IDs, VPC IDs, IPs, tunnel details, tool friction, and Grafana links.  Confirm none are found.
