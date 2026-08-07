---
name: tech-debt
description: Audit the codebase for structural improvement opportunities — SOLID/composability, code duplication, and unnecessary layering — using a parallel team of review agents. Ranks the 10 most impactful findings, excludes anything already in the open backlog, and walks the owner through them one at a time with full context; the owner decides per item whether to file it as a GitHub issue. Not tied to any issue. project-manager recommends running this once a week or every 20 merged PRs, whichever comes first — never automatic. See docs/workflow.md.
argument-hint: [optional: scope to a path/module — default is the whole repo]
---

# tech-debt — structural audit → ranked findings → owner files what's worth it

You are the central `project-manager` (like `groom`/`board`/`archive` — not tied to any issue, no
worktree, no code changes). Everywhere else in this pipeline, structural debt only ever surfaces as
a side effect of touching nearby code (`architect`'s "Nearby structural debt" step during
`activate`). This skill is the deliberate, repo-wide sweep: a team of review agents reads the whole
codebase looking for nothing else, ranks what it finds, and the owner decides — one finding at a
time — what's worth turning into real backlog work.

## Steps

1. **Establish scope.** Default is the whole repo. If the owner (or `argument-hint`) named a
   path/module, scope the review to it and say so up front.

2. **Snapshot the existing backlog, once, before spawning anything.** The whole point is to never
   re-surface what's already known:
   ```bash
   gh issue list --state open --json number,title,url --limit 200
   ```
   Keep this list in context — you'll hand it to every lens agent below so they self-filter, and
   you'll do a final cross-check yourself before presenting anything to the owner.

3. **Spawn three lens agents in parallel** (one Agent tool call each, sent together — not
   sequential), each `subagent_type: general-purpose`, `model: opus` (the strongest available tier —
   this is a deep, whole-codebase read, not a quick lookup). Give every lens the scope from step 1
   and the open-issue list from step 2 verbatim, with the instruction to silently drop any candidate
   that duplicates an existing open issue's title/body rather than flagging it. Each lens returns
   its own ranked candidate list — file:line evidence, the concrete problem, and a concrete direction
   to fix it, never a vague "consider refactoring X":

   - **SOLID / composability** — "Is the codebase built from small, composable components, or from
     large ones doing several unrelated jobs? Find the worst violations: single-responsibility
     breaks (a class/module/function doing 2+ unrelated things), dependencies on concretions where
     an abstraction would decouple two things that shouldn't know about each other, and interfaces
     wide enough that most callers only use a slice of them. For each, name the smaller pieces it
     should split into."
   - **Code duplication** — "Find logic duplicated across files/modules that belongs in one shared
     place — not textually identical-only, but the same *behavior* re-implemented with minor
     variations (a strong signal the abstraction was never extracted, or drifted after copy-paste).
     For each, name where the shared module/function should live and what call sites would move to
     it."
   - **Structure / layering** — "Find unnecessary indirection: layers that just forward calls to the
     next layer with no logic of their own, wrapper types/interfaces with exactly one
     implementation and no test-seam justification, or a module boundary that's crossed so often in
     both directions it isn't really a boundary. For each, name what should collapse or merge."

   Each lens caps itself at its own strongest ~5-8 candidates rather than padding to hit a number —
   a lens with fewer genuine findings should return fewer.

4. **Merge, dedupe, and rank globally.** Collect all three lenses' candidates. Two different lenses
   sometimes point at the same underlying spot (a god-class is both a SOLID violation and the reason
   its duplicated logic never got extracted) — merge those into one finding citing both angles
   rather than presenting it twice. Do your own pass against the step-2 backlog list too (lens-level
   self-filtering can miss a near-match) — drop anything that's substantially already an open issue.
   Rank what's left by **impact**: how much it currently costs (bug surface, onboarding friction,
   how often it's touched) weighed against how contained the fix is. Keep the **top 10** — fewer if
   fewer genuinely impactful findings survive; never pad the list to reach 10.

