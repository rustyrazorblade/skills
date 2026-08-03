# flow — agent delivery workflow

A session-driven, multi-agent delivery pipeline. You (the owner) spend hands-on time only on the
two things a human should own — **defining/prioritizing work** and **final review + merge** — and
the middle runs as a repeatable, agent-driven pipeline. A central coordinator handles cross-issue
state and grooming; the moment you start working a specific issue, it launches a dedicated
per-issue agent as its own separate background Claude Code process — opened in a live iTerm2 tab
or tmux window — that drives that issue's pipeline turn-by-turn with you, in its own context,
until it merges.

This file is the canonical reference. The pipeline is implemented as the plugin's skills
(`/spec-flow:groom|activate|implement|sync-ci|address|finalize|board`) plus a roster of agents: a
`project-manager` central coordinator you talk to directly for cross-issue state and grooming, an
`issue-pm` it spawns per issue to actually drive that issue's lifecycle (see **Coordinator and
issue leads** below); `product-manager` and `architect` at the front of the pipeline (refine →
design → proposal); `tdd-developer` and `build-engineer` for implementation/build; and a review
panel of `reviewer`, `test-rigor-reviewer`, and `observability-reviewer` (plus the built-in
`/code-review` and `/security-review` skills).

It rides on two backbones the consuming repo must provide: **OpenSpec** (the spec-approval seam,
via the `openspec` CLI + the `/opsx:*` commands) and **GitHub** (`gh`-driven issues, labels, and
PRs).

## The two human seams

`groom` runs in the central coordinator; `activate` onward runs in that issue's `issue-pm`, once
it's launched (see **Coordinator and issue leads** below) — the sequence below is the same either
way, just split across two separate processes instead of one conversation:

```
 FOREGROUND (you + coordinator, then you + issue-pm)   BACKGROUND (subagent teams)   GITHUB (you)
 ┌────────────────────────────┐
 │ /spec-flow:groom  rough idea     │
 │   → scoped GitHub issue      │
 │ /spec-flow:activate <issue#>      │
 │   → worktree + branch        │
 │   → architect + domain expert│
 │     design (concurrently)    │
 │   ⏸ you pick the design      │
 │   → openspec explore+propose │
 │     from your chosen design  │
 │   → commit spec              │
 │   → status:spec-review        │──┐
 └────────────────────────────┘  │
        ▲  SEAM 1: you approve the committed spec (design already chosen above)
        │                          │
        │                          ▼
        │                 ┌────────────────────────────┐
        │                 │ /spec-flow:implement <issue#>     │
        │                 │   agent team, you as lead:    │
        │                 │   tdd-developer → review panel│
        │                 │   → fix loop → build-engineer │
        │                 │   → docs polish               │
        │                 │   → push branch, open PR      │
        │                 │   → status:in-review          │──┐
        │                 └────────────────────────────┘  │
        │                                                   ▼
        │                                          ┌──────────────────┐
        │  SEAM 2: you review in GitHub ──────────▶│ leave comments    │
        │                                          └──────────────────┘
        │                 ┌────────────────────────────┐      │
        │                 │ /spec-flow:address <issue#>       │◀─────┘
        │                 │   fix agent in worktree,     │
        │                 │   push, reply to threads     │
        │                 └────────────────────────────┘
        │                                                   │
        │  SEAM 2 (cont.): you squash-merge in GitHub ◀──────┘
        │                          │
        │                          ▼
        │                 ┌────────────────────────────┐
        └─────────────────│ /spec-flow:finalize <issue#>      │
                          │   sync+archive openspec,     │
                          │   remove worktree, close issue│
                          └────────────────────────────┘
```

**Design decision, before Seam 1.** `/spec-flow:activate` stops **twice**. First, right after the
**`architect` agent** designs the work and surfaces options + trade-offs (with a relevant
**domain-expert agent**, if one is available, consulted *concurrently* and adding deeper facts) —
**you decide** among the options *before anything is generated*, so a chosen alternative can never
leave stale traces of the rejected recommendation in the generated spec/tasks. The agents never
make the call.

**Seam 1 — spec approval.** Second, `/spec-flow:activate` stops again after generating the spec
from your chosen design and committing it. Nothing is implemented until you explicitly approve.
This stop confirms the spec faithfully reflects the design you already picked — it is not the
first time you see the decision. (Upstream of both stops, at `groom`, the **`product-manager`
agent** refines the raw idea into scope + testable acceptance criteria — the *what/why* — which the
architect then designs the *how* for.)

