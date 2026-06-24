# flow — agent delivery workflow

A session-driven, multi-agent delivery pipeline. You (the owner) spend hands-on time only on the
two things a human should own — **defining/prioritizing work** and **final review + merge** — and
the middle runs as a repeatable, agent-driven pipeline you invoke turn-by-turn from the main
Claude session.

This file is the canonical reference. The pipeline is implemented as the plugin's skills
(`/spec-flow:groom|activate|implement|address|board|finalize`) plus a `reviewer` and a
`test-rigor-reviewer` agent, with `tdd-developer` and `build-engineer` bundled as the
implementation/build agents.

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
made*: a relevant **domain-expert agent (if one is available)** surfaces facts and trade-offs, and
**you decide** — the agent never makes the call. Approving the spec = approving the design.

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
| `/spec-flow:groom` | foreground | Rough idea → scoped GitHub issue (title, scope, acceptance criteria, one `P0–P3` + `status:ready`). |
| `/spec-flow:activate` | foreground | Pick a `status:ready` issue → worktree+branch → openspec explore+propose (domain expert advises) → commit spec → `status:spec-review`, then STOP for your approval. |
| `/spec-flow:implement` | background | After your approval: a `Workflow` script runs the team in the worktree (tdd-developer → review panel → fix loop → build-engineer → docs polish), pushes, opens a PR `Closes #N`, sets `status:in-review`. Invoking this skill is the explicit `Workflow` opt-in. |
| `/spec-flow:address` | foreground-invoked | Pull your PR review comments → fix agent in worktree → push → reply per thread. |
| `/spec-flow:finalize` | foreground | After you squash-merge: openspec sync+archive, remove worktree, close issue. Never merges. |
| `/spec-flow:board` | foreground | Status across all in-flight issues, derived from labels + PR state; highlights what's next and what's blocked on you. |

## Agents

- `reviewer` — reviews a branch diff against its committed spec and **the repo's own documented
  conventions** (its CLAUDE.md / CONTRIBUTING / style guide — whatever the repo documents).
  Complements, does not duplicate, the built-in `/code-review` skill. The review gate also
  **enforces spec-scenario → test traceability**: every `#### Scenario:` in the change's
  `specs/**/spec.md` must have a backing test, and an uncovered scenario is a `major` finding that
  withholds approval and feeds the bounded fix loop until a test is added.
- `test-rigor-reviewer` — audits whether the change's public surface + observable side effects
  have antagonistic, regression-exposing tests (see the Review panel below).
- `tdd-developer`, `build-engineer` — the implementation and build agents (bundled with the
  plugin as canonical bases; see the README's "Extending the agents").

> If the consuming repo defines its own agent with one of these names (project or user scope),
> that one **overrides** the plugin's. Use that to specialize a reviewer for a repo's stack.

## Review panel (`/spec-flow:implement`)

The review stage is not one reviewer — it is a **four-lens panel** (`reviewLenses` in
`skills/implement/implement.workflow.js`) run **in parallel** each round. Their findings **merge**
into one set; a fix round addresses every `blocker`/`major` from **any** lens; **approval requires
every lens to approve with no must-fix findings.** The four lenses:

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

The code-review and security-review lenses invoke the built-in skills, so they run on a
Skill-capable agent (`general-purpose`), not the `reviewer` agent. The merge/approval logic
generalizes over N lenses — there is no per-lens special-casing beyond the spec lens owning
`spec_conformance`/`tests_ran`. To add or remove a lens, edit the `reviewLenses` array; the loop
needs no change.

## Substrate and constraints

- **Session-driven, not cron.** Everything is triggered and narrated by the main session.
  `/spec-flow:implement` runs as a background `Workflow` (in-session, notifies on completion) — that
  is *not* cron; work pauses when you close the session. `/spec-flow:address` is invoked by you when
  you return, never polled.
- **Concurrency.** Several issues can be in flight at once, each isolated in its own worktree.
  `/spec-flow:board` reports across them.
- **Test precondition.** If the full suite has external prerequisites (Docker, a database, a
  broker), `/spec-flow:implement` probes their reachability; if unavailable it degrades to a build +
  prerequisite-independent unit tests and states plainly (in its report and the PR) that the full
  suite did not run. Never silent. Test resources that could collide between concurrent runs
  should carry a per-process-unique seed so two runs never name the same resource.
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
