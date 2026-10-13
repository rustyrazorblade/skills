# issues.md — Skill Feedback Log

The issues file is the file with the role `<issues>`: `docs/5-issues.md` in a single or multi-DC workspace, and `docs/5-issues-<arm>.md` for an arm agent.  `report.md` defines the roles.  It captures friction encountered during a lab session — anything confusing, undocumented, or surprising — so the skill and reference docs can be improved.  It is in the appendix of the lab report.

## Tool Friction Lives Only Here

Tool friction goes in `<issues>` only.  Never mention it in the summary (`1-summary.md`) or the evidence tier (`2-evidence.md`).  An issue that affects the result, for example a node that restarted during a measured window, also goes under `## Threats to validity` in `2-evidence.md`.

## When to Add an Entry

Add an issue whenever:
- A command behaved differently than the docs said
- The skill gave wrong or incomplete guidance
- Something took more trial and error than it should have
- An error message was unhelpful and a better explanation should be pre-empted in docs
- A flag name, default, or workflow step was unclear

Do not add entries for expected failures (e.g. CQL syntax errors from the user's own queries) or for things already documented accurately.

## Format

```markdown
# Issues

## <YYYY-MM-DD> — <session goal>

### Issue 1 — <short title>
**What happened:** <one or two sentences describing the confusion or failure>
**Expected:** <what the docs or skill implied would happen>
**Actual:** <what actually happened>
**Suggested fix:** <what should be updated in the skill or reference docs, and where>

### Issue 2 — <short title>
...
```

## Example

```markdown
### Issue 1 — `cassandra stress start` flag name mismatch
**What happened:** The plan said `--threads` but the CLI rejected it with "unknown flag".
**Expected:** `cassandra stress start KeyValue --threads 100` to work.
**Actual:** The correct flag is `--thread-count`.
**Suggested fix:** Update cassandra.md stress section to use `--thread-count`.
```

## What Happens to These Issues

Issues in `<issues>` are the source of record for improving the easy-db-lab skills. At the end of a session or when opening a new one, skim `<issues>` and — if you have enough context — propose concrete edits to the relevant reference or skill files. If the fix is clear, make it and note it resolved in the issue entry.
