# flow — agent delivery workflow

A session-driven, multi-agent delivery pipeline. You (the owner) spend hands-on time only on the
two things a human should own — **defining/prioritizing work** and **final review + merge** — and
the middle runs as a repeatable, agent-driven pipeline. A central coordinator handles cross-issue
state and grooming; the moment you start working a specific issue, it launches a dedicated
per-issue agent as its own separate background Claude Code process — you attach to it yourself
(`claude attach <id>`) — that drives that issue's pipeline turn-by-turn with you, in its own
context, until it merges.

This file is the canonical reference. The pipeline is implemented as the plugin's skills
(`/spec-flow:groom|activate|implement|sync-ci|address|finalize|board|archive|setup`) plus a roster of agents: a
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
 │   → review w/ owner          │
 │     (scope + backlog check)  │
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
                          │   close issue, remove worktree│
                          │   (spec archived later, in    │
                          │   bulk, by project-manager)   │
                          └────────────────────────────┘
```

**Owner review, right after claiming — not a third seam.** Before any design work starts,
`/spec-flow:activate` reviews the issue with you directly: is the scope/acceptance criteria you
wrote at `groom` still what you want, and does anything else open in the backlog overlap, duplicate,
or depend on it — a check `groom` can't have made, since it only ever saw the backlog as it stood
when this issue was filed. `issue-pm` searches open issues itself and drafts **up to five**
issue-specific questions from what it actually finds, asked **one at a time**, never a fixed
checklist — a simple issue may earn none at all. This runs for every issue, `type:docs` and
`type:tech-debt` included (their fast paths only ever skip the design/spec machinery further down,
never this). It's not counted as one of the two seams below — it's a lighter, unconditional check
that happens before either of them, not a third owner-approval gate — but it uses the same
override mechanism: `.spec-flow/owner-instructions` (see **Overriding either seam's default** below)
can tell it to skip this review for the run, same free-text, owner's-own-words instruction the
seams already read.

**Design decision, before Seam 1.** `/spec-flow:activate` stops **twice**. First, right after the
**`architect` agent** designs the work and surfaces options + trade-offs (with a relevant
**domain-expert agent**, if one is available, consulted *concurrently* and adding deeper facts) —
**you decide** among the options *before anything is generated*, so a chosen alternative can never
leave stale traces of the rejected recommendation in the generated spec/tasks. The agents never
make the call. (A `type:docs` issue skips this design stop entirely — see **Docs fast path** below.)

**Seam 1 — spec approval.** Second, `/spec-flow:activate` stops again after generating the spec
from your chosen design and committing it. Nothing is implemented until you explicitly approve.
This stop confirms the spec faithfully reflects the design you already picked — it is not the
first time you see the decision. (For a content-only `type:docs` issue there's no spec to generate
or commit — this stop instead reviews the issue's own scope + acceptance criteria; see **Docs fast
path** below.)

**`design.md` must actually carry the architect's reasoning, not a compressed memory of it.**
`openspec-propose`'s own template has no idea steps 3/4 of this pipeline exist, so nothing
guarantees the architect's full advice — the alternatives it presented, the domain-expert facts
behind them — survives from that conversation into the committed file. `activate` step 5 requires
two sections regardless of what `openspec-propose` produced on its own: `## Alternatives
Considered` (every option the architect presented, why each rejected one lost, and whether you
overrode its recommendation — copied in from step 3's actual output, not re-synthesized from
memory), and `## Domain Facts` when a domain-expert was consulted (omitted entirely, not stubbed,
when one wasn't). `proposal.md`'s `## What Changes` is held to the same bar — the actual shape of
the change, not a restated title. None of this is optional polish: it's what makes Seam 1's render
(step 7) something you can actually approve from, instead of having to reconstruct the
architect's reasoning from memory of a conversation three steps back.

**AC coverage is a committed artifact, not a claim.** Where a spec is generated, `activate` step 5
also writes `openspec/changes/issue-<N>/ac-coverage.md` — a table mapping every acceptance
criterion from the issue, and every risk the architect's design surfaced, to the scenario(s) that
cover it (or an explicit, one-line exclusion reason). Every row must resolve one way or the other
before the spec is considered done — nothing gets left unresolved and silently summarized away.
Step 7 renders this table verbatim at Seam 1 (as its own node in the explain view, or inline in
terminal mode) instead of re-narrating coverage in prose, so a dropped criterion is something you
can see directly rather than something you'd have to take the model's word for.

**Spec override and conflict detection.** Where a spec is generated, `activate` step 5 also writes
`openspec/changes/issue-<N>/overrides.md` — always, even when it has nothing to report, so its
absence is never mistaken for "nothing was checked":
- **Overrides existing behavior**: every `MODIFIED`/`REMOVED` requirement in this change's delta
  specs, compared against the current baseline (`openspec/specs/<capability>/spec.md` — the
  already-merged, currently-true spec) — the actual before → after text, not just the fact that a
  `MODIFIED` header exists. This is what "this change overrides a previous decision" looks like
  made explicit instead of left for you to notice by reading headers.