**Seam 2 — GitHub review + merge.** The pipeline only ever pushes the issue branch and opens a
PR. It never merges and never pushes to `main`. You review in GitHub, optionally loop through
`/spec-flow:address`, and perform the squash-merge yourself. Merge convention: rebase + squash to a
single commit — one clean commit per PR on a fast-forward main history (never a merge commit,
never the branch's individual commits); rebase onto current main first so the squash fast-forwards.

## Lifecycle and labels

```
status:    ready ──▶ spec-review ──▶ in-progress ──▶ in-review ──▶ addressing ──▶ (merged)
           │             │               │               │             │
 /spec-flow:    groom     activate        implement       (PR open)      address       finalize
           │         + YOU approve                   + YOU review   ⟲ loop        + YOU merged
```

Fixed label vocabulary (bootstrapped once with `bin/bootstrap-labels.sh`):

| Kind | Labels | Meaning |
|---|---|---|
| Priority | `P0` `P1` `P2` `P3` | Exactly one per issue. `P0` = drop everything. |
| Lifecycle | `status:ready` | Groomed; awaiting activation. |
| | `status:spec-review` | Spec committed; awaiting your approval (Seam 1). |
| | `status:in-progress` | Background team implementing. |
| | `status:in-review` | PR open; awaiting your GitHub review (Seam 2). |
| | `status:addressing` | Resolving your review comments. |

**"What's next" rule:** the highest-priority issue (`P0` over `P1` …) carrying `status:ready`.

## Naming

The issue number is the only thing that has to be stable — on a given machine there is never more
than one worktree per issue, so nothing else needs a human-readable name to stay unambiguous.
Two things are derived directly from it, deterministically, no title-derived slug involved:

```
GitHub issue     #N
OpenSpec change  issue-N
pull request     body contains "Closes #N"
```

The git branch and worktree are **not** part of that set, and don't need to be — Claude Code names
and places them itself. `issue-pm` runs as a background session, and Claude Code isolates every
background session into its own git worktree automatically, before it touches any file (see
[Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees)). A stage never
assumes a branch or worktree name; it resolves them from wherever it's already running
(`git rev-parse --abbrev-ref HEAD`, `git rev-parse --show-toplevel`). If a stage needs to recover
state from outside that issue's own session, it goes straight to `openspec/changes/issue-N` for
the change or `Closes #N` in a PR's body for the PR — computed directly from the issue number, not
discovered. (`activate` still orients itself at whatever it finds in `openspec/changes/` before
assuming that name is free — see its **Re-activation** rule — in case older work predates this
convention.) Worktrees are long-lived (one per issue, across many stages and sessions, resumed
automatically by Claude Code across restarts) — **not** the Agent tool's throwaway
`isolation:"worktree"`.

## Coordinator and issue leads

Two tiers of agent, not one. `project-manager` is the **central coordinator** — cross-issue board,
grooming new work, deciding what's next. It does not drive an individual issue's
`activate → implement → address → finalize` itself, and it never runs that lifecycle in-session as
a subagent either. Instead:

- When you want to start or resume work on a specific issue, `project-manager` runs
  `scripts/spawn-issue-pm.sh <N>`, which launches a dedicated **`issue-pm`** (named `issue-pm-<N>`)
  as its **own separate background Claude Code process** — `claude --bg` — and opens a live,
  attached view of it in an iTerm2 tab or tmux window (your configured **display mode**, below).
  You talk to that process directly, in its own context; it never shares the coordinator's.
- That `issue-pm` owns the issue's **entire remaining lifecycle** — both stops inside `activate`,
  `implement`, any `sync-ci`/`address` rounds, and `finalize` — entirely in its own session with
  you, in its own Claude-Code-isolated worktree. It hands back once the issue is merged, archived,
  and closed.
- Several issues can be in flight at once, each its own process, each its own tab. `project-manager`
  checks `claude agents --json` before spawning, so it never launches a duplicate for an issue that
  already has one running; move between tabs, or back to the coordinator's, as you go.
- `project-manager` still runs `groom` and `board` itself (no issue exists to hand off yet, or the
  work spans all issues), and `adopt-tiering` (repo-wide, not tied to any issue).
- `project-manager` never attaches to an `issue-pm`'s session, runs `claude logs` against one, or
  reads its transcript. Its view of an in-flight issue is exactly what `claude agents --json` plus
  GitHub give it — labels, PR, CI, and whether the session is alive — which is the entire point of
  running it as a separate process instead of a subagent: the coordinator's own context never
  fills with one issue's implementation detail.

This is the default flow, not an opt-in — every time you start work on an issue, expect
`project-manager` to launch its `issue-pm` as a fresh process rather than driving the stages
inline.

### Display mode

`issue-pm` opens in a live terminal tab so you can talk to it the moment it's launched. Resolution
order: a `--display` flag on `spawn-issue-pm.sh` (`iterm`, `tmux`, or `none`), then the
`SPEC_FLOW_DISPLAY` env var, then `display=<mode>` in the repo's `.claude/spec-flow.conf`, then
autodetect from the current terminal (`$TMUX` set → tmux; `$TERM_PROGRAM` = `iTerm.app` → iterm;
otherwise none). `project-manager` never passes `--display` itself — it's your standing
preference, not a per-issue decision. `none` backgrounds the session without opening anything, for
dispatching several issues in a row; the attach command is still printed either way.

### Worktree isolation

`issue-pm` sessions get their file isolation from Claude Code itself, not from this plugin: every
background session (`--bg`) is moved into its own git worktree automatically, before it edits any
file, branched from the repo's default branch. Nothing in this plugin creates, names, or excludes
that worktree — see **Naming** above for what that means for cross-stage state, and
[Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees) for how Claude
Code places, resumes, and eventually sweeps it. `finalize` still removes an issue's worktree and
branch explicitly, on its own schedule (tied to the issue merging, not to session idleness) — see
**The skills** below. One-time setup: add `.claude/worktrees/` to the repo's `.gitignore` (see
**Prerequisites** in the README) so these checkouts never show up as untracked files in your
primary checkout.

