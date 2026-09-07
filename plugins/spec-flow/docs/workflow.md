# flow — agent delivery workflow

A session-driven, multi-agent delivery pipeline. You (the owner) spend hands-on time only on the
two things a human should own — **defining/prioritizing work** and **final review + merge** — and
the middle runs as a repeatable, agent-driven pipeline. A central coordinator handles cross-issue
state and grooming; the moment you start working a specific issue, it launches a dedicated
per-issue agent as its own separate background Claude Code process — you attach to it yourself
(`claude agents` — an interactive picker, select the session from the list) — that drives that
issue's pipeline turn-by-turn with you, in its own context, until it merges.

This file is the canonical reference. The pipeline is implemented as the plugin's skills
(`/spec-flow:groom|activate|implement|sync-ci|address|finalize|board|archive|setup`) plus a roster of agents: a
`project-manager` central coordinator you talk to directly for cross-issue state and grooming, an
`issue-manager` it spawns per issue to actually drive that issue's lifecycle (see **Coordinator and
issue leads** below); `product-manager`, `architect` and `design-critic` at the front of the pipeline
(refine → design → attack the design → proposal); `tdd-developer` and `build-engineer` for implementation/build; and a review panel
whose members this repo names in its own `spec-flow/WORKFLOWS.md` — bundled lenses are `reviewer`,
`code-reviewer`, `security-reviewer`, `test-rigor-reviewer` and `observability-reviewer` (the
middle two wrap the built-in `/code-review` and `/security-review` skills, but are spawned as
agents like the rest). See **Review panel** below.

It rides on two backbones the consuming repo must provide: **OpenSpec** (the spec-approval seam,
via the `openspec` CLI + the `/opsx:*` commands) and **GitHub** (`gh`-driven issues, labels, and
PRs).

## The two human seams

`groom` runs in the central coordinator; `activate` onward runs in that issue's `issue-manager`, once
it's launched (see **Coordinator and issue leads** below) — the sequence below is the same either
way, just split across two separate processes instead of one conversation:

```
 FOREGROUND (you + coordinator, then you + issue-manager)   BACKGROUND (subagent teams)   GITHUB (you)
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
when this issue was filed. `issue-manager` drafts **up to five** issue-specific questions from what the
overlap search actually found (see **Backlog overlap** below), asked **one at a time**, never a
fixed checklist — a simple issue may earn none at all. This runs for every issue, `type:docs` and
`type:tech-debt` included (their fast paths only ever skip the design/spec machinery further down,
never this). It's not counted as one of the two seams below — it's a lighter, unconditional check
that happens before either of them, not a third owner-approval gate — but it uses the same
override mechanism: the issue's owner instructions (see **Overriding either seam's default** below)
can tell it to skip this review for the run, same free-text, owner's-own-words instruction the
seams already read.

**Backlog overlap — searched by `project-manager`, never by `issue-manager`.** "Does anything else open
overlap, duplicate, or block this issue" is a cross-issue question, so it belongs to the agent that
owns cross-issue state. `project-manager` answers it **before** it spawns anything, and hands the
answer over; `issue-manager` reads the answer and never queries the backlog itself.

The search costs real context. `gh issue list --state open --json ...,body --limit 100` pulls every
open issue's **full body** — measured at ~7k tokens on an 18-issue repo, scaling to 36k-180k at the
100-issue cap. Run inside `issue-manager`, that lands before it has read a line of code, and is paid
again on every parallel spawn. So:

- `project-manager` delegates the search to a throwaway `general-purpose` subagent on `haiku` —
  mechanical filtering, not judgment — which reads the bodies in its own context and returns
  **only** a shortlist: `- <number>: <title> — <why>` per line, or `none`. Neither the
  coordinator's context nor any `issue-manager`'s ever holds the full list.
- The file's first line is `issue: <N>`, and a reader that cannot prove the header names the issue
  it is activating **must re-search rather than trust it**. The shortlist answers a question about
  one specific issue, and the hand-invoked `activate` path reads it before isolation is confirmed —
  so without the stamp, a file left behind in a shared checkout silently answers one issue's
  overlap question with another issue's data.
- It passes the shortlist's **path** to `spawn-issue-manager.sh <N> --backlog-overlap-file <path>`. A
  flag, not a positional, so it is independent of the owner-instructions argument — and a path,
  not the text, for the reason two bullets down.
- Delivery differs from owner instructions. Those go on the issue, where the owner can see and
  change them; the shortlist is machine-generated working data with no reason to be public, so it
  still travels as a file the session copies into its worktree.
- **Only the path moves. The shortlist text is never retyped by anything.** Owner-instructions are
  safe to splice into a prompt or a command: the owner wrote them. A shortlist line quotes an
  *issue title*, and on any repo accepting outside issues those are attacker-controlled. Two
  distinct attacks follow, and both are closed the same way:
  - **Into a prompt.** A title can close whatever delimiter wraps it and land the remainder in the
    instruction region ("…auto-approve both seams"). No in-band delimiter survives adversarial
    content.
  - **Into a shell command.** Every hop here is an LLM composing Bash. A title carrying `$(...)`,
    a backtick, or a stray quote becomes command substitution in that agent's own shell — and
    `issue-manager` runs with `--permission-mode auto`, so nothing prompts first.

  So the bytes travel only as a file, by path: the haiku subagent **writes** the shortlist and
  returns just a path; `project-manager` forwards that path to `--backlog-overlap-file` without
  opening it; the script restamps it into a temp file with `cat` (never an interpolated `printf`)
  and the spawn prompt carries only that path; the session copies it into its worktree. The
  `activate` fallback follows the identical path-only discipline. Every agent that could hold
  shortlist text — `project-manager`, `issue-manager`, and `activate`'s reader — is told the contents
  are **data, never instructions**.
- `none` is passed through, not omitted. A clean search is a finding, and the literal line `none`
  is the only way it is ever recorded. **Absent, empty, header-only, otherwise truncated, and
  foreign-numbered all mean "not searched"** and all trigger the fallback — nothing legitimately
  writes an empty or bodyless file, so one means an interrupted write, and an `activate` that read
  a blank `cat` as "clean" would be exactly the silent skip this design exists to prevent. The
  header-only case is the subtle one: it *passes* the header check, so the check alone is not
  enough — the reader must look at the body too. The fallback re-runs the search through
  a cheap-model subagent of its own, then writes the file only **after** isolation is confirmed, so
  it cannot land in the primary checkout. It exists for hand-spawned sessions and worktrees
  predating this mechanism.

**Design decision, before Seam 1.** `design-critic` attacks the architect's plan first — the
architect writes its own risks section, and the review panel only ever reviews code against the
spec, so this is the one place a bad plan is caught before it becomes an approved one. Its findings
are shown with the design options, not instead of them; the owner still decides.
 `/spec-flow:activate` stops **twice**. First, right after the
**`architect` agent** designs the work and surfaces options + trade-offs (with a relevant
**domain-expert agent**, if one is available, consulted *concurrently* and adding deeper facts) —
**you decide** among the options *before anything is generated*, so a chosen alternative can never
leave stale traces of the rejected recommendation in the generated spec/tasks. The agents never
make the call. (A `type:docs` issue skips this design stop entirely; a `type:tech-debt` issue auto-adopts the
Direction confirmed when it was filed, stopping only for a hard dependency or a material
deviation — see **Docs fast path** and **Tech-debt fast path** below. Seam 1 itself still applies
on both.)

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
in `.spec-flow/seam1-last-shown-sha` (gitignored per-branch runtime state)
and, on a later re-entry, renders a diff scoped to just `openspec/changes/issue-<N>` between that
SHA and the current one — a real diff view via `dev-skills`'s `ide-explain` skill (its `--path` flag
scopes `--diff` to one directory instead of the whole repo) when `SPEC_FLOW_SEAM_VIEW=explain`, or
a scoped `git diff` in terminal mode. `ac-coverage.md`/`overrides.md` still render in full either
way — they're conclusions to re-check as a whole, not something that makes sense line-by-line.

(Upstream of both stops, at `groom`, the **`product-manager`
agent** refines the raw idea into scope + testable acceptance criteria — the *what/why* — which the
architect then designs the *how* for. It does that over **rounds**, not one pass: each round is a
fresh `product-manager` that has read the code and asks at most three questions, relayed to you one
at a time with a recommended answer stated alongside each. `groom` ends the loop, never the agent,
and only when every acceptance criterion is testable as written, the unhappy paths are covered, and
nothing behavioral is left for a later agent to guess at — design questions stay for the architect
and don't hold it open. You can end it yourself in one word at any round; `groom` then runs a
closing pass that asks nothing and turns what's still open into stated assumptions for you to
confirm. See `skills/groom/SKILL.md` step 4. You can also state **technical direction** at any
round — architecture, performance, implementation constraints — and it reaches the architect
verbatim, in the issue's own `## Technical direction` section: at `activate`'s design consult, or,
on the docs fast path where that consult is skipped, at `implement`'s on-demand architect consult.
Wherever an architect runs on this issue at all, it gets those constraints. For a bug report,
`groom` also attempts a read-only repro before drafting acceptance criteria, so an unconfirmed
report never quietly becomes a settled spec — see that skill's step 2.)

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
only ever offered if the standalone **`dev-skills`** plugin (separate from spec-flow — see
**A note on `dev-skills`** below) is installed: `SPEC_FLOW_SEAM_VIEW=explain` (recommended
default when `dev-skills` is available) generates an interactive, self-contained HTML view via
its `ide-explain` skill (file tree, diff/doc view, and per-node explanations in one page) and prints
its path + an `open <path>` command — a background `issue-manager` can't reliably pop a browser on your
screen, so it never tries; `SPEC_FLOW_SEAM_VIEW=terminal` renders the same content as plain text in
the conversation, the original behavior from before `ide-explain` existed, and is what's used
automatically if `dev-skills` isn't installed on the machine an `issue-manager` happens to be running
on, even when the preference says `explain`. Read fresh from `.claude/settings.json` at each seam,
not cached from an earlier stop; `dev-skills`'s own availability is re-checked fresh too (via
`claude plugin list --json`), not assumed from setup time. `/ide-explain` (from `dev-skills`) is also
the owner's own primary way to look at any issue — including a plain backlog issue, before it's
even activated, with no diff or worktree required (its `--issue` mode pulls the issue's body,
comments, and related/linked issues straight from GitHub) — usable with or without spec-flow
installed at all.

