## 1. Extract shared helpers (do first — pure refactor at this step; see task 7 for a later,
      deliberate departure discovered while building on top of it)

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

- [x] 2.1 Create `plugins/review-tools/skills/walkthrough/scripts/generate-walkthrough.py` with the
      manifest schema from design.md decision 2 (`title`, `subtitle?`, `diagram: {type, source,
      caption?}`, `steps: [{title, narration, kind?, excerpts: [{path, startLine, endLine?, code,
      lang?, highlight?}]}]`).
- [x] 2.2 Implement validation, using `fail()` from `html_shell.py`, matching spec.md's
      requirements exactly:
      - missing/unreadable/empty manifest, or empty `steps` → fail, no output file
      - missing/empty `diagram`, or empty `diagram.source` → fail
      - a step missing `title`/`narration`/non-empty `excerpts` → fail naming the step (1-based
        index + title if present)
      - an excerpt missing `path`/`startLine`/`code` → fail naming both the step and the excerpt
- [x] 2.3 CLI surface: `generate-walkthrough.py --manifest <path.json> [--out <path>] [--open]` —
      no `--title`/`--subtitle` flags. Same "print path + `open <path>` line, `--open` only for
      foreground use" contract as `explain`, via the shared helpers from section 1.

## 3. Viewer shell (assets/viewer.html)

- [x] 3.1 Create `plugins/review-tools/skills/walkthrough/assets/viewer.html` — self-contained,
      vanilla JS, no framework, no build step, `<!--MANIFEST-->` marker for injection, a
      `DEMO_MANIFEST` fallback for opening the shell directly (matching `explain`'s own
      convention).
- [x] 3.2 Diagram renders first (before any step content): embed `diagram.source` (SVG or HTML)
      directly, plus `diagram.caption` if given.
- [x] 3.3 Steps render in manifest order: title, narration (markdown — copy `explain`'s
      `renderMarkdown`/`inlineMD` logic into this file per design.md decision 8, don't write a
      second renderer), one-or-more code excerpts (each showing `path:startLine`-`endLine`, a
      `data-lang` attribute from `lang` if given, `highlight` lines visually distinguished via
      CSS), and a `kind` badge if present (any string value → a badge; unrecognized values get a
      generic/neutral style; omitted → no badge).
- [x] 3.4 Vertical-scroll default layout (steps stacked top-to-bottom).
- [x] 3.5 Runtime toggle control: flips a `.horizontal` class on the steps container; CSS switches
      to horizontal layout via `scroll-snap-type: x mandatory` — no JS-driven animation.
      Re-toggling returns to vertical. One artifact, no regeneration needed either direction.
- [x] 3.6 Horizontal-mode nav chrome: step counter ("Step N of M"), prev/next buttons, and
      keyboard left/right arrow navigation — all functional for moving between steps.
- [x] 3.7 Confirm no `http://`, `https://`, or `fetch(` anywhere in the shell — self-contained,
      `file://`-safe.

## 4. Fixtures and test suite

- [x] 4.1 Create `plugins/review-tools/skills/walkthrough/scripts/fixtures/` with small JSON
      manifests: a valid multi-step manifest (diagram + 2+ steps, at least one with a `kind`, at
      least one step with multiple excerpts), and one fixture per failure mode (missing manifest
      path handled by test invocation itself; empty manifest; missing diagram; empty diagram
      source; step missing title; step missing narration; step with empty excerpts; excerpt
      missing path; excerpt missing startLine; excerpt missing code).
- [x] 4.2 Create `plugins/review-tools/skills/walkthrough/scripts/test-generate-walkthrough.sh`,
      bash 3.2 compatible (no associative arrays, no `mapfile`), following
      `test-generate-explain.sh`'s conventions: a `check()` helper tallying PASS/FAIL,
      JSON-shaped assertions delegated to `python3 -` for parsing rendered HTML.
