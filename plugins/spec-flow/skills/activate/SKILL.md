---
name: activate
description: Activate a groomed GitHub issue for development — create its git worktree and branch, delegate the design to the architect agent (concurrently with a domain-expert agent, if one is available), stop for the owner's design decision BEFORE generating anything, then run OpenSpec explore+propose to produce a committed spec from the chosen design and stop again for the owner's spec approval. Second stage of the flow delivery workflow (see docs/workflow.md). Two owner touchpoints — the design choice, then the spec approval (Seam 1); it never implements.
argument-hint: [issue number — omit to take the highest-priority status:ready issue]
---

# activate — decide the design, spec the work, then stop for approval

You are the PM/lead in the main session. Take a `status:ready` issue and produce a committed,
owner-approvable OpenSpec change on an isolated worktree. This skill stops for the owner **twice**:
once at step 4 to pick the design, before anything is generated, and again at step 7 — **Seam
1** — to approve the resulting spec. Neither stop is optional; when the spec is committed and
approved you hand back — you do not implement, and you do not start `/spec-flow:implement`.

Input: an issue number `#N`. If omitted, pick the highest-priority `status:ready` issue that is
unassigned or already assigned to you (`gh issue list --label status:ready --json
number,title,labels,assignees` and choose `P0` over `P1` …, skipping any issue assigned to someone
else — that's their claim, not yours to take), and confirm the choice with the owner.

## Steps

1. **Load the issue and claim it.** `gh issue view <N> --json number,title,body,labels,assignees`.
   Derive a kebab-case `slug` from the title (concise, e.g. `predicate-pushdown`).

   **Multi-user guard.** Check `assignees` against the authenticated user
   (`gh api user --jq .login`). If the issue is already assigned to someone else, **stop** — tell
   the owner it's claimed and let them pick a different issue or coordinate with whoever has it;
   do not proceed. If it's unassigned, or already assigned to the current user (the re-activation
   case), claim it before doing anything else:
   ```bash
   gh issue edit <N> --add-assignee @me
   ```
   This is what makes "who's working on what" visible to other users of this repo — claim before
   creating the worktree, not after.

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

3. **Design first — delegate to the `architect` agent, concurrently with a domain expert.** Before
   generating anything, spawn the `architect` subagent with the issue's scope + acceptance
   criteria. If a domain-expert agent is available in the consuming repo (e.g. a database or
   domain expert), spawn it **at the same time** — one message, two tool calls — with the same
   scope + acceptance criteria; both are independent read-only advisors working from the same
   input, so there's no reason to serialize them. The architect returns a design proposal —
   approach, structure/boundaries (SOLID), data model, key interfaces, risks & impact, and
   **trade-offs framed as owner decisions** (recommended option + alternatives + why). The
   domain-expert returns the domain facts behind those trade-offs. If the architect's design
   raises a specific domain question neither agent already answered, follow up with a second,
   targeted domain-expert consult before step 4. Both agents **advise**; neither makes the call.

4. **Stop and route the decision to the owner — before generating anything.** Every consequential
   design / data-model choice the architect surfaced (new tables / partition or clustering keys /
   indexes / schema changes / a new public interface / a concurrency model) is the **owner's** to
   make. Present the architect's (and domain-expert's) options inline — recommended choice +
   alternatives + why, and the risks — and **wait for the owner to choose** before proceeding to
   step 5. This is a real pause, not a formality folded into the final spec review at step 7: the
   spec generated in step 5 embodies whatever the owner picks here, so a chosen alternative must
   never leave stale traces of the rejected recommendation in `tasks.md` or the scenarios. The
   agents never make the architectural call.

   **Also present any nearby structural debt the architect flagged**, alongside the design options.
   For each item the architect marked "fold into this change," confirm with the owner and, if
   agreed, note it so step 5 adds it as an explicit task. For each item marked "recommend as a
   separate issue," ask the owner whether to file it now (if so, `gh issue create` it as its own
   ungroomed backlog item — this is the owner's explicit call, not something you do on your own
   initiative) or leave it for later. Never fold a "separate issue" item into the current change's
   scope without the owner explicitly saying so.

