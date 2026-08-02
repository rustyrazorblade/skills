---
name: implement
description: Implement an approved issue — run the background subagent team (tdd-developer → 5-lens review panel → fix loop → build-engineer → docs polish) via a Workflow script in the issue's worktree, then push the branch and open a PR. Third stage of the flow delivery workflow (see docs/workflow.md). Requires the owner to have approved the committed spec first. Invoking this skill is the explicit opt-in to multi-agent Workflow orchestration.
argument-hint: [issue number, with its spec already approved]
---

# implement — build the approved spec, open a PR

You are this issue's `issue-pm`, running as your own dedicated background session. The owner has
**approved the committed spec** for issue `#N`. Drive the implementation team to completion and
open a review-ready PR. The team runs as a background `Workflow` — **invoking this skill is the
owner's explicit opt-in to that orchestration** (it may spawn several subagents).

Input: an issue number `#N`, OpenSpec change `issue-<N>` — deterministic, from `activate`. You're
already running inside this issue's worktree — Claude Code's own background-session isolation put
you there, on whatever branch it assigned; resolve it with `git rev-parse --abbrev-ref HEAD`
rather than assuming a name. If `openspec/changes/issue-<N>` isn't there, list `openspec/changes/`
(excluding `archive/`) and orient yourself in whatever is — it may predate this naming.

## Steps

1. **Confirm the precondition.** The issue must be `status:spec-review` AND the owner must
   have approved. If you can't confirm approval from the conversation, ask before proceeding.
   Flip the label to in-progress:
   ```bash
   gh issue edit <N> --remove-label status:spec-review --add-label status:in-progress
   ```

2. **Open a draft PR early — keep CI warm.** Push the branch (it already carries the committed spec)
   and open a **draft** PR *now*, before implementation runs. CI triggers on `pull_request` and runs
   on draft PRs, so from here every checkpoint push during implementation exercises the full suite in
   parallel with local work — CI is the slow backstop the tiering model relies on, and this keeps it
   busy instead of idle until the end. **Re-running this skill is normal** (resuming after a crash,
   after residual findings, or after the owner sends you back) — check for an existing PR first and
   reuse it rather than erroring on a duplicate:
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   git -C <worktree> push -u origin "$BR"
   PR=$(gh pr list --head "$BR" --json number --jq '.[0].number // empty')
   if [ -z "$PR" ]; then
     gh pr create --draft --head "$BR" --base main \
       --title "<issue title>" \
       --body "Closes #<N>

   Draft — implementation in progress. The unit tier runs locally; the full suite runs in CI on each push."
     PR=$(gh pr list --head "$BR" --json number --jq '.[0].number // empty')
   fi
   ```
   `--base main` must match the repo's actual default branch — the same one `activate` branched
   from (see its "if `main` is not the repo's default branch, substitute it" caveat). Keep `<PR>`
   — step 5 needs it.

3. **Test tiering — the local gate is the unit tier, not the full suite.** The team runs the fast
   **unit** tier locally (plus the branch's `.spec-flow/flagged-tests`, if any); the full/integration
   suite is CI's gate and is never run locally. See **Test tiering (unit / integration)** in
   `docs/workflow.md`. No stack probe, no full-vs-degraded decision — the workflow handles this. If
   the repo hasn't split its tests into unit/integration tiers yet, the team runs the repo's default
   test command and says so; the tiering degrades gracefully.

4. **Run the implementation Workflow.** Invoke the `Workflow` tool with the script bundled in
   this plugin and pass `args`:
   ```json
   {
     "scriptPath": "${CLAUDE_PLUGIN_ROOT}/skills/implement/implement.workflow.js",
     "args": {
       "worktree": "<abs path — $(git rev-parse --show-toplevel), Claude Code's own isolated checkout for this session>",
       "repoRoot": "<abs repo root>",
       "change":   "issue-<N>",
       "issue":    <N>,
       "base":     "origin/main",
       "buildSystem": "auto"
     }
   }
   ```
   `base` must match the repo's actual default branch (same substitution caveat as step 2's
   `--base`) — the review lenses diff `base...HEAD` in the worktree, so a wrong base reviews the
   wrong range. `buildSystem` is a hint for the build phase — the project's build tool (`cargo`,
   `gradle`, `npm`, `go`, `pytest`, …) or `"auto"` to let the build-engineer discover the real
   runner from the repo. It is NOT an exhaustive switch; the agents detect the actual commands.
   The script: tdd-developer applies the OpenSpec tasks test-first → a **five-lens review panel**
   reviews the diff in parallel (spec-conformance + repo rules; the built-in `/code-review`
   correctness lens; the built-in `/security-review` lens, which self-gates to security-relevant
   surfaces; the `test-rigor-reviewer` lens for antagonistic/regression-exposing test coverage; the
   `observability-reviewer` lens for prod-diagnosability of new paths/failures, which self-gates) →
   fix loop until **every** lens approves with no blocker/major (bounded) → build-engineer gets the
   build clean (format/lint/build) → docs polish. It returns a summary (unit tier ran locally / full
   suite runs in CI, review verdict, residual findings). See `docs/workflow.md` ("Review panel") for the lens
   semantics. The team **commits and pushes the branch at checkpoints**, so CI runs the full suite on
   the draft PR throughout implementation rather than only at the end.

5. **Mark the PR ready and report.** When the workflow returns approved, finalize the already-open
   draft PR (outward-facing — done here in this session, narrated):
   ```bash
   git -C <worktree> push origin "$BR"                     # ensure the final state is pushed
   gh pr ready <PR>                                        # un-draft — ready for your review (Seam 2)
   gh pr edit <PR> --body "Closes #<N>

   <final summary from the workflow, INCLUDING the note that the unit tier ran locally and the full suite runs in CI>

   <if non_blocking_findings is non-empty, a 'Surfaced, non-blocking' section listing each one — these never blocked approval but the owner should still see them at Seam 2>"
   gh issue edit <N> --remove-label status:in-progress --add-label status:in-review
   ```
   Give the owner the PR URL for GitHub review (Seam 2). When they leave comments, the next
   step is `/spec-flow:address <N>`; after they squash-merge, `/spec-flow:finalize <N>`.

## Rules

- **Never merge, never push to `main`.** This skill pushes only the issue branch, opens a *draft*
  PR, and later marks it ready — it never merges.
- **If a PR already exists for the branch (re-run), reuse it rather than erroring.** Common after
  a resumed/interrupted run, residual findings sent back for another pass, or the owner asking for
  another round.
- **Draft until approved.** The PR opens as a draft so CI runs during implementation; mark it ready
  only after the review panel approves. If the panel can't reach `approve` within the bounded fix
  loop, leave the PR a draft and surface the residual findings to the owner — never mark a
  red/unapproved PR ready.
- The PR body must state plainly that the unit tier ran locally and the full suite runs in CI — the
  reviewer relies on CI (gate is green CI) for full-suite results. Never imply the full suite ran locally.
- All code work happens in the worktree; this session only orchestrates, pushes, and manages the PR.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