## The skills

| Skill | Phase | Does |
|---|---|---|
| `/spec-flow:groom` | foreground | Rough idea → scoped GitHub issue (the `product-manager` refines scope + testable acceptance criteria; one `P0–P3` + `status:ready`). |
| `/spec-flow:activate` | foreground | Pick a `status:ready` issue → worktree+branch → `architect` + domain expert design it concurrently → STOP for your design choice → openspec explore+propose from your chosen design → commit spec → `status:spec-review`, then STOP again for your spec approval (Seam 1). |
| `/spec-flow:implement` | background | After your approval: opens a **draft** PR (`Closes #N`) early and pushes at checkpoints so CI runs during implementation, while `issue-pm` drives tdd-developer → review panel → fix loop → build-engineer → docs polish in the worktree — by default as an **agent team** it leads, or the original `Workflow` script where agent teams aren't enabled (`SPEC_FLOW_IMPLEMENT_MODE`); then marks the PR ready and sets `status:in-review`. Invoking this skill is the explicit opt-in to that orchestration. |
| `/spec-flow:address` | foreground-invoked | Pull your PR review comments → fix agent in worktree → push → reply per thread. |
| `/spec-flow:sync-ci` | foreground-invoked | Pull the branch's latest CI failures into `.spec-flow/flagged-tests` so the local loop guards them for the rest of the branch. Owner-invoked when CI reports red; never polls. See **Test tiering** below. |
| `/spec-flow:finalize` | foreground | After you squash-merge: openspec sync+archive, remove worktree, close issue. Never merges. |
| `/spec-flow:board` | foreground | Status across all in-flight issues, derived from labels + PR state; highlights what's next and what's blocked on you. |
| `/spec-flow:adopt-tiering` | setup (one-time) | Split a repo's existing suite into the unit / integration tiers the tiering model assumes (classify by evidence → present → separate structurally → wire CI) and open a PR. Run once per repo; not tied to an issue. See **Test tiering** below. |

## Agents

