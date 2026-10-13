# Overrides and conflicts: issue-98

## Overrides existing behavior

No baseline spec under `openspec/specs/` covers the easy-db-lab plugin.  The baseline specs (`backlog-overlap`, `blocked-dependency`, `delivery-board`, `explain`, `idea-refinement`, `issue-body-edits`, `issue-closure`, `issue-manager-spawn`, `owner-presentation`, `repo-config`, `test-policy`, `walkthrough`) cover spec-flow and dev-skills.  `easy-db-lab-lab-report` is new, with ADDED requirements only.

`easy-db-lab-report-upload` exists only as the in-flight `issue-96` delta.  This change MODIFIES seven of its requirements:

| Requirement | Currently, per issue-96 delta | This change |
|---|---|---|
| The upload procedure uses an explicit list of absolute paths | Journal entry and result go to `journal.md`.  "The run skill SHALL NOT drop one of its four files."  The second-upload scenario uses "the same four names". | Journal role `<journal>`.  Single-cluster run uploads exactly the five tier files.  A scaffold-only tier file is the one allowed omission, named in `<journal>`.  Nested evidence pages are not listed.  Second upload uses five names. |
| The run skill uploads the report at Completion step 2 | After a successful build, one upload of `results.md`, `journal.md`, `issues.md`, `plan.md`.  Failures go to `journal.md` and `issues.md`. | First write `1-summary.md` and run the check.  A failed check blocks the build at Completion with no teardown.  The upload holds the five tier files.  Failures go to `<journal>` and `<issues>`. |
| Every real top-level down is gated on a successful upload | Before every real `down`, run the upload; `down --auto-approve` only on exit 0, with no exception. | Run Finalize first (write summary, check, `make gate`), then upload.  A non-redaction check failure does not block the `down`.  A redaction failure (exit 3) skips the upload and lets the `down` run.  An upload retry does not re-check. |
| Interactive upload failure before teardown stops the teardown | Failures go to `journal.md` and `issues.md`. | Same behavior; file names become the roles `<journal>` and `<issues>`. |
| Unattended upload failure before teardown stops the teardown | No `down` after a failed upload unless the launcher said "shut down anyway"; `journal.md` and `issues.md`. | Same behavior with roles.  States that the rule does not apply to a redaction failure, which skips the upload and lets the `down` run. |
| Multi-DC uploads go through every DC wrapper before any down | Uploads "the same files" and, at step 2, "the four files" through every DC wrapper. | Uploads the five tier files.  Derives Mimir URL and tenant per DC wrapper.  Applies to `LAYOUT=multi` only; `LAYOUT=arms` follows the arms rule. |
| Explore uploads every eligible docs markdown file before teardown | Excludes `SUMMARY.md` and `results.md` while it holds only scaffold comments.  No Finalize step. | Runs Finalize first.  Excludes `SUMMARY.md` and every scaffold-only tier file.  Names each excluded file in `<journal>`. |

This change also ADDS two requirements to `easy-db-lab-report-upload`: image and CSV detection through the support check, and the arms upload (arm gate and final upload).

The most visible override: `issue-96` says a `down` runs only after a successful upload.  This change lets the `down` run after a redaction failure with no upload, by owner decision B.  The report stays local, and `run <cluster-dir> --finalize` uploads it later.

Skill behavior that no spec records also changes: the scaffold files (`results.md`, `plan.md`, `journal.md`, `issues.md`) are replaced, the "Parallel arms" rule changes from one workspace per arm to one test directory, and explore now scaffolds `docs/`.  Old workspaces are not supported.

## Conflicts with other in-flight changes

`ls openspec/changes | grep -v archive` lists `issue-96` and `issue-98`.  `issue-96` is merged (commit `407e8ae`) but not yet archived.  It touches `easy-db-lab-report-upload` and `easy-db-lab-tool-discovery`.

- `easy-db-lab-report-upload`: this change modifies the seven requirements in the table above, by exact header.  This is a clean supersede, not a hard conflict.  `issue-98` builds on the merged `issue-96` text and restates each modified requirement in full.  Requirement headers are unchanged.  The requirements "One shared reference holds the upload procedure and the teardown gate", "Unattended Completion without a teardown intent leaves the cluster up and offers a teardown entry point", "A binary without report upload skips every upload", and "Teardown belongs to the run skill, not to plans" are not modified.
- `easy-db-lab-tool-discovery`: not modified.  `detect-cluster-layout.sh` gains `LAYOUT=arms` and skips `bin`; these are specified as ADDED requirements in `easy-db-lab-lab-report`, so "Explore resolves the binary through the cluster layout" stays as written.
- Archive order: `issue-96` MUST be archived before `issue-98`.  The MODIFIED blocks need the baseline `openspec/specs/easy-db-lab-report-upload/spec.md` that the `issue-96` archive creates.
