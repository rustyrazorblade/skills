---
name: address
description: Address the owner's GitHub review comments on an issue's PR — pull the comments, fix them in the issue's worktree, push, and reply per review thread. Fourth stage of the flow delivery workflow (see docs/workflow.md). Owner-invoked when they return after reviewing; never polls.
argument-hint: [issue number, or its PR number]
---

# address — resolve the owner's PR review comments

You are this issue's `issue-pm`, running as your own dedicated background session. The owner
reviewed the PR for issue `#N` in GitHub and left comments. Pull them, fix them in the worktree,
push, and reply to each thread. This is owner-invoked (run it when you're back) — there is no
polling.

Input: an issue number `#N` (or its PR number). You're already running inside this issue's
worktree — Claude Code's own background-session isolation put you there, on whatever branch it
assigned; resolve it with `git rev-parse --abbrev-ref HEAD` rather than assuming a name. If you
need to recover the PR from scratch (not already known from context), search by issue instead of
by branch name: `gh pr list --search "Closes #<N> in:body" --json number,headRefName`.

## Steps

1. **Find the PR and fetch review comments.**
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   gh pr list --head "$BR" --json number,url
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
   Instruct it to make focused commits, keep the **unit tier** (plus the branch's
   `.spec-flow/flagged-tests`, if any) green locally as its gate — never the full/integration
   suite, which is CI's gate — and **never push or touch main**. See **Test tiering (unit /
   integration)** in `docs/workflow.md`.

4. **Push the branch** (outward-facing — done here, narrated):
   ```bash
   git -C <worktree> push origin "$BR"
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
   gh issue comment <N> --body "🔧 Addressed <N-comments> review comment(s), pushed \`<short-sha>\`."
   ```
   Report what changed and the PR URL. The owner re-reviews; loop `/spec-flow:address` again if they
   leave more comments, or they squash-merge and you run `/spec-flow:finalize <N>`.

## Rules

- Never merge, never push to `main` — only the issue branch.
- Tolerate the zero-new-comments case gracefully.
- Reply to the actual review threads so the owner sees resolution in context, not just a force-push.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