**Orchestration**
- `project-manager` — the **central coordinator**, the agent you talk to directly. It knows the
  whole lifecycle, runs the board, tracks which issues have an `issue-pm` running (`claude agents
  --json`), decides what's next by priority + lifecycle, and **delegates** — `groom` to the
  `product-manager` subagent, and any specific issue's `activate → implement → address → finalize`
  to that issue's `issue-pm`, launched as its own background process. It coordinates; it does not
  implement, does not drive an issue's stages inline, and never crosses your two seams. Wire it as
  a repo's **default agent** (in that repo's `.claude/settings.json`) to make it your standing
  entry point. The plugin ships **no** root `settings.json` with an `agent` field — opting your
  repos in is your choice, per repo, so the plugin never hijacks the main thread of every project
  that installs it.
- `issue-pm` — the **per-issue delivery lead**, launched by `project-manager` (named
  `issue-pm-<N>`, via `scripts/spawn-issue-pm.sh`) as its own separate background Claude Code
  process when you start or resume work on issue `#N`. You talk to it directly in the iTerm2 tab
  or tmux window that opens for it — not a subagent you switch to inside another conversation. It
  becomes your point of contact for that issue alone: claims it, drives `activate` (both owner
  stops) → `implement` → `sync-ci`/`address` as needed → `finalize`, then hands back. See
  **Coordinator and issue leads** above.

**Front of pipeline (refine → design → proposal)**
- `product-manager` — refines a rough idea into a tight problem statement, in/out scope, and
  **testable WHEN/THEN acceptance criteria** (the *what/why*). Consulted during `/spec-flow:groom`;
  the project-manager brings its draft back to you to edit. Owns the what/why, never the how.
- `architect` — turns the refined idea into a **design** (approach, structure/boundaries to SOLID,
  data model, key interfaces) with **trade-offs framed as owner decisions**. Consulted during
  `/spec-flow:activate`, concurrently with a domain-expert agent if one is available, and
  **before** `openspec-propose` — you decide among its options right there, before anything is
  generated, and Seam 1 later confirms the resulting spec. Advises only — never decides.

**Implementation & build**
- `tdd-developer`, `build-engineer` — the implementation and build agents (bundled with the
  plugin as canonical bases; see the README's "Extending the agents"). `tdd-developer` reads the
  bundled `references/rust-style-guide.md` when the project is Rust, or
  `references/kotlin-style-guide.md` when the project is Kotlin, and holds itself to the matching
  guide.

**Review panel** (run in parallel during `/spec-flow:implement` — see the Review panel below)
- `reviewer` — the authority on **does the implementation match the spec**: reviews the branch diff
  against its committed spec and **the repo's own documented conventions** (its CLAUDE.md /
  CONTRIBUTING / style guide). Complements, does not duplicate, the built-in `/code-review` skill.
  Also **enforces spec-scenario → test traceability**: every `#### Scenario:` in the change's
  `specs/**/spec.md` must have a backing test, and an uncovered scenario is a `major` finding that
  withholds approval and feeds the bounded fix loop until a test is added.
- `test-rigor-reviewer` — audits whether the change's public surface + observable side effects
  have antagonistic, regression-exposing tests.
- `observability-reviewer` — audits whether the change's new code paths + failure modes are
  diagnosable in production (logging at the right level with structured context, metrics on
  operations + errors with bounded label cardinality, tracing/spans around new I/O, no
  silently-swallowed failures, no secrets/PII in telemetry). Self-gates when the diff adds no new
  path/I/O/failure.

> If the consuming repo defines its own agent with one of these names (project or user scope),
> that one **overrides** the plugin's. Use that to specialize a reviewer for a repo's stack.

## Review panel (`/spec-flow:implement`)

Two modes, chosen by `SPEC_FLOW_IMPLEMENT_MODE` (`skills/implement/SKILL.md`, step 4):

