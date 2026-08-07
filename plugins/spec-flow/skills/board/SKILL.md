---
name: board
description: Report status across all in-flight delivery pipelines — every issue by lifecycle label with its priority, stage, live issue-pm session, and PR state — and highlight what's next, what's blocked on the owner, and what's stalled. Use when the owner asks 'where do things stand' or 'what should I work on'. Part of the flow delivery workflow (see docs/workflow.md).
---

# board — status across all in-flight pipelines

You are the central `project-manager`. Give the owner one view of the whole pipeline, derived from
GitHub labels (including liveness and blocking, not just lifecycle) + PR state, cross-checked
against this machine's local sessions where they happen to match. Read-only; you don't change
anything.

## Steps

Steps 1-4 are independent reads — issue them together (parallel tool calls) rather than one at a
time.

1. **Gather issues by lifecycle.** This one call is also where liveness and blocking come from —
   `agent:active` and `blocked` are ordinary labels, already in this response, no separate call.
   `subIssuesSummary` is what tells an epic (a parent issue rolled up from GitHub native
   sub-issues) apart from a directly-workable issue — see the epics note below:
   ```bash
   gh issue list --state open --json number,title,labels,url,assignees,subIssuesSummary --limit 100
   ```
   Bucket by the `status:*` label; read the `P?` label as priority. Issues carrying **no
   `status:*` label** are the raw backlog — not yet groomed, so no `P?` either. Keep them
   separate; they're the fallback when nothing labeled is actionable. Also fetch the current user
   (`gh api user --jq .login`) once, to tell "assigned to you" apart from "claimed by someone
   else" — this repo may have multiple users.

   **Epics are never directly workable — pull them out of every actionable bucket.** Any issue
   with `subIssuesSummary.total > 0` is a parent/epic: its own scope is just a rollup of its
   children, so it has nothing to spec or implement on its own —
   `scripts/spawn-issue-pm.sh` refuses to spawn against one (confirmed by real use, 2026-08-06:
   without this, a broad parent issue got claimed and spawned into its own worktree with nothing
   coherent to build). Set them aside into their own section (below) regardless of what
   `status:*` label they happen to carry, and never let one win "next up" or show as an
   activatable `status:ready` item — point at its sub-issues (`gh issue view <N> --json
   subIssues --jq '.subIssues.nodes[] | "#\(.number) \(.title)"'`) instead.

2. **Gather PR state AND CI state in one call.** `statusCheckRollup` carries every check for
   every open PR, so there's no need to loop `gh pr checks` per PR:
   ```bash
   gh pr list --state open --json number,headRefName,title,reviewDecision,url,statusCheckRollup --limit 100
   ```
   Roll each PR's `statusCheckRollup` array into one CI status — an `in-review` PR is only
   actionable by the owner once CI is green; while CI runs there is nothing for them to do:
   **green** if every entry is complete and successful (`conclusion` ∈ SUCCESS/NEUTRAL/SKIPPED,
   or the legacy commit-status `state` = SUCCESS), **running** if any entry is still in progress
   (`status` ∈ QUEUED/IN_PROGRESS, or legacy `state` = PENDING), otherwise **failing**. An empty
   `statusCheckRollup` (no CI configured on the repo) counts as green — nothing to wait on.

3. **Cross-check local sessions (secondary — enriches rows, isn't the liveness signal):**
   ```bash
   claude agents --json --all
   ```
   **`--all` is required, not optional** — confirmed by test: every `issue-pm` is a `background`
   session, and `claude agents --json` without `--all` excludes background sessions entirely
   (0 results, regardless of state), only ever returning `interactive` ones. Omitting `--all` here
   doesn't narrow the list to live sessions, it silently empties it, and this whole cross-check
   step would never find a match. The `agent:active` label from step 1 is the liveness signal —
   durable, visible to every user's `project-manager` regardless of machine (see **Coordination
   signals** in `docs/workflow.md`). `claude agents --json --all` only ever reflects *this*
   machine's local session registry, so use it only to enrich a row when its `name`
   (`issue-pm-<N>`) happens to match one already labeled `agent:active` **and** its `state` is
   `working` or `blocked`, matching `spawn-issue-pm.sh`'s own definition of live — `--all` also
   pulls in `done`/`failed` sessions, and offering `claude attach` on one of those would be
   misleading, not a live jump-in. That's when you can offer
   `claude attach <id>` (`.id` from this JSON) as a direct jump-in. No match (or a match that's
   `done`/`failed`) is unremarkable (someone else's machine, or yours from earlier today with the
   session evicted or finished) — it does **not** mean stalled; only a **missing `agent:active`
   label** means that. An issue past `status:ready` without the label is **stalled**: nothing is
   driving it forward even though its status label says it should be — surface that, it doesn't
   happen automatically anywhere else.

4. **Check the OpenSpec archive buildup (cheap, independent — issue it alongside steps 1-3).**
   `finalize` closes an issue but never archives its OpenSpec change — that's `project-manager`'s
   job, batched, once enough have piled up on the default branch (`/spec-flow:archive`):
   ```bash
   DEFAULT_BR=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   git ls-tree --name-only "origin/$DEFAULT_BR:openspec/changes" 2>/dev/null | grep -v '^archive$'
   ```
   Empty output → nothing pending, omit it from the render entirely. Non-empty → count the lines;
   this is purely informational here (`/spec-flow:archive` does its own threshold check against
   this same count when actually asked to run) — just surface the number, don't decide whether
   it's "enough" yourself.

