# flow

A Claude Code plugin: a **session-driven, multi-agent delivery pipeline** over **OpenSpec** +
**GitHub**. You own the two human seams — **defining/prioritizing work** and **final review +
merge** — and the middle (spec → implement → review → fix → build → docs → PR) runs as
agents you invoke turn-by-turn from the main Claude session.

```
groom ─▶ activate ─▶ [SEAM 1: you approve the spec] ─▶ implement ─▶ [SEAM 2: you review + squash-merge] ─▶ finalize
                                                          │
                                                  4-lens review panel
```

See [`docs/workflow.md`](docs/workflow.md) for the full design (the two seams, lifecycle/labels,
the 1:1:1:1 naming, and the review panel).

## Prerequisites (in the consuming repo)

- **OpenSpec** — the `openspec` CLI installed and initialized in the repo (the spec backbone;
  the skills use `/opsx:*` and `openspec` commands).
- **GitHub** — `gh` authenticated, and the repo hosted on GitHub (issues/labels/PRs backbone).
- **Labels** — run the bootstrap once to create the `P0–P3` + `status:*` labels:
  ```bash
  bash bin/bootstrap-labels.sh   # cwd inside the target repo; gh authenticated
  ```
- **Built-in skills** — `/code-review` and `/security-review` are used by two of the review
  lenses (they degrade to an inline pass if unavailable).

## Install

**Quick / single session** (load the plugin directly from a directory):
```bash
claude --plugin-dir /path/to/spec-flow
```

**Marketplace** (reusable across repos):
```bash
/plugin marketplace add /path/to/spec-flow      # or a GitHub repo / URL hosting it
/plugin install spec-flow@spec-flow-tools
```
For team/project scope, the consuming repo's `.claude/settings.json` can declare the marketplace
under `extraKnownMarketplaces` and list `"spec-flow@spec-flow-tools"` in `enabledPlugins`.

## Commands

All skills are namespaced under the plugin:

| Command | Does |
|---|---|
| `/spec-flow:groom` | Rough idea → scoped, labeled GitHub issue (scope, acceptance criteria, one `P0–P3`). |
| `/spec-flow:activate <N>` | Worktree + branch → OpenSpec explore+propose → commit spec → **stop for your approval** (Seam 1). |
| `/spec-flow:implement <N>` | After approval: background team (tdd-developer → 4-lens review panel → fix loop → build-engineer → docs) → push branch → open PR. |
| `/spec-flow:address <N>` | Pull your PR review comments → fix in the worktree → push → reply per thread. |
| `/spec-flow:board` | One view of every in-flight issue: stage, priority, PR/CI state, what's next, what's blocked on you. |
| `/spec-flow:finalize <N>` | After you squash-merge: sync+archive the OpenSpec change, remove the worktree, close the issue. |

## Bundled agents

- **`reviewer`** — spec-conformance + the repo's own documented rules + spec-scenario→test traceability.
- **`test-rigor-reviewer`** — antagonistic, regression-exposing test coverage of the change's
  public surface and its observable side effects.
- **`tdd-developer`** — test-first (red→green→refactor), SOLID. The implementer.
- **`build-engineer`** — gets the build clean (format/lint/build), adapts to the project's tool.

> **Override note:** plugin agents are namespaced (`flow:reviewer`, …), but the workflow spawns
> them by bare name (`reviewer`, `tdd-developer`, …). If the consuming repo defines its own agent
> with the same name (project `.claude/agents/` or user `~/.claude/agents/`), **that one overrides
> the plugin's** — a deliberate way to specialize an agent for a repo's stack.

## Extending the agents

`tdd-developer` and `build-engineer` are bundled as **canonical, general-purpose bases**. Grow
them in place with per-language and per-library best practices (e.g. a Rust/Cargo section, a
Node/pnpm section, framework-specific testing idioms) as you adopt this plugin across stacks —
they are the single source you maintain, and every repo using the plugin inherits the improvements.

## Notes

- The pipeline **never merges and never pushes to `main`** — it only pushes the issue branch and
  opens a PR. The squash-merge is your action in GitHub.
- Significant design / data-model decisions are made at Seam 1 (spec approval): a domain-expert
  agent (if the repo has one) advises, you decide; the agent never makes the call.
- Issue/PR numbers are always rendered with a brief `(description)` — a bare number is meaningless.
