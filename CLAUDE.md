# Skills Repository: Claude Instructions

## How work reaches this repo

Three rules govern every change here.  They are not defaults to weigh; they hold unless Jon says otherwise for a specific piece of work.

**Always work on a branch, in a worktree.**  Never edit the shared checkout to make a change.  Create a worktree for the branch and work there.  This keeps the shared checkout on `main` and clean, so the branch you are standing on is never a surprise.

**File new issues with `/spec-flow:groom`.**  Do not write an issue body by hand, and do not call `gh issue create` directly.  `groom` interviews for the shape of the work, records the scope, the acceptance criteria and the chosen design, and applies the labels the pipeline reads.  An issue filed any other way is missing the parts every later stage depends on.

**Never change `main` directly without Jon's authorization for that change.**  Committing to `main`, pushing to `main`, and merging into it each need him to say so first.  Authorization for one change does not carry to the next.

## Local development

To test plugin skills locally as slash commands, install the local directory as a marketplace.  Then add all the plugins.

## Plugin settings.json: never set a default agent

Do not create a settings.json file at a plugin root, such as plugins/<plugin>/settings.json, with an "agent" field.  This field makes Claude Code run the main thread as that agent at startup, in every project, whenever the plugin is enabled.  Keep agents available for explicit invocation; do not let one hijack the main thread.  If you find such a file, remove it.

## Template naming: `<destination-filename>.template`

A template a plugin ships for seeding a file in a consuming repo, whose destination is a single named file, is named for the file it becomes: the destination filename, plus a `.template` suffix.  A reader then pairs the two without opening either.

Worked example: `plugins/spec-flow/references/TESTING.md.template` is copied into a consuming repo as `spec-flow/TESTING.md`.

The rule does not reach a template with no single destination.  `plugins/spec-flow/references/ci/github-actions-gradle.yml` and its nextest sibling are named for the runner they wire, because the owner picks one of several and names the copied workflow file themselves.

## Version bumping

When you work on a branch or PR, ask if the user wants to bump the plugin version.  Show the current version.  Ask for the new version before you make any changes.

Two files hold the version for each plugin; update both together:
- `plugins/<plugin>/.claude-plugin/plugin.json`, the `version` field
- `plugins/<plugin>/.codex-plugin/plugin.json`, the `version` field

Example:
```
Current version: 0.1.0
What should the new version be?
```

Once the user confirms, update both files.  Do not bump the version without asking first.

## easy-db-lab plugin: testing

Local test runs live in `tests/` at the repo root; this directory is gitignored.  Plans go under `tests/plans/`.  Cluster workspaces go under `tests/clusters/`.  For example:

```
tests/
  plans/
    single-node-cassandra.md
  clusters/
    20240530-143022/     ← cluster workspace created by setup-cluster.sh
```

Use this directory for end-to-end tests of the plan-to-run flow, locally.

## cassandra-expert plugin: training skill architecture

The `cassandra-expert:training` skill delivers interactive, session-based Cassandra training.

Structure:

```
plugins/cassandra-expert/skills/training/
  SKILL.md                           ← instructor persona and methodology
  sessions/
    01-fundamentals.md               ← session index: topic list plus reference file paths
    02-query-anti-patterns.md
    03-schema-anti-patterns.md
    04-sai.md

plugins/cassandra-expert/references/training/
  01-fundamentals/
    01-data-distribution.md
    02-keyspaces.md
    03-types.md
    04-tables-primary-key.md
    ... (and so on)
  02-query-anti-patterns/
  03-schema-anti-patterns/
  04-sai/
```

Session file names and reference folder names both follow the `NN-session-name` pattern.  This numbering gives each session a canonical order.

Key design principles:
- Each topic lives in its own reference file, loaded on demand, not all held in context at once.
- Session files stay lightweight: a topic name plus a path to its reference file.
- SKILL.md defines the pedagogy. It does not hold topic content.

To add a session: create `sessions/NN-<session-name>.md` with a topic table (name plus reference path), add topic files under `references/training/NN-<session-name>/NN-topic-name.md`, and register the session in `skills/training/SKILL.md` under "Available Sessions."

To add a topic to an existing session: create `references/training/NN-<session>/NN-topic-name.md`, add a row to `sessions/NN-<session>.md`, and number it in sequence (NN = a two-digit number).

Each topic file needs these sections:
- `## Objective`, one sentence on what the learner will know.
- `## Why This Matters`, the key reasoning for correct Cassandra usage.
- `## Concept`, an explanation, with tables or diagrams as needed.
- `## Examples`, CQL and code in Go, Java, and Python, where relevant.
- `## Pulse Check`, one or more questions, each followed by the expected answer in italics and parentheses.  A topic that covers several distinct ideas needs a pulse check per idea, so each one gets tested.

Sessions planned: `01-fundamentals`, `02-query-anti-patterns`, `03-schema-anti-patterns`, and `04-sai` are done.  `operators`, an operator-focused session, is next.

### Validation scripts

Prefer these for any factual claim: which column kinds Cassandra can index, which operators parse, a specific yaml setting, or driver behavior.  For each claim, write a Python script that exercises it against a live cluster and records PASS or FAIL against the expected result.  Keep these scripts under `plugins/cassandra-expert/skills/training/scripts/`, with a `README.md` that catalogs what each one tests.

`skills/training/scripts/verify-sai-capabilities.py` is the canonical pattern:
- Self-contained, uv-runnable via PEP 723 metadata: the first two lines are `#!/usr/bin/env -S uv run --script` and a `# /// script` block declaring `requires-python` and `dependencies`. Run it with one command, `uv run path/to/script.py`; no venv setup needed.
- A list of case dicts, each with `name`, the CQL or action under test, and `expect_accept` (a boolean). Keep query/operator cases and column-kind cases in separate lists (`OPERATOR_CASES`, `CASES`), so each grows independently.
- Catches `InvalidRequest` and `SyntaxException` and reports the first line of the server message with PASS or FAIL, so a failure shows why the server rejected it.
- Creates and drops its own keyspace, such as `sai_verify`, so runs stay idempotent.
- Exits 0 only if every case matches its expectation, so it works in CI.
- Ships with a sibling `README.md`: requirements (uv, a reachable 5.0+ cluster), an invocation example, and the cases expected to accept or reject.

When you add a new feature or claim to the training, add cases to an existing script where they fit, or create a new script in the same directory, in the same pattern.  Verify any claim you can verify mechanically: a broken claim in teaching material costs far more than a few lines of Python.

### Cassandra documentation source

When you audit training material, use the official Cassandra docs to verify CQL syntax, version-specific features, and command accuracy.  Jon's recommendations in reference files override generic Cassandra docs.

### Coding standards for examples

- Show Go, Java, and Python examples for driver-level code.
- Go: note explicitly that gocql auto-prepares.
- Java and Python: show the explicit `session.prepare()` call.
- Always use prepared statements with `?` placeholders.  Never use string concatenation.
