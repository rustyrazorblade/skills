---
name: activate
description: Activate a groomed GitHub issue for development — create its git worktree and branch, run OpenSpec explore+propose to produce a committed spec (consulting a domain-expert agent for any architectural/data-model decisions), and stop for the owner's spec approval. Second stage of the flow delivery workflow (see docs/workflow.md). This is the human approval seam; it never implements.
argument-hint: [issue number — omit to take the highest-priority status:ready issue]
---

# activate — spec the work, then stop for approval

You are the PM/lead in the main session. Take a `status:ready` issue and produce a committed,
owner-approvable OpenSpec change on an isolated worktree. **This is Seam 1.** When the spec is
committed you STOP and hand back — you do not implement, and you do not start `/spec-flow:implement`.

Input: an issue number `#N`. If omitted, pick the highest-priority `status:ready` issue
(`gh issue list --label status:ready --json number,title,labels` and choose `P0` over `P1` …),
and confirm the choice with the owner.

## Steps

1. **Load the issue.** `gh issue view <N> --json number,title,body,labels`. Derive a
   kebab-case `slug` from the title (concise, e.g. `predicate-pushdown`).

2. **Create the worktree + branch** (1:1:1:1 naming) from up-to-date `main`:
   ```bash
   git -C <repo-root> fetch origin
   git -C <repo-root> worktree add ".claude/worktrees/issue-<N>-<slug>" -b "issue-<N>-<slug>" origin/main
   ```
   All spec work happens inside that worktree path from here on. (If `main` is not the repo's
   default branch, substitute it.)

   **Exclude `.claude/worktrees/` from git** (idempotent, one-time; the nested checkouts must
   never show up as untracked/stageable content in the primary working tree):
   ```bash
   grep -qxF '.claude/worktrees/' <repo-root>/.git/info/exclude 2>/dev/null \
     || printf '\n# spec-flow long-lived worktrees (local-only, never commit)\n.claude/worktrees/\n' \
        >> <repo-root>/.git/info/exclude
   ```
   Uses `.git/info/exclude`, not a committed `.gitignore` — this is local repo state, not
   something to push to `main`.

3. **Design first — delegate to the `architect` agent.** Before generating the proposal, spawn the
   `architect` subagent with the issue's scope + acceptance criteria. It returns a design proposal —
   approach, structure/boundaries (SOLID), data model, key interfaces, and **trade-offs framed as
   owner decisions** (recommended option + alternatives + why). This design feeds the OpenSpec
   proposal below. The architect **advises**; it never makes the call.

4. **Explore + propose, inside the worktree.** Run the OpenSpec flow for a change named
   `<slug>` against the issue's scope and acceptance criteria, folding in the architect's design:
   - Use `openspec-explore` to think through the change if it's non-trivial.
   - Use `openspec-propose` to generate proposal + design + specs + tasks for `<slug>`, carrying
     the architect's recommended design (and the alternatives) into the proposal/design docs.
   - Translate the issue's acceptance criteria into spec `#### Scenario:` blocks.

5. **Route significant decisions to the owner — and to a domain expert for facts.** Every
   consequential design / data-model choice the architect surfaced (new tables / partition or
   clustering keys / indexes / schema changes / a new public interface / a concurrency model) is the
   **owner's** to make. Where deeper domain facts are needed, also consult a relevant
   **domain-expert agent if one is available** (e.g. a database or domain expert configured in
   the consuming repo) for trade-offs. **Present the options to the owner and let the owner choose**;
   capture the owner's decision in the spec/design. The agents never make the architectural call —
   they advise only.

6. **Commit the spec on the branch:**
   ```bash
   git -C <worktree> add openspec/changes/<slug>
   git -C <worktree> commit -m "<slug>: spec (proposal/design/specs/tasks) for #<N>"
   ```

7. **Render the spec INLINE for review, then mark spec-review and STOP.**
   ```bash
   gh issue edit <N> --remove-label status:ready --add-label status:spec-review
   ```
   **Show the spec in the conversation — do NOT just point at the worktree path.** The owner
   reviews here, not in an editor. Render the substance inline: the **proposal** (why + what
   changes + scope), the **design decisions** (each decision, and any rejected alternative or
   open review choice called out explicitly), the **delta-spec requirements + their
   `#### Scenario:` blocks** (the testable contract), and the **tasks** in order. Summarize
   faithfully — it must be enough to approve or redirect without opening a file. You may also
   give the path as a secondary reference, but the inline render is the deliverable. State that
   nothing will be implemented until they approve. **Do not proceed to implementation.** When
   the owner approves, the next step is `/spec-flow:implement <N>`.

## Rules

- **Show, don't link.** At the review seam, render the spec inline in the conversation; never
  hand back only a file path and expect the owner to open it. The owner is not in an editor.
- Stop at the spec. No implementation, no `/spec-flow:implement`, no pushing the branch.
- Worktree managed by `git worktree` (long-lived), never the Agent throwaway isolation.
- One change per issue; the change name equals the slug; branch/worktree are `issue-<N>-<slug>`.
- Architectural / data-model decisions are the owner's; a domain-expert agent advises only.
- If the worktree/branch already exists (re-activation), reuse it rather than erroring.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
