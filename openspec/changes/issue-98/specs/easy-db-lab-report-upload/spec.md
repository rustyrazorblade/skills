## MODIFIED Requirements

### Requirement: The upload procedure uses an explicit list of absolute paths

The upload procedure SHALL build the file list before it runs the command.  It SHALL name each file explicitly by its absolute path `<cluster-dir>/docs/<name>`, and it SHALL NOT pass a raw glob to the CLI.  It SHALL write the journal entry for the upload to `<journal>` before the command runs.  It SHALL run the upload to completion, check the exit code, and record the result in `<journal>`.  In a single-cluster workspace the run skill SHALL upload exactly the five tier files: `1-summary.md`, `2-evidence.md`, `3-plan.md`, `4-journal.md`, and `5-issues.md`.  Nested evidence pages SHALL NOT be in the list.  The only file the run skill MAY leave out SHALL be a tier file that holds only scaffold content; the skill SHALL name each such file in `<journal>`.  The run skill SHALL NOT drop any other tier file to make an upload pass.

#### Scenario: Absolute paths through the wrapper

- **WHEN** the skill builds an upload command
- **THEN** every file argument is an absolute path under `<cluster-dir>/docs/`
- **AND** no argument is a glob pattern

#### Scenario: Journal entry before the command

- **WHEN** the skill is about to run `$EDB report upload`
- **THEN** it writes the journal entry for the upload to `<journal>` first
- **AND** the uploaded journal holds the upload intent but not the later `down` entry, which is acceptable

#### Scenario: Single-cluster run uploads the five tier files

- **WHEN** the run skill uploads, at Completion or at the gate, in a single-cluster workspace
- **THEN** the upload names exactly the five tier files

#### Scenario: A scaffold-only tier file is excluded and named

- **WHEN** a tier file holds only scaffold content at upload time
- **THEN** the run skill leaves it out of the upload
- **AND** it names the file in `<journal>`

#### Scenario: A missing run-skill file is not dropped

- **WHEN** a tier file that is not scaffold-only is missing and the CLI rejects the batch
- **THEN** the skill does not remove that file from the command to make the upload pass
- **AND** it handles the rejection as an upload failure

#### Scenario: A second upload of the same names replaces the first

- **WHEN** the run skill uploads the same five names at Completion and again before teardown
- **THEN** the second upload replaces the earlier copy of each name
- **AND** S3 holds one key per name for the test

### Requirement: The run skill uploads the report at Completion step 2

At Completion, the run skill SHALL write `1-summary.md` and run the check step per `references/report.md` before it builds.  When the check passes and the build succeeds, the run skill SHALL run one `$EDB report upload` command with the five tier files, before it shows the step 3 menu.  A build is successful only when `make` exits 0 and `docs/report/index.html` exists.  The skill MUST NOT upload until the check passes and the build succeeds.  At Completion with no teardown, a failed check SHALL block the build until it is fixed.  A failed step-2 upload MUST NOT affect the cluster.

#### Scenario: Successful check and build trigger the upload

- **WHEN** the check passes, `make -C <cluster-dir>/docs` exits 0, and `<cluster-dir>/docs/report/index.html` exists
- **THEN** the skill runs one `$EDB report upload` with the five tier files
- **AND** it does this before it shows the step 3 menu

#### Scenario: Failed check blocks the build at Completion

- **WHEN** the check fails at Completion and no teardown follows
- **THEN** the skill does not build or upload until the failure is fixed

#### Scenario: Failed build blocks the upload

- **WHEN** the mdbook build fails or `docs/report/index.html` is missing
- **THEN** the skill does not upload
- **AND** it diagnoses, logs to `<issues>`, fixes the build, and runs `make` again before any upload

#### Scenario: Successful upload is journaled

- **WHEN** the step-2 upload exits 0
- **THEN** `<journal>` records the command and its result

#### Scenario: Step-2 upload fails in an interactive session

