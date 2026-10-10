## Context

The easy-db-lab plugin has three skills that touch a cluster: `plan` writes `plan.md`, `run` executes it in a cluster workspace and owns all reporting (`docs/journal.md`, `docs/issues.md`, `docs/results.md`, the mdbook build), and `explore` is an interactive guide.  The binary now has `report upload FILE...`, which puts markdown files into the current test's documents in S3 and rebuilds the Grafana document index.  No skill calls it.  Today `run` Completion Option 2 runs a bare `$EDB down` with no gate, and `explore` Teardown has no report step.

The skills also carry tool details that drift: `references/commands.md` is a hand-written copy of `$EDB commands` output in an old format, and several skill lines hard-code commands that no longer exist.  The owner's principle: agents learn the tool's capabilities from the binary first, so they adapt to whatever tool version is present.  Skills carry policy (when to upload, the gate on `down`); the binary carries syntax.

The wrapper that `setup-cluster.sh` writes `cd`s into its own directory before it execs the binary.  In a multi-DC workspace the wrappers are at `<cluster-dir>/<dc>/easy-db-lab`, and `docs/` is shared at the cluster root, so relative `docs/` paths break.  Each DC has its own `state.json` and is a separate Grafana test.

## Goals / Non-Goals

**Goals:**

- Every real top-level `$EDB down` that a skill runs is preceded by a successful upload of the markdown report, or by an explicit, journaled decision to shut down anyway.
- The report reaches Grafana at Completion even if the cluster stays up.
- One shared reference holds the upload procedure and the gate; skills point to it.
- Skills learn commands from the binary (`$EDB help`, `$EDB help <topic>`, `$EDB commands`, `--help`) and stop when no binary resolves.
- Stale command syntax in the skills and `environment.md` is fixed or replaced by a pointer to the right `help <topic>`.

**Non-Goals:**

- Changes to the easy-db-lab CLI, including adding `report upload` to a help topic.
- Uploading images, `docs/report/` HTML, or any non-markdown file.
- Uploads during plan execution, for example after each step.
- Retry or backoff logic beyond asking the user (or reporting to the launcher).
- `down --all` and `down <vpcId>`.
- Special handling for existing plans that contain a `down` step (owner Q3b).
- Live tests of the upload failure paths (owner Q9).

## Decisions

### Decision 1: one shared reference, gate stated as a property of `down`

Create `plugins/easy-db-lab/references/report-upload.md`.  It holds the upload procedure and the teardown gate.  The gate is one rule: immediately before every real top-level `$EDB down` (not `spark down`, not `--dry-run`), run the upload procedure; run `$EDB down --auto-approve` only on exit 0.  `run/SKILL.md` states the rule once near "Run Commands to Completion" and its Completion bullets point to the reference.  `explore/SKILL.md` Teardown points to the same reference.

### Decision 2: the upload procedure

1. Build the file list before the command.  List each file explicitly by absolute path `<cluster-dir>/docs/<name>`.  Never pass a raw glob to the CLI.
2. Write the journal entry for the upload before the command runs (the rule at `run/SKILL.md:179`).  The uploaded journal therefore holds the upload intent but not the later `down` entry.  This is acceptable (A3).
3. Run one `$EDB report upload <files...>` per DC wrapper, to completion.
4. Check the exit code.  Record the result in `journal.md`, per DC.
5. On failure, show the CLI error, write to `journal.md` and `issues.md`, and follow the failure handling below.  The reference explains the two failure messages: "Nothing was uploaded. Rejected: ..." (validation; nothing stored) and the mid-batch failure that names stored documents and says "Run report upload again" (index not rebuilt).

### Decision 3: run uploads the fixed four; explore uploads every eligible `docs/*.md`

The run skill scaffolds all four files, so it always uploads `results.md journal.md issues.md plan.md`.  It never drops a file to make the upload pass (A4).

The explore skill lists every `docs/*.md` that exists, then excludes `SUMMARY.md` (mdbook scaffolding) always, and excludes `results.md` while it holds only the scaffold comments.  The journal names each excluded file.  The list is fixed before the command runs.  No `docs/` or no eligible file means no upload, and `down` runs.  A rejected batch (for example a stray `index.md`, which the CLI reserves, or a bad name) goes through the normal failure gate.

### Decision 4: failure handling

