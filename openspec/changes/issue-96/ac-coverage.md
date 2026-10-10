# Acceptance-criteria coverage: issue-96

Spec files: `R` = `specs/easy-db-lab-report-upload/spec.md`, `T` = `specs/easy-db-lab-tool-discovery/spec.md`.

| Source | Requirement | Covering scenario(s) | Status |
|---|---|---|---|
| AC | Step 2 builds successfully (exit 0 and `docs/report/index.html`), then one `$EDB report upload` of the four files before the step 3 menu | R: "Successful build triggers the upload" | ✅ Covered |
| AC | mdbook build fails, then no upload until the build is fixed; `run/SKILL.md:281` stays in force | R: "Failed build blocks the upload" | ✅ Covered |
| AC | Upload succeeds, then `journal.md` records the command and its result | R: "Successful upload is journaled" | ✅ Covered |
| AC | Step-2 upload fails with no shutdown request: show error, log to journal and issues, ask the user; cluster not affected | R: "Step-2 upload fails in an interactive session", "Step-2 upload fails in an unattended session" | ✅ Covered |
| AC | Option 2: upload the four files again; `down` only on exit 0 | R: "Completion Option 2" | ✅ Covered |
| AC | Shutdown intent stated earlier: same upload-then-`down` without prompting | R: "Shutdown intent stated earlier by the user", "Shutdown intent stated by a launcher" | ✅ Covered |
| AC | Option 1, explore, later shut down: upload with the current journal before `down`; `down` only on exit 0 | R: "Shutdown after Option 1 exploration" | ✅ Covered |
| AC | Explore teardown with `docs/`: upload markdown report files before `down`, same gate | R: "Workspace with a full docs directory", "Workspace with a partial docs directory" | ✅ Covered |
| AC | Explore teardown with no `docs/`: run `down`, no upload | R: "Workspace with no docs directory" | ✅ Covered |
| AC | `$EDB down --dry-run` needs no upload | R: "Dry run needs no upload" | ✅ Covered |
| AC | Upload before teardown fails (expired SSO, invalid filename, missing file): no `down`, show error, journal and issues, ask the user | R: "Upload fails before teardown" | ✅ Covered |
| AC | User says shut down anyway: run `down`, journal that the report was not uploaded | R: "User says shut down anyway" | ✅ Covered |
| AC | User fixes the cause and retries: upload again, `down` only on success | R: "User fixes the cause and retries" | ✅ Covered |
| AC | Unattended and upload fails: no `down`, log to journal and issues, report to the launcher at that stop point | R: "Unattended failure with no override" | ✅ Covered |
| AC | `references/commands.md` no longer exists and nothing points to it; agents learn `report upload` from `$EDB commands` | T: "The file is gone", "No reference to the file remains", "report upload is learned from the binary" | ✅ Covered |
| AC | Binary not found: plan, run, explore stop and report the paths searched (interactive first asks for a path) | T: "Interactive session with no binary found", "Unattended session with no binary found", "Nothing is written from memory" | ✅ Covered |
| AC | Binary has no `report upload`: skip every upload, note once in journal, `down` with no gate | R: "Binary has no report upload" | ✅ Covered |
| Assumption | A1: same name replaces the earlier copy | R: "A second upload of the same names replaces the first" | ✅ Covered |
| Assumption | A2: only a real `down` needs the gate | R: "Dry run needs no upload", "Spark down is not gated" | ✅ Covered |
| Assumption | A3: journal entry written before the command; uploaded journal lacks the later `down` entry | R: "Journal entry before the command" | ✅ Covered |
| Assumption | A4: a missing file rejects the batch; the skill never drops a file | R: "A missing run-skill file is not dropped" | ✅ Covered |
| Decision | Q1: shared `references/report-upload.md`; gate stated once on every real top-level `$EDB down` (not `spark down`); Completion bullets point to it | R: "The run skill points to the shared reference", "The explore skill points to the shared reference", "Spark down is not gated" | ✅ Covered |
| Decision | Q2: launcher MAY authorize "shut down anyway" by explicit instruction, recorded verbatim; launcher's stated intent counts | R: "Launcher authorizes shut down anyway", "Shutdown intent stated by a launcher" | ✅ Covered |
| Decision | Q3: plan skill no longer tells authors to add teardown; teardown belongs to the run skill's Completion gate | R: "Plan skill has no teardown guidance" | ✅ Covered |
| Decision | Q3b: existing plans with a `down` step get no special handling; the general gate covers them | R: "A plan step that runs down" | ✅ Covered |
| Decision | Q4: explore uploads every `docs/*.md` in one command; no `docs/` or no `.md` means no upload; rejected batch goes through the failure gate; run keeps the fixed four | R: "Workspace with a full docs directory", "Workspace with no docs directory", "Workspace whose docs directory has no eligible file", "A rejected batch in explore", "Successful build triggers the upload" | ✅ Covered |
| Decision | Q5: delete `commands.md`; update every reference | T: "The file is gone", "No reference to the file remains", "Run verifies a plan command", "Plan verifies its commands" | ✅ Covered |
| Decision | Q5 clarification: discovery is `help`, then `help <topic>`, plus `commands` / `--help`; explore gains help-first discovery | T: "Explore discovers help-first", "Run and plan keep help-first discovery", "Binary predates the topic guides" | ✅ Covered |
| Decision | Q5b: no binary means fail fast with the path searched; nothing written from memory | T: "Interactive session with no binary found", "Unattended session with no binary found", "Nothing is written from memory" | ✅ Covered |
| Decision | Live-check finding: `help provisioning` shows `down --auto-approve`; no help topic mentions `report upload`, so skills carry the policy and the binary carries syntax | R: "Gated down does not wait for stdin", "The run skill points to the shared reference"; T: "report upload is learned from the binary" | ✅ Covered |
| Decision | Q6: binary without `report upload` (detected via `$EDB commands`) skips uploads, notes once, `down` with no gate | R: "Binary has no report upload" | ✅ Covered |
| Decision | Q7: absolute `<cluster-dir>/docs/...` paths; multi-DC uploads through every DC wrapper; `down` only after all succeed; per-DC journal; explore same rule | R: "Absolute paths through the wrapper", "All DC uploads succeed", "One DC upload fails", "Multi-DC Completion step 2"; T: "Multi-DC workspace" | ✅ Covered |
| Decision | Q8: fold in explore `--clickhouse.backup` fix, `down --auto-approve`, multi-DC `down` targeting | T: "Explore teardown block"; R: "Gated down does not wait for stdin", "All DC uploads succeed" | ✅ Covered |
| Decision | Q9: no live test of failure paths; live tests cover the happy paths; failure handling reviewed by reading | None; this is a verification decision, not skill behavior | ⚠️ Excluded — test strategy, not behavior; carried in tasks.md groups 6 and 7 |
| Decision | F6: one sentence at `plan/SKILL.md:23` excluding teardown from `--previous` steps | R: "Previous run with an ad-hoc teardown" | ✅ Covered |
| Decision | F7: no action | None | ⚠️ Excluded — the owner chose no action, so there is no behavior to specify |
| Decision | F8: list existing files explicitly before the upload command; never a raw glob | R: "Absolute paths through the wrapper", "Workspace with a partial docs directory" | ✅ Covered |
| Decision | QA: unattended with no teardown intent reports "cluster still up" and stops; "Completion / teardown" resume entry point; coordinator never runs `down` | R: "Unattended run with no shutdown intent", "Relaunch for teardown", "Coordinator does not run down itself" | ✅ Covered |
| Decision | QB: explore resolves `$EDB` via `detect-cluster-layout.sh`; no workspace means `bin/easy-db-lab` then `PATH`; none means fail fast | T: "Single-DC workspace", "Multi-DC workspace", "No workspace", "Unattended session with no binary found" | ✅ Covered |
| Decision | QC: explore excludes `SUMMARY.md` always and scaffold-only `results.md`; journal names each excluded file; list fixed before the command | R: "SUMMARY.md and a scaffold-only results.md are excluded", "Workspace whose docs directory has no eligible file" | ✅ Covered |
| Decision | QD: fix stale syntax (explore 149-154, run 243, environment.md 65, explore 61/64-65, explore help-first 30-34/188); syntax-only blocks become `help <topic>` pointers | T: "Explore observability block", "Run verify step", "Environment reference", "Explore provisioning lines", "Explore discovers help-first" | ✅ Covered |
| Decision | QD amendment: `logs backup/ls`, `metrics *`, `cassandra nodetool` missing; `init --db/--app` become `--db.count/--app.count` on init lines only | T: "Explore observability block", "Run verify step", "Explore provisioning lines" | ✅ Covered |
| Decision | QE: run keeps its ask-for-`--binary`; fails only with no path or a non-executable path; plan and explore use `command -v`, interactive asks first, unattended never asks | T: "Interactive session with no binary found", "Unattended session with no binary found" | ✅ Covered |
| Risk | Markdown only: three skills, new reference, `commands.md` deletion, `environment.md` | T: "The file is gone", "Environment reference"; R: "The run skill points to the shared reference" | ✅ Covered |
| Risk | Each upload costs S3 PUTs; an expired-SSO failure can be slow (retries) | R: "Upload fails before teardown", "User fixes the cause and retries" | ✅ Covered |
| Risk | No harness or eval covers easy-db-lab skills; "tested" needs live runs under gitignored `tests/` | None; verification concern | ⚠️ Excluded — test strategy, not behavior; carried in tasks.md group 7 |
| Risk | A later upload of fewer files never removes earlier documents | R: "A second upload of the same names replaces the first" (run always sends the same four names) | ✅ Covered |
| Risk | The same basename twice in one invocation rejects the batch | R: "Absolute paths through the wrapper" (explicit list), "A rejected batch in explore" | ✅ Covered |
| Risk | Explore's `docs/*.md` sweep can include `SUMMARY.md`, a reserved `index.md`, or a bad name, and reject the batch | R: "SUMMARY.md and a scaffold-only results.md are excluded", "A rejected batch in explore" | ✅ Covered |
| Risk | The mid-batch failure stores some documents and does not rebuild the index | R: "Upload fails before teardown", "User fixes the cause and retries" | ✅ Covered |
