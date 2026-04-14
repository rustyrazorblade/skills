# Skills Repository — Claude Instructions

## Local Development

To test plugin skills locally as slash commands, use `bin/claude` instead of `claude`. It passes `--plugin-dir` pointing at the local plugin directory:

```bash
bin/claude
```

This is required because there is no declarative way to register a local plugin directory in `.claude/settings.json`. The `--plugin-dir` flag is the only mechanism for local plugin testing.

## cassandra-expert Plugin

### Training Skill Architecture

The `cassandra-expert:training` skill delivers interactive, session-based Cassandra training.

**How it's structured:**

```
plugins/cassandra-expert/skills/training/
  SKILL.md                           ← instructor persona + methodology
  sessions/
    01-fundamentals.md               ← session index (topic list + reference file paths)
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

Both the session file names and the reference folder names are numbered (`NN-session-name`) to give sessions a canonical order.

**Key design principles:**
- Each topic is a **separate reference file**, loaded on demand (not all in context at once)
- Session files are lightweight indexes: topic name + path to reference file
- The SKILL.md defines pedagogy; it does NOT contain topic content

**Adding a new session:**
1. Create `sessions/NN-<session-name>.md` with a topic table (name + reference file path)
2. Add topic files to `references/training/NN-<session-name>/NN-topic-name.md`
3. Register the session in `skills/training/SKILL.md` under "Available Sessions"

**Adding a new topic to an existing session:**
1. Create `references/training/NN-<session>/NN-topic-name.md`
2. Add a row to the session index file (`sessions/NN-<session>.md`)
3. Number topics sequentially (NN = two-digit number)

**Topic file structure (required sections):**
- `## Objective` — one sentence: what the learner will know
- `## Why This Matters` — the critical reasoning for correct Cassandra usage
- `## Concept` — explanation with tables/diagrams as needed
- `## Examples` — CQL and code (Go, Java, Python) — all three where relevant
- `## Pulse Check` — one or more questions, each followed by the expected answer in italics and parentheses. Topics that cover multiple distinct ideas (e.g. types, table options, DML basics) should have a pulse check per major idea so each one gets tested.

**Sessions planned:**
- `01-fundamentals` — developer focused (DONE)
- `02-query-anti-patterns` — query and application anti-patterns (DONE)
- `03-schema-anti-patterns` — schema design anti-patterns (DONE)
- `04-sai` — Storage-Attached Indexes deep dive (DONE)
- `operators` — operator focused (TODO)

**Validation scripts (strongly preferred for any factual claim):**

When training material or reference docs make a concrete claim about what Cassandra accepts, rejects, or does — column kinds that can be indexed, operators that parse, specific yaml settings, driver behavior — write a Python script that exercises the claim against a live cluster and records PASS/FAIL vs. expected. These scripts sit in `plugins/cassandra-expert/skills/training/scripts/` with a `README.md` cataloguing what each one tests.

Reference: `skills/training/scripts/verify-sai-capabilities.py` is the canonical pattern. It follows these conventions:
- **Self-contained, uv-runnable via PEP 723 inline metadata.** First two lines are `#!/usr/bin/env -S uv run --script` and a `# /// script` block declaring `requires-python` and `dependencies`. Users run with a single `uv run path/to/script.py`; no venv setup needed.
- **List of case dicts**, each with `name`, the CQL / action under test, and `expect_accept` (boolean). Queries/operators and column-kind tests live in separate lists (`OPERATOR_CASES`, `CASES`, etc.) so they can be extended independently.
- **Catches the specific server exceptions** (`InvalidRequest`, `SyntaxException`) and reports the first line of the server message alongside PASS/FAIL — so when a case fails, the output tells you *why* the server rejected it, not just that it did.
- **Creates and drops its own keyspace** (e.g. `sai_verify`) so runs are idempotent and don't pollute the cluster.
- **Exits 0 if every case matches expectation, non-zero otherwise.** This makes the script usable in CI.
- **Documented in a sibling `README.md`** with requirements (uv, reachable 5.0+ cluster), an invocation example, and a bulleted list of cases expected to accept vs. reject.

When new features or claims are added to the training, add cases to the existing scripts where they fit, or create a new script in the same directory with the same pattern. Claims that can be mechanically verified should be — the cost of a broken claim in teaching material is much higher than the cost of a few lines of Python.

**Cassandra documentation source (for auditing training material):**
- Use these to verify CQL syntax, version-specific features, and command accuracy
- Jon's recommendations in reference files OVERRIDE generic Cassandra docs

**Coding standards for examples:**
- Always show Go, Java, AND Python examples for driver-level code
- Go: gocql auto-prepares — note this explicitly
- Java/Python: must explicitly call `session.prepare()` — show this pattern
- Always use prepared statements with `?` placeholders, never string concatenation