- **Conflicts with other in-flight changes**: every other open `openspec/changes/*` directory that
  touches the same capability as this one, judged for whether it actually modifies/removes the same
  requirement (not just folder-name overlap) — flagged prominently if so, noted as benign overlap
  otherwise.
A genuine hard conflict (two changes modifying the same requirement incompatibly) is a real
blocker, the same class as an architect-flagged hard dependency (see **Overriding either seam's
default** below) — it always stops Seam 1 for you, even under a full auto-approve instruction.
Step 7 renders this file the same way it renders `ac-coverage.md`.

**Structural validation is a pre-flight gate, not a review artifact.** Before either of the above,
`activate` step 5 runs `openspec validate issue-<N> --type change --strict --json` on the generated
spec — a requirement with no scenario, a missing/malformed delta header, and similar mechanical
defects are caught and fixed there, never carried into what you see at Seam 1. (Confirmed by test:
`openspec validate` doesn't check a scenario's internal shape, so step 5 separately confirms every
`#### Scenario:` has real `- **WHEN**`/`- **THEN**` bullets, not free prose.) Nothing renders here
because there's no judgment call for you to make — by the time you see the spec, it's already
structurally valid; `ac-coverage.md`/`overrides.md` above are for the calls that are actually yours
to weigh in on.

**A re-review shows only what changed since your last look.** If the spec gets regenerated after
you've already seen it once at Seam 1 — you redirected `activate`, or you're re-activating a stale
change — step 7 doesn't re-dump the whole spec again. It tracks the commit SHA it last showed you
in `.spec-flow/seam1-last-shown-sha` (gitignored, same category as `.spec-flow/owner-instructions`)
and, on a later re-entry, renders a diff scoped to just `openspec/changes/issue-<N>` between that
SHA and the current one — a real diff view via `review-tools`'s `explain` skill (its `--path` flag
scopes `--diff` to one directory instead of the whole repo) when `SPEC_FLOW_SEAM_VIEW=explain`, or
a scoped `git diff` in terminal mode. `ac-coverage.md`/`overrides.md` still render in full either
way — they're conclusions to re-check as a whole, not something that makes sense line-by-line.

