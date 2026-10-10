## Why

easy-db-lab has a new command, `easy-db-lab report upload FILE...`.  It puts markdown files into the current test's documents in S3 and rebuilds the index that the Grafana Tests and comparison dashboards show.  The easy-db-lab plugin skills do not use this command, so lab reports stay only on the local disk, and a cluster can go `down` without its report in Grafana.  Also, the skills carry a hand-written command reference (`references/commands.md`) and hard-coded command syntax that has drifted from the binary.  This change makes the skills upload the report before every real teardown, and makes them learn the tool from the binary instead of from stale copies.

## What Changes

- **`plugins/easy-db-lab/references/report-upload.md` (new).**  One shared reference holds two things.  (1) The upload procedure: build an explicit list of existing files (never a raw glob), use absolute paths `<cluster-dir>/docs/<file>`, write the journal entry, run one `$EDB report upload` command per DC wrapper, check the exit code, record the result.  It explains how to read the two CLI failure messages ("Nothing was uploaded. Rejected: ..." and the mid-batch "Run report upload again" message).  (2) The teardown gate: immediately before every real top-level `$EDB down` (not `spark down`, not `down --dry-run`), run the upload procedure, and run `$EDB down --auto-approve` only on exit 0.  It also holds interactive and unattended failure handling, the launcher's "shut down anyway" authorization, the multi-DC rule (upload through every DC wrapper, then `down` on every DC), and the rule for a binary that has no `report upload`.
- **`plugins/easy-db-lab/skills/run/SKILL.md` (modified).**
  - Completion step 2: after `make` exits 0 and `docs/report/index.html` exists, run one upload of `results.md journal.md issues.md plan.md` before the step 3 menu.  A failed build still blocks the upload.  A failed step-2 upload does not touch the cluster: interactive asks retry or continue; unattended records it in the completion report and continues.
  - Completion step 3: Option 2, a stated shutdown intent (from the user or the launcher), and a later shutdown request during Option 1 all go through the teardown gate in `report-upload.md`.  `$EDB down` becomes `$EDB down --auto-approve`, on every DC.
  - A new rule near "Run Commands to Completion" states the gate once as a property of every real `$EDB down`.
  - A new resume entry point "Completion / teardown" lets a coordinator or the owner relaunch the run skill on a workspace to run the gated teardown.  In unattended mode with no teardown intent, Completion reports "cluster still up" to the launcher and stops.
  - Discovery: the `commands.md` fallback (line 46) and the `commands.md` load in step 3 (line 220) are removed.  The step 3 precondition now verifies plan commands against `$EDB commands`, `$EDB help <topic>`, and `--help`.  Discovery checks `$EDB commands` for `report upload` and records support once.
  - Binary resolution keeps the ask-for-`--binary` question.  With no path, or a path that is not executable, the skill stops and reports the paths searched.
  - Stale syntax: `$EDB cassandra nodetool status` (line 243) becomes `$EDB cassandra nt status`.
- **`plugins/easy-db-lab/skills/explore/SKILL.md` (modified).**
  - Binary resolution: run `detect-cluster-layout.sh` first and use the wrapper(s) it finds; with no workspace, use `bin/easy-db-lab`, then `PATH`.  Interactive asks for a path when none resolves; unattended stops and reports the paths searched.
  - Discovery becomes help-first: `$EDB help`, then `$EDB help <topic>`, then `$EDB commands` and `--help` (lines 30-34 and Guidance Principle 1 at line 188).
  - Teardown: upload every existing `docs/*.md` in one command per DC wrapper, minus `SUMMARY.md` and minus a `results.md` that holds only scaffold comments, before `$EDB down --auto-approve`.  The journal names each excluded file.  No `docs/` or no eligible file means no upload.  The stale `--clickhouse.backup` example is removed.
  - Stale syntax: `logs backup`, `logs ls`, `metrics backup`, `metrics ls` (lines 148-154) are removed and replaced by a pointer to `$EDB help observability`.  `init --db/--app` on the init lines (61, 64-65) becomes `--db.count/--app.count`, and the bare `easy-db-lab` on lines 64-65 becomes `$EDB`.
- **`plugins/easy-db-lab/skills/plan/SKILL.md` (modified).**
  - Teardown guidance is removed: the gap-check bullet (line 138), the "Tear down (if applicable)" outline step (line 231), and the quality-gate bullet (line 281).  One sentence states that teardown belongs to the run skill's Completion gate.
  - One sentence at line 23 excludes teardown steps from the steps that `--previous` carries into a new plan.
  - The `commands.md` fallback (line 66) and the `commands.md` checks (lines 272, 301) are removed; plan commands are verified against `$EDB commands`, `help <topic>`, and `--help`.  With no binary, the skill stops and reports the paths searched (interactive first asks for a path).
- **`plugins/easy-db-lab/references/commands.md` (deleted).**  **BREAKING** for any reader that loads it.  No skill or reference points to it after this change.
- **`plugins/easy-db-lab/references/environment.md` (modified).**  Line 65 no longer names `easy-db-lab metrics`, which does not exist; it points to `$EDB help observability` for log and metric queries.

## Capabilities

### New Capabilities

- `easy-db-lab-report-upload`: uploading the markdown lab report at Completion and before every real teardown, the exit-code gate on `down`, failure handling in interactive and unattended modes, multi-DC handling, explore's file selection, and teardown ownership by the run skill.
- `easy-db-lab-tool-discovery`: how the plan, run, and explore skills resolve the binary, learn commands from the binary (help-first), detect `report upload` support, and carry no hand-written command reference or stale syntax.

### Modified Capabilities

None.  No baseline spec under `openspec/specs/` covers the easy-db-lab plugin.

## Impact

- Markdown only: three skill files, one new reference, one deleted reference, one edited reference.  No script or CLI change.
- Each upload costs a few S3 PUTs.  An upload with an expired AWS SSO session can be slow to fail because the CLI retries.
- The change alters existing skill behavior: the plan skill no longer suggests teardown steps, and `commands.md` is gone.
- No harness or eval covers the easy-db-lab skills, so verification is live end-to-end runs under the gitignored `tests/` directory.