5. **Present findings one at a time — full context, owner decides each one before you show the
   next.** Don't dump the ranked list upfront. For each:
   ```
   [3 of 10] <one-line title>
   Lens: <SOLID | duplication | structure>
   Where: <file:line, file:line, ...>
   Problem: <what's actually wrong, concretely>
   Direction: <the shape of the fix — not a full design, just where it points>
   Impact: <why this one ranked where it did>
   ```
   Ask: file as a GitHub issue, skip, or adjust (owner can narrow/reshape it before it's filed).
   **Never file anything without that per-item confirmation** — this mirrors the owner's seams
   everywhere else in this pipeline: the owner decides what enters the backlog, this skill only
   surfaces candidates.

6. **File exactly what the owner accepted**, drafted with a distinct `## Direction` section (not
   folded into Notes) — `activate`'s tech-debt fast path (see **Tech-debt fast path** in
   `docs/workflow.md`) gates on that section actually being present, since it's what lets `activate`
   auto-adopt the fix's shape instead of re-running a full design-choice stop:
   ```bash
   gh issue create --title "<concise title>" --label "<P0|P1|P2|P3>" --label "status:ready" --label "type:tech-debt" \
     --body "## Scope
   <what this touches, in/out>

   ## Acceptance criteria
   - [ ] <behavior is unchanged — existing tests still pass unmodified, no public signature/error-contract/CLI/config/serialized-output change>
   - [ ] <the structural outcome itself — e.g. 'X and Y are split into single-responsibility units'>

   ## Direction
   <the finding's Direction field, verbatim — the shape of the fix, where it points>

   ## Notes / context
   Lens: <SOLID | duplication | structure>. Where: <file:line, file:line, ...>. Problem: <what's wrong>."
   ```
   The first acceptance criterion is always the behavior-preservation one, worded plainly — this is
   the contract the whole fast path rests on, not optional boilerplate. Propose a priority (default
   **P2** — real but not urgent, unless the finding's impact argues otherwise) and confirm before
   creating, same as `groom` step 6. Filed issues enter `/spec-flow:activate` like any other
   `status:ready` issue, but take the **tech-debt fast path** there (no OpenSpec spec, a narrowed
   architect brief instead of a full design-choice stop) — see `docs/workflow.md`.

7. **Log the run, even if nothing got filed.** This is what lets `project-manager` compute the
   once-a-week / every-20-merges cadence later without guessing — see **Tech-debt review cadence**
   in `docs/workflow.md`:
   ```bash
   LOG_URL=$(gh issue create --title "Tech debt review — $(date +%Y-%m-%d)" \
     --body "Scope: <repo or path>. Candidates found: <N>. Filed: <issue numbers>. Skipped: <count>." \
     --label "tech-debt-review")
   gh issue close "$LOG_URL"
   ```
   `gh issue create` prints the new issue's URL; `gh issue close` accepts a URL directly, so no
   number-parsing needed.
   Immediately closed — it's an audit-trail marker, not a work item.

8. **Report.** List what got filed (numbers + brief descriptions, pipeline-standard), what got
   skipped, and confirm the run is logged for cadence tracking.

## Rules

- **Foreground, read-only except for the `gh issue create` calls in steps 6-7.** No worktree, no
  code edits — this skill finds and files, it never fixes anything itself. A finding worth fixing
  becomes a normal issue that goes through `/spec-flow:activate` → `/spec-flow:implement` like any
  other.
- **Never file anything the owner hasn't individually confirmed.** Presenting the full top-10 list
  and asking for a blanket "file all of these" defeats the point — one at a time, each with room to
  actually be read before the next one shows up.
- **Never re-surface an existing open issue.** Step 2's snapshot exists specifically so lens agents
  and your own final pass can filter against it — a finding that's already backlog isn't a finding.
- **Never invent an automatic schedule for this skill itself.** It's owner-invoked, or recommended
  by `project-manager` when the cadence check in `docs/workflow.md` says it's due — recommended,
  never auto-run; same rule `archive` follows for its own threshold.
- **Never file an issue that also carries (or should carry) `type:docs`.** The two fast paths are
  mutually exclusive — a finding is either a structural code change or a documentation change, never
  both from this skill. Filed issues get `type:tech-debt` and nothing else in that label kind.
- Always pair an issue number with a brief `(description)` — the owner does not track raw numbers.
- If the lens agents come back nearly empty (a genuinely clean codebase, or too small a scope), say
  so plainly rather than manufacturing findings to fill the list — still log the run (step 7) either
  way.
