# report-upload.md — Report Upload and Teardown Gate

`$EDB report upload FILE...` puts markdown files into the current test's documents in S3.  It then rebuilds the document index that the Grafana Tests and comparison dashboards show.  This reference holds the upload procedure and the teardown gate.  The run and explore skills both follow it.

The report itself, and Finalize, follow `report.md`.  This reference names the journal and the issues file by role: `<journal>` and `<issues>`.  `report.md` resolves each role to a file name per layout.

The skills carry the policy: when to upload, and the gate on `down`.  The binary carries the syntax.  Read the syntax of `report upload` from `$EDB commands`.  No `$EDB help <topic>` guide covers it.

## Support Check

At discovery, check `$EDB commands` for `report upload`:

```bash
$EDB commands | grep -A2 '^  report'
```

If `report upload` is absent, the binary does not support uploads.  Then:

- Skip every upload, at run Completion step 2 and before teardown.
- Write this once in `<journal>`: the binary has no `report upload`, so the skill skips every upload.  If `<journal>` does not exist yet, the run skill writes the note in its first journal entry after scaffolding.  If the explore skill has no `docs/` directory, tell the user instead.
- Run `$EDB down --auto-approve` with no gate.

### Image and CSV support

Today `report upload` accepts `.md` files only.  Check once, at discovery, whether this binary also accepts images and CSV:

```bash
$EDB commands | awk '{ match($0, /^ */); i = RLENGTH } r && i <= ri { r = 0 } u && i <= ui { u = 0 } !r && $1 == "report" { r = 1; ri = i; next } r && !u && $1 == "upload" { u = 1; ui = i; next } u && $1 == "<FILE>" && /\.png/ && /\.csv/ { ok = 1 } END { exit !ok }' && echo "images and CSV: supported" || echo "images and CSV: not supported"
```

`$EDB commands` prints `report`, `upload`, and the `<FILE>` argument on three lines, each indented below the one before.  The probe reads only the `<FILE>` line inside the `report` and `upload` block.  Support exists only when that line lists both `.png` and `.csv`.  Record the result once in `<journal>`.

- **Not supported:** upload only `.md` files.
- **Supported:** also upload every `images/*.png` and `data/*.csv` file that the uploaded tier files reference, by absolute path.

## Choose the Files

Build the file list before the command runs.  Name each file explicitly by its absolute path, `<cluster-dir>/docs/<name>`.  Never pass a raw glob to the CLI.  The wrapper changes to its own directory before it runs the binary, so a relative `docs/` path breaks.

### Run skill: the five tier files

In a single-cluster workspace, and in each DC of a multi-DC workspace, the run skill uploads the five tier files:

```bash
$EDB report upload \
  <cluster-dir>/docs/1-summary.md \
  <cluster-dir>/docs/2-evidence.md \
  <cluster-dir>/docs/3-plan.md \
  <cluster-dir>/docs/4-journal.md \
  <cluster-dir>/docs/5-issues.md
```

Nested evidence pages, such as `evidence/latency.md`, are not in the list.  They are in the book and in `export/report.zip`.

The only file the run skill may leave out is a tier file that holds only scaffold content: headings and one-line comments.  This command prints nothing for a scaffold-only file: `grep -v -E '^[[:space:]]*(#|<!--.*-->[[:space:]]*$|$)' <file>`.  Name each such file in `<journal>`.

Never drop any other tier file to make an upload pass.  If a file is missing and the CLI rejects the batch, treat it as an upload failure.  A second upload of the same five names replaces the earlier copy of each name, so S3 holds one key per name for the test.

### Explore skill: every eligible `docs/*.md`

1. If `<cluster-dir>/docs/` does not exist, do not upload.  Tell the user "docs/ not found; no report uploaded" before `down`.  In an unattended session, put this line in the report to the launcher.  Go to the teardown gate as if the upload exited 0.
2. List every `.md` file that exists directly in `<cluster-dir>/docs/`.
3. Exclude `SUMMARY.md`.  It is mdbook scaffolding.
4. Exclude every tier file that holds only scaffold content.  This command prints nothing for a scaffold-only file: `grep -v -E '^[[:space:]]*(#|<!--.*-->[[:space:]]*$|$)' <cluster-dir>/docs/<file>`.
5. Write each excluded file name in `<journal>`.
6. If no eligible file remains, do not upload.  Go to the teardown gate as if the upload exited 0.
7. Otherwise, write the remaining files as absolute paths in one `$EDB report upload` command.

