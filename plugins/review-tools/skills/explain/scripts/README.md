# explain scripts

- `generate-explain.py` — deterministic generator (a git diff, a GitHub issue + its related
  issues, and/or docs -> a self-contained HTML explain view). Stdlib only + shells out to
  `git`/`gh`, no pip deps. See `../SKILL.md` for the full CLI and manifest schema.
- `init-explain.sh` — bootstraps a curated (hand-authored) explain view directory. macOS bash 3.2
  compatible.
- `test-generate-explain.sh` — structural self-test for the two scripts above.

## Running the test

```bash
plugins/review-tools/skills/explain/scripts/test-generate-explain.sh
```

No arguments. It builds a throwaway git repo + fixture files under `mktemp -d`, runs
`generate-explain.py` against them, and asserts:

- the output HTML file exists
- it contains no literal `<!--MANIFEST-->` (the marker was fully replaced)
- it contains no `http://`, `https://`, or `fetch(` substring (self-contained, no network)
- the embedded `window.MANIFEST` JSON parses, with the expected node count and kind mix
  (one `diff` node, four `markdown` nodes, one `code` node) when `--diff` is passed
- the `diff` node's `patch` field round-trips the actual known change made to the fixture file,
  and its `path` matches the changed file
- calling the generator with no flags at all fails loudly (non-zero exit), rather than silently
  producing an empty view
- `--issue` mode: with a faked `gh` on `PATH` (no network), a primary issue linked to one issue via
  a native dependency and another via a bare `#N` mention resolves to exactly those three markdown
  nodes, the primary node includes its comment thread, and no diff base/head ever appears in
  `meta` when `--diff` wasn't passed

It also greps `assets/viewer.html` for the structural markers a browser-side test would otherwise
check — `window.MANIFEST`, a `kind === "diff"` / `"code"` / `"markdown"` branch for each of the
three node kinds, and a markdown-render + diff-parse function — since there's no headless browser
available to actually execute the viewer's JS here.

Prints `PASS`/`FAIL` per assertion and a final tally; exits non-zero if anything failed, so it's
usable as a CI check. Requires `git` and `python3` (bash 3.2 compatible otherwise); `gh` is only
needed for the `--issue` mode test, and that test fakes it, so nothing here needs network access
or real GitHub credentials.
