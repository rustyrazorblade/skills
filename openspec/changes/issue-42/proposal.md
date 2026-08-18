## Why

`explain`'s IDE-style file-tree/diff/pane view is well suited to reviewing a *change* (a diff, an
issue, a PR), but it's the wrong shape for learning how something works end-to-end when there's no
diff to open it against — a newcomer needs an ordered, one-idea-at-a-time narrative (see the shape
first, then the code), not a self-navigated reference page. This isn't limited to "how does this
work" either — the same shape (diagram first, then a guided code walkthrough) fits a technical-debt
review, an areas-for-improvement pass, general recommendations, or a performance analysis just as
well; only the content differs.

## What Changes

- Adds a new `walkthrough` skill to the `review-tools` plugin, alongside `explain`: an
  agent-authored, diagram-first, ordered-step code presentation, rendered as one self-contained
  static HTML file (no server, no CDN, opens via `file://`).
- New deterministic renderer/generator (`generate-walkthrough.py`) that validates an agent-supplied
  JSON manifest (diagram + ordered steps, each with narration, code excerpts, and an optional
  `kind` tag) and renders it — it never fetches or derives content itself; all content is written
  by the invoking agent, mirroring how `explain`'s `--explain-map` already works.
- New static viewer shell (`assets/viewer.html`) with a genuinely different interaction model from
  `explain`'s IDE-tree layout: diagram-first, ordered steps, vertical scroll by default with a
  runtime toggle to horizontal slide-by-slide navigation (counter, prev/next, keyboard arrows) —
  one generated artifact serves both modes, no regeneration needed to switch.
- Extracts three helpers (`fail()`, the `<!--MANIFEST-->` injection helper, the temp-output-path
  helper) that are genuinely identical between `generate-explain.py` and the new
  `generate-walkthrough.py` into a small shared module, `plugins/review-tools/lib/html_shell.py`,
  and refactors `generate-explain.py` to import from it instead of keeping its own copies —
  **no behavior change** to `explain` (its own test suite must stay green throughout).
- Bumps `plugins/review-tools/.claude-plugin/plugin.json`'s version and updates its
  `description`/`keywords` to mention `walkthrough` alongside `explain`.

## Capabilities

### New Capabilities
- `walkthrough`: an agent-authored, diagram-first, ordered-step code presentation tool — manifest
  schema, validation rules, rendering (diagram + steps + code excerpts + kind badges), and the
  vertical-default/horizontal-toggle presentation with nav chrome.

### Modified Capabilities
- None. The `html_shell.py` extraction changes `explain`'s internal implementation only — no
  observable behavior, CLI surface, or requirement of the `explain` capability changes (verified by
  its own test suite staying green), so no delta spec against `explain` is needed.

## Impact

- New files: `plugins/review-tools/skills/walkthrough/{SKILL.md,scripts/generate-walkthrough.py,
  scripts/test-generate-walkthrough.sh,scripts/fixtures/*,scripts/README.md,assets/viewer.html}`,
  `plugins/review-tools/lib/html_shell.py`.
- Modified files: `plugins/review-tools/skills/explain/scripts/generate-explain.py` (import the
  three extracted helpers instead of defining them locally), `plugins/review-tools/.claude-plugin/
  plugin.json` (version bump + description/keywords).
- No changes to `explain`'s manifest schema, CLI surface, or `assets/viewer.html`.
- No new third-party dependencies (Python stdlib only; no Mermaid or other client-side rendering
  library — diagrams are agent-authored inline SVG/HTML).
