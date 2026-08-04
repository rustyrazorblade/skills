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
individual issue itself. When you're ready to start or resume an issue, it launches a dedicated
**`issue-pm`** (named `issue-pm-<N>`) as its **own separate background Claude Code process**,
opened in a live iTerm2 tab or tmux window (your choice — see **Display mode** below) that you
talk to directly — not a subagent in the coordinator's own context. That process owns
`activate → implement → address → finalize` for that one issue, end to end, in its own git
worktree (Claude Code's `EnterWorktree` isolates it — called explicitly as its first action, not
automatic for everything; see **Prerequisites** below), and hands back once it's merged. Several issues
can be in flight at once, each its own process, each its own tab. Wire `project-manager` as a
repo's **default agent** to make it your standing entry point (see below).

See [`docs/workflow.md`](docs/workflow.md) for the full design (the two seams, lifecycle/labels,
the naming/correlators, and the review panel).

## Prerequisites (in the consuming repo)

- **OpenSpec** — the `openspec` CLI installed and initialized in the repo (the spec backbone;
  the skills use `/opsx:*` and `openspec` commands).
- **GitHub** — `gh` authenticated, and the repo hosted on GitHub (issues/labels/PRs backbone). If
  you have more than one `gh` account/host configured (common in a corporate environment running
  both github.com and a GitHub Enterprise host), make sure the one active by default (`gh auth
  status`) is the right one for this repo — every skill and `scripts/spawn-issue-pm.sh` shell out
  to bare `gh` commands with no `--repo`/account override, so whichever account is active is the
  one they act as. Fix with `gh auth switch` or `GH_HOST` if it's picking the wrong one.
- **Labels** — run the bootstrap once to create the `P0–P3` + `status:*` + `agent:active`/`blocked`
  labels:
  ```bash
  bash bin/bootstrap-labels.sh   # cwd inside the target repo; gh authenticated
  ```
- **Built-in skills** — `/code-review` and `/security-review` are used by two of the review
  lenses (they degrade to an inline pass if unavailable).
