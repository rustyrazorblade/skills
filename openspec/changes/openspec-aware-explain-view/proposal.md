## Why

`explain`'s `--diff` mode (including the `--worktree`/`--branch` aliases) currently treats every
changed file identically: a raw unified diff. For an OpenSpec document — a delta spec under an
in-flight `openspec/changes/*/` directory, or a baseline `openspec/specs/**/spec.md` — that's the
wrong presentation. These files are typically brand-new in the diff (a fresh change dir has never
existed before), so the diff is 100% green additions with nothing to actually review line-by-line;
what the owner needs is to *read* the spec, understand what's ADDED/MODIFIED/REMOVED, and — for a
MODIFIED requirement specifically — see what the requirement said before, compared against a
capability's existing baseline (a different file entirely, not git history of the same one). None
of that is served by a diff view.

## What Changes

- In `--diff` mode, a changed file whose path matches OpenSpec's own directory convention
  (`openspec/specs/**/*.md`, or `openspec/changes/*/{specs/**/*.md,proposal.md,design.md,tasks.md}`)
  renders as a markdown/content node instead of a diff node — no diff view, explanation pane only.
  This is scoped strictly to OpenSpec paths; every other file keeps its existing diff view +
  explanation pane exactly as today, including brand-new non-OpenSpec files.
- A matched file whose content contains OpenSpec's delta headers (`## ADDED/MODIFIED/REMOVED/
  RENAMED Requirements`) gets additional treatment on top of the plain render: a summary line with
  per-category counts, jump links to each category, and — for each requirement under `##
  MODIFIED Requirements` — a "Currently: / This change:" prose comparison against the same-titled
  requirement in that capability's baseline spec (`openspec/specs/<capability>/spec.md`, looked up
  from the delta spec's own path). A matched file without delta headers (`proposal.md`,
  `design.md`, `tasks.md`, an unchanged-shape baseline spec) renders as plain markdown, same as
  today's `--change` mode already does — nothing to categorize.
- A new dev-only preview mechanism: a canned fixture (a baseline spec + a delta spec exercising
  all three categories) and a `preview.sh` script that always renders it, so the feature above (and
  `explain`'s rendering generally) can be demonstrated and iterated on without depending on this
  repo's own real diff state at any given moment.

## Capabilities

### New Capabilities
(none — this extends the existing `explain` capability, it doesn't introduce a new one)

### Modified Capabilities
- `explain`: adds OpenSpec-path detection in `--diff` mode, the delta-header-aware summary/jump-nav/
  old-vs-new-comparison rendering, and the dev-only preview fixture/script. All additive to
  existing behavior — no existing requirement's observable behavior for non-OpenSpec files changes.

## Impact

- `plugins/review-tools/skills/explain/scripts/generate-explain.py` — new OpenSpec-path detection,
  delta-header parsing, baseline-requirement lookup, and prose-comparison injection, all in the
  deterministic generator; no model tokens involved.
- `plugins/review-tools/skills/explain/assets/viewer.html` — likely no changes needed; the
  existing delta-section color-coding (from a prior change) already renders `## ADDED/MODIFIED/
  REMOVED/RENAMED Requirements` headings distinctly, and the "Currently:/This change:" prose can be
  spliced into the markdown text before it reaches the existing renderer.
- `plugins/review-tools/skills/explain/scripts/test-generate-explain.sh` — new test coverage for
  the detection/rendering logic, in the same fixture-based, no-network style as existing tests.
- `plugins/review-tools/skills/explain/scripts/preview-fixture/` and `scripts/preview.sh` — new,
  dev-convenience only; not part of the skill's shipped behavior or its CLI surface.
- No changes to `spec-flow` — this lives entirely in the standalone `review-tools` plugin, which
  already carries OpenSpec-awareness (delta-section coloring) independent of spec-flow.