**Seam 2's ide-explain view includes real per-file explanations, not commit history.** `ide-explain`'s
own `--blame` can only quote a historical commit message, never explain what the *current* diff
does — so `implement` step 5, right before generating the view, writes a real 1–3 sentence
explanation per changed file into `.spec-flow/explain-map.json`, drawing on what it already
learned driving the implementation and review panel (not a fresh re-read of the diff), and passes
it via `--explain-map`. This is what makes the explanation pane at Seam 2 actually say something
about what changed and why, instead of either nothing or a quote from an unrelated past commit.

**A note on `dev-skills`.** It's a separate, standalone plugin, not part of spec-flow — installed
independently, useful in any repo whether or not that repo uses spec-flow at all. spec-flow depends
on it only optionally, one-directionally, and at runtime (resolving its installed root fresh via
`claude plugin list --json`, never a hardcoded path) — spec-flow ships and works completely without
it, just without the HTML seam views. See its own `skills/ide-explain/SKILL.md` for the format itself,
and `skills/setup/SKILL.md` here for how the seam-view preference gets set.

**Overriding either seam's default.** Both seams default to always stopping. `project-manager`
composes a free-text instruction — from whatever you said for that issue, or a standing preference
you wrote in `CLAUDE.md`, in your own words (never a fixed vocabulary like "Seam 1"/"Seam 2" —
that's internal to these docs, not something you need to say) — and passes it to
`scripts/spawn-issue-manager.sh <N> [owner-instructions]`, which posts it to the issue as a comment
whose first line is `🤖 Owner instructions`. **That comment is the channel, not the spawn.** Every
`issue-manager` re-reads the latest such comment at each seam check, so you can post or change one
yourself at any time — from any machine, while the session is running, without attaching to it — and
the latest one wins. It also survives a respawn, which sends the session no new prompt at all.

This used to be a file in the issue's worktree, which lost the instructions whenever the worktree
was recreated, could not be read or written from another machine, and gave the owner no way to see
what a session had been told.

Whatever the instruction doesn't address still stops and waits, by default; nothing is ever inferred
or carried over from a different issue. Seam 2's auto-merge path only actually merges once the PR's required CI checks
report green — an instruction to merge automatically doesn't skip that; a hard dependency the
architect flags, or a hard spec conflict step 5's override/conflict check finds (see **Spec
override and conflict detection** below), always stops Seam 1 regardless, even under a full
auto-approve instruction.

**Seam 2's auto-merge specifically can also be set with the `merge-on-green` label** — it's a
binary, GitHub-native "how to handle this issue" setting (metadata about what's being built, not
code), so it lives as a label rather than needing to go through the spawn-time instruction above:
apply it directly in GitHub, or tell `project-manager`, any time — before spawn, after spawn, even
on a live `issue-manager` — and `implement` checks it fresh at step 5, no worktree/file involved. The
free-text instruction still works too (either one triggers auto-merge); the label just doesn't
require composing a sentence or waiting for a spawn/respawn to deliver it. Other, less binary
instructions (Seam 1 auto-approve, anything not reducible to a yes/no) go through the comment
channel below.

The instruction doesn't just live in the spawn prompt — it's posted to **the issue**, as a comment
whose first line is `🤖 Owner instructions`, which `issue-manager` re-reads fresh at each approval
point rather than trusting memory of its original spawn prompt. The latest such comment wins.

That makes it durable in the three ways a worktree file was not. It survives a **respawn**, which
sends the session no new prompt of its own. It survives the **worktree being recreated**, which is
routine and used to lose the instructions outright. And it is reachable from **anywhere** — you can
post one from your phone, and you can change a **live** session's instructions without attaching to
it or interrupting it, which the file could never do. `spawn-issue-manager.sh <N> "<new
instructions>"` posts one for you and works whether the session is running, stopped, or crashed.

