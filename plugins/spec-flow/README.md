# spec-flow

A Claude Code plugin: a **session-driven, multi-agent delivery pipeline** over **OpenSpec** +
**GitHub**. You own the two human seams — **defining/prioritizing work** and **final review +
merge** — and the middle (spec → implement → review → fix → build → docs → PR) runs as
agents you invoke turn-by-turn.

```
groom ─▶ activate ─▶ [SEAM 1: you approve the spec] ─▶ implement ─▶ [SEAM 2: you review + squash-merge] ─▶ finalize
  │          │                                              │
refine     design                                  review panel (repo-defined)
(product)  (architect)
```

Two tiers of agent run this. A **`project-manager`** is the central coordinator you talk to
directly — it runs the board, grooms new work, and decides what's next, but doesn't drive an
individual issue itself. When you're ready to start or resume an issue, it launches a dedicated
**`issue-manager`** (named `issue-manager-<N>-<slug>` — a readable slug from the issue's own title, so several
open sessions are distinguishable at a glance in `claude agents`; falls back to the bare `issue-manager-<N>`
for a title with no alphanumeric characters to slug) as its **own separate background
Claude Code process** —
you attach to it yourself (`claude agents` — an interactive picker, select it from the list;
there is no direct "attach by id" command) rather than having a tab
or window opened for you — not a subagent in the coordinator's own context. That process owns
`activate → implement → address → finalize` for that one issue, end to end, in its own git
worktree (Claude Code's `EnterWorktree` isolates it — called explicitly as its first action, not
automatic for everything; see **Prerequisites** below), and hands back once it's merged. Several
issues can be in flight at once, each its own process, attach to whichever one you want to talk to.
Wire `project-manager` as a repo's **default agent** to make it your standing entry point (see
below).

See [`docs/workflow.md`](docs/workflow.md) for the full design (the two seams, lifecycle/labels,
the naming/correlators, and the review panel).

## Prerequisites (in the consuming repo)

**Fastest path: run `/spec-flow:setup`** once you've installed the plugin — it explores which of
the items below are already true and only walks you through what's missing, one at a time with a
recommended default, instead of you self-diagnosing this list by hand. The list itself:

- **OpenSpec** — the `openspec` CLI installed and initialized in the repo (the spec backbone;
  the skills use `/opsx:*` and `openspec` commands).
- **GitHub** — `gh` authenticated, and the repo hosted on GitHub (issues/labels/PRs backbone). If
  you have more than one `gh` account/host configured (common in a corporate environment running
  both github.com and a GitHub Enterprise host), make sure the one active by default (`gh auth
  status`) is the right one for this repo — every skill and `scripts/spawn-issue-manager.sh` shell out
  to bare `gh` commands with no `--repo`/account override, so whichever account is active is the
  one they act as. Fix with `gh auth switch` or `GH_HOST` if it's picking the wrong one.
- **Labels** — run the bootstrap once to create the `P0–P3` + `status:*` +
  `agent:active`/`blocked`/`needs-attention` labels:
  ```bash
  bash bin/bootstrap-labels.sh   # cwd inside the target repo; gh authenticated
  ```
- **Built-in skills** — `/code-review` and `/security-review` are used by two of the review
  lenses (they degrade to an inline pass if unavailable).
