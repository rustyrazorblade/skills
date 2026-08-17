## Context

`explain`'s `--diff` mode builds one `kind: "diff"` node per changed file via `diff_nodes_from()`
in `generate-explain.py`, unconditionally — every file, including OpenSpec documents, gets a raw
unified-diff node. Separately, `--change <dir>` mode already builds `kind: "markdown"` nodes for
an OpenSpec change directory's `proposal.md`/`design.md`/`tasks.md`/`specs/**/*.md` via
`change_nodes_from()` → `markdown_node()`, and `markdown_node()` already classifies delta-spec
files (via `delta_badge_for()`) for the file-tree badge, while `viewer.html`'s `renderMarkdown`
already color-codes `## ADDED/MODIFIED/REMOVED/RENAMED Requirements` sections. This change extends
that existing OpenSpec-awareness in two directions: (1) `--diff` mode gains the same
path-based detection so OpenSpec files render as content there too, not just under `--change`, and
(2) delta-spec rendering gains a summary/jump-nav and, for `MODIFIED` requirements, an old-vs-new
comparison against the capability's baseline spec.

This was worked through interactively with the owner via `openspec-explore` before this proposal —
see that conversation for the shape of the questions asked; this document captures the resulting
decisions and the alternatives that were on the table for each.

## Goals / Non-Goals

**Goals:**
- In `--diff` mode, an OpenSpec-path file renders as content (markdown), never a raw diff.
- A delta spec (contains OpenSpec's delta headers) gets a summary line, jump links, and — for each
  `MODIFIED` requirement — a "Currently:/This change:" comparison against its baseline.
- `--change` mode's existing markdown nodes for delta specs get the same enrichment, for free, by
  sharing the same rendering path as the new `--diff`-mode detection (see Decisions).
- A dev-only preview fixture + script, so this feature (and `explain` generally) can be
  demonstrated without depending on this repo's own real diff state.

**Non-Goals:**
- No change to non-OpenSpec file handling in any mode — a brand-new `.py` file still renders as a
  diff, by explicit owner decision (code always gets diff + explanation, regardless of how new).
- No line-level diff of the old-vs-new requirement text (prose blocks only — see Decisions).
- No tree-level restructuring (separate sidebar entries per ADDED/MODIFIED/REMOVED category) — the
  split is presentational, within one node's rendered page.
- The preview fixture/script is not part of `explain`'s shipped CLI surface or its manifest schema
  — it's a repo-local dev convenience, not a feature to document in `SKILL.md`'s usage section.

## Decisions

**1. OpenSpec-path detection is path-based only, not content-based.**
`openspec/specs/**/*.md`, `openspec/changes/*/specs/**/*.md`, and `openspec/changes/*/
{proposal,design,tasks}.md` are matched by path; a file's content is never sniffed to decide
*whether* it's an OpenSpec doc (content IS sniffed afterward, to decide whether it's specifically a
*delta* spec — see decision 3). *Alternatives considered:* content-based detection (grep for delta
headers regardless of path) was rejected — it can't ever match `proposal.md`/`design.md`/
`tasks.md` (which have no delta headers), and risks false positives on an unrelated file that
happens to discuss those header strings in prose. A hybrid (path AND content, with graceful
degradation for non-delta openspec/ files) was also considered and is behaviorally equivalent to
pure path-based once content-based classification is layered on top for delta-vs-plain within an
already-matched path — so the simpler pure-path rule was chosen with no loss of behavior.

**2. Scope is strictly OpenSpec paths — code always keeps its diff view.**
A brand-new non-OpenSpec file is still rendered as a diff (all-green), even though the same
"100%-additions diff isn't useful" argument could apply generally. *Alternatives considered:* a
general rule ("any brand-new file renders as content, not diff") was raised and explicitly
rejected by the owner — code review wants the diff view plus the explanation pane together, always;
generalizing would have removed that for every new file, not just spec docs.

**3. Two rendering tiers, split on delta-header presence within an already-matched path.**
A matched OpenSpec file with no delta headers (`proposal.md`, `design.md`, `tasks.md`, an
unchanged-shape baseline spec) renders as plain markdown — nothing to categorize. A matched file
WITH delta headers gets the full enrichment (summary, jump-nav, old-vs-new). This mirrors
`markdown_node()`'s existing `delta_badge_for()` classification, which already makes exactly this
same content-based distinction for the file-tree badge — reusing that signal rather than
introducing a second detection mechanism.