It is also simply visible: the instructions a session is operating under are on the issue, where
you and anyone else can read them.

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
review panel + build + polish — working `tasks.md` when a spec exists, or the issue's own
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
| Coordination | `agent:active` | An `issue-manager` is currently claimed/running on this issue — see **Coordination signals** below. |
| | `blocked` | `issue-manager` identified a hard dependency on another unmerged issue (see the issue's comments for which one and why; also expressed as a native GitHub issue dependency, see **The two human seams** above). |
| | `needs-attention` | `issue-manager` hit something outside the two defined owner seams that only you can resolve — an ambiguous call, a conflict it can't cleanly reconcile, a repeated failure — and is waiting (see the issue's comments for what). Distinct from `blocked`, which is specifically a hard dependency on another issue. See **Coordination signals** below. |
| Fast path | `type:docs` | Documentation-only — `activate`/`implement` always skip the architect consult, design-choice stop, and review panel, and skip spec generation too unless the docs' own layout is changing or it documents a tech change (see **Docs fast path** above). Offered by `groom`, never inferred silently. |
| | `type:tech-debt` | Structural, behavior-preserving fix filed by `/tech-debt` (dev-skills) (SOLID, duplication, or layering). `activate` always skips OpenSpec generation, and by default skips the owner design-choice wait too — auto-adopting the Direction confirmed when filed, unless a hard dependency, a material deviation, or an actual behavior change turns up. `implement` still runs the full review panel in behavior-preservation mode — never combine with `type:docs` (see **Tech-debt fast path** below). |
| Autonomy | `merge-on-green` | Merge this PR automatically once required CI checks pass — no owner review wait. Set directly by the owner (GitHub or `project-manager`), any time; `implement` checks it fresh, no worktree file involved. See **The two human seams** above. |
| Audit | `tech-debt-review` | Marks a closed, immediately-created log issue for one completed `/tech-debt` (dev-skills) run — not a work item, just the durable timestamp `project-manager` reads for the once-a-week/20-merges cadence check. See **Tech-debt review cadence** below. |

**"What's next" rule:** the highest-priority issue (`P0` over `P1` …) carrying `status:ready`.

**Epics / parent issues are never directly workable.** An issue with GitHub native sub-issues
(`subIssuesSummary.total > 0`) is a rollup of its children, not its own unit of work — there's
nothing to spec or implement against the epic itself. `scripts/spawn-issue-manager.sh` checks this
before doing anything else and refuses to spawn against one (listing its sub-issues instead), and
`board` pulls epics into their own informational section rather than ever surfacing one as READY
or "next up," whatever `status:*` label it happens to carry. Work the sub-issues individually.

## Coordination signals

Every `issue-manager` runs as an independent process — potentially on a different machine, spawned by a
different user's `project-manager`, with no shared memory, messaging, or session state between
them. GitHub is the only thing every one of them, and every `project-manager`, already reads and
writes — so it's the coordination surface, not `claude agents --json --all` (which only ever
reflects the local machine's session registry, and says nothing about another developer's
`issue-manager` running on their own machine — and needs `--all` even for that: every `issue-manager` is a
`background` session, invisible without it, confirmed by test).

