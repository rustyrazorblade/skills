# Acceptance-criteria coverage: issue-98

Spec files: `L` = `specs/easy-db-lab-lab-report/spec.md`, `U` = `specs/easy-db-lab-report-upload/spec.md`.

| Source | Requirement | Covering scenario(s) | Status |
|---|---|---|---|
| AC: Scaffold | `setup-cluster.sh` scaffolds five tier files, `SUMMARY.md`, `Makefile`, `book.toml`, CSS, style, `images/`, `data/`; no `results.md` | L: "A new workspace gets the tier scaffold" | ✅ Covered |
| AC: Scaffold | `--plan` is copied to `docs/3-plan.md` | L: "The plan is copied to the plan tier" | ✅ Covered |
| AC: Scaffold | `book.toml` references the house CSS through `additional-css` | L: "book.toml wires the house CSS" | ✅ Covered |
| AC: Scaffold | `make` title is the summary's plain-words title, not the cluster slug | L: "The title is the plain-words title" | ✅ Covered |
| AC: Scaffold | `report/index.html` is the summary; sidebar shows Evidence, nested pages, then Appendix with Plan, Journal, Issues | L: "The built book opens on the summary", "Nested evidence pages sit under Evidence" | ✅ Covered |
| AC: Scaffold | Stats table: right-aligned numeric columns, sticky headers, zebra rows | L: "Stats tables are readable" | ✅ Covered |
| AC: Scaffold | A verdict value renders as a badge in its colour | L: "A verdict renders as a badge" | ✅ Covered |
| AC: Scaffold | Printing uses the print styles | L: "Printing uses the print styles" | ✅ Covered |
| AC: Exports | `make` on a sample tree produces `export/jira.txt` and `export/report.zip` | L: "make produces the exports" | ✅ Covered |
| AC: Exports | `jira.txt` holds the summary tier in wiki markup; images by file name | L: "jira.txt holds the summary tier" | ✅ Covered |
| AC: Exports | `report.zip` holds summary, evidence, nested pages, images, CSV; no plan, journal, issues | L: "report.zip holds only the customer tiers" | ✅ Covered |
| AC: Graph | CSV fixture through uv gives a PNG in `docs/images/` with the shared style | L: "A CSV fixture becomes a styled PNG" | ✅ Covered |
| AC: Graph | Baseline and candidate arms get their fixed role colours | L: "Each arm gets its role colour", "Role colours are fixed" | ✅ Covered |
| AC: Graph | Mimir unreachable or no series: non-zero exit, clear message, no empty PNG | L: "Mimir is unreachable", "The query returns no series", "Empty input writes no PNG" | ✅ Covered |
| AC: Check | Wrong sign against the CSV (`metrics21667`) is flagged before `make` | L: "Wrong sign (the metrics21667 pattern)" | ✅ Covered |
| AC: Check | Wrong size or wrong unit is flagged before `make` | L: "Wrong size", "Wrong unit" | ✅ Covered |
| AC: Check | Summary and evidence agree: check passes and `make` proceeds | L: "Summary and evidence agree" | ✅ Covered |
| AC: Check | Cassandra run with no `cassandra-expert` reads "Reasoning review: not run (cassandra-expert not installed)" | L: "Cassandra expert is not installed" | ✅ Covered |
| AC: Check | Cassandra summary with no "Reasoning review" line fails the check | L: "A Cassandra summary without the line fails" | ✅ Covered |
| AC: Check | Check fails at a teardown gate: upload with "⚠ Unchecked" Caveats line, failure in issues, `down` runs | L: "Check failure at a teardown gate"; U: "Check failure does not block the down" | ✅ Covered |
| AC: Check | Redaction fails at a teardown gate: nothing uploaded, failure logged, `down` runs | L: "Redaction failure at a teardown gate"; U: "Redaction failure skips the upload" | ✅ Covered |
| AC: Check | Owner fixes and runs `run <cluster-dir> --finalize`: upload with no `down` | L: "The owner uploads after the fix" | ✅ Covered |
| AC: Exit | Stop after step 2 through the gate: uploaded summary holds "Partial: stopped after step 2" and one sentence | L: "Stop after step 2 at the teardown gate" | ✅ Covered |
| AC: Exit | Pause writes `1-summary.md` with a Partial verdict before the session stops | L: "Pause writes a Partial summary" | ✅ Covered |
| AC: Exit | Explore with no `docs/SUMMARY.md` runs `setup-cluster.sh` before its first report write; wrapper unchanged | L: "Explore starts with no report scaffold", "An existing wrapper is kept" | ✅ Covered |
| AC: Exit | Explore at teardown has written `1-summary.md` with a verdict and a Findings table | L: "Explore writes a summary at teardown" | ✅ Covered |
| AC: Upload | Scaffold-only tier files are excluded by both skills and named in the journal | U: "SUMMARY.md and scaffold-only tier files are excluded", "A scaffold-only tier file is excluded and named" | ✅ Covered |
| AC: Upload | Run upload in a single-cluster workspace names exactly the five tier files | U: "Single-cluster run uploads the five tier files" | ✅ Covered |
| AC: Upload | Cross-cluster: one report under `<test-dir>/docs/`, one journal and issues per arm, uploaded through every arm's wrapper | L: "One report per cross-cluster test", "The arms scaffold"; U: "Final upload list" | ✅ Covered |
| AC: Upload | `report upload` without image/CSV support: only `.md` uploaded, upload succeeds | U: "Binary does not accept images and CSV" | ✅ Covered |
| AC: Upload | `report upload` with image/CSV support: also `images/*.png` and `data/*.csv`, through the support check | U: "Binary accepts images and CSV" | ✅ Covered |
| AC: Content | No account IDs, VPC IDs, IPs, or tunnel details in summary and evidence tiers | L: "Customer tiers hold no infrastructure identifiers", "An IP in the Query line or JSON fails", "Fetch refuses an unmapped IP node label" | ✅ Covered |
| AC: Content | Tool friction in `5-issues.md` is not mentioned in summary or evidence | L: "Tool friction stays out of the customer tiers" | ✅ Covered |
| AC: Content | A result-affecting issue appears under "Threats to validity" | L: "A result-affecting issue" | ✅ Covered |
| AC: Content | Every A/B Noise floor cell links to its evidence block or reads "not measured" | L: "Every Noise floor cell is a link or \"not measured\"", "Not measured allows a verdict", "Confirmed inside the noise floor fails" | ✅ Covered |
| AC: Content | Every summary claim maps to an evidence block with image, stats, Window, Query, Data link | L: "A summary claim maps to a full evidence block", "An incomplete evidence block fails" | ✅ Covered |
| AC: Content | No Grafana graph links in summary and evidence tiers | L: "No Grafana links in the customer tiers" | ✅ Covered |
| AC: Docs | plan, run, explore, report-upload, journal hold no stale `results.md` reference | L: "No stale results.md reference", "No vague screenshot instruction", "Plan previous reads the tier files" | ✅ Covered |
| AC: E2E | Short A/B plan to Completion on a real cluster: verdict and table, Mimir PNG and CSV, passing check, `make` with three outputs, five-file upload in order 1 to 5 | L: "A full A/B run on a real cluster"; tasks 10.2 | ✅ Covered |
| Scope (debt) | Scaffold naming `<destination>.template`; static `book.toml.template` | L: "Templates follow the destination naming rule" | ✅ Covered |
| Scope (debt) | Reporting rules move from run SKILL.md to `report.md`; fix "step 66 above" | L: "Run SKILL.md holds no reporting rules", "Both skills load the reference" | ✅ Covered |
| Scope (debt) | README stops advertising the operator agent | L: "README advertises no operator agent" | ✅ Covered |
| Scope | Fixed summary layout (title, verdict, table, reasoning line, What this means, Caveats) | L: "An A/B summary uses the comparison table", "Any other run uses the Findings table", "A verdict outside the four values fails", "Cassandra reasoning review is done" | ✅ Covered |
| Scope | Placeholder title fails the check (m1) | L: "A placeholder title fails the check", "An empty title falls back to the cluster name" | ✅ Covered |
| Scope | STE prose rules: numbers once, nodes by role | L: "A number in summary prose", "Nodes are named by role" | ✅ Covered |
| Scope | Evidence after each measuring step | L: "A measuring step adds an evidence block" | ✅ Covered |
| Scope | Default stats columns with swappable statistics | L: "Swapped statistic columns for a counter" | ✅ Covered |
| Risk (architect) | Teardown gate now runs Finalize at every exit; unattended check FAIL handling | U: "Gate order", "Check failure does not block the down"; L: "Unattended gate proceeds", "Unattended Completion with no teardown" | ✅ Covered |
| Risk (architect) | Nested evidence pages are not uploaded; images broken in Grafana until CLI support | U: "Single-cluster run uploads the five tier files", "Binary accepts images and CSV" | ✅ Covered |
| Risk (architect) | Cross-cluster: which workspace holds the comparison summary | L: "One report per cross-cluster test", "Final Finalize after the last arm" | ✅ Covered |
| Risk (architect) | Explore provisions without `setup-cluster.sh`, so `docs/` may lack the scaffold | L: "Explore starts with no report scaffold", "Explore starts with a scaffold" | ✅ Covered |
| Risk (architect) | First `make` needs network for uv packages | None | ⚠️ Excluded — environment property, accepted by the owner; no behavior to specify |
| Risk (architect) | `src = "."` copies `data/`, `export/`, Makefile, style into `report/` | None | ⚠️ Excluded — verified harmless by the architect and accepted; no behavior change |
| Risk (architect) | Pause writes a Partial summary, which is non-scaffold, so it uploads later | L: "Pause writes a Partial summary"; U: "A scaffold-only tier file is excluded and named" | ✅ Covered |
| Risk (architect) | No migration; old workspaces break on resume | None | ⚠️ Excluded — out of scope by the issue ("Old workspaces: not supported") |
| Risk (architect) | Hard dependency: real-binary image/CSV upload test needs the unfiled CLI change and the D7 wording contract | U: "Binary accepts images and CSV" (stub `$EDB`, task 1.2) | ✅ Covered |
| Risk (addendum) | An arm must fetch before its own `down`; a missed fetch is permanent | L: "A failed fetch does not stop the run", "Final Finalize with a check failure" | ✅ Covered |
| Risk (addendum) | An arm's later upload replaces only its appendix files; coordinator copy stale until then | U: "Arm gate upload" (requirement text: later arm upload replaces only that arm's files) | ✅ Covered |
| Risk (addendum) | `--gate` edits `1-summary.md` after the subagent reviewed it | L: "A clean gate removes a stale line", "Check failure at a teardown gate"; requirement limits the edit to one Unchecked line | ✅ Covered |
| Risk (addendum) | The arms marker is a shared contract across three scripts | L: "The arms scaffold", "Layout detection reports arms", "Seeds script refuses arms" | ✅ Covered |
| Critic (decision 8) | Findings 1, 2, 5, 6, 7, 11, 12: arms layout, per-arm down, Final Finalize, per-arm files, generated SUMMARY, arm-prefixed names and per-arm windows, no seeds script, Parallel arms rewrite | L: "The arms scaffold", "Arm gate", "Teardown without an arm", "Final Finalize after the last arm", "Arms with different windows", "Nodes are named by role", "Seeds script refuses arms", "No two agents write the same file" | ✅ Covered |
