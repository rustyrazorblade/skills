# report-upload.md — Report Upload and Teardown Gate

`$EDB report upload FILE...` puts markdown files into the current test's documents in S3.  It then rebuilds the document index that the Grafana Tests and comparison dashboards show.  This reference holds the upload procedure and the teardown gate.  The run and explore skills both follow it.

The skills carry the policy: when to upload, and the gate on `down`.  The binary carries the syntax.  Read the syntax of `report upload` from `$EDB commands`.  No `$EDB help <topic>` guide covers it.

## Support Check

At discovery, check `$EDB commands` for `report upload`:

```bash
$EDB commands | grep -A2 '^  report'
```

If `report upload` is absent, the binary does not support uploads.  Then:

- Skip every upload, at run Completion step 2 and before teardown.
- Write this once in `docs/journal.md`: the binary has no `report upload`, so the skill skips every upload.  If `docs/journal.md` does not exist yet, the run skill writes the note in its first journal entry after scaffolding.  If the explore skill has no `docs/` directory, tell the user instead.
- Run `$EDB down --auto-approve` with no gate.

## Choose the Files

Build the file list before the command runs.  Name each file explicitly by its absolute path, `<cluster-dir>/docs/<name>`.  Never pass a raw glob to the CLI.  The wrapper changes to its own directory before it runs the binary, so a relative `docs/` path breaks.

### Run skill: the fixed four

The run skill always uploads the same four files:

```bash
$EDB report upload \
  <cluster-dir>/docs/results.md \
  <cluster-dir>/docs/journal.md \
  <cluster-dir>/docs/issues.md \
  <cluster-dir>/docs/plan.md
```

Never drop one of these four files to make an upload pass.  If a file is missing and the CLI rejects the batch, treat it as an upload failure.  A second upload of the same four names replaces the earlier copy of each name, so S3 holds one key per name for the test.

### Explore skill: every eligible `docs/*.md`

1. If `<cluster-dir>/docs/` does not exist, do not upload.  Tell the user "docs/ not found; no report uploaded" before `down`.  In an unattended session, put this line in the report to the launcher.  Go to the teardown gate as if the upload exited 0.
2. List every `.md` file that exists directly in `<cluster-dir>/docs/`.
3. Exclude `SUMMARY.md`.  It is mdbook scaffolding.
4. Exclude `results.md` while it holds only the scaffold headings and comments.  This command prints nothing for a scaffold-only file: `grep -v -E '^[[:space:]]*(#|<!--.*-->[[:space:]]*$|$)' <cluster-dir>/docs/results.md`.
5. Write each excluded file name in `docs/journal.md`.
6. If no eligible file remains, do not upload.  Go to the teardown gate as if the upload exited 0.
7. Otherwise, write the remaining files as absolute paths in one `$EDB report upload` command.

Fix the list before the command runs.  Do not change the list to make a rejected batch pass.

## Upload Procedure

1. Choose the files, as above.
2. Write the journal entry for the upload in `docs/journal.md` before the command runs.  The entry names the command and the files.  The uploaded journal then holds the upload intent, but not the later `down` entry.  This is acceptable; the local journal holds the full record.
3. Run one `$EDB report upload <files...>` command per DC wrapper.  Run each command to completion.
4. Check the exit code of each command.
5. Record each DC's result in `docs/journal.md`: the exit code, and the output on success or the CLI error on failure.
6. If any command exits non-zero, show the CLI error, write the failure to `docs/journal.md` and `docs/issues.md`, and follow "Failure Handling" below.

## Teardown Gate

The gate applies to every real top-level `$EDB down` that a skill runs.  It does not apply to `$EDB spark down`.  It does not apply to `$EDB down --dry-run`, because a dry run destroys nothing.

Immediately before every real top-level `$EDB down`:

1. Run the upload procedure.
2. If every upload exits 0, run `$EDB down --auto-approve`.  Never run a bare `$EDB down`: it waits for a confirmation on stdin, and the Bash tool has no stdin.
3. If an upload exits non-zero, do not run `down`.  Follow "Failure Handling" below.

Each `down` attempt gets its own upload first.  An earlier successful upload does not cover a later `down`, because the journal has changed since then.

This gate covers a plan step that runs a real `$EDB down`.  Such a step needs no special handling.

## Multi-DC

In a multi-DC workspace, each DC has its own wrapper at `<cluster-dir>/<dc>/easy-db-lab` and is a separate Grafana test.  `docs/` is shared at the cluster root.

1. Upload the same files through every DC's wrapper, with absolute paths to `<cluster-dir>/docs/`.
2. Record each DC's upload result in a separate `docs/journal.md` entry.
3. If any DC's upload exits non-zero, run `down` on no DC.  Follow "Failure Handling" below.
4. After every DC's upload exits 0, run `$EDB down --auto-approve` through every DC's wrapper.

The same rule applies at run Completion step 2: upload through every DC's wrapper, and record each DC's result separately.

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
3. Write the failure to `docs/journal.md` and `docs/issues.md`.
4. Ask the user to choose: retry, shut down anyway, or keep the cluster up.

- **Retry:** the user can fix the cause first, for example with `aws sso login`.  Run the upload procedure again.  Run `$EDB down --auto-approve` only if the new upload exits 0.  If it fails again, start this procedure again at step 1.
- **Shut down anyway:** run `$EDB down --auto-approve`, on every DC.  Write in `docs/journal.md` that the report was not uploaded.
- **Keep the cluster up:** do not run `down`.  Write the choice in `docs/journal.md`.

### Interactive, at run Completion step 2

The cluster is not affected.

1. Show the CLI error to the user.
2. Write the failure to `docs/journal.md` and `docs/issues.md`.
3. Ask the user to choose: retry, or continue to step 3.

### Unattended, before teardown

1. Do not run `down`, unless the launcher explicitly instructed the skill to shut down anyway.
2. Write the failure to `docs/journal.md` and `docs/issues.md`.
3. If the launcher gave no explicit "shut down anyway" instruction, report the failure to the launcher at this stop point, and stop.  The cluster stays up.
4. If the launcher gave an explicit "shut down anyway" instruction, write that instruction verbatim in `docs/journal.md`.  Then run `$EDB down --auto-approve`, on every DC, and write in `docs/journal.md` that the report was not uploaded.

A stated shutdown intent is not a "shut down anyway" instruction.  It starts the gated teardown; it does not authorize a `down` after a failed upload.

### Unattended, at run Completion step 2

1. Write the failure to `docs/journal.md` and `docs/issues.md`.
2. Put the failure in the completion report to the launcher.
3. Continue to step 3.