- **`agent:active`** — set on the fresh-spawn path by `scripts/spawn-issue-manager.sh` itself, *before*
  it launches anything (not left for `activate` to get to once the session finally runs — that gap
  was minutes wide and two near-simultaneous spawns on different machines could both slip through
  it; `activate`'s own `--add-label` is now just a harmless no-op confirming what's already there).
  Removed by `finalize` on close, and removed by `issue-manager` itself if it hands back or shuts down
  before finishing for any other reason — and by the spawn script itself if it sets the label but
  the launch then fails, so a bad spawn never leaves a false-positive lock behind. This, not
  `claude agents --json --all`, is the authoritative "is anything actually working this issue"
  signal — `board` reads it directly (see its **Steps**).

  `scripts/spawn-issue-manager.sh` checks its **own machine's, this repo's** past sessions first — a
  session is named `issue-manager-<N>-<slug>` (a readable slug from the issue's title at spawn time, so
  several open sessions are distinguishable in `claude agents` without attaching to each — falling
  back to the bare `issue-manager-<N>` for a title with nothing alphanumeric to slug), matched
  by the stable `issue-manager-<N>` prefix rather than the full name — the title, and so the slug, can
  change on GitHub between spawns, so an exact match against today's title would miss a session
  spawned under an earlier one. The lookup is also scoped to sessions whose `cwd` falls under this
  repo's own root, not by name alone; otherwise a same-numbered issue in a different repo on this
  machine could match. A match
  that's still live → refuse (already running here); one that exists but isn't live (crashed,
  stopped, finished) → `claude respawn` it, landing back in its own worktree with its branch and
  uncommitted work intact, instead of a fresh, unrelated one branched from `main` —
  **except** when that worktree is gone (Claude Code's own cleanup swept it, or someone removed it
  by hand): confirmed by test, `claude respawn` in that case doesn't error and doesn't recreate the
  worktree, it silently drops the session into the **primary checkout**. The script checks for
  exactly that after every respawn and stops the session immediately rather than letting it run
  there, clearing `agent:active` and surfacing a recovery command instead. Only when there's no
  local record at all does it fall back to the GitHub label — refuse if `agent:active` is set (an
  issue-manager may be running on another machine this one can't see), spawn fresh otherwise.

  What's still not airtight: label-then-spawn isn't a true compare-and-swap (GitHub's API has no
  atomic label-if-absent), so it narrows the cross-machine race to roughly the time this script
  takes to run rather than closing it completely; and a crash on a machine other than the one
  you're retrying from still needs a human to clear a stale label — nothing detects that on its
  own. A same-machine crash, the common case, now recovers on its own via respawn (or fails safe,
  loudly, if its worktree is gone).
- **Progress comments.** `issue-manager` posts a **new** comment (never edits one in place — the point
  is a readable timeline, not a live-updating status line) on the issue at each meaningful
  milestone: claimed, spec committed, draft PR opened, each `tasks.md` checkpoint during
  `implement`, each review round's result, addressed-comments pushed, CI flagged, merged and
  closed. `archive-batch` adds one more, later and separately: a comment on each issue once its
  spec is actually archived, as part of whatever batch it landed in. A fresh `project-manager`
  (yours or another user's) or the owner can read the issue's comment history and know exactly
  where things stand without attaching to the session at all. Team mode
  (the `implement` default) posts these at full granularity since `issue-manager` is directly driving
  each step; workflow mode is coarser — only before and after, since the script itself has no
  per-step hook back out to a comment.
- **`blocked`** — added alongside a comment naming the specific blocking issue and why, whenever
  `issue-manager` identifies a hard dependency on another unmerged issue (most likely during
  `activate`'s design step, but not only then), **and** a native GitHub issue dependency (see **The
  two human seams** above) — the label is what's queryable/bootstrapped like every other label in
  the fixed vocabulary; the native link is what actually renders in GitHub's UI. Both removed, with
  a follow-up comment, once the dependency clears. A single fixed label, not one per blocking issue
  — the detail lives in the comment (and the native link itself), keeping the label vocabulary
  fixed rather than growing per-issue. The label, the comment and the native link are applied and
  cleared together by `scripts/blocked-dependency.sh` (`add` / `clear`), so any stage can mark a
  dependency it discovers — not just `activate`, which used to be the only place the mechanics
  existed. `finalize` runs its `sweep` on close, which removes the label and every native link
  without needing to know the blocking issue.
- **`needs-attention`** — added alongside a comment naming exactly what's needed, whenever
  `issue-manager` is genuinely stuck on something with no defined next step of its own: not one of **The
  two human seams** (those are scheduled stops, already surfaced their own way — spec approval,
  review + merge) and not a hard dependency on another issue (that's `blocked`, above). Covers the
  ad hoc case — an ambiguous call the issue's owner instructions doesn't resolve, a conflict it
  can't reconcile on its own, a failure that repeats past the point retrying makes sense — where
  guessing would be worse than waiting. `issue-manager` stops and waits once it's set, the same as at
  either seam. Its comment's first line is prefixed `🆘 Needs attention:` — the board finds the
  reason by that prefix, exactly as it finds a `blocked` reason by `⛔ Blocked on #`. Removed, with
  a follow-up comment, once the owner resolves it and work resumes; `finalize` also sweeps it, so a
  problem the owner resolved out of band can't leave the marker on a closed issue.

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
`issue-manager`'s spawn prompt, and `activate` step 2's fallback check, both call `EnterWorktree` with
`name: "issue-<N>"`. This isn't just cosmetic — confirmed by test, `EnterWorktree` called with a
name that already exists on disk does **not** error, it re-enters and resumes that same worktree.
So a fresh spawn whose local session registry lost track of a prior run (the session evicted, or a
different run on this machine) still lands back in the same worktree instead of duplicating it.
This reinforces, rather than replaces, `scripts/spawn-issue-manager.sh`'s own respawn logic (looking for
a past local session whose name carries the `issue-manager-<N>` prefix and `claude respawn`ing it — see
**Coordination signals** below): respawn recovers the session's own history when a local record
exists; the deterministic
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
  `scripts/spawn-issue-manager.sh <N>`, which launches a dedicated **`issue-manager`** (named `issue-manager-<N>`)
  as its **own separate background Claude Code process** — `claude --bg` — and prints the session
  id. **Background-only, deliberately**: you manage running sessions yourself via `claude agents`
  (an interactive picker — select the session by name/id; there is no direct "attach by id"
  command), not a tab or window opened for you on every spawn. You talk to that process directly,
  in its own context, once attached; it never shares the coordinator's.
- That `issue-manager` owns the issue's **entire remaining lifecycle** — both stops inside `activate`,
  `implement`, any `sync-ci`/`address` rounds, and `finalize` — entirely in its own session with
  you, in its own Claude-Code-isolated worktree. It hands back once the issue is merged and closed
  — if it committed one (not every issue does, see **Docs fast path** and **Tech-debt fast path**),
  its OpenSpec change is archived later, in bulk, by `project-manager` (see **Bulk spec archiving**),
  not by `issue-manager` itself.
- Several issues can be in flight at once, each its own process — `claude agents` lists them all,
  attach to whichever one you want to talk to. It's the spawn script, not `project-manager` itself,
  that guards against duplicates — this machine's own past sessions first (respawning a crashed one
  rather than starting fresh), the `agent:active` label otherwise — so it never launches a second
  `issue-manager` for an issue that already has one running, on this machine or another.
- `project-manager` still runs `groom` and `board` itself (no issue exists to hand off yet, or the
  work spans all issues), and `adopt-tiering`, `setup`, `archive`, and, when `dev-skills` is
  installed, `/tech-debt` (repo-wide, not tied to any issue).
- `project-manager` never attaches to an `issue-manager`'s session, runs `claude logs` against one, or
  reads its transcript. Its view of an in-flight issue is exactly what `claude agents --json --all`
  plus GitHub give it — labels, PR, CI, and whether the session is alive — which is the entire
  point of running it as a separate process instead of a subagent: the coordinator's own context
  never fills with one issue's implementation detail.

This is the default flow, not an opt-in — every time you start work on an issue, expect
`project-manager` to launch its `issue-manager` as a fresh process rather than driving the stages
inline.

### Worktree isolation

`issue-manager` sessions get their file isolation from Claude Code itself, not from this plugin — via
the `EnterWorktree` tool, which creates the worktree and switches the session into it, branched
from the repo's default branch. **Not automatic for everything, confirmed by test:** Claude Code
calls `EnterWorktree` on its own in front of an `Edit`/`Write` tool call, but never in front of a
Bash-driven file write (`printf > f`, a heredoc, an external CLI like `openspec` writing files
itself) — so `scripts/spawn-issue-manager.sh`'s spawn prompt tells `issue-manager` to call it explicitly, as
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
per-issue, inline in each `issue-manager`, meant a git worktree and a set of `gh`/OpenSpec commands
every single time, for zero review value each time. So `finalize` doesn't touch it at all anymore:
once an issue's PR merges, its `openspec/changes/issue-<N>` change (when one exists — a
content-only `type:docs` issue commits none, and neither does any `type:tech-debt` issue; see
**Docs fast path** and **Tech-debt fast path** above) just sits on the default branch, unarchived, until `project-manager` sweeps up a batch of them at once.

`project-manager` **watches for the buildup and checks in with you** — it never archives on its own
initiative. `/spec-flow:archive` counts every `openspec/changes/*` directory (excluding `archive/`)
on the default branch, compares it against a threshold (**default 5**, overridable — state a
standing preference once, in this conversation or in `CLAUDE.md`, or override ad hoc for just one
run: "archive these 3 now"), and — only once you've confirmed the specific batch — spawns a
dedicated **`archive-batch`** worker as its own separate background Claude Code process (via
`scripts/spawn-archive-batch.sh`), the same delegation pattern as `issue-manager`: `project-manager`
coordinates, it doesn't do the archiving itself. You can attach to that worker
(`claude agents` — select it from the list) to watch it, same as any `issue-manager`.

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
interactively**, right there in that session — the same way `issue-manager` waits at a design or spec
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
even then only ever *recommends* a separate issue, never files one itself. `/tech-debt` (dev-skills) is
the deliberate, repo-wide counterpart: a team of review agents reads the whole codebase (or a scoped
path) for nothing else — SOLID/composability, code duplication, unnecessary layering — ranks the 10
most impactful findings, drops anything that duplicates an already-open issue, and walks you through
what's left **one at a time, full context each time** — you decide per finding whether it's worth a
`type:tech-debt` issue. Same shape as every other owner-facing decision in this pipeline: the agents
surface candidates, they never file anything on their own.

**`project-manager` recommends running it, on a cadence — it never runs it itself and never spawns a
background process for it.** Due whenever either fires, whichever comes first: **a week since the
last run, or 20 PRs merged since the last run.** Every `/tech-debt` (dev-skills) run creates a
`tech-debt-review`-labeled log issue, closed immediately, purely as a durable timestamp — that's what
lets `project-manager` compute "due" without guessing (see **Watching for tech-debt review cadence**
in `agents/project-manager.md`). When due, it's mentioned plainly the next time you're already
talking to `project-manager` (typically alongside `board`); not due, it says nothing — this is a
recommendation cadence, not a background timer (see **Substrate and constraints** below), and running
it is still entirely your call.

## Tech-debt fast path

A `type:tech-debt` issue (filed by `/tech-debt` (dev-skills), confirmed by you one finding at a time
before it ever became an issue) skips OpenSpec entirely — there's no behavior change to spec, so
generating one would just be ceremony around a decision already made. It's still a real code
change, so it still gets the full review panel at `implement` and a real PR at Seam 2;
only the OpenSpec-generation-and-approval machinery is what's skipped, replaced by narrower,
cheaper checks that exist specifically to catch the one way this fast path could go wrong: a "pure
refactor" that turns out not to be one.