(Upstream of both stops, at `groom`, the **`product-manager`
agent** refines the raw idea into scope + testable acceptance criteria — the *what/why* — which the
architect then designs the *how* for. `groom` itself grills shape-defining scope ambiguity — one
question at a time, its own recommended answer stated alongside each one, dependent questions
ordered before what depends on them — rather than drafting around it and hoping you redline the
right things; see `skills/groom/SKILL.md` step 1. For a bug report, it also attempts a read-only
repro before drafting acceptance criteria, so an unconfirmed report never quietly becomes a settled
spec — see that skill's step 2.)

**Seam 2 — GitHub review + merge.** By default, the pipeline only ever pushes the issue branch and
opens a PR — it never merges *that* PR and never pushes it to `main`. You review in GitHub,
optionally loop through `/spec-flow:address`, and perform the squash-merge yourself. Merge
convention: rebase + squash to a single commit — one clean commit per PR on a fast-forward main
history (never a merge commit, never the branch's individual commits); rebase onto current main
first so the squash fast-forwards. (`finalize` itself only closes the issue and removes its
worktree afterward — it doesn't touch the OpenSpec archive at all; that's separate, no-review
bookkeeping `project-manager` does in bulk across several issues at once, see **Bulk spec
archiving** below.)

**Seam visualization.** At both seams, the rendered content — the spec/scope at Seam 1, the diff
at Seam 2 — can be shown two ways, an owner preference set once per repo by `/spec-flow:setup`, and
only ever offered if the standalone **`review-tools`** plugin (separate from spec-flow — see
**A note on `review-tools`** below) is installed: `SPEC_FLOW_SEAM_VIEW=explain` (recommended
default when `review-tools` is available) generates an interactive, self-contained HTML view via
its `explain` skill (file tree, diff/doc view, and per-node explanations in one page) and prints
its path + an `open <path>` command — a background `issue-pm` can't reliably pop a browser on your
screen, so it never tries; `SPEC_FLOW_SEAM_VIEW=terminal` renders the same content as plain text in
the conversation, the original behavior from before `explain` existed, and is what's used
automatically if `review-tools` isn't installed on the machine an `issue-pm` happens to be running
on, even when the preference says `explain`. Read fresh from `.claude/settings.json` at each seam,
not cached from an earlier stop; `review-tools`'s own availability is re-checked fresh too (via
`claude plugin list --json`), not assumed from setup time. `/explain` (from `review-tools`) is also
the owner's own primary way to look at any issue — including a plain backlog issue, before it's
even activated, with no diff or worktree required (its `--issue` mode pulls the issue's body,
comments, and related/linked issues straight from GitHub) — usable with or without spec-flow
installed at all.

**A note on `review-tools`.** It's a separate, standalone plugin, not part of spec-flow — installed
independently, useful in any repo whether or not that repo uses spec-flow at all. spec-flow depends
on it only optionally, one-directionally, and at runtime (resolving its installed root fresh via
`claude plugin list --json`, never a hardcoded path) — spec-flow ships and works completely without
it, just without the HTML seam views. See its own `skills/explain/SKILL.md` for the format itself,
and `skills/setup/SKILL.md` here for how the seam-view preference gets set.

**Two more standing preferences, asked once by `project-manager` itself (not `/spec-flow:setup`,
not `issue-pm`).** Unlike seam visualization above, these are gated on a specific tool actually
being in use, so they're asked by `project-manager` on its own first look at the repo rather than
folded into `setup`'s fixed checklist — see **Startup checks** in `agents/project-manager.md` for
the exact detection commands and phrasing:
- **`SPEC_FLOW_UNIFIED_MEMORY`** — when MemSearch is enabled, whether every issue's worktree should
  share one MemSearch memory store instead of each getting its own (MemSearch keys memory off the
  git toplevel by default, and every worktree has a distinct one). `spawn-issue-pm.sh` computes and
  exports the actual shared path fresh at every spawn when this is `"1"` — never stored as a fixed
  path itself, since an absolute path baked into checked-in settings would be wrong on every other
  machine this repo is cloned to.
- **`SPEC_FLOW_AUTO_INDEX`** — when claude-context is connected, whether `activate` should index
  each new issue worktree with it automatically, right after isolating (`skills/activate/SKILL.md`
  step 2) — claude-context indexes by absolute path, so each worktree needs its own call regardless
  of this setting; the setting only controls whether that call happens automatically or not at all.

**Overriding either seam's default.** Both seams default to always stopping. `project-manager`
composes a free-text instruction — from whatever you said for that issue, or a standing preference
you wrote in `CLAUDE.md`, in your own words (never a fixed vocabulary like "Seam 1"/"Seam 2" —
that's internal to these docs, not something you need to say) — and passes it to
`scripts/spawn-issue-pm.sh <N> [owner-instructions]`. Whatever the instruction doesn't address
still stops and waits, by default; nothing is ever inferred or carried over from a different
issue's spawn. Seam 2's auto-merge path only actually merges once the PR's required CI checks
report green — an instruction to merge automatically doesn't skip that; a hard dependency the
architect flags, or a hard spec conflict step 5's override/conflict check finds (see **Spec
override and conflict detection** below), always stops Seam 1 regardless, even under a full
auto-approve instruction.

**Seam 2's auto-merge specifically can also be set with the `merge-on-green` label** — it's a
binary, GitHub-native "how to handle this issue" setting (metadata about what's being built, not
code), so it lives as a label rather than needing to go through the spawn-time instruction above:
apply it directly in GitHub, or tell `project-manager`, any time — before spawn, after spawn, even
on a live `issue-pm` — and `implement` checks it fresh at step 5, no worktree/file involved. The
free-text instruction still works too (either one triggers auto-merge); the label just doesn't
require composing a sentence or waiting for a spawn/respawn to deliver it. Other, less binary
instructions (Seam 1 auto-approve, anything not reducible to a yes/no) still go through the
file below.

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

**Docs fast path.** A purely documentation issue (README, a docs/mdBook tree, comments — no
behavior change) doesn't need an architect's design or a design-choice stop to decide between. Set
`type:docs` at `groom` (offered, never inferred silently — see its step 3); `activate` always skips
the architect/domain-expert consult and the design-choice stop for it. Whether it *also* gets a
committed OpenSpec spec is a second, separate decision — most docs changes shouldn't get one at
all, because translating a page's own prose into OpenSpec `#### Scenario:` blocks just duplicates
the book:

- **Content edit (the default, assumed unless the issue says otherwise)** — expanding, correcting,
  or clarifying existing pages, adding examples, fixing wording; the docs' own organization isn't
  changing and nothing behavioral is being documented for the first time. `activate` skips spec
  generation entirely — no `openspec/changes/issue-<N>` directory — and Seam 1 becomes a quick
  review of the issue's own scope + acceptance criteria (already reviewed once at `groom`) instead
  of a generated spec.
- **Structural, or documenting an accompanying tech change** — the docs' own layout/organization is
  changing (new chapter, reorganized `SUMMARY.md`/table of contents, split or merged sections), or
  the issue documents real new behavior. That's a decision worth a committed, reviewable record —
  `activate` runs the normal OpenSpec flow, but keeps it **surface-level**: the structural approach
  and affected pages, never the prose that's actually going into the book.

`implement` runs a single lightweight doc-writing pass either way instead of tdd-developer + the
five-lens panel + build + polish — working `tasks.md` when a spec exists, or the issue's own
acceptance criteria directly when it doesn't — with `architect` available **on demand** if the doc
writer hits a real architecture question (not a mandatory gate). Seam 1 (spec approval, whichever
form it took) and Seam 2 (review/merge) still apply exactly as normal either way — the fast path
only ever skips machinery that doesn't apply to a docs-only change, never an owner stop. See
`skills/activate/SKILL.md` steps 3 and 5 and `skills/implement/SKILL.md` step 4 for the mechanics.

**Hard dependencies use GitHub's native issue-dependencies API, alongside the `blocked` label.**
When `activate` step 4 finds a hard dependency on another unmerged issue, it sets `blocked` (what
`board` filters on) **and** creates a native `blocked_by` link (`gh api
repos/{owner}/{repo}/issues/<N>/dependencies/blocked_by`, keyed on the blocking issue's numeric
database id, not its repo-scoped number — confirmed live against this plugin's own repo) so the
relationship renders directly in GitHub's own UI, not just in a comment. Additive, not a
replacement — the label stays queryable (`gh issue list --label blocked`) in a way the native link
alone isn't.

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
| | `status:spec-review` | Spec committed and awaiting your approval (Seam 1) — or, for a content-only `type:docs` issue or any `type:tech-debt` issue, no spec at all, just a quick review of its own scope + acceptance criteria (or Direction). |
| | `status:in-progress` | Background team implementing. |
| | `status:in-review` | PR open; awaiting your GitHub review (Seam 2). |
| | `status:addressing` | Resolving your review comments. |
| Coordination | `agent:active` | An `issue-pm` is currently claimed/running on this issue — see **Coordination signals** below. |
| | `blocked` | `issue-pm` identified a hard dependency on another unmerged issue (see the issue's comments for which one and why; also expressed as a native GitHub issue dependency, see **The two human seams** above). |
| | `needs-attention` | `issue-pm` hit something outside the two defined owner seams that only you can resolve — an ambiguous call, a conflict it can't cleanly reconcile, a repeated failure — and is waiting (see the issue's comments for what). Distinct from `blocked`, which is specifically a hard dependency on another issue. See **Coordination signals** below. |
| Fast path | `type:docs` | Documentation-only — `activate`/`implement` always skip the architect consult, design-choice stop, and review panel, and skip spec generation too unless the docs' own layout is changing or it documents a tech change (see **Docs fast path** above). Offered by `groom`, never inferred silently. |
| | `type:tech-debt` | Structural, behavior-preserving fix filed by `/spec-flow:tech-debt` (SOLID, duplication, or layering). `activate` always skips OpenSpec generation, and by default skips the owner design-choice wait too — auto-adopting the Direction confirmed when filed, unless a hard dependency, a material deviation, or an actual behavior change turns up. `implement` still runs the full review panel in behavior-preservation mode — never combine with `type:docs` (see **Tech-debt fast path** below). |
| Autonomy | `merge-on-green` | Merge this PR automatically once required CI checks pass — no owner review wait. Set directly by the owner (GitHub or `project-manager`), any time; `implement` checks it fresh, no worktree file involved. See **The two human seams** above. |
| Audit | `tech-debt-review` | Marks a closed, immediately-created log issue for one completed `/spec-flow:tech-debt` run — not a work item, just the durable timestamp `project-manager` reads for the once-a-week/20-merges cadence check. See **Tech-debt review cadence** below. |

**"What's next" rule:** the highest-priority issue (`P0` over `P1` …) carrying `status:ready`.

**Epics / parent issues are never directly workable.** An issue with GitHub native sub-issues
(`subIssuesSummary.total > 0`) is a rollup of its children, not its own unit of work — there's
nothing to spec or implement against the epic itself. `scripts/spawn-issue-pm.sh` checks this
before doing anything else and refuses to spawn against one (listing its sub-issues instead), and
`board` pulls epics into their own informational section rather than ever surfacing one as READY
or "next up," whatever `status:*` label it happens to carry. Work the sub-issues individually.

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

  `scripts/spawn-issue-pm.sh` checks its **own machine's, this repo's** past sessions first — a
  session named `issue-pm-<N>` is only unique within one repo (GitHub issue numbers are per-repo),
  so the lookup is scoped to sessions whose `cwd` falls under this repo's own root, not by name
  alone; otherwise a same-numbered issue in a different repo on this machine could match. A match
  that's still live → refuse (already running here); one that exists but isn't live (crashed,
  stopped, finished) → `claude respawn` it, landing back in its own worktree with its branch and
  uncommitted work intact, instead of a fresh, unrelated one branched from `main` —
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
  `implement`, each review round's result, addressed-comments pushed, CI flagged, merged and
  closed. `archive-batch` adds one more, later and separately: a comment on each issue once its
  spec is actually archived, as part of whatever batch it landed in. A fresh `project-manager`
  (yours or another user's) or the owner can read the issue's comment history and know exactly
  where things stand without attaching to the session at all. Team mode
  (the `implement` default) posts these at full granularity since `issue-pm` is directly driving
  each step; workflow mode is coarser — only before and after, since the script itself has no
  per-step hook back out to a comment.
- **`blocked`** — added alongside a comment naming the specific blocking issue and why, whenever
  `issue-pm` identifies a hard dependency on another unmerged issue (most likely during
  `activate`'s design step, but not only then), **and** a native GitHub issue dependency (see **The
  two human seams** above) — the label is what's queryable/bootstrapped like every other label in
  the fixed vocabulary; the native link is what actually renders in GitHub's UI. Both removed, with
  a follow-up comment, once the dependency clears. A single fixed label, not one per blocking issue
  — the detail lives in the comment (and the native link itself), keeping the label vocabulary
  fixed rather than growing per-issue.
- **`needs-attention`** — added alongside a comment naming exactly what's needed, whenever
  `issue-pm` is genuinely stuck on something with no defined next step of its own: not one of **The
  two human seams** (those are scheduled stops, already surfaced their own way — spec approval,
  review + merge) and not a hard dependency on another issue (that's `blocked`, above). Covers the
  ad hoc case — an ambiguous call `.spec-flow/owner-instructions` doesn't resolve, a conflict it
  can't reconcile on its own, a failure that repeats past the point retrying makes sense — where
  guessing would be worse than waiting. `issue-pm` stops and waits once it's set, the same as at
  either seam. Removed, with a follow-up comment, once the owner resolves it and work resumes.

## Naming

The issue number is the only thing that has to be stable. Three things are derived directly from
it, deterministically, no title-derived slug involved:

```
GitHub issue     #N
OpenSpec change  issue-N   (not always present — skipped for content-only type:docs issues, see Docs fast path, and unconditionally for type:tech-debt issues, see Tech-debt fast path)
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
  you, in its own Claude-Code-isolated worktree. It hands back once the issue is merged and closed
  — if it committed one (not every issue does, see **Docs fast path** and **Tech-debt fast path**),
  its OpenSpec change is archived later, in bulk, by `project-manager` (see **Bulk spec archiving**),
  not by `issue-pm` itself.
- Several issues can be in flight at once, each its own process — `claude agents` lists them all,
  attach to whichever one you want to talk to. It's the spawn script, not `project-manager` itself,
  that guards against duplicates — this machine's own past sessions first (respawning a crashed one
  rather than starting fresh), the `agent:active` label otherwise — so it never launches a second
  `issue-pm` for an issue that already has one running, on this machine or another.
- `project-manager` still runs `groom` and `board` itself (no issue exists to hand off yet, or the
  work spans all issues), and `adopt-tiering`, `setup`, `archive`, and `tech-debt` (repo-wide, not
  tied to any issue).
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

## Bulk spec archiving

`finalize`'s OpenSpec archive is pure bookkeeping — no code, nothing to review — and doing it
per-issue, inline in each `issue-pm`, meant a git worktree and a set of `gh`/OpenSpec commands
every single time, for zero review value each time. So `finalize` doesn't touch it at all anymore:
once an issue's PR merges, its `openspec/changes/issue-<N>` change (when one exists — a
content-only `type:docs` issue commits none, see **Docs fast path** above) just sits on the default
branch, unarchived, until `project-manager` sweeps up a batch of them at once.

`project-manager` **watches for the buildup and checks in with you** — it never archives on its own
initiative. `/spec-flow:archive` counts every `openspec/changes/*` directory (excluding `archive/`)
on the default branch, compares it against a threshold (**default 5**, overridable — state a
standing preference once, in this conversation or in `CLAUDE.md`, or override ad hoc for just one
run: "archive these 3 now"), and — only once you've confirmed the specific batch — spawns a
dedicated **`archive-batch`** worker as its own separate background Claude Code process (via
`scripts/spawn-archive-batch.sh`), the same delegation pattern as `issue-pm`: `project-manager`
coordinates, it doesn't do the archiving itself. You can attach to that worker
(`claude attach <id>`) to watch it, same as any `issue-pm`.

The worker (`agents/archive-batch.md`) does the whole batch in one pass: one short-lived worktree
cut from the default branch, `openspec-sync-specs`/`openspec-archive-change` for every pending
change in the batch, one combined commit, one PR (`scripts/archive-batch-pr.sh` handles the
push/open/merge mechanics), a progress comment on each archived issue, then it reports and
finishes — no looping, no respawn support, since nothing owner-valuable is at risk if it crashes
(worst case, an abandoned worktree; re-running `/spec-flow:archive` just recomputes the buildup
fresh from the default branch and spawns a new worker).

**Once you've confirmed the batch, the rest is fully autonomous — including the merge.** There's no
second upfront check-in before landing the PR; that would defeat the point of batching in the first
place. Two things still involve you, and neither is a silent guess: a PR that can't merge
automatically (required checks pending, branch protection) stops the worker and reports —
mechanical, the same way `implement`'s own auto-merge reports a blocked merge. A genuine content
conflict while reconciling two changes' delta specs is different: rather than stopping and handing
back for you to resolve separately later, the worker **pauses and works it out with you
interactively**, right there in that session — the same way `issue-pm` waits at a design or spec
seam — then continues the batch from where it left off once you've resolved it together. It posts
a comment on every issue involved first, so there's a trail (and an attach pointer) even if you're
not watching when it happens.

This is **session-driven, not cron** (see **Substrate and constraints** below) — nothing runs
`/spec-flow:archive` automatically or on a timer; you decide when, or `project-manager` offers when
it notices the count while doing something else. `board` surfaces how many specs are pending so you
notice, but never triggers anything itself. An issue's own `finalize` — closing it, removing its
worktree — never waits on its archive actually landing; the OpenSpec change sitting unarchived on
the default branch is expected, normal state between batches, not a problem to fix per-issue.

## Tech-debt review cadence

Structural debt otherwise only surfaces as a side effect of touching nearby code — `architect`'s
"Nearby structural debt" step during `activate` flags what a change happens to brush up against, and
even then only ever *recommends* a separate issue, never files one itself. `/spec-flow:tech-debt` is
the deliberate, repo-wide counterpart: a team of review agents reads the whole codebase (or a scoped
path) for nothing else — SOLID/composability, code duplication, unnecessary layering — ranks the 10
most impactful findings, drops anything that duplicates an already-open issue, and walks you through
what's left **one at a time, full context each time** — you decide per finding whether it's worth a
`type:tech-debt` issue. Same shape as every other owner-facing decision in this pipeline: the agents
surface candidates, they never file anything on their own.

**`project-manager` recommends running it, on a cadence — it never runs it itself and never spawns a
background process for it.** Due whenever either fires, whichever comes first: **a week since the
last run, or 20 PRs merged since the last run.** Every `/spec-flow:tech-debt` run creates a
`tech-debt-review`-labeled log issue, closed immediately, purely as a durable timestamp — that's what
lets `project-manager` compute "due" without guessing (see **Watching for tech-debt review cadence**
in `agents/project-manager.md`). When due, it's mentioned plainly the next time you're already
talking to `project-manager` (typically alongside `board`); not due, it says nothing — this is a
recommendation cadence, not a background timer (see **Substrate and constraints** below), and running
it is still entirely your call.

## Tech-debt fast path

A `type:tech-debt` issue (filed by `/spec-flow:tech-debt`, confirmed by you one finding at a time
before it ever became an issue) skips OpenSpec entirely — there's no behavior change to spec, so
generating one would just be ceremony around a decision already made. It's still a real code
change, so it still gets the full five-lens review panel at `implement` and a real PR at Seam 2;
only the OpenSpec-generation-and-approval machinery is what's skipped, replaced by narrower,
cheaper checks that exist specifically to catch the one way this fast path could go wrong: a "pure
refactor" that turns out not to be one.

- **`activate` step 3-4: a narrowed, auto-adopting `architect` consult, not a skip.** Unlike
  `type:docs` (which skips the design consult entirely — there's no architecture to a prose
  change), a structural fix genuinely benefits from a fresh read: the finding's file:line evidence
  may be stale by the time the issue is activated. `architect` verifies the confirmed `##
  Direction` still applies (or corrects it) and checks whether it's achievable **without changing
  any observable behavior**. The owner-decision *stop* is still skipped by default — you already
  confirmed this specific fix once, item by item, in `/spec-flow:tech-debt` — but only when nothing
  went wrong: a hard dependency, a material deviation from the confirmed Direction, or the fix
  turning out not to be behavior-preserving all still stop for you, same as a hard dependency
  always has. See **Escalation** below for what happens then.
- **`activate` step 5: no spec, but a read-only surface listing against what's already spec'd.**
  Instead of generating a change, `activate` greps `openspec/specs/**` for requirements whose
  subject matter overlaps the finding's touched files/modules and appends what it finds to the
  issue body under `## Adjacent specified behavior (must be preserved)` — so both the lightweight
  Seam 1 review and `implement`'s review panel have it without re-deriving it.
- **Seam 1, lightweight but not skipped.** Same principle as the docs fast path: no spec to
  approve, but still a real stop showing the confirmed Direction and the adjacent-behavior list
  before implementation starts — cheap, since you already reviewed the substance once at filing
  time.
- **`implement`: full panel, in behavior-preservation mode.** `tdd-developer` works from the
  issue's Direction (no `tasks.md` exists) with an explicit instruction to stop and report, not
  implement, if the clean fix would require a real behavior change. The `spec` lens (`reviewer`
  agent) switches to a documented **tech-debt fast path mode** (see `agents/reviewer.md`) whose
  contract is behavior-preservation, not spec conformance: any change to a public
  signature/error-contract/CLI/config/serialized output is a `blocker` regardless of whether a
  canonical spec covers it, and — the check that catches what the adjacent-specs list can't — a
  **deleted existing test or a changed assertion is automatic evidence of a behavior change**, since
  committed specs are an incomplete map of what the software actually does and the pre-existing
  test suite is the more complete oracle. The other four lenses run exactly as normal. Because no
  spec exists yet when this fast path starts, the branch also has no commits and thus no draft PR
  at `implement` step 2 — `implement`'s Implement phase opens it itself, right after the first
  commit lands (see `skills/implement/SKILL.md` step 2/4a and `implement.workflow.js`).

**Escalation, when it turns out not to be behavior-preserving.** Two catch points, same three
options either way — proceed with a corrected still-preserving shape, narrow the fix to what
genuinely is preserving, or split the behavior change into its own freshly groomed issue and run
the full pipeline for it: `architect`'s consult at `activate` (before anything is implemented), or
`tdd-developer`/the `spec` lens mid-`implement` (after some of it already is). Full detail in
`agents/issue-pm.md`'s **Escalation** section — never silently pick an option; this is exactly the
kind of consequential call that belongs to you.

**`type:docs` and `type:tech-debt` never combine** — an issue is either a documentation change or a
structural code change, never both; `activate` falls back to the full pipeline if it ever finds
both labels on the same issue (labeling ambiguity is reason enough not to trust either fast path).

## The skills

| Skill | Phase | Does |
|---|---|---|
| `/spec-flow:groom` | foreground | Rough idea → scoped GitHub issue. Grills shape-defining ambiguity (recommended default per question); for a bug, verifies read-only before scoping it; offers `type:docs` for documentation-only work. The `product-manager` refines scope + testable acceptance criteria; one `P0–P3` + `status:ready`. |
| `/spec-flow:activate` | foreground | Pick a `status:ready` issue → worktree+branch → `architect` + domain expert design it concurrently → STOP for your design choice → openspec explore+propose from your chosen design → commit spec → `status:spec-review`, then STOP again for your spec approval (Seam 1). A `type:docs` issue always skips the design stop, and skips spec generation too unless it's structural/tech-accompanying — see **Docs fast path** above. A `type:tech-debt` issue always skips spec generation and, by default, the design-choice stop too (`architect` auto-adopts the confirmed Direction unless something's wrong) — see **Tech-debt fast path** above. |
| `/spec-flow:implement` | background | After your approval: opens a **draft** PR (`Closes #N`) early and pushes at checkpoints so CI runs during implementation, while `issue-pm` drives tdd-developer → review panel → fix loop → build-engineer → docs polish in the worktree — by default as an **agent team** it leads, or the original `Workflow` script where agent teams aren't enabled (`SPEC_FLOW_IMPLEMENT_MODE`); then marks the PR ready and sets `status:in-review`. A `type:docs` issue instead runs one lightweight doc-writing pass (`tasks.md` if a spec exists, otherwise the issue's own acceptance criteria directly; architect on demand), skipping the panel/build/polish. A `type:tech-debt` issue still runs the full panel, in behavior-preservation mode (no spec to conform to), working from the issue's Direction instead of `tasks.md`. Invoking this skill is the explicit opt-in to that orchestration. |
| `/spec-flow:address` | foreground-invoked | Pull your PR review comments → fix agent in worktree → push → reply per thread. |
| `/spec-flow:sync-ci` | foreground-invoked | Pull the branch's latest CI failures into `.spec-flow/flagged-tests` so the local loop guards them for the rest of the branch. Owner-invoked when CI reports red; never polls. See **Test tiering** below. |
| `/spec-flow:finalize` | foreground | Once the feature PR has merged (your squash-merge by default, or `implement`'s own auto-merge if instructed): closes the issue, removes its worktree. Never merges the feature PR, and never touches the OpenSpec archive — that's `project-manager`'s job, batched — see **Bulk spec archiving** above. |
| `/spec-flow:board` | foreground | Status across all in-flight issues, derived from labels + PR state; highlights what's next, what's blocked on you, and how many specs are pending the next `/spec-flow:archive`. |
| `/spec-flow:archive` | foreground-invoked | Count the pending un-archived specs against a threshold (default 5, overridable); once confirmed with you, spawns a dedicated `archive-batch` worker to sync+archive them all in one pass and land one PR — see **Bulk spec archiving** above. |
| `/spec-flow:tech-debt` | foreground-invoked | Repo-wide structural audit: a parallel team of review agents finds SOLID/composability, duplication, and unnecessary-layering issues, ranks the 10 most impactful, drops anything already an open issue, and walks you through the rest one at a time — you decide per finding whether it becomes a `type:tech-debt` issue, which then takes the **Tech-debt fast path** above through `activate`/`implement`. `project-manager` recommends running the audit itself once a week or every 20 merged PRs, whichever comes first — never automatic. See **Tech-debt review cadence** above. |
| `/spec-flow:adopt-tiering` | setup (one-time) | Split a repo's existing suite into the unit / integration tiers the tiering model assumes (classify by evidence → present → separate structurally → wire CI) and open a PR. Run once per repo; not tied to an issue. See **Test tiering** below. |
| `/spec-flow:setup` | setup (one-time, re-runnable) | Explore this repo's Prerequisites state, then walk through only what's missing — OpenSpec init, `gh` auth, labels, the agent-teams env var, `.gitignore` entries, CI tiering — one item at a time with a recommended default. Not tied to an issue. |

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
- `archive-batch` — the **one-shot bulk archiver**, launched by `project-manager` (named
  `archive-batch`, via `scripts/spawn-archive-batch.sh`) as its own separate background process
  once you've confirmed a pending batch of OpenSpec changes should be archived. Not tied to any
  issue and not long-running: does the batch, opens and merges one PR, comments on each archived
  issue, reports, and finishes. See **Bulk spec archiving** above.

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

Each lens's full substance lives only in its agent file — `skills/implement/SKILL.md` and
`implement.workflow.js` send only a short parameter stub (worktree/base/change/issue), never a
restated mandate. `code-reviewer`/`security-reviewer` keep Skill-tool access (omit a restrictive
`tools:` line) to invoke their built-in skills. Merge/approval logic generalizes over N lenses —
only the spec lens owns `spec_conformance`/`tests_ran`. To add or remove a lens: write its agent
file, then add a stub entry in both SKILL.md and `implement.workflow.js`'s `reviewLenses` array.

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
  polled. `/spec-flow:tech-debt`'s once-a-week/20-merges cadence (see above) is the same shape —
  `project-manager` only ever *recommends* it when you're already talking to it; nothing runs it on
  a timer.
- **Concurrency.** Several issues can be in flight at once, each isolated in its own worktree.
  `/spec-flow:board` reports across them.
- **Test tiering.** The local gate is the fast **unit** tier plus the branch's
  `.spec-flow/flagged-tests` — never the full suite; the full/integration suite is CI's gate.
  `/spec-flow:implement` states plainly in its report and the PR that the unit tier ran locally and
  the full suite runs in CI. See **Test tiering (unit / integration)** above. Test resources that
  could collide between concurrent runs should carry a per-process-unique seed so two runs never
  name the same resource.
- **Owner rules, structurally enforced.** OpenSpec before implementation for anything with a design
  decision to record (a content-only `type:docs` issue has none — see **Docs fast path** — and
  implements straight from its scope + acceptance criteria; a `type:tech-debt` issue has none
  either — see **Tech-debt fast path** — and implements straight from its confirmed Direction,
  behavior-preservation checked in place of spec conformance); TDD; significant design
  decisions are the owner's (an advisor agent only advises); the feature lands on `main` via PR,
  merged by the owner by default. An `issue-pm` merges it itself only when the `merge-on-green`
  label is set or explicitly instructed to for that run (see **Overriding either seam's default**,
  above), never on its own initiative, and only after required CI checks are green. Separately,
  the OpenSpec archive is never code and never touched by any single issue's `finalize` — it's
  `project-manager`'s bulk job, batched and confirmed with the owner (see **Bulk spec archiving**).

## Conventions

- **Issue/PR numbers always carry a `(description)`.** Every issue or PR number rendered in a
  board, status update, PR body, or prose is paired with a brief parenthetical description —
  `#85 (field identity)`, `PR #97 (test-rigor agent)` — never a bare number. A number alone is
  meaningless to the reader.

## Bootstrap

**`/spec-flow:setup`** walks through the full Prerequisites checklist interactively (see the
README) and is the recommended way to bring a repo onto this plugin. The label vocabulary alone —
one piece of that checklist — is created idempotently, safe to re-run on its own too:

```bash
bash bin/bootstrap-labels.sh   # from the plugin dir, with the cwd inside the target repo
```
