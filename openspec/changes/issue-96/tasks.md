## 1. New reference: plugins/easy-db-lab/references/report-upload.md

- [x] 1.1 Create `plugins/easy-db-lab/references/report-upload.md` with a "Support check" section: at discovery, check `$EDB commands` for `report upload`; if absent, skip every upload, note it once in `journal.md`, and run `$EDB down --auto-approve` with no gate.
- [x] 1.2 Add the "Upload procedure" section: build an explicit file list (never a raw glob), use absolute paths `<cluster-dir>/docs/<name>`, write the journal entry before the command, run one `$EDB report upload` per DC wrapper to completion, check the exit code, and record each DC's result in `journal.md`.  State that the run skill never drops one of its four files.
- [x] 1.3 Add the file-selection rules: run uploads the fixed four (`results.md journal.md issues.md plan.md`); explore lists every existing `docs/*.md`, excludes `SUMMARY.md` always and `results.md` while it holds only the scaffold comments, and names each excluded file in `journal.md`; no `docs/` or no eligible file means no upload.
- [x] 1.4 Add the "Teardown gate" section: immediately before every real top-level `$EDB down` (not `spark down`, not `--dry-run`), run the upload procedure; run `$EDB down --auto-approve` only on exit 0; each `down` attempt gets its own upload first.
- [x] 1.5 Add the multi-DC rule: upload through every DC wrapper; run `down` on any DC only after every upload exits 0; then run `down --auto-approve` on every DC.
- [x] 1.6 Add "Reading a failure": the validation rejection ("Nothing was uploaded. Rejected: ...") and the mid-batch failure ("Run report upload again", index not rebuilt).  Name the common causes: expired AWS SSO session, invalid filename, missing file, stray `index.md`.
- [x] 1.7 Add interactive failure handling: before teardown, no `down`, show the CLI error, write to `journal.md` and `issues.md`, ask retry / shut down anyway / keep the cluster up; "shut down anyway" runs `down --auto-approve` and journals "report not uploaded"; a retry uploads again and runs `down` only on success.  At step 2: the cluster is not affected; ask retry or continue to step 3.
- [x] 1.8 Add unattended failure handling: never `down` after a failed upload unless the launcher explicitly instructed "shut down anyway", recorded verbatim in `journal.md`; log to `journal.md` and `issues.md`; report to the launcher at that stop point.  At step 2: log, put it in the completion report, continue.

## 2. plugins/easy-db-lab/skills/run/SKILL.md

- [x] 2.1 Discovery (line 46): remove the `commands.md` fallback.  Add the `report upload` support check that points to `report-upload.md`.
- [x] 2.2 Before Starting (line 112): keep the ask-for-`--binary` question; add that the skill stops and reports the paths searched when the user has no path or the path is not executable, and that an unattended run never asks and stops with the paths searched.
- [x] 2.3 Near "Run Commands to Completion" (line 69): add one rule that every real top-level `$EDB down` is gated by `../../references/report-upload.md`; `spark down` and `down --dry-run` are exempt.
- [x] 2.4 Execution Loop step 3 (line 220): replace the `commands.md` load with verification against `$EDB commands`, `$EDB help <topic>`, and `--help`; keep the database references and the `--` separator rule; correct the `cassandra nodetool` example wording to point at `nt`.
- [x] 2.5 Execution Loop step 4 (line 243): change `$EDB cassandra nodetool status` to `$EDB cassandra nt status`.
- [x] 2.6 Completion step 2 (lines 273-281): after the verified build (exit 0 and `docs/report/index.html` exists), run the upload of the four files per `report-upload.md` before step 3; a failed build still blocks the upload.
- [x] 2.7 Completion step 3 (lines 283-312): route a stated shutdown intent (user or launcher), Option 2, and a later shutdown request during Option 1 through the teardown gate; change `$EDB down` to `$EDB down --auto-approve` on every DC.
- [x] 2.8 Completion step 3: in unattended mode with no teardown intent, report "cluster still up" to the launcher and stop.
- [x] 2.9 Pausing and Resuming: add the "Completion / teardown" resume entry point; state that a coordinator relaunches the run skill there and never runs `$EDB down` itself.  Update the Parallel arms bullet "No agent decides teardown on its own" to point to it.

## 3. plugins/easy-db-lab/skills/explore/SKILL.md