- **WHEN** the step-2 upload exits non-zero and the user has not asked to shut down
- **THEN** the skill shows the CLI error, writes the failure to `<journal>` and `<issues>`, and asks the user to retry or to continue to step 3
- **AND** the cluster is not affected

#### Scenario: Step-2 upload fails in an unattended session

- **WHEN** the step-2 upload exits non-zero and the run skill is unattended
- **THEN** the skill writes the failure to `<journal>` and `<issues>`
- **AND** it puts the failure in the completion report and continues to step 3

### Requirement: Every real top-level down is gated on a successful upload

Immediately before every real top-level `$EDB down` that a skill runs, the skill SHALL run Finalize and then the upload procedure.  Finalize SHALL be, in order: write `1-summary.md`; run the check (script, subagent, and `cassandra-expert` for a Cassandra run); on a non-redaction failure, apply the check-failure rule of `references/report.md`; run `make gate`.  The skill SHALL run `$EDB down --auto-approve` only if the upload exits 0, with two exceptions: a non-redaction check failure SHALL NOT block the `down`, and a redaction failure (`report-check.py` exit 3) SHALL skip the upload, be logged, and let the `down` run.  An upload retry SHALL re-upload only and SHALL NOT re-run the check.  A `down --dry-run` SHALL NOT need an upload.  `spark down` SHALL NOT be gated.  Each `down` attempt SHALL get its own upload first.

#### Scenario: Completion Option 2

- **WHEN** the user picks Completion Option 2
- **THEN** the skill runs Finalize and uploads the five tier files again
- **AND** it runs `$EDB down --auto-approve` only if the upload exits 0

#### Scenario: Shutdown intent stated earlier by the user

- **WHEN** the user stated a shutdown intent earlier in the session
- **THEN** the skill runs the same Finalize-upload-`down` sequence without prompting

#### Scenario: Shutdown intent stated by a launcher

- **WHEN** the launcher of an unattended run stated a shutdown intent
- **THEN** the skill treats it as a stated shutdown intent
- **AND** it runs the Finalize-upload-`down` sequence without prompting

#### Scenario: Shutdown after Option 1 exploration

- **WHEN** the user picks Option 1, explores, and later asks to shut down
- **THEN** the skill runs Finalize and uploads the tier files, with the current journal, before `$EDB down`
- **AND** it runs `down` only if the upload exits 0

#### Scenario: Gate order

- **WHEN** a skill reaches a teardown gate
- **THEN** it writes the summary, runs the check, runs `make gate`, uploads, and only then runs `down`

#### Scenario: Check failure does not block the down

- **WHEN** a non-redaction check fails at the gate
- **THEN** the report uploads with the "⚠ Unchecked: <reasons>" Caveats line and the `down` runs after a successful upload

#### Scenario: Redaction failure skips the upload

- **WHEN** `report-check.py` exits 3 at the gate
- **THEN** the skill does not upload, logs the failure, and runs `$EDB down --auto-approve`

#### Scenario: Upload retry does not re-check

- **WHEN** the upload at the gate fails and the user picks retry
- **THEN** the skill re-runs only the upload

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

When the upload before teardown exits non-zero in an interactive session, the skill MUST NOT run `down`.  It SHALL show the CLI error, write the failure to `<journal>` and `<issues>`, and ask the user to retry, shut down anyway, or keep the cluster up.  The reference SHALL explain the two CLI failure messages: the validation rejection ("Nothing was uploaded. Rejected: ...") and the mid-batch failure ("Run report upload again").

#### Scenario: Upload fails before teardown

- **WHEN** the upload before teardown exits non-zero, for example for an expired AWS SSO session, an invalid filename, or a missing file
- **THEN** the skill does not run `down`
- **AND** it shows the CLI error, writes the failure to `<journal>` and `<issues>`, and asks the user what to do

#### Scenario: User says shut down anyway

- **WHEN** the user tells the skill to shut down anyway after a failed upload
- **THEN** the skill runs `$EDB down --auto-approve`
- **AND** it writes to `<journal>` that the report was not uploaded