- **Interactive, before teardown:** do not run `down`.  Show the CLI error.  Write to `journal.md` and `issues.md`.  Ask: retry, shut down anyway, or keep the cluster up.  "Shut down anyway" runs `$EDB down --auto-approve` and writes to `journal.md` that the report was not uploaded.  A retry re-runs the upload and runs `down` only on success.  Each `down` attempt gets its own upload first.
- **Interactive, at step 2:** the cluster is not affected.  Show the error, log it, and ask: retry or continue to step 3.
- **Unattended, before teardown:** never run `down` after a failed upload, unless the launcher explicitly instructed "shut down anyway"; record that instruction verbatim in `journal.md`.  Log the failure to `journal.md` and `issues.md` and report to the launcher at that stop point.
- **Unattended, at step 2:** log the failure, put it in the completion report, and continue.
- A launcher's stated shutdown intent counts as a stated intent for automatic teardown.
- **Unattended with no teardown intent:** Completion step 3 reports "cluster still up" to the launcher and stops.  A new run-skill resume entry point, "Completion / teardown", lets a coordinator or the owner relaunch the run skill on the workspace to run the gated teardown.  A coordinator must not run `$EDB down` itself.

### Decision 5: multi-DC

Upload the same files through every DC's wrapper.  Run `down` on any DC only after every DC's upload succeeds; then run `down --auto-approve` on every DC.  The journal records each DC's upload result separately.  Explore uses the same rule, with `docs/` at the cluster root.

### Decision 6: `report upload` support detection

At discovery, the skill checks `$EDB commands` for `report upload`.  If it is absent, uploads are not supported: the skill skips every upload, notes it once in `journal.md`, and runs `down --auto-approve` with no gate.

### Decision 7: discovery from the binary; delete `commands.md`

Delete `references/commands.md` and every reference to it (`run/SKILL.md:46`, `:220`; `plan/SKILL.md:66`, `:272`, `:301`).  Discovery order in every skill: `$EDB help`, then `$EDB help <topic>`, then `$EDB commands` and `--help`.  Explore gets this order; run and plan already have it.  No binary means fail fast: the skill stops and reports the paths searched, and writes nothing from memory.  Run keeps its ask-for-`--binary` question and fails only when the user has no path or the path is not executable.  Interactive plan and explore ask for a path first; unattended never asks.

### Decision 8: explore resolves `$EDB` through `detect-cluster-layout.sh`

Explore runs `detect-cluster-layout.sh` first and uses the wrapper or wrappers it finds; multi-DC yields the list of DC wrappers for Decision 5.  With no workspace, explore uses `bin/easy-db-lab`, then `PATH`.  If none resolves, Decision 7's fail-fast applies.

### Decision 9: plan skill drops teardown

Remove teardown guidance from the plan skill (`plan/SKILL.md:138`, `:231`, `:281`) and state that teardown belongs to the run skill's Completion gate.  Add one sentence at `plan/SKILL.md:23` that excludes teardown steps from the `--previous` carry-over.  The rule that the run skill owns all reporting (`plan/SKILL.md:234`) stays, so plans contain no upload step.

### Decision 10: folded-in debt

- Explore Teardown loses `$EDB down --clickhouse.backup`; the flag does not exist.
- Every gated `down` is `$EDB down --auto-approve`.  A bare `down` reads stdin for confirmation, and the agent's Bash tool has no stdin.
- Multi-DC `down` targets every DC after all uploads (Decision 5).
- Stale syntax, per the amended QD: explore `logs backup`, `logs ls`, `metrics backup`, `metrics ls` become a pointer to `$EDB help observability`; run `cassandra nodetool` becomes `cassandra nt`; `environment.md:65` drops `easy-db-lab metrics` for a pointer to `help observability`; explore init lines change `--db/--app` to `--db.count/--app.count` (init lines only; `--db`/`--app` are real flags on `hosts`) and bare `easy-db-lab` to `$EDB`.

## Alternatives Considered

### D1: where the gate lives

- **Recommended by the architect (CHOSEN, owner Q1):** a new shared `plugins/easy-db-lab/references/report-upload.md` with (1) the upload procedure (fixed allowlist results/journal/issues/plan, absolute paths, journal entry, run, check exit code, record result and S3 URIs, how to read the two failure messages) and (2) the teardown gate ("Immediately before every real `$EDB down`, run the upload procedure; run `down` only on exit 0"; dry-run exempt; interactive/unattended failure handling; shut-down-anyway logs report not uploaded; re-upload before each down attempt).  The gate is phrased as a property of `down`, one rule in run near "Run Commands to Completion" (`run/SKILL.md:69`); Completion bullets point to it.  Chosen because the procedure exists once and both skills point to it.  The owner added that the gate applies to every real top-level `$EDB down`, not `spark down`.
- **Alternative 1 (rejected):** inline the full text in each skill.  Self-contained, but the procedure exists twice and drifts; run would repeat it at three points.
- **Alternative 2 (rejected):** keep the gate in run and have explore point at `../run/SKILL.md`.  This couples one skill to another skill's internals; the repo does not do this anywhere else.