Fix the list before the command runs.  Do not change the list to make a rejected batch pass.

## Upload Procedure

1. Choose the files, as above.
2. Write the journal entry for the upload in `<journal>` before the command runs.  The entry names the command and the files.  The uploaded journal then holds the upload intent, but not the later `down` entry.  This is acceptable; the local journal holds the full record.
3. Run one `$EDB report upload <files...>` command per DC wrapper.  Run each command to completion.
4. Check the exit code of each command.
5. Record each DC's result in `<journal>`: the exit code, and the output on success or the CLI error on failure.
6. If any command exits non-zero, show the CLI error, write the failure to `<journal>` and `<issues>`, and follow "Failure Handling" below.

## Teardown Gate

The gate applies to every real top-level `$EDB down` that a skill runs.  It does not apply to `$EDB spark down`.  It does not apply to `$EDB down --dry-run`, because a dry run destroys nothing.

Immediately before every real top-level `$EDB down`:

1. Run Finalize, per `report.md`: write `1-summary.md`; run the check in its order (the script, `cassandra-expert` for a Cassandra run, the issues written to `<issues>`, then the subagent); on a non-redaction failure, apply the teardown-gate check-failure rule; run `make gate`.
2. Run the upload procedure.
3. If every upload exits 0, run `$EDB down --auto-approve`.  Never run a bare `$EDB down`: it waits for a confirmation on stdin, and the Bash tool has no stdin.
4. If an upload exits non-zero, do not run `down`.  Follow "Failure Handling" below.  A retry re-runs the upload only; it does not re-run the check.

Two exceptions to step 4's rule:

- **A non-redaction check failure** never blocks the `down`.  `make gate` writes the "⚠ Unchecked: <reasons>" line under Caveats, the failure goes to `<issues>`, and the report uploads.  The `down` runs after a successful upload.
- **A redaction failure** (`report-check.py` exits 3) skips the upload.  Write the failure to `<journal>` and `<issues>`, and run `$EDB down --auto-approve`.  An unattended run reports "report not uploaded: redaction" to the launcher.  The owner fixes the report and uploads later with `run <cluster-dir> --finalize`, which runs no `down`.

Each `down` attempt gets its own Finalize and upload first.  An earlier successful upload does not cover a later `down`, because the journal has changed since then.

This gate covers a plan step that runs a real `$EDB down`.  Such a step needs no special handling.

### A failed down after a good upload

A `down` can fail after every upload exits 0, for example when the SOCKS proxy drops in the middle of the `down`.  Some services can already be stopped.

1. This is not an upload failure.  Do not use "Failure Handling" below.
2. Write the `down` command and its error to `<journal>` and `<issues>`.
3. Run the gate again once: Finalize, the upload procedure, then `$EDB down --auto-approve`.  The journal has changed, so the upload must run again.
4. If the second `down` also fails, stop.  Leave the cluster for a manual retry.
5. Report the failure to the user, or to the launcher in an unattended run.  Give the workspace path and the `down` error.

## Multi-DC

This section applies to `LAYOUT=multi` only.  `LAYOUT=arms` follows "Arms" below.

In a multi-DC workspace, each DC has its own wrapper at `<cluster-dir>/<dc>/easy-db-lab` and is a separate Grafana test.  `docs/` is shared at the cluster root.

1. Upload the same tier files through every DC's wrapper, with absolute paths to `<cluster-dir>/docs/`.
2. Record each DC's upload result in a separate `<journal>` entry.
3. If any DC's upload exits non-zero, run `down` on no DC.  Follow "Failure Handling" below.
4. After every DC's upload exits 0, run `$EDB down --auto-approve` through every DC's wrapper.