#### Scenario: User fixes the cause and retries

- **WHEN** the user fixes the cause, for example with `aws sso login`, and asks for a retry
- **THEN** the skill uploads again
- **AND** it runs `down` only if the new upload exits 0

#### Scenario: User keeps the cluster up

- **WHEN** the user chooses to keep the cluster up after a failed upload
- **THEN** the skill does not run `down`
- **AND** it records the choice in `<journal>`

### Requirement: Unattended upload failure before teardown stops the teardown

When the run skill is unattended and the upload before teardown fails, the skill MUST NOT run `down`, unless the launcher explicitly instructed it to shut down anyway.  It SHALL write the failure to `<journal>` and `<issues>` and report the failure to the launcher at that stop point, as the unattended rule requires.  When the launcher's explicit "shut down anyway" instruction exists, the skill SHALL record it verbatim in `<journal>` before it runs `down`.  This rule SHALL NOT apply to a redaction failure, which skips the upload and lets the `down` run.

#### Scenario: Unattended failure with no override

- **WHEN** the run skill is unattended, the upload before teardown fails, and the launcher gave no explicit "shut down anyway" instruction
- **THEN** the skill does not run `down`
- **AND** it writes the failure to `<journal>` and `<issues>` and reports the failure to the launcher at that stop point

#### Scenario: Launcher authorizes shut down anyway

- **WHEN** the run skill is unattended, the upload before teardown fails, and the launcher explicitly instructed it to shut down anyway
- **THEN** the skill records the launcher's instruction verbatim in `<journal>`
- **AND** it runs `$EDB down --auto-approve` and writes to `<journal>` that the report was not uploaded

### Requirement: Multi-DC uploads go through every DC wrapper before any down

In a multi-DC workspace, the skill SHALL upload the same tier files through every DC's wrapper, with absolute paths to the shared `<cluster-dir>/docs/`.  It SHALL run `down` on any DC only after every DC's upload exits 0, and then it SHALL run `$EDB down --auto-approve` on every DC.  The journal SHALL record each DC's upload result separately.  The skill SHALL derive the Mimir URL and tenant per DC wrapper for `report-graph.py fetch`.  The explore skill SHALL use the same rule.  This rule SHALL apply to `LAYOUT=multi` only; `LAYOUT=arms` SHALL follow the arms upload rule.

#### Scenario: All DC uploads succeed

- **WHEN** a multi-DC teardown runs and every DC's upload exits 0
- **THEN** the skill runs `down --auto-approve` through every DC's wrapper
- **AND** `<journal>` records each DC's upload result separately

#### Scenario: One DC upload fails

- **WHEN** a multi-DC teardown runs and one DC's upload exits non-zero
- **THEN** the skill runs `down` on no DC
- **AND** it follows the interactive or unattended failure handling

#### Scenario: Multi-DC Completion step 2

- **WHEN** a multi-DC run reaches Completion step 2 with a passing check and a successful build
- **THEN** the skill uploads the five tier files through every DC's wrapper
- **AND** it records each DC's result separately

### Requirement: Explore uploads every eligible docs markdown file before teardown

When the explore skill tears down a workspace that has a `docs/` directory, it SHALL first run Finalize per `references/report.md`.  It SHALL list every existing `docs/*.md` explicitly, exclude `SUMMARY.md`, and exclude every tier file that holds only scaffold content.  It SHALL name each excluded file in `<journal>`.  It SHALL upload the remaining files in one command per DC wrapper before `$EDB down`, with the same exit-code gate and failure handling as the run skill.  When no `docs/` exists or no eligible file remains, it SHALL run `$EDB down --auto-approve` and SHALL NOT try to upload.

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
- **AND** `<journal>` names each excluded file

#### Scenario: SUMMARY.md and scaffold-only tier files are excluded

- **WHEN** any tier file holds only scaffold content, and `docs/` holds `SUMMARY.md`
- **THEN** both skills exclude those files from the upload
- **AND** `<journal>` names each excluded file

#### Scenario: A rejected batch in explore

