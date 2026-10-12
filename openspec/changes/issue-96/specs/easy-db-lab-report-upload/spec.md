## ADDED Requirements

### Requirement: One shared reference holds the upload procedure and the teardown gate

The easy-db-lab plugin SHALL ship `plugins/easy-db-lab/references/report-upload.md`.  This reference SHALL hold the upload procedure and the teardown gate.  The run skill SHALL state the gate once, as a rule on every real top-level `$EDB down`, near "Run Commands to Completion", and its Completion bullets SHALL point to the reference.  The explore skill Teardown SHALL point to the same reference.  No skill SHALL point to another skill's `SKILL.md` for this procedure.

#### Scenario: The run skill points to the shared reference

- **WHEN** a reader opens `run/SKILL.md` Completion
- **THEN** each upload and teardown bullet points to `../../references/report-upload.md`
- **AND** the gate rule appears once in the run skill, near "Run Commands to Completion"

#### Scenario: The explore skill points to the shared reference

- **WHEN** a reader opens `explore/SKILL.md` Teardown
- **THEN** it points to `../../references/report-upload.md`
- **AND** it does not point to `../run/SKILL.md`

### Requirement: The upload procedure uses an explicit list of absolute paths

The upload procedure SHALL build the file list before it runs the command.  It SHALL name each file explicitly by its absolute path `<cluster-dir>/docs/<name>`, and it SHALL NOT pass a raw glob to the CLI.  It SHALL write the journal entry for the upload before the command runs.  It SHALL run the upload to completion, check the exit code, and record the result in `journal.md`.  The run skill SHALL NOT drop one of its four files to make an upload pass.

#### Scenario: Absolute paths through the wrapper

- **WHEN** the skill builds an upload command
- **THEN** every file argument is an absolute path under `<cluster-dir>/docs/`
- **AND** no argument is a glob pattern

#### Scenario: Journal entry before the command

- **WHEN** the skill is about to run `$EDB report upload`
- **THEN** it writes the journal entry for the upload first
- **AND** the uploaded `journal.md` holds the upload intent but not the later `down` entry, which is acceptable

#### Scenario: A missing run-skill file is not dropped

- **WHEN** one of the run skill's four files is missing and the CLI rejects the batch
- **THEN** the skill does not remove that file from the command to make the upload pass
- **AND** it handles the rejection as an upload failure

#### Scenario: A second upload of the same names replaces the first

- **WHEN** the run skill uploads the same four names at Completion step 2 and again before teardown
- **THEN** the second upload replaces the earlier copy of each name
- **AND** S3 holds one key per name for the test

### Requirement: The run skill uploads the report at Completion step 2

When Completion step 2 builds the report successfully, the run skill SHALL run one `$EDB report upload` command with `<cluster-dir>/docs/results.md`, `<cluster-dir>/docs/journal.md`, `<cluster-dir>/docs/issues.md`, and `<cluster-dir>/docs/plan.md`, before it shows the step 3 menu.  A build is successful only when `make` exits 0 and `docs/report/index.html` exists.  The skill MUST NOT upload until the build succeeds.  A failed step-2 upload MUST NOT affect the cluster.

#### Scenario: Successful build triggers the upload

- **WHEN** `make -C <cluster-dir>/docs` exits 0 and `<cluster-dir>/docs/report/index.html` exists
- **THEN** the skill runs one `$EDB report upload` with the four files
- **AND** it does this before it shows the step 3 menu

#### Scenario: Failed build blocks the upload

- **WHEN** the mdbook build fails or `docs/report/index.html` is missing
- **THEN** the skill does not upload
- **AND** it diagnoses, logs to `issues.md`, fixes the build, and runs `make` again under the rule at `run/SKILL.md:281`, before any upload

#### Scenario: Successful upload is journaled

- **WHEN** the step-2 upload exits 0
- **THEN** `journal.md` records the command and its result

#### Scenario: Step-2 upload fails in an interactive session

- **WHEN** the step-2 upload exits non-zero and the user has not asked to shut down
- **THEN** the skill shows the CLI error, writes the failure to `journal.md` and `issues.md`, and asks the user to retry or to continue to step 3
- **AND** the cluster is not affected

#### Scenario: Step-2 upload fails in an unattended session

- **WHEN** the step-2 upload exits non-zero and the run skill is unattended
- **THEN** the skill writes the failure to `journal.md` and `issues.md`
- **AND** it puts the failure in the completion report and continues to step 3

### Requirement: Every real top-level down is gated on a successful upload

Immediately before every real top-level `$EDB down` that a skill runs, the skill SHALL run the upload procedure, and it SHALL run `$EDB down --auto-approve` only if the upload exits 0.  A `down --dry-run` SHALL NOT need an upload.  `spark down` SHALL NOT be gated.  Each `down` attempt SHALL get its own upload first.

#### Scenario: Completion Option 2

- **WHEN** the user picks Completion Option 2
- **THEN** the skill uploads the four files again
- **AND** it runs `$EDB down --auto-approve` only if the upload exits 0