### D2 / F2: a plan step that runs `down`

- **Recommended by the architect (rejected):** treat a plan step whose command is a real `down` as a stated shutdown intent, and defer it to Completion.
- **Alternative (rejected):** gate it where it stands.  This uploads a placeholder `results.md` and never builds the report.
- **Alternative (rejected):** leave it out of scope.
- **OWNER OVERRIDE (not any architect option, Q3):** "just remove the teardown from the plan. the agent knows how to tear the cluster down."  The plan skill stops telling authors to add teardown steps (`plan/SKILL.md:138`, `:231`, `:281`), and the plan skill comes into scope.  Existing plans with a `down` step get no special handling (Q3b); the general gate from D1 covers them.

### D3: which files explore uploads

- **Recommended by the architect (rejected):** a fixed allowlist of the four names; include each that exists; one command; no `docs/` or none of the four means no upload.
- **Alternative B (architect rejected; CHOSEN by the owner):** upload all `docs/*.md`.  The architect rejected it because it sweeps in `SUMMARY.md`, a stray `index.md` (reserved, `DocumentNames.kt:61`) or a bad name rejects the batch, and the set is unbounded.
- **Alternative C (rejected):** require all four, and ask if one is missing.  Explore would prompt almost every time.
- **Alternative D (rejected):** ask the user which files at every teardown.
- **OWNER OVERRIDE (Q4, refined by QC):** the owner chose "upload all `docs/*.md`" over the architect's fixed-four allowlist.  After the second critic pass, the owner refined it: always exclude `SUMMARY.md`, and exclude `results.md` while it holds only scaffold comments; the journal names each excluded file; the list is fixed before the command runs (A4-compatible), never a raw glob (F8).  A rejected batch goes through the normal failure gate.  The run skill keeps the fixed four.

### D4: `commands.md`

- **Recommended by the architect (rejected):** full regeneration from the local binary (about 515 changed lines; the flag format changed to `--hosts=<hostList>`, positionals print `<FILE> (required)`), rewrite the preamble, and amend the acceptance criterion to `<FILE>`.
- **Alternative (rejected):** hand-insert a report block in the old format.
- **Alternative (rejected):** change the CLI `paramLabel`.  Out of scope.
- **OWNER OVERRIDE (Q5, Q5 clarification, Q5b):** delete `commands.md` entirely.  "get rid of it. the agent should discover the commands and help topics automatically."  Agents discover from the binary (`$EDB help`, `help <topic>`, `commands`, `--help`), so they adapt to whatever tool version is present.  No binary means fail fast: "the point of the skill is to use the binary."  The issue's `commands.md` acceptance criterion is replaced.

### D5: failure handling

- **Interactive (CHOSEN):** on failure, no `down`; show the CLI error; write to journal and issues; ask retry, shut down anyway, or keep the cluster up.  Step-2 failure: retry or continue to step 3.
- **Unattended (CHOSEN):** never `down` after a failed upload; log both; report to the launcher; a step-2 failure goes in the completion report and the run continues.
- **Sub-decision, recommended by the architect (CHOSEN by the owner, Q2):** a launcher's explicit instruction may count as "shut down anyway", recorded verbatim in `journal.md`.  A launcher's stated shutdown intent also counts for automatic teardown.
- **Sub-decision alternative, the design critic's reading (rejected by the owner):** never shut down after a failed upload in unattended mode.  **Note:** here the owner picked the architect's alternative over the critic's reading.
- **Multi-DC, recommended (CHOSEN, Q7):** upload through every DC's wrapper; `down` on any DC only after all uploads succeed.  The journal records each DC's result separately.
- **Multi-DC alternative (rejected):** first DC only.
- **Out of scope:** `down --all`, `down <vpcId>`.

### Debt

- **Fold in (CHOSEN, Q8):** explore Teardown `--clickhouse.backup`, which does not exist.
- **Fold in (CHOSEN, Q8):** `$EDB down --auto-approve` after a successful upload.  A bare `down` reads stdin (`Down.kt:513-519`); the agent's Bash has no stdin.  `easy-db-lab help provisioning` step 5 already shows `down --auto-approve`.
- **Plan-skill teardown wording:** now in scope (owner Q3).
- **Multi-DC down targeting:** folded in (CHOSEN, owner Q8).
- Nothing is filed separately.

