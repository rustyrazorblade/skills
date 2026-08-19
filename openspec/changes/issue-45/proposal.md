## Why

`plugins/spec-flow/skills/tech-debt/SKILL.md` is a repo-wide structural-debt audit (SOLID/
composability, duplication, unnecessary layering) that is already generic in mechanism — plain `gh
issue list`/`gh issue create`, `general-purpose` agents (not any spec-flow-specific agent type), no
worktree/issue coupling, no code edits. Only its *location*, inside spec-flow, is spec-flow-
specific: a repo using only `review-tools` can't use it, and a repo-wide audit tool is artificially
coupled to an unrelated plugin's presence. This mirrors `explain`'s own extraction from spec-flow
into standalone `review-tools` for the same reason.

## What Changes

- Moves the skill to `plugins/review-tools/skills/tech-debt/SKILL.md`, generalizing its prose so it
  carries **zero references to spec-flow** — no mention of `project-manager`, `groom`, `board`,
  `archive`, `architect`, `/spec-flow:activate`, or `docs/workflow.md` anywhere in the moved file
  (an explicit owner decision, overriding the architect's own recommendation to keep one short
  integration paragraph — see `design.md`).
- Renames the command from `/spec-flow:tech-debt` to `/tech-debt` (bare) / `/review-tools:tech-debt`
  (namespaced), following the plugin's own directory/skill-name convention (matching `explain`/
  `walkthrough`). No compatibility alias is kept — this is a deliberate breaking rename, confirmed
  with the owner.
- Updates six spec-flow files to reference the moved command/location instead of a spec-flow-owned
  copy: `README.md`, `agents/reviewer.md`, `agents/project-manager.md`, `docs/workflow.md`,
  `skills/activate/SKILL.md`, `bin/bootstrap-labels.sh`.
- `project-manager`'s tech-debt review cadence recommendation is reworded to be **conditional
  prose** ("if you have a tech-debt audit skill installed, it's about due") rather than backed by
  an explicit `claude plugin list --json`/jq detection command — trusting the agent's own runtime
  awareness of its available skills instead of hardcoding a check against the `review-tools@`
  plugin id specifically. This is a deliberate departure from the existing `EXPLAIN_ROOT` detection
  pattern used elsewhere in spec-flow for `explain`, made explicitly by the owner during design
  (see `design.md` decision 2) — no new plugin-detection code is added anywhere by this change.
- Adds a `/tech-debt` row to the repo-root `README.md`'s `review-tools` skills table, matching the
  existing `/explain`/`/walkthrough` rows.
- Bumps both plugins' `plugin.json` versions (`.claude-plugin/` and `.codex-plugin/` pairs) — exact
  numbers confirmed with the owner at implementation time, per this repo's version-bump convention.

## Capabilities

### New Capabilities
- `tech-debt`: a standalone, repo-wide structural-debt audit skill living in `review-tools` — scope
  establishment, backlog self-filtering, three parallel SOLID/duplication/structure lens agents,
  merge/dedupe/rank to a top-10 list, one-at-a-time owner-confirmed issue filing (with a distinct
  `## Direction` section), a cadence log marker, zero dependency on any other plugin's vocabulary,
  and graceful degradation for any consumer (e.g. spec-flow) that recommends it without a hardcoded
  cross-plugin detection mechanism.

### Modified Capabilities
- None formally tracked. No existing `openspec/specs/` capability covers spec-flow's
  `project-manager` prose/cadence behavior — only `explain` has a committed baseline spec today.
  Those instruction-file changes are still made (see `tasks.md`) but have no baseline requirement to
  diff against; consistent with how most of spec-flow's own agent-instruction behavior isn't
  OpenSpec-specced.

## Impact

- New file: `plugins/review-tools/skills/tech-debt/SKILL.md` (moved + generalized).
- Removed: `plugins/spec-flow/skills/tech-debt/` (the whole directory).
- Modified: `plugins/spec-flow/README.md`, `plugins/spec-flow/agents/reviewer.md`,
  `plugins/spec-flow/agents/project-manager.md`, `plugins/spec-flow/docs/workflow.md`,
  `plugins/spec-flow/skills/activate/SKILL.md`, `plugins/spec-flow/bin/bootstrap-labels.sh`,
  `README.md` (repo root), `plugins/spec-flow/.claude-plugin/plugin.json` +
  `.codex-plugin/plugin.json`, `plugins/review-tools/.claude-plugin/plugin.json` +
  `.codex-plugin/plugin.json`.
- No change to the audit's own SOLID/duplication/structure lens logic — explicitly out of scope.
- No change to `architect`'s in-context "nearby structural debt" flag during `activate` — a
  different, smaller mechanism; whether it should also delegate to the moved skill is a separate,
  undecided question.
- **Breaking:** `/spec-flow:tech-debt` no longer resolves after this change. Anyone with muscle
  memory or scripts referencing it must switch to `/tech-debt` / `/review-tools:tech-debt`.