- **WHEN** the explore upload is rejected, for example for a stray `index.md` or a bad file name
- **THEN** the skill does not run `down`
- **AND** it follows the normal failure handling

## ADDED Requirements

### Requirement: Image and CSV upload is detected through the support check

At discovery, the skill SHALL extend the `report upload` support check: support for images and CSV SHALL exist only when the `report upload <FILE>` line in `$EDB commands` lists both `.png` and `.csv`.  Without that support, the skill SHALL upload only `.md` files.  With that support, the skill SHALL also upload every `images/*.png` and `data/*.csv` that the uploaded tier files reference, by absolute path.

#### Scenario: Binary does not accept images and CSV

- **WHEN** the binary's `report upload` does not accept images and CSV
- **THEN** the skill uploads only `.md` files
- **AND** the upload succeeds

#### Scenario: Binary accepts images and CSV

- **WHEN** the binary's `report upload` accepts images and CSV
- **THEN** the skill also uploads `images/*.png` and `data/*.csv`, detected through the support check

### Requirement: Cross-cluster arms upload through the arm gate and the final upload

In `LAYOUT=arms`, each arm's gate SHALL upload `3-plan-<arm>.md`, `4-journal-<arm>.md`, and `5-issues-<arm>.md` through that arm's wrapper, with the existing upload-failure handling, before that arm's `down`.  The coordinator's final upload SHALL send every top-level `.md` that `docs/SUMMARY.md` links, by absolute path, minus scaffold-only files, through every arm's wrapper.  The final upload SHALL run no `down`.  A later arm upload SHALL replace only that arm's files; the index keeps the rest.

#### Scenario: Arm gate upload

- **WHEN** an arm agent reaches its teardown gate
- **THEN** it uploads its own plan, journal, and issues files through its own wrapper
- **AND** it runs `down` on its own arm only if the upload exits 0

#### Scenario: Final upload list

- **WHEN** the coordinator runs `run <test-dir> --finalize`
- **THEN** the upload holds `1-summary.md`, `2-evidence.md`, `3-plan.md`, every `3-plan-<arm>.md`, `4-journal.md`, `5-issues.md`, and every `4-journal-<arm>.md` and `5-issues-<arm>.md`, minus scaffold-only files
- **AND** it runs through every arm's wrapper

### Requirement: The AWS SSO session check warns and never strands a cluster

Before it provisions, the skill SHALL run the SSO session check in `references/report-upload.md`.  The check SHALL read only key names and `expiresAt` from the profile's SSO cache entry, and SHALL NOT print or store any token value.  Because the SDK refreshes the cached access token from its refresh token for the whole Identity Center session, a short `expiresAt` SHALL produce a warning and SHALL NOT stop a run.  The check SHALL stop the run, and ask for `aws sso login --profile "$AWS_PROFILE"`, only when there is no cached token, no refresh token, or `aws sts get-caller-identity` fails; the stop line SHALL include the first line of the `sts` error.  Before each upload and each teardown, an expired-token or expired-SSO error SHALL stop the run with the cluster up: an interactive run asks for the login, and an unattended run reports CLUSTER STILL UP with the workspace path.  After the login, the run SHALL resume at the gate.

#### Scenario: A short token with a refresh token only warns

- **WHEN** the cached access token has 10 minutes left and the cache entry holds a refresh token
- **THEN** the check prints a warning with the minutes left and the run continues

#### Scenario: No refresh token stops the run

- **WHEN** the cache entry holds no refresh token
- **THEN** the check stops the run and asks for `aws sso login --profile "$AWS_PROFILE"`

#### Scenario: An sts failure stops the run with its cause

- **WHEN** `aws sts get-caller-identity` fails
- **THEN** the check stops the run and its stop line includes the first line of the error

#### Scenario: An expired session at the upload keeps the cluster up

- **WHEN** an upload fails with an expired-token error in an unattended run
- **THEN** the skill runs no `down` and reports CLUSTER STILL UP with the workspace path