5. **Render a board** grouped by stage, priority-sorted within each group. An `in-review` PR
   goes under **BLOCKED ON YOU only when its CI is green**; while CI is running it goes under
   **IN FLIGHT** with its CI state, because the owner has nothing to act on yet:

   ```
   ## Delivery board

   ⛳ BLOCKED ON YOU
     spec-review   #N P1  <title>  @you  🟢 active (attach: claude attach a1b2c3)  → ready to approve (spec, or for a content-only docs issue, its plan)
     in-review     #M P0  <title>  @you  PR #P  ✅ CI  🟢 active → review in GitHub: <url>

   🔧 IN FLIGHT (agents / CI)
     in-review     #M P1  <title>  @you  PR #P  ⏳ CI  🟢 active (awaiting CI — not on you yet)
     in-review     #M P1  <title>  @you  PR #P  ❌ CI  🟢 active (CI failing — /spec-flow:sync-ci)
     in-progress   #K P2  <title>  @alice        🟢 active (no local session — probably @alice's machine)
     addressing    #J P1  <title>  @you  PR #Q   🔴 STALLED — no agent:active label
     in-progress   #F P2  <title>  @you           🔒 BLOCKED on #41 (see issue comments) · 🟢 active

   📋 READY
     ready         #L P0  <title>  (unclaimed)      → spawn: ${CLAUDE_PLUGIN_ROOT}/scripts/spawn-issue-pm.sh L   ← next up
     ready         #Q P1  <title>  @alice            (claimed by @alice)

   📥 BACKLOG (ungroomed)
     (no labels)   #H     <title>                  → /spec-flow:groom <H>

   📦 EPICS (not directly workable — see sub-issues)
     status:ready  #E P1  <title>  (unclaimed)  3 sub-issues (1 done)  → #E1 (login retry), #E2 (token refresh), #E3 (session cleanup)

   (agent:active: 4 · blocked: 1 · local sessions matched: 2 · open PRs: 2 · specs pending archive: 3 → /spec-flow:archive)
   ```
   Drop the `specs pending archive` clause from that summary line entirely when step 4 found
   nothing pending — don't render "specs pending archive: 0," just omit it. Drop the **EPICS**
   section entirely when step 1 found none. An epic keeps whatever `status:*` label it happens to
   carry (shown as-is, informational only) but is never counted toward READY, BLOCKED ON YOU, IN
   FLIGHT, or **Next up** below — list its sub-issue numbers so the owner can pick one directly
   instead of spawning against the epic itself.
   Show the assignee on every row (`@you`, `@<other-user>`, or `(unclaimed)` for `status:ready`
   issues with no assignee — everything before `status:ready` is unclaimed by design, since
   `/spec-flow:activate` is what claims it). Show the liveness marker (🟢 `agent:active` / 🔴
   stalled) on every row past `status:ready`, an attach command only when step 3 found a local
   match, and 🔒 on anything carrying `blocked` — that's the whole point of steps 1 and 3.

6. **Call out the two things that matter most — scoped to the current user, not the whole team.**
   With multiple users on this repo, an item assigned to someone else is never "blocked on you" or
   "next up" for you, even though it's still worth showing in the board for visibility:
   - **Next up** — ranked by **distance to landed**, not just priority label, walking this ladder
     until something applies, considering only items assigned to **you** (or unclaimed, for
     `status:ready`) **and never an epic** (step 1's `subIssuesSummary` check — an epic can't be
     "next up," only its sub-issues can): (1) a `status:in-review` PR **whose CI is green** and
     assigned to you — one merge away from shipping, and `/spec-flow:finalize` can't run until it
     merges; (2) the highest-priority `status:ready` issue that's **unclaimed** to activate — never
     one already assigned to someone else, and never an epic (offer its highest-priority unclaimed
     sub-issue instead); (3) if nothing is `status:ready` either, the highest-value
     **BACKLOG** issue to groom — and if it looks too large to spec and land as one unit, say so
     and suggest splitting it into smaller issues instead. **Keep the train moving** — landing
     what's already close beats starting something new, and starting something small beats
     reporting a stall.
   - **Blocked on you** — your seams, and only items **assigned to you**: anything in
     `status:spec-review` (approve the spec, or for a content-only `type:docs`/`type:tech-debt`
     issue, its plan) and any `status:in-review` PR **whose CI is green**
     (review/merge in GitHub). An `in-review` PR with CI still **running** is NOT blocked on you —
     surface it under IN FLIGHT as awaiting CI, and a PR with **failing** CI as needing
     `/spec-flow:sync-ci` (pull the failures into the branch's flagged set, then re-run the fix
     loop) — surface it under IN FLIGHT too, since it isn't gating anything else, but `sync-ci` is
     owner-invoked and never polls, so you're still the one who has to run it once you notice it
     here. An item in the same states but assigned to someone else is neither
     — it's their seam, not yours; still show it (in IN FLIGHT or its own section) so the team has
     visibility, just don't claim it's actionable by you.
   - **Stalled** — any issue assigned to you past `status:ready` with no `agent:active` label
     (step 3). Call these out explicitly and offer the fix: `${CLAUDE_PLUGIN_ROOT}/scripts/spawn-issue-pm.sh <N>` to
     resume it.
   - **Blocked** — any issue carrying the `blocked` label, regardless of assignee (visibility
     matters here even more than usual — someone should know a dependency exists). Name the
     blocking issue from its most recent `⛔ Blocked on #M` comment; don't just say "blocked."

## Rules

- Read-only. Never change labels, push, or merge from this skill.
- **Always pair a number with a description.** Every issue/PR number you render carries a brief
  `(description)` — `#85 (field identity)`, `PR #97 (test-rigor agent)` — never a bare `#85`. The
  owner does not track raw numbers. (Workflow convention; see docs/workflow.md.)
- Sort within each group by priority (`P0` first).
- If a `status:*` label and the PR state disagree (e.g. labeled in-review but PR merged),
  flag the drift so the owner can run `/spec-flow:finalize`.
