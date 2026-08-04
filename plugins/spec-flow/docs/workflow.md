# flow — agent delivery workflow

A session-driven, multi-agent delivery pipeline. You (the owner) spend hands-on time only on the
two things a human should own — **defining/prioritizing work** and **final review + merge** — and
the middle runs as a repeatable, agent-driven pipeline. A central coordinator handles cross-issue
state and grooming; the moment you start working a specific issue, it launches a dedicated
per-issue agent as its own separate background Claude Code process — you attach to it yourself
(`claude attach <id>`) — that drives that issue's pipeline turn-by-turn with you, in its own
context, until it merges.

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
                          │   close issue, remove worktree│
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

**Seam 2 — GitHub review + merge.** By default, the pipeline only ever pushes the issue branch and
opens a PR — it never merges *that* PR and never pushes it to `main`. You review in GitHub,
optionally loop through `/spec-flow:address`, and perform the squash-merge yourself. Merge
convention: rebase + squash to a single commit — one clean commit per PR on a fast-forward main
history (never a merge commit, never the branch's individual commits); rebase onto current main
first so the squash fast-forwards. (`finalize`'s own tiny, no-review archive-only PR afterward is
a separate, standing exception — it opens and merges that one itself; see **The skills** below.)

**Overriding either seam's default.** Both seams default to always stopping. `project-manager`
composes a free-text instruction — from whatever you said for that issue, or a standing preference
you wrote in `CLAUDE.md`, in your own words (never a fixed vocabulary like "Seam 1"/"Seam 2" —
that's internal to these docs, not something you need to say) — and passes it to
`scripts/spawn-issue-pm.sh <N> [owner-instructions]`. Whatever the instruction doesn't address
still stops and waits, by default; nothing is ever inferred or carried over from a different
issue's spawn. Seam 2's auto-merge path only actually merges once the PR's required CI checks
report green — an instruction to merge automatically doesn't skip that; a hard dependency the
architect flags always stops Seam 1 regardless, even under a full auto-approve instruction.

The instruction doesn't just live in the spawn prompt — it's persisted to
**`.spec-flow/owner-instructions`** at the issue's worktree root — gitignored via the one-time,
trunk-branch `.gitignore` entry every issue's worktree already inherits (see **Prerequisites** in
the README; the same entry also covers `.spec-flow/flagged-tests` below) — which `issue-pm`
re-reads fresh at each approval point rather than trusting memory of its original spawn prompt.
This is what makes updating it work across a crash: `claude respawn` (used to recover a
stopped/crashed `issue-pm`, see **Coordination
signals** below) sends no new prompt of its own, so `spawn-issue-pm.sh <N> "<new instructions>"`
on that same issue instead writes the new text directly into the already-resolved worktree. A
currently **live** `issue-pm` is untouched by any of this — the spawn script refuses to respawn
over a running session; changing a live session's instructions means attaching and saying so
directly.

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
| Coordination | `agent:active` | An `issue-pm` is currently claimed/running on this issue — see **Coordination signals** below. |
| | `blocked` | `issue-pm` identified a hard dependency on another unmerged issue (see the issue's comments for which one and why). |

**"What's next" rule:** the highest-priority issue (`P0` over `P1` …) carrying `status:ready`.

## Coordination signals

Every `issue-pm` runs as an independent process — potentially on a different machine, spawned by a
different user's `project-manager`, with no shared memory, messaging, or session state between
them. GitHub is the only thing every one of them, and every `project-manager`, already reads and
writes — so it's the coordination surface, not `claude agents --json --all` (which only ever
reflects the local machine's session registry, and says nothing about another developer's
`issue-pm` running on their own machine — and needs `--all` even for that: every `issue-pm` is a
`background` session, invisible without it, confirmed by test).

- **`agent:active`** — set on the fresh-spawn path by `scripts/spawn-issue-pm.sh` itself, *before*
  it launches anything (not left for `activate` to get to once the session finally runs — that gap
  was minutes wide and two near-simultaneous spawns on different machines could both slip through
  it; `activate`'s own `--add-label` is now just a harmless no-op confirming what's already there).
  Removed by `finalize` on close, and removed by `issue-pm` itself if it hands back or shuts down
  before finishing for any other reason — and by the spawn script itself if it sets the label but
  the launch then fails, so a bad spawn never leaves a false-positive lock behind. This, not
  `claude agents --json --all`, is the authoritative "is anything actually working this issue"
  signal — `board` reads it directly (see its **Steps**).

  `scripts/spawn-issue-pm.sh` checks its **own machine's** past sessions first: a session named
  `issue-pm-<N>` that's still live → refuse (already running here); one that exists but isn't live
  (crashed, stopped, finished) → `claude respawn` it, landing back in its own worktree with its
  branch and uncommitted work intact, instead of a fresh, unrelated one branched from `main` —
  **except** when that worktree is gone (Claude Code's own cleanup swept it, or someone removed it
  by hand): confirmed by test, `claude respawn` in that case doesn't error and doesn't recreate the
  worktree, it silently drops the session into the **primary checkout**. The script checks for
  exactly that after every respawn and stops the session immediately rather than letting it run
  there, clearing `agent:active` and surfacing a recovery command instead. Only when there's no
  local record at all does it fall back to the GitHub label — refuse if `agent:active` is set (an
  issue-pm may be running on another machine this one can't see), spawn fresh otherwise.

  What's still not airtight: label-then-spawn isn't a true compare-and-swap (GitHub's API has no
  atomic label-if-absent), so it narrows the cross-machine race to roughly the time this script
  takes to run rather than closing it completely; and a crash on a machine other than the one
  you're retrying from still needs a human to clear a stale label — nothing detects that on its
  own. A same-machine crash, the common case, now recovers on its own via respawn (or fails safe,
  loudly, if its worktree is gone).
- **Progress comments.** `issue-pm` posts a **new** comment (never edits one in place — the point
  is a readable timeline, not a live-updating status line) on the issue at each meaningful
  milestone: claimed, spec committed, draft PR opened, each `tasks.md` checkpoint during
  `implement`, each review round's result, addressed-comments pushed, CI flagged, merged/archived.
  A fresh `project-manager` (yours or another user's) or the owner can read the issue's comment
  history and know exactly where things stand without attaching to the session at all. Team mode
  (the `implement` default) posts these at full granularity since `issue-pm` is directly driving
  each step; workflow mode is coarser — only before and after, since the script itself has no
  per-step hook back out to a comment.
- **`blocked`** — added alongside a comment naming the specific blocking issue and why, whenever
  `issue-pm` identifies a hard dependency on another unmerged issue (most likely during
  `activate`'s design step, but not only then). Removed, with a follow-up comment, once the
  dependency clears. A single fixed label, not one per blocking issue — the detail lives in the
  comment, keeping the label vocabulary fixed and bootstrapped rather than growing per-issue.

## Naming

The issue number is the only thing that has to be stable. Three things are derived directly from
it, deterministically, no title-derived slug involved:

```
GitHub issue     #N
OpenSpec change  issue-N
worktree         issue-N   (EnterWorktree, passed this name explicitly)
pull request     body contains "Closes #N"
```

The worktree's name is passed explicitly, not left to Claude Code's default random one:
`issue-pm`'s spawn prompt, and `activate` step 2's fallback check, both call `EnterWorktree` with
`name: "issue-<N>"`. This isn't just cosmetic — confirmed by test, `EnterWorktree` called with a
name that already exists on disk does **not** error, it re-enters and resumes that same worktree.
So a fresh spawn whose local session registry lost track of a prior run (the session evicted, or a
different run on this machine) still lands back in the same worktree instead of duplicating it.
This reinforces, rather than replaces, `scripts/spawn-issue-pm.sh`'s own respawn logic (looking for
a past local session named `issue-pm-<N>` and `claude respawn`ing it — see **Coordination signals**
below): respawn recovers the session's own history when a local record exists; the deterministic
worktree name recovers the *files* even when it doesn't.

The git branch itself is still Claude Code's own naming — a stage never assumes a branch name; it
resolves it from wherever it's already running (`git rev-parse --abbrev-ref HEAD`). If a stage
needs to recover state from outside that issue's own session, it goes straight to
`openspec/changes/issue-N` for the change or `Closes #N` in a PR's body for the PR — computed
directly from the issue number, not discovered. (`activate` still orients itself at whatever it
finds in `openspec/changes/` before assuming that name is free — see its **Re-activation** rule —
in case older work predates this convention.) Worktrees are long-lived (one per issue, across many
stages and sessions, resumed automatically by Claude Code across restarts) — **not** the Agent
tool's throwaway `isolation:"worktree"`.

## Coordinator and issue leads

Two tiers of agent, not one. `project-manager` is the **central coordinator** — cross-issue board,
grooming new work, deciding what's next. It does not drive an individual issue's
`activate → implement → address → finalize` itself, and it never runs that lifecycle in-session as
a subagent either. Instead:

- When you want to start or resume work on a specific issue, `project-manager` runs
  `scripts/spawn-issue-pm.sh <N>`, which launches a dedicated **`issue-pm`** (named `issue-pm-<N>`)
  as its **own separate background Claude Code process** — `claude --bg` — and prints the session
  id and the `claude attach <id>` command. **Background-only, deliberately**: you manage running
  sessions yourself via `claude agents` (list) / `claude attach <id>`, not a tab or window opened
  for you on every spawn. You talk to that process directly, in its own context, once attached; it
  never shares the coordinator's.
- That `issue-pm` owns the issue's **entire remaining lifecycle** — both stops inside `activate`,
  `implement`, any `sync-ci`/`address` rounds, and `finalize` — entirely in its own session with
  you, in its own Claude-Code-isolated worktree. It hands back once the issue is merged, archived,
  and closed.
- Several issues can be in flight at once, each its own process — `claude agents` lists them all,
  attach to whichever one you want to talk to. It's the spawn script, not `project-manager` itself,
  that guards against duplicates — this machine's own past sessions first (respawning a crashed one
  rather than starting fresh), the `agent:active` label otherwise — so it never launches a second
  `issue-pm` for an issue that already has one running, on this machine or another.
- `project-manager` still runs `groom` and `board` itself (no issue exists to hand off yet, or the
  work spans all issues), and `adopt-tiering` (repo-wide, not tied to any issue).
- `project-manager` never attaches to an `issue-pm`'s session, runs `claude logs` against one, or
  reads its transcript. Its view of an in-flight issue is exactly what `claude agents --json --all`
  plus GitHub give it — labels, PR, CI, and whether the session is alive — which is the entire
  point of running it as a separate process instead of a subagent: the coordinator's own context
  never fills with one issue's implementation detail.

This is the default flow, not an opt-in — every time you start work on an issue, expect
`project-manager` to launch its `issue-pm` as a fresh process rather than driving the stages
inline.

### Worktree isolation

`issue-pm` sessions get their file isolation from Claude Code itself, not from this plugin — via
the `EnterWorktree` tool, which creates the worktree and switches the session into it, branched
from the repo's default branch. **Not automatic for everything, confirmed by test:** Claude Code
calls `EnterWorktree` on its own in front of an `Edit`/`Write` tool call, but never in front of a
Bash-driven file write (`printf > f`, a heredoc, an external CLI like `openspec` writing files
itself) — so `scripts/spawn-issue-pm.sh`'s spawn prompt tells `issue-pm` to call it explicitly, as
its very first action, with `name: "issue-<N>"`, rather than trusting it to happen implicitly or
letting it generate a random name; `activate` step 2 verifies isolation happened rather than
assuming it, and passes the same name if it has to call `EnterWorktree` itself as a fallback. This
plugin names the worktree, deterministically — see **Naming** above for why that matters — but
still doesn't create or exclude it directly; see
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
| `/spec-flow:finalize` | foreground | Once the feature PR has merged (your squash-merge by default, or `implement`'s own auto-merge if instructed): syncs+archives OpenSpec (via its own small self-merged PR), closes the issue, removes the worktree. Never merges the feature PR itself. |
| `/spec-flow:board` | foreground | Status across all in-flight issues, derived from labels + PR state; highlights what's next and what's blocked on you. |
| `/spec-flow:adopt-tiering` | setup (one-time) | Split a repo's existing suite into the unit / integration tiers the tiering model assumes (classify by evidence → present → separate structurally → wire CI) and open a PR. Run once per repo; not tied to an issue. See **Test tiering** below. |

## Agents

**Orchestration**
- `project-manager` — the **central coordinator**, the agent you talk to directly. It knows the
  whole lifecycle, runs the board, tracks which issues have an `issue-pm` running (`agent:active`,
  via `board`), decides what's next by priority + lifecycle, and **delegates** — `groom` to the
  `product-manager` subagent, and any specific issue's `activate → implement → address → finalize`
  to that issue's `issue-pm`, launched as its own background process. It coordinates; it does not
  implement, does not drive an issue's stages inline, and only crosses your two seams when you
  explicitly instruct it to for that run (see **Overriding either seam's default**, above; neither
  it nor the `issue-pm` it launches ever infers or assumes one). Wire it as
  a repo's **default agent** (in that repo's `.claude/settings.json`) to make it your standing
  entry point. The plugin ships **no** root `settings.json` with an `agent` field — opting your
  repos in is your choice, per repo, so the plugin never hijacks the main thread of every project
  that installs it.
- `issue-pm` — the **per-issue delivery lead**, launched by `project-manager` (named
  `issue-pm-<N>`, via `scripts/spawn-issue-pm.sh`) as its own separate background Claude Code
  process when you start or resume work on issue `#N`. You attach to it yourself (`claude attach
  <id>`, printed by the spawn script) — not a subagent you switch to inside another conversation.
  It becomes your point of contact for that issue alone: claims it, drives `activate` (both owner
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

**Review panel** — `reviewer`, `code-reviewer`, `security-reviewer`, `test-rigor-reviewer`,
`observability-reviewer`; the five lenses run in parallel during `/spec-flow:implement`. Their
individual mandates are described once, in full, in **Review panel** below — not repeated here.

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
   spec-scenario → test traceability. Full mandate: `agents/reviewer.md`.
2. **code-review** (`code-reviewer` agent, invoking the built-in `/code-review` skill) — a
   correctness-bug hunt: logic errors, boundary/edge cases, unhandled error paths, panics,
   concurrency/async ordering, resource leaks, caller/callee contract violations. Full mandate:
   `agents/code-reviewer.md`.
3. **security-review** (`security-reviewer` agent, invoking the built-in `/security-review` skill)
   — input validation, isolation, auth/authz, injection, secret/data exposure, external-surface
   hardening. **Self-gates**: enumerates whether the change touches any security-relevant surface
   and returns **approve + empty findings** when it touches none. Full mandate:
   `agents/security-reviewer.md`.
4. **test-rigor** (`test-rigor-reviewer` agent) — audits **test rigor** for the change's public
   surface + observable side effects, both directions (missing antagonistic coverage AND
   over-built tests). Also runnable **standalone** to audit an existing surface. Full mandate:
   `agents/test-rigor-reviewer.md`.
5. **observability** (`observability-reviewer` agent) — audits whether the change's new code paths
   and failure modes are **diagnosable in production** (logging/metrics/tracing, no silent
   failures, no leaked secrets). **Self-gates** on a diff introducing no new path/I/O/failure. Full
   mandate: `agents/observability-reviewer.md`.

All five are backed by this plugin's own agent definitions — spawning by that agent type already
applies the agent file's full mandate, process, and output contract as the teammate's system
prompt, so both `skills/implement/SKILL.md` and `implement.workflow.js` only send a short
parameter stub (worktree/base/change/issue), not a restatement. The agent file is the single place
each lens's substance lives; edit it there. `code-reviewer`/`security-reviewer` need Skill-tool
access to invoke their built-in skills, which they keep by omitting a restrictive `tools:` line
(unlike `reviewer`'s Read/Bash/Grep/Glob). The merge/approval logic generalizes over N lenses
regardless — there is no per-lens special-casing beyond the spec lens owning
`spec_conformance`/`tests_ran`. To add or remove a lens: write its agent file, then add a stub
entry in both SKILL.md and `implement.workflow.js`'s `reviewLenses` array.

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
  `.spec-flow/` entry in the repo's `.gitignore` — the one-time, trunk-branch entry from
  **Prerequisites** in the README (also covers `owner-instructions` above); `/spec-flow:sync-ci`
  additionally double-checks it's there on each run, so it never commits either way.
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
  decisions are the owner's (an advisor agent only advises); the feature lands on `main` via PR,
  merged by the owner by default. An `issue-pm` merges it itself only when explicitly instructed
  to for that run (see **Overriding either seam's default**, above), never on its own initiative,
  and only after required CI checks are green (`finalize`'s own small archive-only bookkeeping PR
  is a separate, standing exception, and it's never code).

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
