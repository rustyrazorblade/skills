# walkthrough scripts

- `generate-walkthrough.py` — deterministic renderer (an agent-authored manifest -> a
  self-contained HTML presentation). Stdlib only; no pip deps, no `git`/`gh`, no network. See
  `../SKILL.md` for the full CLI and manifest schema.
- `test-generate-walkthrough.sh` — structural self-test for the script above and the viewer shell.
- `fixtures/` — the manifests the test suite runs against: `valid.json` and `kinds.json` for the
  happy paths, `script-data-content.json` for the injection-escaping regression, and one small
  manifest per failure mode (empty, unparseable, no title, no diagram, empty diagram source,
  unsupported diagram type, empty steps, a step missing its title or narration, a step with an
  empty excerpt list, an excerpt missing its path/startLine/code, and a bad `highlight`). The
  non-UTF-8 manifest case is built on the fly by the test itself rather than checked in as bytes.

## Running the test

```bash
plugins/review-tools/skills/walkthrough/scripts/test-generate-walkthrough.sh
```

No arguments, no network, no GitHub credentials, no `git` — it runs the generator against the
checked-in `fixtures/` and asserts on the output HTML. Requires `python3`; bash 3.2 compatible
otherwise (no associative arrays, no `mapfile`).

What it checks:

- a valid manifest exits 0 and produces an output file with no literal `<!--MANIFEST-->` left in it
- the output contains no `http://`, `https://`, or `fetch(` substring (self-contained, no network)
- the embedded `window.MANIFEST` JSON parses, and the title/subtitle, diagram (type, source,
  caption), step order, per-step `kind`, and each excerpt's `path`/`startLine`/`endLine`/`code`/
  `lang`/`highlight` all round-trip from the manifest
- the diagram container precedes all step content in the rendered document
- a `tech-debt`/`performance`/`recommendation` manifest renders through a **byte-identical** shell
  to an `explanation` one — the assertion that there is no per-kind code path
- an unrecognized `kind` string still renders rather than failing validation, and a step that omits
  `kind` carries no badge
- content that could break out of the injected `<script>` tag (an HTML-template excerpt containing
  `<!--[if IE]><script>…</script>`) leaves no raw `<` in the injected payload, still parses back to
  the exact authored code, and opens no extra script tag in the document
- every failure mode exits non-zero and leaves **no output file behind**; the step- and
  excerpt-level ones additionally name the offending step (1-based position + title) and the
  excerpt within it in the error message

It also greps `assets/viewer.html` for the structural markers a browser-side test would otherwise
check — the `window.MANIFEST` reference and `DEMO_MANIFEST` fallback, the markdown renderer, the
diagram/caption embedding, the kind badge, the `path:line` reference construction, `data-lang`, the
`scroll-snap-type: x mandatory` horizontal layout, the toggle control and its `.horizontal` class
flip, the counter, the prev/next buttons, and the `ArrowLeft`/`ArrowRight` keydown handler — plus
the fact that the steps container ships **without** the `.horizontal` class, since vertical is the
default. It also greps the shell itself for `http://`/`https://`/`fetch(`, so the `file://`-safety
holds even before a manifest is injected. There's no headless browser available here, so the
viewer's JS is checked for structure, not executed.

Prints `PASS`/`FAIL` per assertion and a final tally; exits non-zero if anything failed, so it's
usable as a CI check.