- [x] 3.1 Step 1 binary resolution (line 26): run `detect-cluster-layout.sh` first and use the wrapper(s) it finds; with no workspace, use `bin/easy-db-lab`, then `PATH` via `command -v`; interactive asks for a path when none resolves; unattended stops and reports the paths searched.
- [x] 3.2 Step 1 discovery (lines 30-34): make discovery help-first (`$EDB help`, `$EDB help <topic>`, then `$EDB commands` and `--help`), with the `Unmatched argument` fallback; add the `report upload` support check.
- [x] 3.3 Step 2 provisioning (lines 61, 64-65): change `--db`/`--app` to `--db.count`/`--app.count` on the `init` lines only; change the bare `easy-db-lab` on lines 64-65 to `$EDB`.
- [x] 3.4 Teardown (lines 96-110): remove `$EDB down --clickhouse.backup`; add the upload of eligible `docs/*.md` per `report-upload.md` before `$EDB down --auto-approve`, with the gate and failure handling; keep `--dry-run` as the exempt preview; state the multi-DC rule.
- [x] 3.5 Observability (lines 148-154): remove `logs backup`, `logs ls`, `metrics backup`, `metrics ls`; point to `$EDB help observability`.  Correct any remaining block in the file that repeats tool syntax, or replace it with a pointer to the right `help <topic>`.
- [x] 3.6 Guidance Principles (line 188): change principle 1 to the help-first order.

## 4. plugins/easy-db-lab/skills/plan/SKILL.md

- [x] 4.1 Previous Run (line 23): add one sentence that excludes teardown steps from the steps carried into a new plan.
- [x] 4.2 Binary resolution (lines 29-34, 66): remove the `commands.md` fallback; check with `command -v`; interactive asks for a path first; unattended or no usable path stops and reports the paths searched; nothing is written from memory.
- [x] 4.3 Gap analysis (line 138): remove the "Teardown is included if AWS cost matters" bullet.
- [x] 4.4 Step 3 outline (line 231): remove "Tear down (if applicable)"; add one sentence that teardown belongs to the run skill's Completion gate.  Keep the rule that the run skill owns all reporting (line 234), so plans contain no upload step.
- [x] 4.5 Step 4 quality gate (lines 271-278, 281): replace the `commands.md` check with verification against `$EDB commands`, `help <topic>`, and `--help`; remove the "Teardown is included if cost matters" bullet.
- [x] 4.6 Step 5 review (lines 300-302): replace the `references/commands.md` check with the binary sources.

## 5. plugins/easy-db-lab/references/ (commands.md, environment.md)

- [x] 5.1 Delete `plugins/easy-db-lab/references/commands.md`.
- [x] 5.2 `references/environment.md` line 65: remove `easy-db-lab metrics`; point to `easy-db-lab help observability` for log and metric queries.
- [x] 5.3 Run `grep -rn "commands\.md" plugins/` and confirm no match.
- [x] 5.4 Ask the owner whether to bump the easy-db-lab plugin version (current `0.12.1` in `plugins/easy-db-lab/.claude-plugin/plugin.json`, plus `plugins/easy-db-lab/.codex-plugin/plugin.json`); update both files only after the owner gives the new version.

## 6. Review of failure paths by reading

- [x] 6.1 Read `report-upload.md`, run Completion, and explore Teardown against every failure scenario in `specs/easy-db-lab-report-upload/spec.md` (interactive failure, shut down anyway, retry, keep up, unattended failure, launcher override, one DC fails, rejected explore batch, step-2 failure).  Failure paths are verified by reading only, not live, per owner decision Q9.  Record the result per scenario.

## 7. Live end-to-end verification (owner decision Q9)

- [ ] 7.1 Install the local repo as a marketplace and enable the easy-db-lab plugin so the edited skills load as slash commands.
- [ ] 7.2 Write a single-DC plan under `tests/plans/` (gitignored) and run it with the run skill into a workspace under `tests/clusters/<timestamp>/` (gitignored).  Confirm: the step-2 upload runs after a good build; the gate upload runs before teardown; teardown is `down --auto-approve`; the S3 prefix `reports/<tenant>/<name>-<clusterId>/` holds one key per name (four keys, no duplicates).
- [ ] 7.3 Explore teardown with a partial `docs/` (for example `journal.md` and `issues.md` only, plus `SUMMARY.md` and a scaffold-only `results.md`): confirm the upload holds only the eligible files, the journal names the excluded files, and `down` runs only after exit 0.
- [ ] 7.4 Explore teardown with no `docs/`: confirm no upload runs and `down --auto-approve` runs.
- [ ] 7.5 Multi-DC run (two DCs, workspace under `tests/clusters/`): confirm the upload runs through every DC wrapper, `journal.md` records each DC's result separately, and `down --auto-approve` runs on every DC only after all uploads succeed.
- [ ] 7.6 Confirm no cluster from 7.2-7.5 is left running (`$EDB status` per workspace).
- [ ] 7.7 Run `grep -rn "commands\.md" plugins/` again on the final tree and confirm no file references `commands.md`.