- **`activate` step 3-4: a narrowed, auto-adopting `architect` consult, not a skip.** Unlike
  `type:docs` (which skips the design consult entirely — there's no architecture to a prose
  change), a structural fix genuinely benefits from a fresh read: the finding's file:line evidence
  may be stale by the time the issue is activated. `architect` verifies the confirmed `##
  Direction` still applies (or corrects it) and checks whether it's achievable **without changing
  any observable behavior**. The owner-decision *stop* is still skipped by default — you already
  confirmed this specific fix once, item by item, in `/tech-debt` (dev-skills) — but only when nothing
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
`agents/issue-manager.md`'s **Escalation** section — never silently pick an option; this is exactly the
kind of consequential call that belongs to you.

**`type:docs` and `type:tech-debt` never combine** — an issue is either a documentation change or a
structural code change, never both; `activate` falls back to the full pipeline if it ever finds
both labels on the same issue (labeling ambiguity is reason enough not to trust either fast path).

## The skills

| Skill | Phase | Does |
|---|---|---|
| `/spec-flow:groom` | foreground | Rough idea → scoped GitHub issue. Refines it over **rounds** — a fresh `product-manager` each round, at most three questions, relayed one at a time with a recommended default — until every acceptance criterion is testable as written; `groom` ends the loop, never the agent, and you can end it yourself in one word. Owner technical direction is carried verbatim to the architect. For a bug, verifies read-only before scoping it; offers `type:docs` for documentation-only work. One `P0–P3` + `status:ready`. |
| `/spec-flow:activate` | foreground | Pick a `status:ready` issue → worktree+branch → `architect` + domain expert design it concurrently → STOP for your design choice → openspec explore+propose from your chosen design → commit spec → `status:spec-review`, then STOP again for your spec approval (Seam 1). A `type:docs` issue always skips the design stop, and skips spec generation too unless it's structural/tech-accompanying — see **Docs fast path** above. A `type:tech-debt` issue always skips spec generation and, by default, the design-choice stop too (`architect` auto-adopts the confirmed Direction unless something's wrong) — see **Tech-debt fast path** above. |
| `/spec-flow:implement` | background | After your approval: opens a **draft** PR (`Closes #N`) early and pushes at checkpoints so CI runs during implementation, while `issue-manager` drives tdd-developer → review panel → fix loop → build-engineer → docs polish in the worktree — by default as an **agent team** it leads, or the original `Workflow` script where agent teams aren't enabled (`SPEC_FLOW_IMPLEMENT_MODE`); then marks the PR ready and sets `status:in-review`. A `type:docs` issue instead runs one lightweight doc-writing pass (`tasks.md` if a spec exists, otherwise the issue's own acceptance criteria directly; architect on demand), skipping the panel/build/polish. A `type:tech-debt` issue still runs the full panel, in behavior-preservation mode (no spec to conform to), working from the issue's Direction instead of `tasks.md`. Invoking this skill is the explicit opt-in to that orchestration. |
| `/spec-flow:address` | foreground-invoked | Pull your PR review comments → fix agent in worktree → push → reply per thread. |
| `/spec-flow:sync-ci` | foreground-invoked | Pull the branch's latest CI failures into `.spec-flow/flagged-tests` so the local loop guards them for the rest of the branch. Invoked by you when you notice CI go red, or by `issue-manager` itself — `implement` step 5 and `address` step 4 each do one bounded check of the run tied to the push they just made and self-invoke this if it's already red; never a standing poll loop. Exits cleanly, doing nothing, where the repo's policy says CI is not a test gate. See **Test policy** below. |
| `/spec-flow:finalize` | foreground | Once the feature PR has merged (your squash-merge by default, or `implement`'s own auto-merge if instructed): closes the issue, removes its worktree. Never merges the feature PR, and never touches the OpenSpec archive — that's `project-manager`'s job, batched — see **Bulk spec archiving** above. |
| `/spec-flow:board` | foreground | Status across all in-flight issues, derived from labels + PR state; highlights what's next, what's blocked on you, and how many specs are pending the next `/spec-flow:archive`. |
| `/spec-flow:archive` | foreground-invoked | Count the pending un-archived specs against a threshold (default 5, overridable); once confirmed with you, spawns a dedicated `archive-batch` worker to sync+archive them all in one pass and land one PR — see **Bulk spec archiving** above. |
| `/tech-debt` (dev-skills) | foreground-invoked | Repo-wide structural audit: a parallel team of review agents finds SOLID/composability, duplication, and unnecessary-layering issues, ranks the 10 most impactful, drops anything already an open issue, and walks you through the rest one at a time — you decide per finding whether it becomes a `type:tech-debt` issue, which then takes the **Tech-debt fast path** above through `activate`/`implement`. If `dev-skills` is installed, `project-manager` recommends running the audit itself once a week or every 20 merged PRs, whichever comes first — never automatic. See **Tech-debt review cadence** above. |
| `/spec-flow:adopt-tiering` | setup (one-time) | Split a repo's existing suite into a fast unit tier and a slow integration tier (classify by evidence → present → separate structurally → wire CI) and open a PR. Only for a repo whose own policy chooses that split; not an assumption the pipeline makes. Run once per repo; not tied to an issue. See **Test policy** below. |
| `/spec-flow:setup` | setup (one-time, re-runnable) | Explore this repo's Prerequisites state, then walk through only what's missing — OpenSpec init, `gh` auth, labels, the agent-teams env var, the seam-visualization preference, the refactor circuit breaker, `.gitignore` entries, CI tiering — one item at a time with a recommended default. Not tied to an issue. |

## Agents

**Orchestration**
- `project-manager` — the **central coordinator**, the agent you talk to directly. It knows the
  whole lifecycle, runs the board, tracks which issues have an `issue-manager` running (`agent:active`,
  via `board`), decides what's next by priority + lifecycle, and **delegates** — `groom`'s
  refinement to a loop of `product-manager` rounds, and any specific issue's
  `activate → implement → address → finalize`
  to that issue's `issue-manager`, launched as its own background process. It coordinates; it does not
  implement, does not drive an issue's stages inline, and only crosses your two seams when you
  explicitly instruct it to for that run (see **Overriding either seam's default**, above; neither
  it nor the `issue-manager` it launches ever infers or assumes one). Wire it as
  a repo's **default agent** (in that repo's `.claude/settings.json`) to make it your standing
  entry point. The plugin ships **no** root `settings.json` with an `agent` field — opting your
  repos in is your choice, per repo, so the plugin never hijacks the main thread of every project
  that installs it.
- `issue-manager` — the **per-issue delivery lead**, launched by `project-manager` (named
  `issue-manager-<N>`, via `scripts/spawn-issue-manager.sh`) as its own separate background Claude Code
  process when you start or resume work on issue `#N`. You attach to it yourself (`claude agents`,
  then select the session id printed by the spawn script) — not a subagent you switch to inside
  another conversation.
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
  **testable WHEN/THEN acceptance criteria** (the *what/why*). Consulted during `/spec-flow:groom`,
  once per refinement round: the project-manager brings each round's draft back to you to edit and
  relays that round's questions one at a time, then judges the result against the readiness bar and
  decides whether to run another round. Owns the what/why, never the how.