5. **Explore + propose, inside the worktree, from the owner's chosen design.** Run the OpenSpec
   flow for a change named `<slug>` against the issue's scope and acceptance criteria, folding in
   the design the **owner chose** in step 4 — not the architect's raw recommendation if they
   picked differently:
   - Use `openspec-explore` to think through the change if it's non-trivial.
   - Use `openspec-propose` to generate proposal + design + specs + tasks for `<slug>`, carrying
     the owner's chosen design (and why the alternatives were set aside) into the proposal/design
     docs.
   - If the owner agreed at step 4 to fold in any nearby structural-debt item, add it as an
     explicit task in `tasks.md` alongside the feature's own tasks — don't let it get lost between
     the decision and the generated plan.
   - Translate the issue's acceptance criteria into spec `#### Scenario:` blocks.
   - **Build an explicit AC→scenario mapping.** List every acceptance criterion from the issue,
     and every risk/failure-mode the architect's design surfaced ("Risks & impact"), against the
     scenario(s) that cover each. Every criterion and every architect-surfaced risk must map to at
     least one scenario — if one doesn't, either add a scenario for it or explicitly note it as an
     intentional exclusion with a one-line reason. Never let a criterion silently drop out with no
     scenario and no explanation. This mapping is rendered for the owner at step 7.

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
   reviews here, not in an editor. This is confirmation that step 5 faithfully translated the
   design already **chosen at step 4** into a concrete spec — not the first time the owner sees
   the decision. Render the substance inline: the **proposal** (why + what changes + scope), the
   **design the owner chose at step 4** (restated, with the rejected alternatives and why, so the
   owner can confirm this is still what they meant), the **delta-spec requirements + their
   `#### Scenario:` blocks** (the testable contract), the **AC→scenario mapping** from step 5 —
   every acceptance criterion and architect-surfaced risk against its covering scenario(s), with
   any intentional exclusions called out by name so the owner can catch a dropped criterion before
   approving, not after implementation — the **tasks** in order, including any folded-in
   structural-debt task from step 4 — and, if any nearby structural debt was recommended as a
   separate issue, a one-line reminder of its disposition (filed as `#<M>`, or left for later).
   Summarize faithfully — it must be enough to approve or redirect without opening a file. You may
   also give the path as a secondary reference, but the inline render is the deliverable. State
   that nothing will be implemented until they approve. **Do not proceed to implementation.** When
   the owner approves, the next step is `/spec-flow:implement <N>`.

## Rules

- **Show, don't link.** At either stop, render inline in the conversation; never hand back only a
  file path and expect the owner to open it. The owner is not in an editor.
- **Two real stops, in order.** Step 4 (design choice) always precedes step 5 (generation) —
  never generate the spec before the owner has picked among the architect's options. Step 7 (spec
  approval, Seam 1) always follows step 6 (commit) — no implementation, no
  `/spec-flow:implement`, no pushing the branch, until both stops have passed.
- Worktree managed by `git worktree` (long-lived), never the Agent throwaway isolation.
- One change per issue; the change name equals the slug; branch/worktree are `issue-<N>-<slug>`.
- Architectural / data-model decisions are the owner's, made at step 4; the architect and any
  domain-expert agent advise only, never decide.
- **Nearby structural debt is a recommendation, not scope creep.** Never bundle a "recommend as a
  separate issue" item into the current change without the owner explicitly saying so, and never
  file that issue on your own initiative — only at the owner's explicit direction (step 4).
- If the worktree/branch already exists (re-activation), reuse it rather than erroring.
- **Never activate an issue assigned to someone else.** This repo may have multiple users; an
  issue's assignee is another person's claim. Stop and say so rather than proceeding.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