**4. The enrichment lives in `markdown_node()` itself, not in the `--diff`-mode code path.**
`change_nodes_from()` (used by `--change`) already produces its delta-spec nodes via
`markdown_node()`. The new `--diff`-mode OpenSpec detection, when it decides a file should render
as content, ALSO calls `markdown_node()` with that file's head-side text — the same function, not
a parallel implementation. Consequence: `--change` mode's existing delta-spec rendering gains the
summary/jump-nav/old-vs-new treatment automatically, with no separate change needed there — this
directly answers the open question the proposal raised about whether `--change` mode needs its own
work (it doesn't; it inherits the enrichment for free by sharing the function). *Alternative
considered:* enrichment logic duplicated in `diff_nodes_from()` directly — rejected as pure
duplication with no benefit, and it would have left `--change` mode's rendering inconsistent with
`--diff` mode's for the exact same file content.

**5. Old-vs-new comparison is prose ("Currently:"/"This change:"), not a line-level diff.**
Two blocks of full requirement text, not a synthetic `difflib` diff rendered through the diff
view. *Alternatives considered:* a synthetic line-level diff (via `difflib.unified_diff`, rendered
through the existing diff view) was raised and explicitly rejected by the owner — simpler to read
top-to-bottom, cheaper to generate, and consistent with the same prose pattern `spec-flow`'s own
`overrides.md` (a separate, unrelated artifact) already uses for the same kind of before/after.

**6. Baseline lookup is by capability name parsed from the delta spec's own path, and by
requirement title text match — not by any other identifier.**
`openspec/changes/<change-name>/specs/<capability>/spec.md` → capability = `<capability>` →
baseline = `openspec/specs/<capability>/spec.md`. Within that baseline, the specific requirement is
matched by its exact `### Requirement: <title>` text. If the baseline file doesn't exist, or no
requirement in it has a matching title, the comparison is skipped silently for that requirement —
this is a real, expected case (a MODIFIED section can appear in a change introducing a capability
for the first time, e.g. a rename across the same change, or the title itself changed as part of
the edit), not an error condition, and must never break generation or show a broken/empty block.

**7. Preview fixture and script are dev-only, kept out of the skill's own documented CLI.**
`scripts/preview-fixture/` (canned baseline + delta spec covering all three categories, plus the
matching source-code changes and a fake `gh`) and `scripts/preview.sh`. *Alternatives considered:*
previewing against this repo's own real `--worktree`/`--branch` diff (zero fixture maintenance,
but doesn't reliably demonstrate the OpenSpec-aware feature specifically, since this repo may not
have an in-flight delta spec at any given moment) and a `--fixture` flag on a combined script
(both, selectable) — the owner chose the fixture-only version: always demonstrates the full
feature, independent of this repo's real state. Extended later, at the owner's explicit request
("I need to QA every feature of the tool"), from an OpenSpec-only demo into a throwaway git repo
exercising every `generate-explain.py` input in one combined view: the delta spec alongside the
actual modified/new/deleted code diffs it describes, `--blame`, `--explain-map` overriding it,
`--doc`/`--code`, `--symbol`, and `--issue`/`--pr` via a fake `gh` (same offline technique
`test-generate-explain.sh` already used) — see tasks.md §7.

## Risks / Trade-offs

- **[Risk] A delta spec's requirement gets renamed as part of the same change** (title differs
  between the MODIFIED section and what actually exists in the baseline) **→ [Mitigation]** decision
  6's silent-skip behavior — no broken comparison shown, the MODIFIED section still renders fully
  without the old-vs-new block, and this is explicitly documented as expected, not a bug to chase.
- **[Risk] `markdown_node()` picking up new required context (change-dir path, to resolve the
  baseline) changes its call signature** and touches both `change_nodes_from()` and the new
  `--diff`-mode call site **→ [Mitigation]** keep the baseline-lookup context as an optional
  parameter with a safe default (no lookup attempted) so every existing call site keeps working
  unchanged unless it explicitly opts in by passing the change-dir context.
- **[Risk] Preview fixture drifts from the real detection/rendering logic over time** (fixture
  content stops actually exercising ADDED+MODIFIED+REMOVED+baseline-match once code changes) **→
  [Mitigation, partial]** `test-generate-explain.sh` smoke-checks the fixture's OpenSpec content
  (baseline + delta spec) via `--change`, in the same run as the rest of the suite — but this
  covers only that content, not `preview.sh`'s own invocation (the throwaway-git-repo build,
  `--diff`-mode path detection, the fake-`gh` wiring, or any of the other flags it now exercises —
  see tasks.md §7). Nothing in CI runs `preview.sh` itself; a regression specific to that path
  needs an actual manual run to catch.
- **[Risk] The heading/section regexes (`DELTA_HEADING_RE`, `REQUIREMENT_BLOCK_RE`,
  `delta_section_span`'s boundary search) are naive line-anchored patterns with no awareness of
  fenced code blocks** — a requirement whose own body quotes a fenced example containing a
  `## `/`### `-looking line (a markdown-about-markdown example, a shell comment) would get
  truncated at that line, and the Currently:/This change: splice would land inside the open fence;
  a non-OpenSpec doc that merely *mentions* a delta header inside a fenced example would get a
  fabricated badge/summary **→ [Mitigation]** `mask_fenced_code()` blanks out fenced-block interiors
  (mirroring viewer.html's own `FENCE_RE` exactly) before any boundary search runs; every regex
  that decides where a section/requirement starts or ends operates on the masked copy, while the
  actual spliced/parsed content is always sliced back out of the real, unmasked text using the
  offsets found there. Covered by `test-generate-explain.sh`'s fenced-example fixture.

## Open Questions

None outstanding — the `--change`-mode question the proposal flagged is resolved by decision 4
(shared rendering path means no separate work is needed there).
