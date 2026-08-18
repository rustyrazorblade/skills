## 1. Extract shared helpers (do first — pure refactor, no behavior change)

- [x] 1.1 Create `plugins/review-tools/lib/html_shell.py` containing `fail()`, the
      `<!--MANIFEST-->` marker-injection helper (`inject_manifest()`), and the temp-output-path
      helper (`default_out_path()`), moved verbatim from `generate-explain.py`.
- [x] 1.2 Refactor `plugins/review-tools/skills/explain/scripts/generate-explain.py` to import
      these three from `plugins/review-tools/lib/html_shell.py` instead of defining them locally —
      no other change to that file.
- [x] 1.3 Re-run `plugins/review-tools/skills/explain/scripts/test-generate-explain.sh` — must
      still be 85/85 passing. Fix immediately if not; this must land clean before any new code is
      built on top of it.

## 2. Manifest schema and validation

- [ ] 2.1 Create `plugins/review-tools/skills/walkthrough/scripts/generate-walkthrough.py` with the
      manifest schema from design.md decision 2 (`title`, `subtitle?`, `diagram: {type, source,
      caption?}`, `steps: [{title, narration, kind?, excerpts: [{path, startLine, endLine?, code,
      lang?, highlight?}]}]`).
- [ ] 2.2 Implement validation, using `fail()` from `html_shell.py`, matching spec.md's
      requirements exactly:
      - missing/unreadable/empty manifest, or empty `steps` → fail, no output file
      - missing/empty `diagram`, or empty `diagram.source` → fail
      - a step missing `title`/`narration`/non-empty `excerpts` → fail naming the step (1-based
        index + title if present)
      - an excerpt missing `path`/`startLine`/`code` → fail naming both the step and the excerpt
- [ ] 2.3 CLI surface: `generate-walkthrough.py --manifest <path.json> [--out <path>] [--open]` —
      no `--title`/`--subtitle` flags. Same "print path + `open <path>` line, `--open` only for
      foreground use" contract as `explain`, via the shared helpers from section 1.

## 3. Viewer shell (assets/viewer.html)

- [ ] 3.1 Create `plugins/review-tools/skills/walkthrough/assets/viewer.html` — self-contained,
      vanilla JS, no framework, no build step, `<!--MANIFEST-->` marker for injection, a
      `DEMO_MANIFEST` fallback for opening the shell directly (matching `explain`'s own
      convention).
- [ ] 3.2 Diagram renders first (before any step content): embed `diagram.source` (SVG or HTML)
      directly, plus `diagram.caption` if given.
- [ ] 3.3 Steps render in manifest order: title, narration (markdown — copy `explain`'s
      `renderMarkdown`/`inlineMD` logic into this file per design.md decision 8, don't write a
      second renderer), one-or-more code excerpts (each showing `path:startLine`-`endLine`, a
      `data-lang` attribute from `lang` if given, `highlight` lines visually distinguished via
      CSS), and a `kind` badge if present (any string value → a badge; unrecognized values get a
      generic/neutral style; omitted → no badge).
- [ ] 3.4 Vertical-scroll default layout (steps stacked top-to-bottom).
- [ ] 3.5 Runtime toggle control: flips a `.horizontal` class on the steps container; CSS switches
      to horizontal layout via `scroll-snap-type: x mandatory` — no JS-driven animation.
      Re-toggling returns to vertical. One artifact, no regeneration needed either direction.
- [ ] 3.6 Horizontal-mode nav chrome: step counter ("Step N of M"), prev/next buttons, and
      keyboard left/right arrow navigation — all functional for moving between steps.
- [ ] 3.7 Confirm no `http://`, `https://`, or `fetch(` anywhere in the shell — self-contained,
      `file://`-safe.

## 4. Fixtures and test suite

- [ ] 4.1 Create `plugins/review-tools/skills/walkthrough/scripts/fixtures/` with small JSON
      manifests: a valid multi-step manifest (diagram + 2+ steps, at least one with a `kind`, at
      least one step with multiple excerpts), and one fixture per failure mode (missing manifest
      path handled by test invocation itself; empty manifest; missing diagram; empty diagram
      source; step missing title; step missing narration; step with empty excerpts; excerpt
      missing path; excerpt missing startLine; excerpt missing code).
- [ ] 4.2 Create `plugins/review-tools/skills/walkthrough/scripts/test-generate-walkthrough.sh`,
      bash 3.2 compatible (no associative arrays, no `mapfile`), following
      `test-generate-explain.sh`'s conventions: a `check()` helper tallying PASS/FAIL,
      JSON-shaped assertions delegated to `python3 -` for parsing rendered HTML.
- [ ] 4.3 Test coverage, one case per spec.md requirement/scenario:
      - valid manifest renders: diagram before all step content, steps in given order
      - self-containment: no `http(s)://`/`fetch(` in rendered output
      - defaults to vertical layout (structural check for the absence of the `.horizontal` class
        on initial render, and presence of the toggle control)
      - toggle control and horizontal-mode CSS/JS are structurally present (grep-based check on
        the rendered HTML, same "no headless browser" convention `test-generate-explain.sh`
        already uses for `viewer.html`'s own JS)
      - nav chrome elements (counter, prev/next, keyboard handler) structurally present
      - code excerpt + file:line reference render inside their step
      - non-"how it works" `kind` values (`tech-debt`/`performance`/`recommendation`) render
        through the same code path as `explanation` — same assertion logic, different fixture
      - `kind` present → badge present; `kind` omitted → no badge; unrecognized `kind` string
        still renders (doesn't fail)
      - no manifest / empty manifest / empty steps → non-zero exit, no output file
      - step missing a required field → non-zero exit, error names the step
      - excerpt missing a required field → non-zero exit, error names step + excerpt
      - missing diagram / empty diagram source → non-zero exit, clear error
- [ ] 4.4 Full run: all new tests passing, plus `test-generate-explain.sh` still 85/85 (re-verify
      after section 1's refactor is in place alongside the new code).

## 5. Documentation

- [ ] 5.1 Write `plugins/review-tools/skills/walkthrough/SKILL.md`: manifest schema (mirroring how
      `explain`'s `SKILL.md` documents its own schema), CLI usage, and — the actual "how to use
      me" contract — guidance for the invoking agent on what to investigate before authoring a
      manifest and how to write a good diagram/narration for each of the five walkthrough kinds
      (explanation, tech-debt, improvements, recommendations, performance).
- [ ] 5.2 Write `plugins/review-tools/skills/walkthrough/scripts/README.md` documenting the test
      suite, mirroring `explain`'s sibling `scripts/README.md`.

## 6. Versioning

- [ ] 6.1 Ask the owner to confirm the exact new version number for
      `plugins/review-tools/.claude-plugin/plugin.json` before changing it (this repo's
      established convention — propose a minor bump per the repo's stated default, from whatever
      the current version is at implementation time).
- [ ] 6.2 Update `plugin.json`'s `description`/`keywords` to mention `walkthrough` alongside
      `explain`.
