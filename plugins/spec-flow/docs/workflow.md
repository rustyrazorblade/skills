# flow — agent delivery workflow

A session-driven, multi-agent delivery pipeline. You (the owner) spend hands-on time only on the
two things a human should own — **defining/prioritizing work** and **final review + merge** — and
the middle runs as a repeatable, agent-driven pipeline you invoke turn-by-turn from the main
Claude session.

This file is the canonical reference. The pipeline is implemented as the plugin's skills
(`/spec-flow:groom|activate|implement|sync-ci|address|finalize|board`) plus a roster of agents: a
`project-manager` orchestrator you talk to directly; `product-manager` and `architect` at the front
of the pipeline (refine → design → proposal); `tdd-developer` and `build-engineer` for
implementation/build; and a review panel of `reviewer`, `test-rigor-reviewer`, and
`observability-reviewer` (plus the built-in `/code-review` and `/security-review` skills).

It rides on two backbones the consuming repo must provide: **OpenSpec** (the spec-approval seam,
via the `openspec` CLI + the `/opsx:*` commands) and **GitHub** (`gh`-driven issues, labels, and
PRs).

## The two human seams

```
 FOREGROUND (you + PM = the main session)      BACKGROUND (subagent teams)        GITHUB (you)
 ┌────────────────────────────┐
 │ /spec-flow:groom  rough idea     │
 │   → scoped GitHub issue      │
 │ /spec-flow:activate <issue#>      │
 │   → worktree + branch        │
 │   → openspec explore+propose │
 │     (domain expert advises)  │
 │   → commit spec              │
 │   → status:spec-review        │──┐
 └────────────────────────────┘  │
        ▲  SEAM 1: you approve the committed spec (and thereby the design)
        │                          │
        │                          ▼
        │                 ┌────────────────────────────┐
        │                 │ /spec-flow:implement <issue#>     │
        │                 │   Workflow script in worktree:│
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

**Seam 1 — spec approval.** `/spec-flow:activate` stops after committing the spec. Nothing is
implemented until you explicitly approve. This is also where *all significant design decisions are
made*: the **`architect` agent** designs the work and surfaces options + trade-offs (and a relevant
**domain-expert agent**, if one is available, adds deeper facts), and **you decide** — the agents
never make the call. Approving the spec = approving the design. (Upstream of this, at `groom`, the
**`product-manager` agent** refines the raw idea into scope + testable acceptance criteria — the
*what/why* — which the architect then designs the *how* for.)

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

## Naming convention (1:1:1:1)

One stable correspondence so any stage can recover the others from the issue number:

```
GitHub issue  #N  (with slug derived from the title)
git branch        issue-N-slug
git worktree      .claude/worktrees/issue-N-slug
OpenSpec change   slug
pull request      body contains "Closes #N"
```

Worktrees are long-lived (one per issue, across many stages and sessions) and managed via
`git worktree` — **not** the Agent tool's throwaway `isolation:"worktree"`.

## The skills

| Skill | Phase | Does |
|---|---|---|
| `/spec-flow:groom` | foreground | Rough idea → scoped GitHub issue (the `product-manager` refines scope + testable acceptance criteria; one `P0–P3` + `status:ready`). |
| `/spec-flow:activate` | foreground | Pick a `status:ready` issue → worktree+branch → `architect` designs it → openspec explore+propose (architect + domain expert advise) → commit spec → `status:spec-review`, then STOP for your approval. |
| `/spec-flow:implement` | background | After your approval: a `Workflow` script runs the team in the worktree (tdd-developer → review panel → fix loop → build-engineer → docs polish), pushes, opens a PR `Closes #N`, sets `status:in-review`. Invoking this skill is the explicit `Workflow` opt-in. |
| `/spec-flow:address` | foreground-invoked | Pull your PR review comments → fix agent in worktree → push → reply per thread. |
| `/spec-flow:sync-ci` | foreground-invoked | Pull the branch's latest CI failures into `.spec-flow/flagged-tests` so the local loop guards them for the rest of the branch. Owner-invoked when CI reports red; never polls. See **Test tiering** below. |
| `/spec-flow:finalize` | foreground | After you squash-merge: openspec sync+archive, remove worktree, close issue. Never merges. |
| `/spec-flow:board` | foreground | Status across all in-flight issues, derived from labels + PR state; highlights what's next and what's blocked on you. |

## Agents

**Orchestration**
- `project-manager` — the agent you talk to directly. It knows the whole lifecycle, runs the board,
  tracks work-in-progress across in-flight issues, decides what's next by priority + lifecycle, and
  **delegates** every unit of work to the stage skills and the specialist agents. It coordinates; it
  does not implement and never crosses your two seams. Wire it as a repo's **default agent** (in
  that repo's `.claude/settings.json`) to make it your standing entry point. The plugin ships **no**
  root `settings.json` with an `agent` field — opting your repos in is your choice, per repo, so the
  plugin never hijacks the main thread of every project that installs it.

**Front of pipeline (refine → design → proposal)**
- `product-manager` — refines a rough idea into a tight problem statement, in/out scope, and
  **testable WHEN/THEN acceptance criteria** (the *what/why*). Consulted during `/spec-flow:groom`;
  the project-manager brings its draft back to you to edit. Owns the what/why, never the how.
- `architect` — turns the refined idea into a **design** (approach, structure/boundaries to SOLID,
  data model, key interfaces) with **trade-offs framed as owner decisions**. Consulted during
  `/spec-flow:activate`, before `openspec-propose`; its design feeds the proposal. Advises only —
  you decide at Seam 1.

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

The review stage is not one reviewer — it is a **five-lens panel** (`reviewLenses` in
`skills/implement/implement.workflow.js`) run **in parallel** each round. Their findings **merge**
into one set; a fix round addresses every `blocker`/`major` from **any** lens; **approval requires
every lens to approve with no must-fix findings.** The five lenses:

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
`spec_conformance`/`tests_ran`. To add or remove a lens, edit the `reviewLenses` array; the loop
needs no change.

## Test tiering (unit / integration)

The pipeline runs the **unit tier locally and the full suite in CI** — never the full suite locally.
The local TDD loop stays fast while CI stays the authoritative gate. When CI catches a regression,
that specific failing test is run locally for the rest of the branch so the same break can't slip
through again.

**Precondition.** This assumes the consuming repo separates its tests **structurally** into a fast
**unit** tier and a slow **integration** tier, and that **merge is gated on green CI**. A repo that
hasn't split its tests yet is brought onto the convention by a one-time adoption migration (a
separate concern); until then the unit tier is just the repo's default test command and the model
degrades gracefully to running whatever that is.

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

- **Session-driven, not cron.** Everything is triggered and narrated by the main session.
  `/spec-flow:implement` runs as a background `Workflow` (in-session, notifies on completion) — that
  is *not* cron; work pauses when you close the session. `/spec-flow:address` is invoked by you when
  you return, never polled.
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