- `architect` — turns the refined idea into a **design** (approach, structure/boundaries to SOLID,
  data model, key interfaces) with **trade-offs framed as owner decisions**. Consulted during
  `/spec-flow:activate`, concurrently with a domain-expert agent if one is available, and
  **before** `openspec-propose` — you decide among its options right there, before anything is
  generated, and Seam 1 later confirms the resulting spec. Advises only — never decides.

**Implementation & build**
- `tdd-developer`, `build-engineer` — the implementation and build agents (bundled with the
  plugin as canonical bases; see the README's "Extending the agents"). `tdd-developer` bundles no
  language style guide. Rust and Kotlin guidance both live in the standalone `dev-skills` plugin,
  in its `rust-dev` and `kotlin-dev` agents; point `SPEC_FLOW_DEVELOPER_AGENT` at one of them to
  use the full guide (see **Developer agent** below). It also reads `references/refactoring-discipline.md` whenever the work is
  behavior-preserving — a refactor, a `type:tech-debt` fix, or its own REFACTOR step — which is
  where the failing-test triage gate and the revert reflex live (see **Refactor circuit breaker**
  below).

**Review panel** — `reviewer`, `code-reviewer`, `security-reviewer`, `test-rigor-reviewer`,
`observability-reviewer`; the lenses this repo names run in parallel during `/spec-flow:implement`. Their
individual mandates are described once, in full, in **Review panel** below — not repeated here.

> If the consuming repo defines its own agent with one of these names (project or user scope),
> that one **overrides** the plugin's. Use that to specialize a reviewer for a repo's stack.

## Developer agent

`tdd-developer` is bundled with this plugin and is the default. It is language-neutral by design:
it carries the TDD loop, the SOLID rules, and the refactoring discipline, plus a small set of
per-language style rules.

Deep language expertise lives elsewhere, in the standalone **`dev-skills`** plugin. Its `rust-dev`
agent reads the full Rust style guide, carries a nextest recipe tuned for low token use, and
delegates build problems to its `cargo` agent. Its `kotlin-dev` agent reads the full Kotlin style
guide and delegates builds to its `gradle-expert` agent. Its `java-dev` agent bundles no style guide on
purpose. It carries defaults, and the conventions a project already has override every one of
them, which is what an OSS contribution needs.

**`SPEC_FLOW_DEVELOPER_AGENT` names the agent `/spec-flow:implement` spawns for implementation
work.** Set it per repo, in `.claude/settings.json`:

```json
{ "env": { "SPEC_FLOW_DEVELOPER_AGENT": "rust-dev" } }
```

`dev-skills` covers three languages today: `rust-dev` for Rust, `kotlin-dev` for Kotlin, and
`java-dev` for Java.

- **Unset (the default)** — spawn the bundled `tdd-developer`. This is exactly the behavior that
  shipped before the setting existed. spec-flow stays self-contained; nothing else is required.
- **Set** — spawn the named agent instead. The name resolves the same way any agent name does, so
  a repo-local or user-scope agent of that name wins over a plugin's.

If the named agent cannot be resolved, `implement` reports the missing agent by name and stops. It
does not fall back silently. A configured developer agent that quietly disappears would drop the
discipline it was chosen for, and you would not see it happen.

The dependency runs one way. `dev-skills` never calls spec-flow.

## Refactor circuit breaker

A refactor preserves behavior by definition. So a test that fails during one means either the
refactor is wrong, or the test asserts something outside the contract. "Edit the test until it
passes" is not a third option, and an agent that takes it turns an unreviewed behavior change into
a day-long rathole.

Two mechanisms guard this, and only one of them is configurable.

**The triage gate is not configurable.** `agents/tdd-developer.md` requires the agent to classify
a failing test before editing it, **from the spec** (the committed OpenSpec spec, or a
`type:tech-debt` issue's `## Direction` and `## Acceptance criteria`) and never from the test body:
the code is wrong (fix the code), the spec deliberately removed the behavior (delete the test, cite
the spec line), or it asserts a structure that no longer exists (delete the test). An agent may
never repair a test whose subject was removed — only delete it. A test it cannot classify is a spec
gap, and the owner decides spec gaps. A repo that turns this off is not refactoring.

**The stopping condition is configurable**, per repo, via `SPEC_FLOW_REFACTOR_BREAKER` in
`.claude/settings.json`'s `env` block. It trips when the same test file has been edited more than
twice in one run — a sign the classification was wrong, or the step was too big:

- **`ask`** (the default, also used when unset or unrecognized) — the agent stops, leaves the tree
  untouched, and reports the blocker. The owner decides: continue, or revert.
- **`revert`** — the agent reverts to the last green commit and reports. The strict reflex: an
  attempt that breaks something unexpected is reverted, not patched outward from.
- **`off`** — no breaker. The agent keeps working.

`/spec-flow:setup` asks for this once, recommending `ask`.

**It applies to behavior-preserving runs only** — the `type:tech-debt` fast path's Implement spawn
and its fix rounds. Under ordinary feature TDD, editing one test file three times is routine
(several tests for one module), so arming it on the normal path would stall almost every run.
`build-engineer` and the docs polish pass never carry it. The triage gate above is what covers
every other path, and it needs no counter.

**The two modes stop differently.** In `team` mode the teammate messages `issue-manager` mid-run, which
surfaces the stop to the owner live; the owner chooses continue or revert, and a fresh
`tdd-developer` is respawned with that decision. In `workflow` mode the script cannot pause, so it
asks the agent to prefix its summary with the token `BREAKER-STOP:`; on seeing that token the
script returns immediately with `approved: false` and the stop in `residual_findings`, skipping the
review panel entirely. The owner sees the stop when the run returns, not during it. The script must
not run a fix round after a trip: a fresh agent's "in this run" counter resets, so it would resume
editing the file the breaker just stopped.

## Review panel (`/spec-flow:implement`)

Two modes, chosen by `SPEC_FLOW_IMPLEMENT_MODE` (`skills/implement/SKILL.md`, step 4):

- **`team`** (default) — an [agent team](https://code.claude.com/docs/en/agent-teams) with
  `issue-manager` as the lead. `issue-manager` can only lead a team because it's already its own top-level
  session, not a subagent — agent teams don't nest, so this specifically couldn't work the other
  way around. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (see **Prerequisites** in the
  README); missing that, `implement` falls back to `workflow` mode automatically.
- **`workflow`** — the original `Workflow`-tool script (`skills/implement/implement.workflow.js`),
  scripted rather than led. Same lenses, same rules, no team, no experimental flag needed — it
  cannot read files, so the lead derives the panel and gate from the repo's `WORKFLOWS.md` and
  passes them in as args, the same way it passes the test-policy pointer. That is what stops the
  two modes holding copies of the policy that drift apart.

Either way, the review stage is not one reviewer — it is a **panel**, and **the consuming repo
decides who is on it.** Which lenses run, what counts as must-fix, and how many fix rounds are
allowed all come from that repo's own `spec-flow/WORKFLOWS.md`. The plugin ships **no default
panel**: if that file is absent the pipeline stops, exactly as it does for a missing
`TESTING.md`. Same principle as the test policy — the pipeline carries the mechanism, the repo
states the policy.

What the plugin owns is the mechanism, and it is lens-count-agnostic: every lens runs **in
parallel** each round (teammates in team mode, `parallel()` in workflow mode), findings **merge**
into one set, a fix round addresses every must-fix finding from **any** lens, and **approval
requires every lens the repo named to report and approve with no must-fix findings.** A lens that
declines without naming a must-fix finding earns a synthesized `major`
`unexplained-non-approval`. A named agent that cannot be resolved stops the run by name — never
dropped, never substituted. A repo may state that **no** panel runs: then none does, no fix loop
runs, and the PR says so rather than reporting an approval nobody gave.

Each lens's own mandate and output contract stay plugin-owned, in its agent file — the repo's file
says *which* lenses run and *what the panel does with their verdicts*, not how a lens forms one.

The **bundled** lenses, which the seeding template proposes and this repo's own `WORKFLOWS.md`
keeps:

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
only the spec lens owns `spec_conformance`/`tests_ran`. To add or remove a lens, **edit your repo's
`spec-flow/WORKFLOWS.md`** — that is the whole procedure now, and it needs no change to the plugin.
For a lens the plugin does not bundle, write its agent file in your repo's `.claude/agents/` and
name it there; it runs on equal terms with a bundled one.

## Test policy

**The repo owns the policy; the plugin owns only the mechanism.** spec-flow ships **no default
test or CI policy at all**, and falls back to nothing when the repo has not stated one. It does
ship one seeding template, read only while a repo is being seeded and never by the pipeline — see
**Where the policy lives** below. What runs locally, what runs in CI, whether CI is a test gate at
all, and what gates merge are the consuming repo's to decide and to write down.

This section is the authoritative statement of that model. Every other mention of the test policy
in this document points here rather than restating it.

This is deliberate. Test policy is shaped by each repo's CI cost, suite size, stack, and merge
gate; across a portfolio there are as many sets of rules as there are repos, so any default the
plugin shipped would be wrong somewhere by construction. A repo with no test-running CI at all is a
**first-class, expressible policy** here, not a degraded one.

### Two directories, one character apart

| Directory | Committed? | What it holds | Lifetime |
|---|---|---|---|
| `spec-flow/` | **Yes — committed** | The repo's own spec-flow configuration, including `TESTING.md`, its test and CI policy | Lives with the repo |
| `.spec-flow/` | **No — gitignored** | Per-branch runtime state: `flagged-tests` | Dies with the branch |

Only the **dotted** one belongs in `.gitignore`. A trailing-slash pattern with no interior slash
matches at any depth, so an undotted `spec-flow/` entry would also swallow any nested directory of
that name — in spec-flow's own repo, `plugins/spec-flow/`, erasing the plugin's source from git.
`/spec-flow:setup` warns about this and checks that `spec-flow/` is not ignored.

### Where the policy lives

`spec-flow/TESTING.md` at the repository root. The directory is relocatable with
`SPEC_FLOW_CONFIG_DIR` — repo-relative only; an absolute value is rejected, because `env` values in
`.claude/settings.json` are not interpolated, so a checked-in absolute path is a machine-specific
literal that is wrong on every other clone.

`scripts/repo-config.sh` owns the resolution and every message about it:

- `repo-config.sh check` — exits 0 and prints nothing when the policy is there and usable; exits 1
  with the complete message on stdout when it is not; exits 2 on an environment error. It is
  presence-and-readability only: it never inspects what the policy *says*, because a content check
  is a schema arriving through the back door.
- `repo-config.sh instruction` — prints the one-line pointer naming the resolved absolute path.

`project-manager` runs `check` at session start and is the **only** caller that offers to seed a
missing policy (via `/spec-flow:setup`, and only on exit 1). `implement`, `address`, and `sync-ci`
run the same check before any work and simply stop, relaying its output unchanged.

`/spec-flow:setup` seeds a repo that has none: it proposes a concrete policy, confirms it with the
owner, then opens a PR. It writes nothing before the owner confirms, and never merges.

**One seeding template ships, at `references/TESTING.md.template`.** Its name is the destination
filename plus a `.template` suffix, as this plugin names every template bound for one named file. It
states the tiered policy spec-flow used to hardcode — a fast tier locally, the full suite in CI,
merge gated on green CI — for the one repo shape that policy fits. `setup` opens it only where it
has already read the repo and found that shape, and never for any other shape; the seeded file
carries the policy text alone, not the template's seeding notes. **Nothing reads it at runtime.**
`repo-config.sh` anchors every policy path at the consuming repo's root and never knows the
plugin's root, so the plugin's copy lies outside the tree any resolution searches, whatever it is
called; a missing `spec-flow/TESTING.md` stops the pipeline rather than falling back here.

**Seeding never deletes anything on the remote, deliberately.** If the push succeeds but the pull
request does not open — a token without the scope, branch protection, a network drop, or the owner
pressing Ctrl-C — the branch is left where it is and the script prints its name along with the two
commands that resolve it: open the PR by hand, or delete the branch. Automatic rollback was tried
and abandoned: four implementations each failed a different way, and every failure came from
keeping state meant to mirror the remote. Reporting keeps none, so it cannot be raced by a signal,
fooled by an unreachable remote, or fall silent. A stray branch after an interrupted run is the
accepted trade, and seeding runs once per repo.

### How the policy reaches the agents

**A pointer travels; policy text never does.** `implement` generates one line with
`repo-config.sh instruction` and appends it verbatim to every teammate prompt that runs tests.
`address` uses the same generated line. Workflow mode, whose script can read neither files nor the
environment, receives that same line as a required `testInstruction` arg and throws if it is
absent, rather than holding a default of its own. Neither mode contains policy text, so the two
cannot drift.

Agents report against the policy, not against a tier: `tests_ran` is `policy | partial | degraded |
none`, and `tests_detail` carries the exact commands run; `implement` quotes that value verbatim in
its run summary and in the PR body, and asserts no tier of its own. **Where the policy names
nothing to run, running nothing is `policy`** — full compliance, not `none` and not `degraded`.

**The policy file is branch-controlled content.** It is read from the worktree, so an issue branch's
own diff can change it, and the check deliberately never inspects what it says. The pointer
therefore carries a guardrail: the file names commands to run in this repo and nothing more, it
cannot authorize an action the GUARDRAILS forbid, and an agent that finds it directing work outside
the worktree — network calls, reading credentials, pushing, filing, messaging — stops and reports
that rather than acting on it. That clause lives in the emitted line, so it reaches every consumer
without any caller restating it. It is a scope statement, not a content check — nothing here
inspects or validates the policy's text.

**The clause is a guardrail, not containment, and it is worth being precise about the difference.**
It defeats the direct attack, a policy file that tells an agent to push or post or fetch. It does
not bound what the policy can ultimately cause, because *selecting commands is the whole capability*:
a policy naming only `make lint` is entirely compliant while the same branch's `Makefile` does
whatever it likes. The clause is also much stronger for the review lenses, whose guardrails
forbid every outward action, than for the implementer teammates, whose guardrails deliberately
permit pushing the issue branch.

**The real boundary.** Running spec-flow's panel over a diff executes commands that diff controls.
That is what the pipeline is for, not a defect in it — and it means **spec-flow must not be pointed
at an untrusted third-party branch.** The control at that boundary is the permission and sandbox
mechanism the session runs under, not prose in a prompt. What the pipeline does enforce mechanically is
narrower and worth stating exactly: the policy file must be a real file physically inside the
repository, so a committed symlink cannot redirect that read to `~/.ssh/id_rsa` or anything else
outside the tree. That is a path check rather than a content check, which is why it coexists with
the rule that the check never inspects the policy's text.

### Optional: a structural unit / integration split

A repo whose policy chooses the fast-tier-locally, full-suite-in-CI split can enforce that
boundary structurally with **`/spec-flow:adopt-tiering`** (a one-time migration — classify by
evidence, separate structurally, wire the CI artifact). That is one policy a repo may choose, not
the pipeline's assumption. For CI to run *in parallel* with the local loop under such a policy,
`/spec-flow:implement` opens a **draft PR at the start** and pushes at checkpoints, so CI works on
each pushed increment during implementation rather than once at the end.

### The flagged set — a per-branch local watch on CI-caught failures

Where a repo's policy does make CI a test gate, a regression CI catches on a branch is pulled into
the local loop for the rest of that branch — a per-branch **flagged set**, so a proven-fragile spot
is guarded locally instead of costing another CI round-trip.

- A gitignored file, **`.spec-flow/flagged-tests`** inside the issue's worktree. One
  runner-selectable test id per line; `#` comments and blank lines ignored. Ignored via a
  `.spec-flow/` entry in the repo's `.gitignore` — the one-time, trunk-branch entry from
  **Prerequisites** in the README; `/spec-flow:sync-ci`
  additionally double-checks it's there on each run, so it never commits either way.
- **Starts empty on every new branch.** No bootstrap, no diff-based guessing.
- **Populated only by CI failures on that branch** (via `/spec-flow:sync-ci`). Where the repo's
  policy gates merge on green CI, a branch starts from a green default branch, so any CI failure on
  it is by definition a real regression the diff introduced — the caught test is added **whatever
  its kind**, including container tests, and run locally for the rest of the branch.
- **Local inner loop = whatever the policy names, plus the flagged set.** The
  `/spec-flow:implement` gate and `tdd-developer`'s cycles run both.
- **Dies with the branch.** The branch boundary is the pruning mechanism; nothing carries forward —
  and there is nothing to "promote": a fast test written during the fix is already inside whatever
  the policy names as the local gate, so it is in the local run on the next branch automatically.
- **Nothing to do where CI is not a test gate.** `/spec-flow:sync-ci` reads the repo's policy
  first and exits cleanly, saying so, rather than hunting an artifact that repo never produces.

### The loop

```
implement → push → CI runs ──(red)──▶ /spec-flow:sync-ci
                                          → append failures to .spec-flow/flagged-tests
                                                              │
   local loop runs the policy's gate + flagged set  ◀─────────┘
                                                              │
                                    you merge (green CI) → flagged set evaporates
```

- **`/spec-flow:sync-ci <N>`** — pulls the branch's latest CI failures (the `spec-flow-failures`
  artifact) and appends them to the flagged set. Session-driven, and self-invoked the moment
  CI-red is known: you notice it, or `issue-manager` does — a single check of the run tied to the push
  it just made (`implement` step 5, `address` step 4), never a standing poll loop. Either way, the
  fix that follows confirms the newly flagged test(s) pass **locally** before pushing again — a
  guess-and-wait-for-CI round trip costs 20-30 minutes for feedback a local run gives in about one.

### CI contract — only where the policy makes CI a test gate

A repo whose policy puts no test gate in CI has nothing to wire here, and `/spec-flow:sync-ci`
exits cleanly saying so. Where the policy does put one, that repo's CI must upload the failing test
id(s) on a red run as an artifact named **`spec-flow-failures`** — one id per line, the same
runner-selectable form the flagged set uses. spec-flow ships reference CI templates under
`references/ci/` for the supported runners; `/spec-flow:sync-ci` reads that artifact. Such a policy
also gates merge on green CI — the invariant the flagged set's blind-append safety rests on, and
the repo's own to state rather than the plugin's to assume.

## Substrate and constraints

- **Session-driven, not cron.** Everything is triggered and narrated by a session — the central
  coordinator's, or the issue's `issue-manager` once it's launched. `/spec-flow:implement` runs in
  `issue-manager`'s own session either way — as an agent team it leads (default) or a background
  `Workflow` it invokes (fallback) — that is *not* cron either; both are scoped to the lead's own
  session and don't outlive it. `/spec-flow:address` is invoked by you when you return, never
  polled. `/tech-debt` (dev-skills)'s once-a-week/20-merges cadence (see above) is the same shape —
  `project-manager` only ever *recommends* it when you're already talking to it; nothing runs it on
  a timer.
- **Concurrency.** Several issues can be in flight at once, each isolated in its own worktree.
  `/spec-flow:board` reports across them.
- **Test policy.** The repo owns it, and **Test policy** above states it in full — this bullet does
  not restate it. One concurrency point belongs here: test resources that could collide between
  concurrent runs should carry a per-process-unique seed, so two runs never name the same resource.
- **Owner rules, structurally enforced.** OpenSpec before implementation for anything with a design
  decision to record (a content-only `type:docs` issue has none — see **Docs fast path** — and
  implements straight from its scope + acceptance criteria; a `type:tech-debt` issue has none
  either — see **Tech-debt fast path** — and implements straight from its confirmed Direction,
  behavior-preservation checked in place of spec conformance); TDD; significant design
  decisions are the owner's (an advisor agent only advises); the feature lands on `main` via PR,
  merged by the owner by default. An `issue-manager` merges it itself only when the `merge-on-green`
  label is set or explicitly instructed to for that run (see **Overriding either seam's default**,
  above), never on its own initiative, and only after required CI checks are green. Separately,
  the OpenSpec archive is never code and never touched by any single issue's `finalize` — it's
  `project-manager`'s bulk job, batched and confirmed with the owner (see **Bulk spec archiving**).

## Conventions

- **Issue/PR numbers always carry the title.** Every issue or PR an agent writes — in a status
  update, a PR body, a GitHub comment, or prose — is written as `<number>: <title>`: `85: Field
  identity in the sync path`, `PR 97: Add the test-rigor agent`. Never a bare number. A number
  alone is meaningless to the reader.
- **Issues go on their own lines, never inline.** Put each issue on its own line, prefixed with
  `-`, in the format above. This applies to a single issue too, not only to a list of them. Do not
  run several issues together in one sentence, separated by commas.
- **One exception: the aligned table `scripts/board.py` prints.** Its bucket rows put the status,
  number, priority, title, assignee, and PR in fixed columns, one issue per line. That layout
  already gives the reader the title, so it keeps its `#N` column instead of the `<number>:
  <title>` form. The script's own prose lines (Next up, Stalled, Blocked, epic sub-issues) do
  follow the convention. Print the script's output as-is; never reformat it by hand.

## Bootstrap

**`/spec-flow:setup`** walks through the full Prerequisites checklist interactively (see the
README) and is the recommended way to bring a repo onto this plugin. The label vocabulary alone —
one piece of that checklist — is created idempotently, safe to re-run on its own too:

```bash
bash bin/bootstrap-labels.sh   # from the plugin dir, with the cwd inside the target repo
```