## Verified facts

- **A1 (confirmed against CLI source, easy-db-lab HEAD 71bb3ae2):** the S3 key is `reports/<tenant>/<name>-<clusterId>/<file.name>` (`TestDocumentService.kt:89`, `ObservabilityStore.kt:62-72`, `ClusterState.kt:386`).  A plain `PutObjectRequest` overwrites (`S3ObjectStore.kt:56-67`).  The index is rebuilt by listing every `.md` and is deduped by name (`TestDocumentService.kt:102-113`, `DocumentIndex.kt:73-74`).  A later upload of fewer files never removes earlier documents.  The same basename twice in one invocation rejects the batch (`DocumentNames.kt:39-44`).
- **A2:** `--dry-run` returns before teardown (`Down.kt:404`, `:438`, `:476`).  `down` never deletes `reports/` (`Down.kt:598-599`).  Upload works after `down` (`ReportUploadTest.kt:98`).
- **A3:** the file is read at upload time (`TestDocumentService.kt:90-92`).  The governing journal rule is `run/SKILL.md:179`.
- **A4:** `DocumentNames.rejected` checks every file first (`DocumentNames.kt:37-45`, `:57`); `DocumentsRejectedException` says "Nothing was uploaded. Rejected: ..." (`TestDocumentService.kt:15-19`, `:79-80`).  A second failure mode, `DocumentUploadFailedException` mid-batch, names the stored docs, says "Run report upload again", and does not rebuild the index (`:25-34`).  Both exit non-zero (`CommandExecutor.kt:201-208`, `CommandLineParser.kt:203-204`; `setup-cluster.sh:96` execs the binary).
- **F1:** the wrapper `cd`s into its own directory (`setup-cluster.sh:94-95`).  The multi-DC wrapper is at `<cluster-dir>/<dc>/easy-db-lab`; relative `docs/` paths break.  Use absolute `<cluster-dir>/docs/...`.  Each DC has its own `state.json`, which is a separate Grafana test.
- **`help provisioning`:** `easy-db-lab help provisioning` step 5 reads "`easy-db-lab down --auto-approve` — destroy everything."  Re-checked against the local binary for this change.
- **No help topic mentions report upload:** none of the nine topics (`cassandra`, `connecting`, `kits`, `observability`, `profiles`, `provisioning`, `querying`, `spark`, `stress-testing`) contains "report upload".  Only `$EDB commands` lists it (`report upload` with `<FILE> (required)`).  So the skills must carry the upload-before-down policy; the syntax comes from the binary.  Adding it to a help topic is a CLI change and is out of scope.
- **Stale commands (verified live against the local binary):** `logs backup`, `logs ls`, `metrics *`, and `cassandra nodetool` do not exist (`cassandra nt` does).  `down --clickhouse.backup` does not exist; `down` has `--all`, `--packer`, `--dry-run`, `--auto-approve`/`-a`/`--yes`, `--force`, and `<vpcId>`.  `init --db/--app` are legacy aliases that still work; the current flags are `--db.count`/`--app.count`.

## Risks / Trade-offs

- [Each upload costs S3 PUTs, and an expired-SSO failure can be slow because of retries (`RetryUtil`, `S3ObjectStore.kt:63-67`).] → The cost is a few PUTs per teardown.  The slow failure ends in the normal failure gate; the skill shows the error and suggests `aws sso login`.
- [A later upload of fewer files never removes earlier documents.] → Accepted.  The run skill always sends the same four names, so the second upload replaces the first.
- [Explore's every-`docs/*.md` rule can sweep in a stray or badly named file and reject the batch.] → `SUMMARY.md` and a scaffold-only `results.md` are excluded; any other rejection goes through the normal failure gate, where the CLI message names the rejected file.
- [The uploaded journal lacks the final `down` entry.] → Accepted (A3).  The local journal holds it.
- [No help topic documents `report upload`, so an agent may not learn its policy from the binary.] → The skills carry the policy in `report-upload.md`; only syntax comes from the binary.
- [No harness or eval covers easy-db-lab skills.] → Live end-to-end runs under gitignored `tests/` verify the happy paths.  Failure paths are verified by reading the skill text (owner Q9).
- [Removing `commands.md` means an agent with no binary has no reference.] → Intended: the skill fails fast and reports the paths searched.

## Migration Plan

Markdown-only change; it lands with the plugin.  Existing workspaces need no migration.  Existing plans with a `down` step need no special handling; the gate on every real `down` covers them.  Rollback is a revert of the PR.

## Open Questions

None.  The owner decision record resolves every design question.
