# deck scripts

- `generate-deck.py` — deterministic generator (git diff + docs -> a self-contained HTML deck).
  Stdlib only, no pip deps. See `../SKILL.md` for the full CLI and manifest schema.
- `init-deck.sh` — bootstraps a curated (hand-authored) deck directory. macOS bash 3.2 compatible.
- `test-generate-deck.sh` — structural self-test for the two scripts above.

## Running the test

```bash
plugins/spec-flow/skills/deck/scripts/test-generate-deck.sh
```

No arguments. It builds a throwaway git repo + fixture files under `mktemp -d`, runs
`generate-deck.py` against them, and asserts:

- the output HTML file exists
- it contains no literal `<!--MANIFEST-->` (the marker was fully replaced)
- it contains no `http://`, `https://`, or `fetch(` substring (self-contained, no network)
- the embedded `window.MANIFEST` JSON parses, with the expected node count and kind mix
  (one `diff` node, four `markdown` nodes, one `code` node)
- the `diff` node's `patch` field round-trips the actual known change made to the fixture file,
  and its `path` matches the changed file

It also greps `assets/viewer.html` for the structural markers a browser-side test would otherwise
check — `window.MANIFEST`, a `kind === "diff"` / `"code"` / `"markdown"` branch for each of the
three node kinds, and a markdown-render + diff-parse function — since there's no headless browser
available to actually execute the viewer's JS here.

Prints `PASS`/`FAIL` per assertion and a final tally; exits non-zero if anything failed, so it's
usable as a CI check. Requires `git` and `python3` (bash 3.2 compatible otherwise); no other
dependencies.