- [x] 4.3 Test coverage, one case per spec.md requirement/scenario:
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
- [x] 4.4 Full run: all new tests passing, plus `test-generate-explain.sh` still 85/85 (re-verify
      after section 1's refactor is in place alongside the new code).

## 5. Documentation

- [x] 5.1 Write `plugins/review-tools/skills/walkthrough/SKILL.md`: manifest schema (mirroring how
      `explain`'s `SKILL.md` documents its own schema), CLI usage, and — the actual "how to use
      me" contract — guidance for the invoking agent on what to investigate before authoring a
      manifest and how to write a good diagram/narration for each of the five walkthrough kinds
      (explanation, tech-debt, improvements, recommendations, performance).
- [x] 5.2 Write `plugins/review-tools/skills/walkthrough/scripts/README.md` documenting the test
      suite, mirroring `explain`'s sibling `scripts/README.md`.

## 6. Versioning

- [ ] 6.1 Ask the owner to confirm the exact new version number for
      `plugins/review-tools/.claude-plugin/plugin.json` before changing it (this repo's
      established convention — propose a minor bump per the repo's stated default, from whatever
      the current version is at implementation time).
- [x] 6.2 Update `plugin.json`'s `description`/`keywords` to mention `walkthrough` alongside
      `explain`.

## 7. Fixes from the implement review panel

- [x] 7.1 Fixed a real bash 3.2 syntax error in `test-generate-walkthrough.sh` (an apostrophe
      inside a Python comment nested in a heredoc within `$(...)` tripped a known bash 3.2
      command-substitution parser quirk) — the suite silently died mid-run under macOS system
      bash with no pass/fail tally at all, dropping ~60 of 108 assertions (every failure-mode
      case, the vertical-default check, all viewer-shell structural checks). Only appeared to
      pass because Homebrew bash was earlier in `$PATH` during earlier verification. Fixed by
      removing every apostrophe from the affected block, not just the one that first triggered
      it; verified 108/108 under real `/bin/bash` (bash 3.2.57) afterward.
- [x] 7.2 Fixed a real medium-severity XSS: `viewer.html`'s markdown link renderer accepted
      `javascript:`/`data:` URI schemes in step narration with no allow-list, so a link became
      click-to-execute script. Added `isSafeLinkUrl()` (http(s)/mailto or no explicit scheme only)
      and route link rendering through it — an unsafe URL renders as inert text instead of an
      anchor. `explain`'s own viewer has the identical pre-existing gap, fed genuinely untrusted
      GitHub content — flagged for the owner to triage separately, not fixed here (out of scope
      for this change).
- [x] 7.3 Fixed a real observability gap: if the injected manifest ever fails to parse for any
      reason (a future escaping regression, a truncated file), the viewer silently rendered
      `DEMO_MANIFEST` with zero diagnostic — a reviewer could mistake demo content for the real
      thing. `boot()` now logs to the console and shows a visible banner whenever
      `window.MANIFEST` is falsy, whatever the reason.
- [x] 7.4 `generate-walkthrough.py`: guarded the two output-side filesystem operations (reading
      `viewer.html`, writing the output file) with the same `try`/`except OSError` → `fail()`
      pattern already used on the read-manifest path, instead of letting them surface as a raw
      traceback. Also: `--open`'s `webbrowser.open()` return value is now checked, with a stderr
      warning on failure (e.g. a headless host) — previously silent.
- [x] 7.5 `generate-walkthrough.py`: `validate_diagram()` now rejects `http://`/`https://` in
      `diagram.source` — the one network-reference check the tool can cheaply make itself for
      spec.md's self-contained-output requirement, catching the most common real-world trigger
      (an SVG author's default `xmlns` attribute, which `SKILL.md` already tells agents to omit
      but nothing previously enforced).
- [x] 7.6 Added a dedicated regression case to `explain`'s own `test-generate-explain.sh` for the
      `inject_manifest()` escaping fix (7.7) — a `--doc` file quoting the same hostile
      `<!--`+`<script` shape walkthrough's fixture uses. Verified non-vacuous by temporarily
      reverting the escaping fix and confirming this exact case fails; 88/88 passing with the fix
      restored, under real bash 3.2.
- [x] 7.7 Corrected `proposal.md`, `design.md` (decision 7 and its matching Risks entry) to
      honestly describe the `inject_manifest()` escaping change bundled into the shared-lib work,
      instead of the original "pure extraction, no behavior change" claim — see design.md's Risks
      section for the full account of what was found and why it was kept rather than reverted.
      `overrides.md` needed no change: no requirement of the `explain` capability was added,
      modified, or removed (confirmed against `openspec/specs/explain/spec.md`) — only its
      implementation output changed, and strictly for the better.
- [x] 7.8 Fixed a self-referential comment typo in `html_shell.py` ("every `<` then becomes a `<`
      escape" → "... becomes a `\u003c` escape").

## 8. Fixes from the correctness (code-review) pass on round 1's own fixes

- [x] 8.1 Fixed a real falsy-zero bug in `viewer.html`: `Number(excerpt.startLine) || 1` silently
      replaced a legitimate `startLine: 0` with `1`, shifting every displayed gutter line number
      by one and breaking any `highlight` entry written against 0-based input, with no error at
      generation time. Fixed at the source instead: `validate_excerpt()` now rejects
      `startLine < 1` (line numbers are 1-based; 0 is not "unset" -- the field's absence already
      means that, and is already caught separately).
- [x] 8.2 Fixed a real bug in round 1's own diagram self-containment check (7.5): it was a
      case-sensitive substring match, so `HTTPS://` or `Http://` (URL schemes are case-insensitive
      per RFC 3986; easy to produce via autocapitalization or copy-paste) bypassed it silently.
      Now checks against a lowercased copy of `diagram.source`.
      Both caught by an independent correctness pass via the built-in `/code-review` skill.
      Regression-tested (`excerpt-startline-zero.json`, `diagram-mixed-case-url.json`); full
      suite: `test-generate-walkthrough.sh` 108 -> 117, `test-generate-explain.sh` unaffected at
      88 -- both verified under real `/bin/bash` (3.2.57).


## 9. Fixes from the test-rigor pass

- [x] 9.1 Added three wrong-type-input fixtures/cases (`not-an-object.json`,
      `title-wrong-type.json`, `steps-wrong-type.json`) -- every prior failure fixture tested a
      field being ABSENT or EMPTY, never PRESENT-with-the-wrong-shape (a top-level JSON array
      instead of an object, a non-string required field, a non-list `steps`) -- a real mistake an
      agent authoring a manifest by hand could make, and a real antagonistic gap.
- [x] 9.2 Added a positive-case fixture (`excerpt-code-with-url.json`) proving the diagram-only
      self-containment scope is real: an excerpt's `code` containing an `https://` URL is
      accepted and survives into the rendered output. Previously only the *rejection* side
      (`diagram.source` containing a URL) was tested -- a regression broadening the check to the
      whole manifest would have silently broken ordinary source code with a URL constant, with
      nothing in the suite to catch it.
- [x] 9.3 Added coverage for both `--open` outcomes (a documented part of the CLI contract) via
      direct `webbrowser.open` monkeypatching, not the `$BROWSER` env var -- confirmed live that
      `$BROWSER` is not a reliable cross-platform mock (macOS routes `webbrowser.open()` through
      its own AppleScript-based controller regardless of `$BROWSER`).
      `test-generate-walkthrough.sh`: 117 -> 135 passing, verified under real `/bin/bash`
      (3.2.57); `test-generate-explain.sh` unaffected at 88.

## 10. Remaining low-severity security finding

- [x] 10.1 SEC-2 (low): `diagram.source` is an intentional, unsanitized `innerHTML` sink -- the
      one place content executes with no click, unlike the SEC-1 link case -- but its trust
      constraint was undocumented. Added an explicit bullet to `SKILL.md`'s "Authoring the
      diagram" section: the markup must be agent-authored, never text copied from the code/docs/
      issues under review. No code change -- sanitizing would destroy the feature; the authoring
      rule is the only available control, so it needed to be written down.

## 11. Fixes from a second correctness pass (confirming round 8-10's own fixes)

- [x] 11.1 Fixed a real bypass in `isSafeLinkUrl` (7.2's XSS fix): a leading C0 control character
      (e.g. "\x01javascript:alert(1)") or an embedded tab/newline (e.g. "java\tscript:...") let
      a scheme check anchored on `^[a-zA-Z]` fall through to "no explicit scheme" -> accepted,
      while a browser's URL parser strips exactly those characters (WHATWG URL spec) before
      parsing the scheme and still executes it on click. Verified live with node before and
      after the fix. `isSafeLinkUrl` now normalizes the same way a browser does before testing
      the scheme.
- [x] 11.2 Broadened the diagram self-containment check (7.5/8.2) beyond http(s) to also catch
      `ftp://`, `ws://`, `wss://` -- other network schemes an agent could plausibly reference (an
      image src, a websocket) that the prior check silently let through. (Bare protocol-relative
      `//host/...` deliberately NOT added -- too common a substring in ordinary prose/markup for
      a plain substring match to catch safely; spec.md's own scenario only names http(s)
      explicitly.)
      Both caught by a second, focused correctness pass via `/code-review` confirming round
      8-10's own fixes -- this is genuinely a re-review, not the same pass repeated.
      Regression-tested (`diagram-ftp-scheme.json`; the link-scheme fix is covered structurally,
      since no headless browser is available in this suite -- correctness was verified live with
      node during development). `test-generate-walkthrough.sh`: 135 -> 142 passing, verified
      under real `/bin/bash` (3.2.57); `test-generate-explain.sh` unaffected at 88.

**Flagged for the owner, deliberately NOT fixed here (pre-existing gaps in `explain`, outside
this change's scope, found by the same pass):**
- `generate-explain.py`'s own output-side writes (`viewer_path.read_text`,
  `out_path.write_text`) are unguarded, unlike `generate-walkthrough.py`'s now-guarded
  equivalent (7.4) -- a raw traceback instead of a clean `fail()` message.
- `generate-explain.py`'s `--open` still discards `webbrowser.open()`'s return value with no
  diagnostic -- the exact gap fixed in `generate-walkthrough.py` (7.4).
- `explain`'s own markdown link renderer has the identical missing-scheme-allow-list gap as
  SEC-1 (7.2), fed genuinely untrusted GitHub content (already flagged there; repeated here for
  visibility since a second independent pass found it too).

## 12. Fixes from a third correctness pass (nothing new caused by rounds 11's fixes themselves)

- [x] 12.1 Fixed the exact falsy-zero class of bug the `startLine` fix (8.1) closed, but left
      open for `endLine`: `validate_excerpt()` never validated `endLine` at all, so
      `endLine: 0` (or any wrong-typed value) passed silently while the viewer's
      `excerpt.endLine ? "-" + endLine : ""` treats it as absent -- the reference silently
      renders as `path:100` instead of the intended range, with no error at generation time.
      Now validated the same way as `startLine` (must be an int, and `>= startLine` when
      present).
- [x] 12.2 Corrected `SKILL.md`'s self-containment claim, which overstated actual enforcement
      scope ("anywhere, including inside your diagram markup and narration") when the check is
      deliberately `diagram.source`-only (7.5/8.2/11.2) -- narration/excerpt text mentioning a
      URL is fine (inert text, not a live reference) and always has been; the doc now says so
      accurately instead of promising an enforcement that does not exist and would be wrong to
      add (it would contradict the deliberate diagram-only scope and break the already-tested
      excerpt-code URL exemption, 9.2).
      Both from a third, focused correctness pass -- confirmed nothing NEW was introduced by
      round 11's own fixes; these are pre-existing gaps adjacent to what was fixed, not
      regressions. Regression-tested (`excerpt-endline-zero.json`,
      `excerpt-endline-before-start.json`); `test-generate-walkthrough.sh`: 142 -> 151 passing,
      verified under real `/bin/bash` (3.2.57); `test-generate-explain.sh` unaffected at 88.

Three passes of the built-in `/code-review` skill in a row now confirm no new issues introduced
by the fixes themselves -- converging. Moving to Build (format/lint) and Polish.
