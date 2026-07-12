---
name: implement
description: Implement an approved issue — run the background subagent team (tdd-developer → 5-lens review panel → fix loop → build-engineer → docs polish) via a Workflow script in the issue's worktree, then push the branch and open a PR. Third stage of the flow delivery workflow (see docs/workflow.md). Requires the owner to have approved the committed spec first. Invoking this skill is the explicit opt-in to multi-agent Workflow orchestration.
argument-hint: [issue number, with its spec already approved]
---

# implement — build the approved spec, open a PR

You are the PM/lead in the main session. The owner has **approved the committed spec** for
issue `#N`. Drive the implementation team to completion and open a review-ready PR. The team
runs as a background `Workflow` — **invoking this skill is the owner's explicit opt-in to
that orchestration** (it may spawn several subagents).

Input: an issue number `#N`. Its worktree is `.claude/worktrees/issue-<N>-<slug>`, branch
`issue-<N>-<slug>`, OpenSpec change `<slug>`.

## Steps

1. **Confirm the precondition.** The issue must be `status:spec-review` AND the owner must
   have approved. If you can't confirm approval from the conversation, ask before proceeding.
   Flip the label to in-progress:
   ```bash
   gh issue edit <N> --remove-label status:spec-review --add-label status:in-progress
   ```

2. **Test tiering — the local gate is the unit tier, not the full suite.** The team runs the fast
   **unit** tier locally (plus the branch's `.spec-flow/flagged-tests`, if any); the full/integration
   suite is CI's gate and is never run locally. See **Test tiering (unit / integration)** in
   `docs/workflow.md`. No stack probe, no full-vs-degraded decision — the workflow handles this. If
   the repo hasn't split its tests into unit/integration tiers yet, the team runs the repo's default
   test command and says so; the tiering degrades gracefully.

3. **Run the implementation Workflow.** Invoke the `Workflow` tool with the script bundled in
   this plugin and pass `args`:
   ```json
   {
     "scriptPath": "${CLAUDE_PLUGIN_ROOT}/skills/implement/implement.workflow.js",
     "args": {
       "worktree": "<abs path>/.claude/worktrees/issue-<N>-<slug>",
       "repoRoot": "<abs repo root>",
       "change":   "<slug>",
       "issue":    <N>,
       "base":     "origin/main",
       "buildSystem": "auto"
     }
   }
   ```
   `buildSystem` is a hint for the build phase — the project's build tool (`cargo`, `gradle`,
   `npm`, `go`, `pytest`, …) or `"auto"` to let the build-engineer discover the real runner from
   the repo. It is NOT an exhaustive switch; the agents detect the actual commands.
   The script: tdd-developer applies the OpenSpec tasks test-first → a **five-lens review panel**
   reviews the diff in parallel (spec-conformance + repo rules; the built-in `/code-review`
   correctness lens; the built-in `/security-review` lens, which self-gates to security-relevant
   surfaces; the `test-rigor-reviewer` lens for antagonistic/regression-exposing test coverage; the
   `observability-reviewer` lens for prod-diagnosability of new paths/failures, which self-gates) →
   fix loop until **every** lens approves with no blocker/major (bounded) → build-engineer gets the
   build clean (format/lint/build) → docs polish. It returns a summary (unit tier ran locally / full
   suite runs in CI, review verdict, residual findings). See `docs/workflow.md` ("Review panel") for the lens
   semantics.

4. **Push and open the PR** (outward-facing — done here in the main session, narrated):
   ```bash
   git -C <worktree> push -u origin issue-<N>-<slug>
   gh pr create --head issue-<N>-<slug> --base main \
     --title "<issue title>" \
     --body "Closes #<N>

   <summary from the workflow, INCLUDING the note that the unit tier ran locally and the full suite runs in CI>"
   ```

5. **Mark in-review and report.**
   ```bash
   gh issue edit <N> --remove-label status:in-progress --add-label status:in-review
   ```
   Give the owner the PR URL for GitHub review (Seam 2). When they leave comments, the next
   step is `/spec-flow:address <N>`; after they squash-merge, `/spec-flow:finalize <N>`.

## Rules

- **Never merge, never push to `main`.** This skill only pushes the issue branch and opens a PR.
- The PR body must state plainly that the unit tier ran locally and the full suite runs in CI — the
  reviewer relies on CI (gate is green CI) for full-suite results. Never imply the full suite ran locally.
- If the review panel can't reach `approve` within the bounded fix loop, stop and surface the
  residual findings to the owner rather than opening a green-looking PR.
- All code work happens in the worktree; the main session only orchestrates, pushes, and PRs.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