- **Agent teams (optional, default mode)** — `/spec-flow:implement` defaults to running its
  five-lens review as an [agent team](https://code.claude.com/docs/en/agent-teams) led by
  `issue-pm`, which requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (experimental, disabled by
  default):
  ```json
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  ```
  in the consuming repo's (or your own) `settings.json`. Not set? `implement` falls back to the
  bundled `Workflow`-tool script automatically — same five lenses, no team. Set
  `SPEC_FLOW_IMPLEMENT_MODE=workflow` to use that mode on purpose instead of relying on fallback.
- **`.claude/worktrees/` gitignored** — every `issue-pm` runs isolated in its own git worktree via
  Claude Code's `EnterWorktree` tool, called explicitly as `issue-pm`'s first action (confirmed by
  test: isolation is **not** automatic in front of a Bash-driven file write — only in front of an
  Edit/Write tool call — so the spawn prompt calls it up front rather than relying on that). Add
  `.claude/worktrees/` to the repo's `.gitignore` so those checkouts never show up as untracked
  files in your primary checkout (see
  [Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees)).
- **CI contract (for `/spec-flow:sync-ci`)** — the consuming repo's CI needs to run a fast **unit**
  tier plus a full/integration tier, and upload failing test ids as a `spec-flow-failures` artifact
  on a red run, so `sync-ci` has something to pull into the branch's local flagged set. Run
  `/spec-flow:adopt-tiering` once per repo to split an existing suite and wire this; see
  `references/ci/` for the CI templates and **Test tiering** in `docs/workflow.md` for the model.

### Display mode (optional)

`issue-pm` sessions open in a live terminal tab — pick iTerm2 tabs, tmux windows, or no tab at all
(just the background session, for dispatching several issues in a row). Resolution order: a
per-call `--display` flag, then the `SPEC_FLOW_DISPLAY` env var, then autodetect from your current
terminal. For a standing per-repo preference, set `SPEC_FLOW_DISPLAY` in that repo's
`.claude/settings.json` under `"env"`. `project-manager` never overrides this itself — it's your
standing preference, not a per-issue choice.

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
| `/spec-flow:sync-ci <N>` | CI went red → pull the failing test ids into the branch's local flagged set so the fast loop guards them too. Owner-invoked, never polls. |
| `/spec-flow:board` | One view of every in-flight issue: stage, priority, PR/CI state, what's next, what's blocked on you. |
| `/spec-flow:finalize <N>` | After you squash-merge: syncs+archives the OpenSpec change (via its own small self-merged PR), closes the issue, then removes the worktree. |
| `/spec-flow:adopt-tiering` | One-time, repo-wide: split an existing test suite into the unit/integration tiers the pipeline assumes, and wire CI to the `spec-flow-failures` artifact contract. Run once per repo, before relying on `sync-ci`/the tiered gate. |

## Bundled agents

**Orchestration**
- **`project-manager`** — the **central coordinator**, the agent you talk to directly. Runs the
  board, grooms new work, tracks which issues have an `issue-pm` running, and decides what's next.
  It coordinates; it never implements, never drives an issue's stages itself, and never crosses
  your two seams. Wire it as your repo's **default agent** (next section).
- **`issue-pm`** — the **per-issue delivery lead**. `project-manager` launches one (named
  `issue-pm-<N>`) as its own background process — via `scripts/spawn-issue-pm.sh` — when you start
  or resume work on issue `#N`; you talk to it directly in the tab that opens. It owns that issue
  alone, end to end: claims it, drives `activate` (both owner stops) → `implement` →
  `sync-ci`/`address` as needed → `finalize`, then hands back. This is the default flow for working
  an issue, not an opt-in.

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
- **`code-reviewer`** — a correctness-only pass via the built-in `/code-review` skill.
- **`security-reviewer`** — a security pass via the built-in `/security-review` skill; self-gates
  (approve + empty findings) on a change touching no security-relevant surface.
- **`test-rigor-reviewer`** — antagonistic, regression-exposing test coverage of the change's
  public surface and its observable side effects.
- **`observability-reviewer`** — are the change's new code paths + failure modes diagnosable in
  prod (logging/metrics/tracing, no silent failures, no secrets in telemetry)?

> **Override note:** plugin agents are namespaced (`spec-flow:reviewer`, …) when installed.
> `issue-pm` spawns them (as Task-tool subagents, or as `implement`'s agent-team teammates) by
> their **bare name** (`reviewer`, `tdd-developer`, …) first — so if the consuming repo defines its
> own agent with the same bare name (project `.claude/agents/` or user `~/.claude/agents/`), **that
> one overrides the plugin's**, a deliberate way to specialize an agent for a repo's stack. Claude
> Code does **not** automatically fall back to the plugin's namespaced agent when no override
> exists and the bare name isn't otherwise registered — that fallback is this plugin's own code
> (`agentNS()` in `implement.workflow.js`; Team mode's spawn step does the same), which retries as
> `spec-flow:<name>` on a "not found" error rather than relying on platform behavior that isn't
> there.

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
next. When you tell it to start (or resume) a specific issue, it launches that issue's `issue-pm`
as its own process and opens a tab for it — talk to it there to drive that issue directly, and
return to the coordinator's tab (or another issue's `issue-pm`) whenever you want the cross-issue
view again.

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

- The pipeline **never merges your feature PR and never pushes it to `main`** — it only pushes the
  issue branch and opens a PR; the squash-merge is your action in GitHub. The one exception is
  `finalize`'s own small, no-review, archive-only bookkeeping PR (OpenSpec sync, no code), which it
  opens *and* merges itself — see `skills/finalize/SKILL.md`.
- Significant design / data-model decisions are made **before** Seam 1, during `activate`: the
  `architect` (and a domain-expert agent, concurrently, if the repo has one) advises with options +
  trade-offs, you decide right there before anything is generated; Seam 1 then confirms the
  resulting spec faithfully reflects your choice. The agents never make the call.
- Issue/PR numbers are always rendered with a brief `(description)` — a bare number is meaningless.