#### Scenario: Shutdown intent stated earlier by the user

- **WHEN** the user stated a shutdown intent earlier in the session
- **THEN** the skill runs the same upload-then-`down` sequence without prompting

#### Scenario: Shutdown intent stated by a launcher

- **WHEN** the launcher of an unattended run stated a shutdown intent
- **THEN** the skill treats it as a stated shutdown intent
- **AND** it runs the upload-then-`down` sequence without prompting

#### Scenario: Shutdown after Option 1 exploration

- **WHEN** the user picks Option 1, explores, and later asks to shut down
- **THEN** the skill uploads the four files, with the current journal, before `$EDB down`
- **AND** it runs `down` only if the upload exits 0

#### Scenario: Dry run needs no upload

- **WHEN** the command is `$EDB down --dry-run`
- **THEN** the skill runs it without an upload, because nothing is destroyed

#### Scenario: Spark down is not gated

- **WHEN** the skill runs `$EDB spark down`
- **THEN** the skill does not run an upload first

#### Scenario: Gated down does not wait for stdin

- **WHEN** the upload before teardown exits 0
- **THEN** the skill runs `$EDB down --auto-approve`, not a bare `$EDB down`

#### Scenario: A plan step that runs down

- **WHEN** an existing plan contains a step that runs a real `$EDB down`
- **THEN** the general gate applies to that `down` with no special handling

### Requirement: Interactive upload failure before teardown stops the teardown

When the upload before teardown exits non-zero in an interactive session, the skill MUST NOT run `down`.  It SHALL show the CLI error, write the failure to `journal.md` and `issues.md`, and ask the user to retry, shut down anyway, or keep the cluster up.  The reference SHALL explain the two CLI failure messages: the validation rejection ("Nothing was uploaded. Rejected: ...") and the mid-batch failure ("Run report upload again").

#### Scenario: Upload fails before teardown

- **WHEN** the upload before teardown exits non-zero, for example for an expired AWS SSO session, an invalid filename, or a missing file
- **THEN** the skill does not run `down`
- **AND** it shows the CLI error, writes the failure to `journal.md` and `issues.md`, and asks the user what to do

#### Scenario: User says shut down anyway

- **WHEN** the user tells the skill to shut down anyway after a failed upload
- **THEN** the skill runs `$EDB down --auto-approve`
- **AND** it writes to `journal.md` that the report was not uploaded

#### Scenario: User fixes the cause and retries

- **WHEN** the user fixes the cause, for example with `aws sso login`, and asks for a retry
- **THEN** the skill uploads again
- **AND** it runs `down` only if the new upload exits 0

#### Scenario: User keeps the cluster up

- **WHEN** the user chooses to keep the cluster up after a failed upload
- **THEN** the skill does not run `down`
- **AND** it records the choice in `journal.md`

### Requirement: Unattended upload failure before teardown stops the teardown

When the run skill is unattended and the upload before teardown fails, the skill MUST NOT run `down`, unless the launcher explicitly instructed it to shut down anyway.  It SHALL write the failure to `journal.md` and `issues.md` and report the failure to the launcher at that stop point, as the unattended rule requires.  When the launcher's explicit "shut down anyway" instruction exists, the skill SHALL record it verbatim in `journal.md` before it runs `down`.

#### Scenario: Unattended failure with no override

- **WHEN** the run skill is unattended, the upload before teardown fails, and the launcher gave no explicit "shut down anyway" instruction
- **THEN** the skill does not run `down`
- **AND** it writes the failure to `journal.md` and `issues.md` and reports the failure to the launcher at that stop point

#### Scenario: Launcher authorizes shut down anyway

- **WHEN** the run skill is unattended, the upload before teardown fails, and the launcher explicitly instructed it to shut down anyway
- **THEN** the skill records the launcher's instruction verbatim in `journal.md`
- **AND** it runs `$EDB down --auto-approve` and writes to `journal.md` that the report was not uploaded

### Requirement: Unattended Completion without a teardown intent leaves the cluster up and offers a teardown entry point

When the run skill is unattended and no shutdown intent exists, Completion step 3 SHALL report "cluster still up" to the launcher and stop.  The run skill SHALL offer a resume entry point, "Completion / teardown", that a coordinator or the owner can use to relaunch the run skill on the workspace to run the gated teardown.  A coordinator MUST NOT run `$EDB down` itself.

#### Scenario: Unattended run with no shutdown intent

- **WHEN** the run skill is unattended, reaches Completion step 3, and the launcher stated no shutdown intent
- **THEN** the skill reports "cluster still up" to the launcher
- **AND** it stops without running `down`

#### Scenario: Relaunch for teardown

- **WHEN** a coordinator or the owner relaunches the run skill on a workspace at the "Completion / teardown" entry point
- **THEN** the skill runs the gated teardown: upload, check the exit code, then `$EDB down --auto-approve` only on success

