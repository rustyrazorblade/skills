# spec-flow

A Claude Code plugin: a **session-driven, multi-agent delivery pipeline** over **OpenSpec** +
**GitHub**. You own the two human seams — **defining/prioritizing work** and **final review +
merge** — and the middle (spec → implement → review → fix → build → docs → PR) runs as
agents you invoke turn-by-turn.

```
groom ─▶ activate ─▶ [SEAM 1: you approve the spec] ─▶ implement ─▶ [SEAM 2: you review + squash-merge] ─▶ finalize
  │          │                                              │
refine     design                                  5-lens review panel
(product)  (architect)
```

Two tiers of agent run this. A **`project-manager`** is the central coordinator you talk to
directly — it runs the board, grooms new work, and decides what's next, but doesn't drive an
individual issue itself. When you're ready to start or resume an issue, it spawns a dedicated
**`issue-pm`** subagent for that issue (named `issue-pm-<N>`) and you switch to it (via the agent
switcher) — that subagent owns `activate → implement → address → finalize` for that one issue,
end to end, and hands back once it's merged. Several issues can be in flight at once, each with
its own `issue-pm`. Wire `project-manager` as a repo's **default agent** to make it your standing
entry point (see below).

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

**Marketplace** (reusable across repos). From the `rustyrazorblade/skills` marketplace this plugin
ships in:
```bash
/plugin marketplace add rustyrazorblade/skills
/plugin install spec-flow@rustyrazorblade-plugins
```
Or standalone, from a checkout of this plugin directory alone (it declares its own `spec-flow-tools`
marketplace for exactly this):
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
| `/spec-flow:activate <N>` | Worktree + branch → architect + domain expert design it concurrently → **stop for your design choice** → OpenSpec explore+propose from your choice → commit spec → **stop for your approval** (Seam 1). |
| `/spec-flow:implement <N>` | After approval: background team (tdd-developer → 5-lens review panel → fix loop → build-engineer → docs) → push branch → open PR. |
| `/spec-flow:address <N>` | Pull your PR review comments → fix in the worktree → push → reply per thread. |
| `/spec-flow:board` | One view of every in-flight issue: stage, priority, PR/CI state, what's next, what's blocked on you. |
| `/spec-flow:finalize <N>` | After you squash-merge: sync+archive the OpenSpec change, remove the worktree, close the issue. |

## Bundled agents

**Orchestration**
- **`project-manager`** — the **central coordinator**, the agent you talk to directly. Runs the
  board, grooms new work, tracks which issues have an `issue-pm` running, and decides what's next.
  It coordinates; it never implements, never drives an issue's stages itself, and never crosses
  your two seams. Wire it as your repo's **default agent** (next section).
- **`issue-pm`** — the **per-issue delivery lead**. `project-manager` spawns one (named
  `issue-pm-<N>`) when you start or resume work on issue `#N`; you switch to it directly. It owns
  that issue alone, end to end: claims it, drives `activate` (both owner stops) →
  `implement` → `sync-ci`/`address` as needed → `finalize`, then hands back. This is the default
  flow for working an issue, not an opt-in.

**Front of pipeline (refine → design → proposal)**
- **`product-manager`** — refines a rough idea into tight scope + **testable acceptance criteria**
  (the what/why). Consulted during `groom`.
- **`architect`** — turns the refined idea into a **design** (structure, SOLID, data model,
  trade-offs framed as owner decisions) that feeds the OpenSpec proposal. Consulted during
  `activate`, concurrently with a domain-expert agent if one is available, and **before**
  propose — you stop and decide right there, before anything is generated. Advises; never decides.

**Implementation & build**
- **`tdd-developer`** — test-first (red→green→refactor), SOLID. The implementer. Follows the
  bundled Rust style guide automatically when the project is Rust, or the Kotlin style guide when
  the project is Kotlin.
- **`build-engineer`** — gets the build clean (format/lint/build), adapts to the project's tool.

**Review panel (the 5 lenses run in parallel during `implement`)**
- **`reviewer`** — the authority on "does the implementation match the spec?" — spec-conformance +
  the repo's own documented rules + spec-scenario→test traceability.
- **`test-rigor-reviewer`** — antagonistic, regression-exposing test coverage of the change's
  public surface and its observable side effects.
- **`observability-reviewer`** — are the change's new code paths + failure modes diagnosable in
  prod (logging/metrics/tracing, no silent failures, no secrets in telemetry)?
- plus two built-in-skill lenses: **`/code-review`** (correctness) and **`/security-review`**.

> **Override note:** plugin agents are namespaced (`spec-flow:reviewer`, …) when installed, but the
> workflow resolves them **bare-first with a namespaced fallback** — it tries the bare name
> (`reviewer`, `tdd-developer`, …) and, only if no such agent is registered, falls back to
> `spec-flow:<name>`. So if the consuming repo defines its own agent with the same name (project
> `.claude/agents/` or user `~/.claude/agents/`), **that one overrides the plugin's** — a deliberate
> way to specialize an agent for a repo's stack — while the bundled namespaced agent is still found
> when no override exists. (Resolution lives in the `agentNS()` helper in `implement.workflow.js`.)

## Wiring the project-manager as your default agent

The orchestrator is most useful as the agent you land in by default in a repo that uses this
pipeline. Set it **per-project** in the consuming repo's `.claude/settings.json`:

```jsonc
{
  // ... your existing project settings ...
  "agent": "project-manager"
}
```

Now opening that project drops you into the coordinator: it reads the board and tells you what's
next. When you tell it to start (or resume) a specific issue, it spawns that issue's `issue-pm` —
switch to it (via the agent switcher) to drive that issue directly, and switch back to the
coordinator (or to another issue's `issue-pm`) whenever you want the cross-issue view again.

> **Why per-project and not in the plugin?** The plugin deliberately ships **no** root
> `settings.json` with an `agent` field. A plugin that sets a default agent hijacks the main thread
> of *every* project that installs it, at startup, before you type anything. Opting *your* repos in
> via their own settings keeps that choice yours — only the repos you wire run as the PM.

## Extending the agents

`tdd-developer` and `build-engineer` are bundled as **canonical, general-purpose bases**. Grow
them in place with per-language and per-library best practices (e.g. a Rust/Cargo section, a
Node/pnpm section, framework-specific testing idioms) as you adopt this plugin across stacks —
they are the single source you maintain, and every repo using the plugin inherits the improvements.

## Notes

- The pipeline **never merges and never pushes to `main`** — it only pushes the issue branch and
  opens a PR. The squash-merge is your action in GitHub.
- Significant design / data-model decisions are made **before** Seam 1, during `activate`: the
  `architect` (and a domain-expert agent, concurrently, if the repo has one) advises with options +
  trade-offs, you decide right there before anything is generated; Seam 1 then confirms the
  resulting spec faithfully reflects your choice. The agents never make the call.
- Issue/PR numbers are always rendered with a brief `(description)` — a bare number is meaningless.