The same rule applies at run Completion step 2: upload the five tier files through every DC's wrapper, and record each DC's result separately.  For `report-graph.py fetch`, derive the Mimir URL, the tenant, and the `cluster` label per DC wrapper.

## Arms

In `LAYOUT=arms`, each arm is its own cluster and its own Grafana test.  `docs/` is shared at the test directory.

### The arm gate

Before an arm's `down`, the arm agent uploads its own three files through its own wrapper:

```bash
$EDB report upload \
  <test-dir>/docs/3-plan-<arm>.md \
  <test-dir>/docs/4-journal-<arm>.md \
  <test-dir>/docs/5-issues-<arm>.md
```

Use the normal upload procedure and failure handling.  Run `down` on this arm only, and only if the upload exits 0.  The arm gate writes no summary, and it runs no check and no `make`.

### The final upload

The coordinator's `run <test-dir> --finalize` uploads the full report once, after the last arm reports.  The list is every top-level `.md` file that `docs/SUMMARY.md` links, by absolute path, minus scaffold-only files: `1-summary.md`, `2-evidence.md`, `3-plan.md`, every `3-plan-<arm>.md`, `4-journal.md`, `5-issues.md`, and every `4-journal-<arm>.md` and `5-issues-<arm>.md`.  Upload it through every arm's wrapper, and record each arm's result in `<journal>`.  The final upload runs no `down`.

A later arm upload replaces only that arm's three files.  The index keeps the rest.

## Reading a Failure

The CLI has two failure messages.  Both exit non-zero.

- **Validation rejection:** `Nothing was uploaded. Rejected: ...`.  The CLI checks every file before it stores any file.  The message names each rejected file and the reason.  Nothing is stored, and the index does not change.
- **Mid-batch failure:** the message names the documents that were stored, and tells you to `Run report upload again`.  Some files are in S3, but the index is not rebuilt.  A later successful upload of the same files rebuilds it.

Common causes:

- **Expired AWS SSO session.**  The CLI retries before it fails, so this failure can be slow.  Tell the user to run `aws sso login` and then retry.
- **Invalid file name.**  A name must end in `.md` and use only letters, numbers, `.`, `_`, and `-`.
- **Missing file.**  A file in the list does not exist.
- **Stray `index.md`.**  The CLI reserves the name `index.md` for the index, so it rejects the batch.

## Failure Handling

### Interactive, before teardown

1. Do not run `down`.
2. Show the CLI error to the user.
3. Write the failure to `<journal>` and `<issues>`.
4. Ask the user to choose: retry, shut down anyway, or keep the cluster up.

- **Retry:** the user can fix the cause first, for example with `aws sso login`.  Run the upload procedure again.  Do not re-run the check.  Run `$EDB down --auto-approve` only if the new upload exits 0.  If it fails again, start this procedure again at step 1.
- **Shut down anyway:** run `$EDB down --auto-approve`, on every DC.  Write in `<journal>` that the report was not uploaded.
- **Keep the cluster up:** do not run `down`.  Write the choice in `<journal>`.

### Interactive, at run Completion step 2

The cluster is not affected.

1. Show the CLI error to the user.
2. Write the failure to `<journal>` and `<issues>`.
3. Ask the user to choose: retry, or continue to step 3.

### Unattended, before teardown

1. Do not run `down`, unless the launcher explicitly instructed the skill to shut down anyway.
2. Write the failure to `<journal>` and `<issues>`.
3. If the launcher gave no explicit "shut down anyway" instruction, report the failure to the launcher at this stop point, and stop.  The cluster stays up.
4. If the launcher gave an explicit "shut down anyway" instruction, write that instruction verbatim in `<journal>`.  Then run `$EDB down --auto-approve`, on every DC, and write in `<journal>` that the report was not uploaded.

This rule does not apply to a redaction failure.  A redaction failure skips the upload and lets the `down` run; see "Teardown Gate" above.

A stated shutdown intent is not a "shut down anyway" instruction.  It starts the gated teardown; it does not authorize a `down` after a failed upload.

### Unattended, at run Completion step 2

1. Write the failure to `<journal>` and `<issues>`.
2. Put the failure in the completion report to the launcher.
3. Continue to step 3.
