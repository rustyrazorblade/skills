## 1. OpenSpec path detection in --diff mode

- [x] 1.1 Add a path-matching helper for OpenSpec's convention (`openspec/specs/**/*.md`,
      `openspec/changes/*/specs/**/*.md`, `openspec/changes/*/proposal.md`,
      `openspec/changes/*/design.md`, `openspec/changes/*/tasks.md`). Implemented with
      `pathlib` (segment-anchored — finds the `openspec` path component, not a substring match)
      + `fnmatch` glob patterns for the shape, not hand-rolled regex alternation — caught and
      fixed a real anchoring bug (`notopenspec/...` would have matched a naive `*openspec/...`
      glob) before it shipped.
- [x] 1.2 In `diff_nodes_from()`, for each changed file, check the path helper before building a
      diff node; when matched, read the file's head-side content (working tree read when
      `head is None`, `git show <head>:<path>` otherwise) and build a markdown node via
      `markdown_node()` instead of a diff node
- [x] 1.3 Confirmed non-matching files (including brand-new non-OpenSpec files) are completely
      unaffected — still diff nodes, unchanged badge/blame/explain-map behavior (verified live:
      a brand-new `src/newfile.py` in the same diff still renders as `kind: "diff"`, badge "new")

## 2. Delta-spec enrichment shared by --diff and --change modes

- [x] 2.1 Added a capability/requirement-title parser: given a delta spec's own path
      (`openspec/changes/<name>/specs/<capability>/spec.md`), derive the baseline path
      (`openspec/specs/<capability>/spec.md`); given a baseline spec's text, extract each
      `### Requirement: <title>` block verbatim, keyed by exact title text
- [x] 2.2 Added summary-line + jump-link generation for a delta spec's content, driven by the same
      delta-header detection `delta_badge_for()` already uses (counts per present category only —
      omitted from the summary when a category has zero items)
- [x] 2.3 For each requirement under `## MODIFIED Requirements`, look up the same-titled
      requirement in the baseline (task 2.1); when found, splice a "Currently:"/"This change:"
      prose block into the markdown text for that requirement; when not found (missing baseline
      file, or no title match), the requirement's rendering is left untouched — verified live,
      no error, no broken block
- [x] 2.4 Wired into `markdown_node()` itself (not a separate path in `diff_nodes_from()`), gated
      on the node actually being an OpenSpec delta spec, so both `--change <dir>` and the new
      `--diff`-mode detection (task 1.2) share the identical rendering — confirmed live with the
      same fixture content through both entry points, byte-identical output

## 3. Tests

- [x] 3.1 New fixture case(s) in `test-generate-explain.sh`: a baseline spec + a delta spec (under
      a fake change dir) with ADDED, MODIFIED (title matching the baseline), and REMOVED sections;
      asserts the MODIFIED requirement's rendered content contains both the baseline and new text
- [x] 3.2 Fixture case for a MODIFIED requirement with NO baseline match (title mismatch) —
      asserts it still renders fully, with no comparison block, and the generator still exits 0
- [x] 3.3 Fixture case confirming a brand-new NON-OpenSpec file (`src/newfile.py`) still renders
      as a `kind: "diff"` node, unaffected by this change
- [x] 3.4 Fixture case confirming the same delta-spec content produces byte-identical enriched
      output whether reached via `--diff` (path-detected) or via `--change <dir>`
- [x] 3.5 Full suite run: 59/59 passing (49 pre-existing + 10 new)

## 4. Dev-only preview mechanism

- [x] 4.1 Created `plugins/review-tools/skills/explain/scripts/preview-fixture/` — a baseline spec
      (`openspec/specs/widget/spec.md`) and a delta spec under a fake change dir
      (`openspec/changes/demo/specs/widget/spec.md`) with ADDED, MODIFIED (title matching the
      baseline, to exercise the comparison), and REMOVED sections
- [x] 4.2 Created `plugins/review-tools/skills/explain/scripts/preview.sh` — generates and opens
      an explain view from the fixture
- [x] 4.3 Confirmed live: `preview.sh` runs cleanly standalone; the generated manifest shows the
      delta spec node with badge REMOVED, summary "1 added · 1 modified · 1 removed", and a real
      Currently:/This change: comparison block for the MODIFIED requirement

## 5. Documentation

- [x] 5.1 Updated `plugins/review-tools/skills/explain/SKILL.md` to describe the new `--diff`-mode
      OpenSpec rendering behavior (where it applies, what it doesn't affect)
- [x] 5.2 Bumped `plugins/review-tools/.claude-plugin/plugin.json`'s version

## 6. Fixes from an independent (fable-model) review, before archiving

- [x] 6.1 Made every structural regex (`DELTA_HEADING_RE`, `REQUIREMENT_BLOCK_RE`,
      `delta_section_span`'s boundary search) fence-aware via `mask_fenced_code()` — a
      `## `/`### `-looking line inside a requirement's own fenced example was previously
      truncating the requirement and corrupting the Currently:/This change: splice, and a
      non-OpenSpec doc merely mentioning a delta header inside a fence was firing a fabricated
      badge/summary. Regression-covered in `test-generate-explain.sh`.
- [x] 6.2 Root-anchored `--diff` mode's working-tree disk reads (`repo_root()` +
      `read_file_at_ref(..., cwd=...)`) — paths from `git diff` are always repo-root-relative, so
      running the skill from a subdirectory was silently falling back to a raw diff instead of the
      OpenSpec rendering. `--change` mode's own disk-relative reads are untouched.
- [x] 6.3 Corrected `SKILL.md` and this change's own delta spec: a **deleted** OpenSpec file (and
      the defensive read-failure fallback) still render as a diff, not markdown — the original
      wording overclaimed "never renders as a diff, even here."