- **`team`** (default) — an [agent team](https://code.claude.com/docs/en/agent-teams) with
  `issue-pm` as the lead. `issue-pm` can only lead a team because it's already its own top-level
  session, not a subagent — agent teams don't nest, so this specifically couldn't work the other
  way around. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (see **Prerequisites** in the
  README); missing that, `implement` falls back to `workflow` mode automatically.
- **`workflow`** — the original `Workflow`-tool script (`skills/implement/implement.workflow.js`),
  scripted rather than led. Same lenses, same rules, no team, no experimental flag needed.

Either way, the review stage is not one reviewer — it is a **five-lens panel**; in team mode all
five teammates run **in parallel** each round, in workflow mode the script runs all five the same
way via `parallel()`. Their findings **merge** into one set; a fix round addresses every
`blocker`/`major` from **any** lens; **approval requires every lens to approve with no must-fix
findings.** The five lenses:

1. **spec** (`reviewer` agent) — spec-conformance + the repo's documented rules **and**
   spec-scenario → test traceability (every `#### Scenario:` must have a backing test, else a
   `major` finding).
2. **code-review** (`general-purpose` + the built-in `/code-review` skill) — a correctness-bug
   hunt: logic errors, boundary/edge cases, unhandled error paths, panics, concurrency/async
   ordering, resource leaks, caller/callee contract violations.
3. **security-review** (`general-purpose` + the built-in `/security-review` skill) — input
   validation, isolation, auth/authz, injection, secret/data exposure, external-surface hardening.
   It **self-gates**: it first enumerates whether the change touches any security-relevant surface
   and returns **approve + empty findings** when it touches none.
4. **test-rigor** (`test-rigor-reviewer` agent) — audits **test rigor** for the change's public
   surface + observable side effects: does an **antagonistic, regression-exposing** test exist
   (malformed/oversized input, boundary/limit, error-contract honesty, concurrency conflicts,
   isolation, already-exists/not-found, idempotency/replay)? And does each write/op assert its
   **observable side effect** (emitted event/message/row), not just the direct result? A
   happy-path-only surface, or one with no side-effect assertion, is a `major` gap. **No-ops** off
   any public surface or observable side effect. Also runnable **standalone** to audit the
   existing surface.
5. **observability** (`observability-reviewer` agent) — audits whether the change's new code paths
   and failure modes are **diagnosable in production**: logging at an appropriate level with the
   **structured context** (id/operation/outcome) needed to act; **metrics** on new operations and
   error classes with **bounded label cardinality**; **tracing/spans** around new I/O with context
   propagated across new async boundaries; **no silently-swallowed failures**; and **no
   secrets/PII** emitted to logs/spans/metrics. It judges against the repo's existing observability
   stack, not a foreign one. A silent failure or a logged secret is a `blocker`; a new
   operation/error path with no telemetry where conventions expect one is a `major`. It
   **self-gates**: a diff introducing no new path/I/O/failure returns approve + empty findings.

The code-review and security-review lenses invoke the built-in skills, so they run on a
Skill-capable agent (`general-purpose`), not the `reviewer` agent. The merge/approval logic
generalizes over N lenses — there is no per-lens special-casing beyond the spec lens owning
`spec_conformance`/`tests_ran` — in workflow mode that's the `reviewLenses` array needing no
change; in team mode it's the lead's own reasoning, same rule, needing no change either way. To
add or remove a lens, edit both: the teammate list in `skills/implement/SKILL.md`'s Team mode
step, and the `reviewLenses` array in `implement.workflow.js` for Workflow mode.

## Test tiering (unit / integration)

The pipeline runs the **unit tier locally and the full suite in CI** — never the full suite locally.
The local TDD loop stays fast while CI stays the authoritative gate. When CI catches a regression,
that specific failing test is run locally for the rest of the branch so the same break can't slip
through again.

For CI to actually run *in parallel* with the local loop, `/spec-flow:implement` opens a **draft PR
at the start** and pushes at checkpoints — so the full suite runs on each pushed increment *during*
implementation, not just once at the end. CI stays busy while local work continues, and its results
are ready by the time the PR is marked ready for review.

**Precondition.** This assumes the consuming repo separates its tests **structurally** into a fast
**unit** tier and a slow **integration** tier, and that **merge is gated on green CI**. A repo that
hasn't split its tests yet is brought onto the convention by **`/spec-flow:adopt-tiering`** (a
one-time migration — classify by evidence, separate structurally, wire CI); until then the unit tier
is just the repo's default test command and the model degrades gracefully to running whatever that is.

### unit — the fast local tier

Structural, not annotated: the **unit** tier is the unit-test source location the runner selects by
default (fast, no container, no I/O). It runs on **every local TDD cycle** and is the
`/spec-flow:implement` local gate.

- **Gradle** — the `test` source set (unit); integration/container tests live in a separate
  `integrationTest` source set/suite whose classpath *alone* carries Testcontainers/JDBC/network
  deps, so a container test can't compile under `src/test`. Local: `./gradlew test`. CI: `./gradlew check`.