- **Agent teams (optional, default mode)** — `/spec-flow:implement` defaults to running its
  review panel as an [agent team](https://code.claude.com/docs/en/agent-teams) led by
  `issue-manager`, which requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (experimental, disabled by
  default):
  ```json
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  ```
  in the consuming repo's (or your own) `settings.json`. Not set? `implement` falls back to the
  bundled `Workflow`-tool script automatically — same panel, no team. Set
  `SPEC_FLOW_IMPLEMENT_MODE=workflow` to use that mode on purpose instead of relying on fallback.
- **`spec-flow/TESTING.md` — this repo's own test and CI policy.** spec-flow ships **no default
  policy and no fallback**: the repo states what runs locally, what runs in CI, whether CI is a test
  gate at all, and what gates merge, or nothing runs. `/spec-flow:setup` seeds it — it proposes a
  concrete policy, confirms it with you before writing anything, then opens a PR. `project-manager`
  checks it at session start; `implement`, `address` and `sync-ci` each check it before any work
  and stop with a message naming the fix. Seeding reads your repo first; the
  one seeding template the plugin ships, `references/TESTING.md.template`, states the tiered policy
  and is opened only where your repo already has that shape. Nothing reads it at runtime — policy
  resolution is anchored at your repo's root, so the plugin's copy is outside the tree it searches
  — and a missing `spec-flow/TESTING.md` stops the pipeline rather than falling back to it. A repo
  with no test suite and no test-running CI is a perfectly valid policy here; write that plainly
  rather than inheriting a template that does not apply. See **Test policy** in `docs/workflow.md`.
- **`.claude/worktrees/` and `.spec-flow/` gitignored** — every `issue-manager` runs isolated in its
  own git worktree, named `issue-<N>` deterministically, via Claude Code's `EnterWorktree` tool,
  called explicitly as `issue-manager`'s first action (confirmed by test: isolation is **not**
  automatic in front of a Bash-driven file write — only in front of an Edit/Write tool call — so
  the spawn prompt calls it up front rather than relying on that). Add both `.claude/worktrees/`
  and `.spec-flow/` to the repo's `.gitignore`, once, on your trunk branch — every issue's worktree
  branches from trunk and inherits the entry automatically, so this never needs repeating per
  issue. `.claude/worktrees/` keeps those checkouts from showing up as untracked files in your
  primary checkout (see [Run parallel sessions with
  worktrees](https://code.claude.com/docs/en/worktrees)); `.spec-flow/` keeps per-branch runtime
  state — the flagged-test set (`/spec-flow:sync-ci`) and, if you use it, an issue's
  per-branch runtime state — from ever being committed.

  **Add `.spec-flow/` with the leading dot. Never add `spec-flow/`.** They differ by one character
  and mean opposite things: `.spec-flow/` is gitignored per-branch runtime state, while
  `spec-flow/` is the repo's **committed** configuration, above. Worse, a trailing-slash pattern
  with no interior slash matches at any depth, so an undotted entry would also swallow any nested
  directory of that name.
- **CI contract (for `/spec-flow:sync-ci`)** — only where your policy makes CI a test gate. Under
  such a policy the repo's CI uploads failing test ids as a `spec-flow-failures` artifact on a red
  run, so `sync-ci` has something to pull into the branch's local flagged set. Run
  `/spec-flow:adopt-tiering` once per repo if your policy chooses a structural unit/integration
  split and you want it enforced; see `references/ci/` for the CI templates and **Test policy** in
  `docs/workflow.md` for the model. Where your policy says CI is not a test gate, there is nothing
  to wire and `sync-ci` exits cleanly saying so.

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
| `/spec-flow:groom` | Rough idea → scoped, labeled GitHub issue (scope, acceptance criteria, one `P0–P3`). Grills shape-defining ambiguity one question at a time with a recommended default; verifies bug reports read-only before scoping them; offers `type:docs` to fast-track documentation-only work. |
| `/spec-flow:activate <N>` | Claim it → review it with you (scope/AC freshness + backlog overlap, up to 5 issue-specific questions, skippable via owner-instructions) → worktree + branch → architect + domain expert design it concurrently → **stop for your design choice** → OpenSpec explore+propose from your choice → commit spec → **stop for your approval** (Seam 1). A `type:docs` issue always skips the design stop, and skips spec generation too unless the docs' own layout is changing or it documents a tech change — otherwise it's just a quick review of the issue's own scope. A `type:tech-debt` issue always skips spec generation, and by default the design stop too — architect auto-adopts the confirmed Direction unless something's actually wrong. |
| `/spec-flow:implement <N>` | After approval: background team (tdd-developer → the review panel your `spec-flow/WORKFLOWS.md` names → fix loop → build-engineer → docs) → push branch → open PR. A `type:docs` issue instead runs one lightweight doc-writing pass, architect available on demand. A `type:tech-debt` issue still gets the full panel, in behavior-preservation mode (no spec to conform to). |
| `/spec-flow:address <N>` | Pull your PR review comments → fix in the worktree → push → reply per thread. |
| `/spec-flow:sync-ci <N>` | CI went red → pull the failing test ids into the branch's local flagged set so the fast loop guards them too. Runs when you notice CI go red, or when `issue-manager` notices itself (a single check tied to its own push, not a poll loop) — either way the fix confirms the flagged test locally before pushing again. |
| `/spec-flow:board` | One view of every in-flight issue: stage, priority, PR/CI state, what's next, what's blocked on you, and how many specs are pending the next `/spec-flow:archive`. |
| `/spec-flow:finalize <N>` | Once the feature PR has merged (your squash-merge by default, or `implement`'s own auto-merge if instructed): closes the issue, then removes the worktree. Never opens a PR; never touches the OpenSpec archive — that's `project-manager`'s job, batched. |
| `/spec-flow:archive` | Counts un-archived OpenSpec changes against a threshold (default 5, overridable) and, once you confirm the batch, spawns a dedicated background worker to sync+archive them all and land one PR. Not automatic — you (or project-manager noticing the buildup) trigger it. |
| `/tech-debt` | Lives in `dev-skills`, not spec-flow. A parallel team of review agents audits the codebase for SOLID/composability, duplication, and unnecessary layering, ranks the 10 most impactful findings (skipping anything already an open issue), and walks you through them one at a time — you decide per finding whether to file it. If `dev-skills` is installed, `project-manager` recommends running it weekly or every 20 merged PRs, whichever comes first; never automatic. |
| `/spec-flow:adopt-tiering` | One-time, repo-wide, and only where the repo's own policy chooses that split: separate an existing suite into a fast unit tier and a slow integration tier, and wire CI to the `spec-flow-failures` artifact contract. Not an assumption the pipeline makes — a repo whose policy points elsewhere never needs this. |
| `/spec-flow:setup` | One-time, re-runnable: explore this repo's Prerequisites state and walk through only what's missing, one item at a time with a recommended default. The fastest way to onboard a new repo. |

## Bundled agents

**Orchestration**
- **`project-manager`** — the **central coordinator**, the agent you talk to directly. Runs the
  board, grooms new work, tracks which issues have an `issue-manager` running, and decides what's next.
  It coordinates; it never implements, never drives an issue's stages itself, and only crosses
  your two seams when you explicitly instruct it to for that run (see `docs/workflow.md`'s
  "Overriding either seam's default"). Wire it as your repo's **default agent** (next section).
- **`issue-manager`** — the **per-issue delivery lead**. `project-manager` launches one (named
  `issue-manager-<N>`) as its own background process — via `scripts/spawn-issue-manager.sh` — when you start
  or resume work on issue `#N`; attach to it yourself (`claude agents`, then select the session id
  printed by the spawn script) to talk to it directly. It owns that issue alone, end to end: claims
  it, drives `activate` (both owner stops) → `implement` → `sync-ci`/`address` as needed → `finalize`, then
  hands back. This is the default flow for working an issue, not an opt-in.
- **`archive-batch`** — the **one-shot bulk archiver**. `project-manager` launches one (named
  `archive-batch`) as its own background process — via `scripts/spawn-archive-batch.sh` — once
  you've confirmed a pending batch of OpenSpec changes should be archived. Not tied to an issue,
  not long-running: syncs+archives the whole batch, opens and merges one PR, comments on each
  archived issue, reports, and finishes.

**Front of pipeline (refine → design → proposal)**
- **`product-manager`** — refines a rough idea into tight scope + **testable acceptance criteria**
  (the what/why). Consulted during `groom`.
- **`architect`** — turns the refined idea into a **design** (structure, SOLID, data model,
  trade-offs framed as owner decisions) that feeds the OpenSpec proposal. Consulted during
  `activate`, concurrently with a domain-expert agent if one is available, and **before**
  propose — you stop and decide right there, before anything is generated. Advises; never decides.

**Implementation & build**
- **`tdd-developer`** — test-first (red→green→refactor), SOLID. The implementer, and the default
  when no developer agent is configured. It applies core language rules inline; the full style
  guides live in the standalone `dev-skills` plugin (see **Developer agent** in
  `docs/workflow.md`).
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
> `issue-manager` spawns them (as Task-tool subagents, or as `implement`'s agent-team teammates) by
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
next. When you tell it to start (or resume) a specific issue, it launches that issue's `issue-manager`
as its own background process and reports its session id — run `claude agents` and select it to
attach and drive that issue directly, and switch back to the coordinator's own session (or another
issue's `issue-manager`) whenever you want the cross-issue view again.

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

- By default, the pipeline **never merges your feature PR and never pushes it to `main`** — it
  only pushes the issue branch and opens a PR; the squash-merge is your action in GitHub. An
  `issue-manager` merges the feature PR itself only when you explicitly instruct it to for that run
  (see `docs/workflow.md`'s "Overriding either seam's default") — the `merge-on-green` label is
  the simplest way to say so, settable any time in GitHub itself, no session involved — and even
  then only after the PR's required CI checks are green. Separately, `finalize` never touches the
  OpenSpec archive at all (no code, nothing to review either way) — that's `project-manager`'s job,
  batched across however many issues have piled up and confirmed with you first — see **Bulk spec
  archiving** in `docs/workflow.md`.
- Significant design / data-model decisions are made **before** Seam 1, during `activate`: the
  `architect` (and a domain-expert agent, concurrently, if the repo has one) advises with options +
  trade-offs, you decide right there before anything is generated; Seam 1 then confirms the
  resulting spec faithfully reflects your choice. The agents never make the call.
- Issues and PRs are always rendered as `<number>: <title>`, one per line with a `-` prefix — a
  bare number is meaningless, and a comma-joined run of issues is hard to read.