- [x] 6.4 Wired `read_baseline` into the `--doc` node-building path too, so a delta spec reached
      via `--doc` gets the same MODIFIED-requirement baseline comparison `--diff`/`--change`
      already did.
- [x] 6.5 Default title (when `--title` isn't passed) now names what's actually being explained —
      the OpenSpec change dir, diff branch/head, or doc/code filename — instead of the generic
      "Explain" for every invocation.
- [x] 6.6 Fixed `preview.sh`'s BSD-only `mktemp -t` usage (errored on GNU mktemp/Linux) and added a
      `test-generate-explain.sh` smoke check against the shipped `preview-fixture/` itself, per
      design.md's own stated mitigation for fixture drift (previously undone).
- [x] 6.7 Fixed a test assertion (`ospec_diff_py_out`'s no-baseline-match check) that used
      `str.index()` and would raise on a miss, silently aborting later assertions in the same
      block instead of recording a FAIL.
- [x] 6.8 Fixed `default_title()` checking `args.branch` before `head` — a `--diff --branch X
      --head Y` invocation actually diffs against `Y` (`--head` wins per `main()`'s own
      resolution and `--branch`'s own help text), but was titling the page after the ignored `X`.
      Now just checks the already-resolved `head`, which equals `args.branch`'s value in the
      common case anyway. Regression-covered in `test-generate-explain.sh`.
- [x] 6.9 Corrected `SKILL.md`'s `--doc` description — the delta-header summary/category-nav is
      content-triggered regardless of path (like everywhere else), only the MODIFIED-requirement
      baseline *comparison* specifically requires the path to look like a delta spec (that's what
      locates the sibling baseline file). Previous wording implied path-gating for both.

## 7. Preview: QA every feature in one combined view

- [x] 7.1 A design investigation into `explain`'s long-term architecture (decoupling data from
      layout, standalone-app question) surfaced that `init-explain.sh`'s curated-mode schema
      comment had drifted from `SKILL.md`'s documented schema (missing the `"mod"` badgeClass and
      the `comments` field) — fixed both copies (the written `explain.manifest.js` header and the
      terminal echo), with a cross-reference comment so future schema changes update both.
- [x] 7.2 Rebuilt `preview.sh` from a static `--change`-only fixture into a throwaway git repo
      (baseline commit + an uncommitted "in-flight change"), exercising every `generate-explain.py`
      input in ONE combined view instead of OpenSpec content alone: the delta spec (ADDED/MODIFIED
      with baseline comparison/REMOVED) alongside the actual code diffs it describes (a MODIFIED
      file, a NEW file for the ADDED requirement, a DELETED file for the REMOVED requirement),
      `--blame` on the modified file, `--explain-map` overriding the new file's blame with a real
      curated explanation, `--doc`/`--code` (plain markdown/code nodes), `--symbol` blast-radius,
      and `--issue`/`--pr` (a primary issue + a related one via both a dependency link and a `#N`
      mention, plus a PR comment anchored inside the diff and one outside it) via a fake `gh` on
      PATH — same offline technique `test-generate-explain.sh` already used.
- [x] 7.3 Added the fixture files this needed: `baseline-src/` (pre-change source, seeds the
      baseline commit), `src/widget_renaming.py` and the modified `src/widget.py` (post-change
      source), `docs/widget-notes.md` (a plain non-delta doc), `src/widget_helpers.py` (a plain
      `--code` file), `explain-map.json`, and `fake-gh/gh` (executable).
- [x] 7.4 Verified live: `preview.sh` runs cleanly end to end; inspected the generated manifest
      directly and confirmed every node kind/feature listed above is present with the expected
      content (badges, comments, blame vs. explain-map override, blast-radius hits).
- [x] 7.5 Re-ran `test-generate-explain.sh`'s existing preview-fixture smoke check (task 6.6) —
      still 82/82; the new fixture files don't affect the `--change openspec/changes/demo`
      invocation that check exercises.
- [x] 7.6 A fable review of 7.1-7.5 found one real, pre-existing bug made visible by the new
      fixture: `issue_nodes_from()`'s dependency-relation notes were swapped — an issue in #n's
      `blocked_by` list (which, per GitHub's own API naming, BLOCKS #n) was labeled "blocked by
      #n" instead of "blocks #n", and vice versa for `blocking`. Fixed (`generate-explain.py`);
      confirmed live the fixture's #2 now correctly reads "Related: blocked by #1" (#1 blocks its
      own follow-up), not the previous backwards "blocks #1".
- [x] 7.7 Fixed the new `fake-gh/gh`'s `repo view --jq` handling — it was echoing the whole JSON
      object instead of the bare `--jq .nameWithOwner` string a real `gh` would print, so
      `owner_repo` inside `generate-explain.py` became a JSON blob rather than `acme/widgets` (the
      demo happened to still work, since the fake's own `api` patterns suffix-match regardless).
- [x] 7.8 Corrected two stale claims the review caught: `test-generate-explain.sh`'s
      preview-fixture-smoke-check comment (used to claim it runs "the same generator invocation
      preview.sh does" — no longer true now that `preview.sh` does far more than `--change` alone)
      and design.md's fixture-drift mitigation bullet (now states plainly that nothing in CI runs
      `preview.sh` itself — only its fixture's `--change`-reachable content is smoke-checked).
- [x] 7.9 Removed `preview.sh`'s trailing `echo`s duplicating output `generate-explain.py` already
      prints on success (a nitpick from the same review).