- **Rust (nextest)** — `src/` unit tests vs `tests/` integration binaries, selected by
  `.config/nextest.toml` profile `default-filter`s. Local: `cargo nextest run`. CI:
  `cargo nextest run --profile ci --run-ignored all`.

### integration — the CI tier, with a per-branch local watch

The **integration** tier (slow, container/I/O) runs only in CI. But when CI catches a regression on a
branch, that specific failing test is pulled into the local loop for the rest of the branch — a
per-branch **flagged set**, so a proven-fragile spot is guarded locally instead of costing another
full CI round-trip.

- A gitignored file, **`.spec-flow/flagged-tests`** inside the issue's worktree. One
  runner-selectable test id per line; `#` comments and blank lines ignored. Ignored via a
  `.spec-flow/` entry in the repo's `.gitignore` (added once; `/spec-flow:sync-ci` ensures it), so it
  never commits.
- **Starts empty on every new branch.** No bootstrap, no diff-based guessing.
- **Populated only by CI failures on that branch** (via `/spec-flow:sync-ci`). Because a branch
  starts from green `main` (merge is gated on green CI), any CI failure on it is by definition a real
  regression the diff introduced — so the caught test is added, **whatever its tier** (including
  integration/container tests), and run locally for the rest of the branch.
- **Local inner loop = unit tier + flagged set.** The `/spec-flow:implement` gate and
  `tdd-developer`'s cycles run both.
- **Dies with the branch.** The branch boundary is the pruning mechanism; nothing carries forward —
  and there is nothing to "promote": a fast test written during the fix already lives in the unit
  tier by location, so it is in the local run on the next branch automatically.

### The loop

```
implement → push → CI runs full suite ──(red)──▶ /spec-flow:sync-ci
                                                    → append failures to .spec-flow/flagged-tests
                                                              │
   local loop runs unit tier + flagged set  ◀─────────────────┘
                                                              │
                                    you merge (green CI) → flagged set evaporates
```

- **`/spec-flow:sync-ci <N>`** — owner-invoked when CI reports red: pulls the branch's latest CI
  failures (the `spec-flow-failures` artifact) and appends them to the flagged set. Session-driven;
  never polls.

### CI contract

On test failure, the consuming repo's CI must upload the failing test id(s) as an artifact named
**`spec-flow-failures`** — one id per line, the same runner-selectable form the flagged set uses.
spec-flow ships reference CI templates under `references/ci/` for the supported runners;
`/spec-flow:sync-ci` reads that artifact. **Merge is gated on green CI** — the invariant the flagged
set's blind-append safety rests on.

## Substrate and constraints

- **Session-driven, not cron.** Everything is triggered and narrated by a session — the central
  coordinator's, or the issue's `issue-pm` once it's launched. `/spec-flow:implement` runs in
  `issue-pm`'s own session either way — as an agent team it leads (default) or a background
  `Workflow` it invokes (fallback) — that is *not* cron either; both are scoped to the lead's own
  session and don't outlive it. `/spec-flow:address` is invoked by you when you return, never
  polled.
- **Concurrency.** Several issues can be in flight at once, each isolated in its own worktree.
  `/spec-flow:board` reports across them.
- **Test tiering.** The local gate is the fast **unit** tier plus the branch's
  `.spec-flow/flagged-tests` — never the full suite; the full/integration suite is CI's gate.
  `/spec-flow:implement` states plainly in its report and the PR that the unit tier ran locally and
  the full suite runs in CI. See **Test tiering (unit / integration)** above. Test resources that
  could collide between concurrent runs should carry a per-process-unique seed so two runs never
  name the same resource.
- **Owner rules, structurally enforced.** OpenSpec before implementation; TDD; significant design
  decisions are the owner's (an advisor agent only advises); land on `main` via PR (no agent
  merge, no push to `main`).

## Conventions

- **Issue/PR numbers always carry a `(description)`.** Every issue or PR number rendered in a
  board, status update, PR body, or prose is paired with a brief parenthetical description —
  `#85 (field identity)`, `PR #97 (test-rigor agent)` — never a bare number. A number alone is
  meaningless to the reader.

## Bootstrap

The label vocabulary is created once per repo (idempotent — safe to re-run):

```bash
bash bin/bootstrap-labels.sh   # from the plugin dir, with the cwd inside the target repo
```
