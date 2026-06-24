---
name: address
description: Address the owner's GitHub review comments on an issue's PR — pull the comments, fix them in the issue's worktree, push, and reply per review thread. Fourth stage of the flow delivery workflow (see docs/workflow.md). Owner-invoked when they return after reviewing; never polls.
---

# address — resolve the owner's PR review comments

You are the PM/lead in the main session. The owner reviewed the PR for issue `#N` in GitHub
and left comments. Pull them, fix them in the worktree, push, and reply to each thread. This
is owner-invoked (run it when you're back) — there is no polling.

Input: an issue number `#N` (or its PR number). Worktree `.claude/worktrees/issue-<N>-<slug>`,
branch `issue-<N>-<slug>`.

## Steps

1. **Find the PR and fetch review comments.**
   ```bash
   gh pr list --head issue-<N>-<slug> --json number,url
   # Review threads (line comments) + their bodies:
   gh api repos/{owner}/{repo}/pulls/<PR>/comments --paginate
   # Top-level review summaries:
   gh pr view <PR> --json reviews,comments
   ```
   If there are **no new comments** since the last address pass, say so and stop — don't
   invent work.

2. **Mark addressing.**
   ```bash
   gh issue edit <N> --remove-label status:in-review --add-label status:addressing
   ```

3. **Fix in the worktree.** Dispatch a fix agent (background `Agent`) with the worktree path
   and the collected comments. Choose the agent by the nature of the comments:
   - behavior/test/structure changes → `tdd-developer` (test-first);
   - review-rule/spec-conformance concerns → `reviewer` to re-check after fixes, or
     `build-engineer` for build/lint/format.
   Instruct it to make focused commits, keep tests green (full or degraded, as available),
   and **never push or touch main**.

4. **Push the branch** (outward-facing — done here, narrated):
   ```bash
   git -C <worktree> push origin issue-<N>-<slug>
   ```

5. **Reply per thread.** For each review comment you addressed, post a reply noting the commit
   that resolved it:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<PR>/comments/<comment-id>/replies \
     -f body="Addressed in <short-sha>: <one line>."
   ```

6. **Back to in-review.**
   ```bash
   gh issue edit <N> --remove-label status:addressing --add-label status:in-review
   ```
   Report what changed and the PR URL. The owner re-reviews; loop `/spec-flow:address` again if they
   leave more comments, or they squash-merge and you run `/spec-flow:finalize <N>`.

## Rules

- Never merge, never push to `main` — only the issue branch.
- Tolerate the zero-new-comments case gracefully.
- Reply to the actual review threads so the owner sees resolution in context, not just a force-push.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