#### Scenario: Coordinator does not run down itself

- **WHEN** a coordinator wants a cluster torn down
- **THEN** it relaunches the run skill at "Completion / teardown"
- **AND** it does not run `$EDB down` itself

### Requirement: Multi-DC uploads go through every DC wrapper before any down

In a multi-DC workspace, the skill SHALL upload the same files through every DC's wrapper, with absolute paths to the shared `<cluster-dir>/docs/`.  It SHALL run `down` on any DC only after every DC's upload exits 0, and then it SHALL run `$EDB down --auto-approve` on every DC.  The journal SHALL record each DC's upload result separately.  The explore skill SHALL use the same rule.

#### Scenario: All DC uploads succeed

- **WHEN** a multi-DC teardown runs and every DC's upload exits 0
- **THEN** the skill runs `down --auto-approve` through every DC's wrapper
- **AND** `journal.md` records each DC's upload result separately

#### Scenario: One DC upload fails

- **WHEN** a multi-DC teardown runs and one DC's upload exits non-zero
- **THEN** the skill runs `down` on no DC
- **AND** it follows the interactive or unattended failure handling

#### Scenario: Multi-DC Completion step 2

- **WHEN** a multi-DC run reaches Completion step 2 with a successful build
- **THEN** the skill uploads the four files through every DC's wrapper
- **AND** it records each DC's result separately

### Requirement: Explore uploads every eligible docs markdown file before teardown

When the explore skill tears down a workspace that has a `docs/` directory, it SHALL list every existing `docs/*.md` explicitly, exclude `SUMMARY.md`, and exclude `results.md` while it holds only the scaffold comments.  It SHALL name each excluded file in `journal.md`.  It SHALL upload the remaining files in one command per DC wrapper before `$EDB down`, with the same exit-code gate and failure handling as the run skill.  When no `docs/` exists or no eligible file remains, it SHALL run `$EDB down --auto-approve` and SHALL NOT try to upload.

#### Scenario: Workspace with a full docs directory

- **WHEN** the explore skill tears down a workspace whose `docs/` holds eligible markdown files
- **THEN** it uploads them in one command per DC wrapper before `$EDB down`
- **AND** it runs `down` only if the upload exits 0

#### Scenario: Workspace with a partial docs directory

- **WHEN** the explore skill tears down a workspace whose `docs/` holds only some markdown files
- **THEN** it uploads the eligible files that exist, listed explicitly
- **AND** it runs `down` only if the upload exits 0

#### Scenario: Workspace with no docs directory

- **WHEN** the explore skill tears down a workspace that has no `docs/` directory
- **THEN** it runs `$EDB down --auto-approve`
- **AND** it does not try to upload

#### Scenario: Workspace whose docs directory has no eligible file

- **WHEN** the explore skill tears down a workspace whose `docs/` has no markdown file left after the exclusions
- **THEN** it runs `$EDB down --auto-approve` with no upload
- **AND** `journal.md` names each excluded file

#### Scenario: SUMMARY.md and a scaffold-only results.md are excluded

- **WHEN** `docs/` holds `SUMMARY.md` and a `results.md` that contains only the scaffold comments
- **THEN** the upload command contains neither file
- **AND** `journal.md` names both as excluded

#### Scenario: A rejected batch in explore

- **WHEN** the explore upload is rejected, for example for a stray `index.md` or a bad file name
- **THEN** the skill does not run `down`
- **AND** it follows the normal failure handling

### Requirement: A binary without report upload skips every upload

At discovery, the skill SHALL check `$EDB commands` for `report upload`.  When it is absent, the skill SHALL skip every upload, note this once in `journal.md`, and run `$EDB down --auto-approve` with no upload gate.

#### Scenario: Binary has no report upload

- **WHEN** `$EDB commands` does not list `report upload`
- **THEN** the skill skips every upload, at Completion step 2 and before teardown
- **AND** it notes this once in `journal.md`
- **AND** it runs `$EDB down --auto-approve` with no gate

### Requirement: Teardown belongs to the run skill, not to plans

The plan skill SHALL NOT tell authors to add teardown steps.  It SHALL state that teardown belongs to the run skill's Completion gate.  The plan skill's `--previous` handling SHALL exclude teardown steps from the steps it carries into a new plan.  Plans SHALL NOT contain an upload step, because the run skill owns all reporting.

#### Scenario: Plan skill has no teardown guidance

- **WHEN** a reader opens `plan/SKILL.md`
- **THEN** no gap-check bullet, outline step, or quality-gate bullet asks for a teardown step
- **AND** one sentence states that teardown belongs to the run skill's Completion gate

#### Scenario: Previous run with an ad-hoc teardown

- **WHEN** the plan skill runs with `--previous <cluster-dir>` and the previous journal records a teardown
- **THEN** the new plan does not carry a teardown step from that journal

#### Scenario: Plans contain no upload step

- **WHEN** the plan skill writes a plan
- **THEN** the plan contains no `report upload` step
