---
name: activate
description: Activate a groomed GitHub issue for development — claim it, delegate the design to the architect agent (concurrently with a domain-expert agent, if one is available), stop for the owner's design decision BEFORE generating anything, then run OpenSpec explore+propose to produce a committed spec from the chosen design and stop again for the owner's spec approval. Second stage of the flow delivery workflow (see docs/workflow.md). Two owner touchpoints by default — the design choice, then the spec approval (Seam 1) — either auto-approvable per this run's `.spec-flow/owner-instructions`; it never implements itself regardless.
argument-hint: [issue number — omit to take the highest-priority status:ready issue]
---

# activate — decide the design, spec the work, then stop for approval

You are this issue's `issue-pm`, running as your own dedicated background session. Take a
`status:ready` issue and produce a committed,
owner-approvable OpenSpec change on an isolated worktree. This skill stops for the owner **twice**:
once at step 4 to pick the design, before anything is generated, and again at step 7 — **Seam
1** — to approve the resulting spec. Neither stop is optional by default; you hand back once the
spec is committed and approved — you do not implement, and you do not start
`/spec-flow:implement`. The only exception: if `.spec-flow/owner-instructions` at the worktree
root (read fresh at each stop, not just once from your spawn prompt — see `agents/issue-pm.md`)
explicitly says to auto-approve the design and/or the spec for this run, follow that instead of
waiting — see steps 4 and 7 below for exactly how.

Input: an issue number `#N`. If omitted, pick the highest-priority `status:ready` issue that is
unassigned or already assigned to you (`gh issue list --label status:ready --json
number,title,labels,assignees` and choose `P0` over `P1` …, skipping any issue assigned to someone
else — that's their claim, not yours to take), and confirm the choice with the owner.

## Steps

1. **Load the issue and claim it.** `gh issue view <N> --json number,title,body,labels,assignees`.
   The OpenSpec change for this issue is named `issue-<N>` — deterministic, nothing to derive from
   the title.

   **Multi-user guard.** Check `assignees` against the authenticated user
   (`gh api user --jq .login`). If the issue is already assigned to someone else, **stop** — tell
   the owner it's claimed and let them pick a different issue or coordinate with whoever has it;
   do not proceed. Otherwise claim it before doing anything else — `--add-assignee`/
   `--add-label` are safe to repeat, but only post the "claimed" comment on a **genuinely fresh**
   claim, not a re-activation (the issue was already assigned to you): re-running this on your own
   in-flight issue shouldn't repost it every time.
   ```bash
   ME=$(gh api user --jq .login)
   # gh's own --jq flag does NOT support jq's --arg passthrough (confirmed live: "accepts at most
   # 1 arg(s), received 3") — interpolate the value straight into the jq expression string instead.
   # GitHub logins are alphanumeric/hyphen only, so this is safe to inline without escaping issues.
   # Use exact-match `any(...)`, not `contains([...])` — jq's array `contains` is a SUBSTRING test
   # on string elements (confirmed live: contains(["jon"]) matches login "jonhaddad"), which would
   # false-positive ALREADY_MINE for any login containing yours as a substring.
   ALREADY_MINE=$(gh issue view <N> --json assignees --jq "[.assignees[].login] | any(. == \"$ME\")")
   gh issue edit <N> --add-assignee @me --add-label agent:active
   if [[ "$ALREADY_MINE" != "true" ]]; then
     gh issue comment <N> --body "🏗️ Claimed — starting design."
   fi
   ```
   This is what makes "who's working on what" visible to other users of this repo — claim before
   anything else. `agent:active` and the comment are the only things that make you visible to
   *another* user's `project-manager` (or your own, from a different machine) — nothing else about
   this session is; see **Coordination signals** in `docs/workflow.md`.

2. **Ensure you're isolated in your own worktree — verify it, don't assume it.** Isolation is
   **not** automatic for everything: confirmed by test, Claude Code only isolates you in front of
   an `Edit`/`Write` tool call — never before a Bash-driven file write (`printf > f`, a heredoc,
   an external CLI like `openspec` writing files itself), and `gh` calls (step 1) don't trigger it
   either. If `scripts/spawn-issue-pm.sh` spawned you, its prompt already told you to call
   `EnterWorktree` as your very first action, before step 1 — so by now you should already be
   isolated. **Check, don't trust it:** `git rev-parse --show-toplevel` should return a path
   containing `.claude/worktrees/issue-<N>`, not the repo's primary checkout. If it doesn't
   (started some other way, or the spawn-time isolation didn't take), call `EnterWorktree` yourself
   right now with `name: "issue-<N>"` — the same literal name the spawn prompt uses — before
   anything else, including before the OpenSpec commands in step 5, since those write files via a
   Bash-invoked CLI and won't trigger isolation on their own. Passing the name is what keeps this
   deterministic and, if a worktree named `issue-<N>` already exists (a prior run this local
   session registry lost track of), resumes it automatically instead of erroring or creating a
   second one — confirmed by test. Once confirmed, every subsequent action — tool-driven or
   Bash-driven — lands there, not in the owner's primary checkout.

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
   scope without the owner explicitly saying so. **In auto mode (below), there's no owner to ask —
   never fold ANY flagged debt item into scope on your own, "fold into this change" or not. List
   every item, exactly as the architect recommended it, in the auto-approval comment instead, for
   the owner to triage once they're back.**

   **If the architect's design surfaces a hard dependency on another, unmerged issue** (this one
   genuinely can't land first, not just "would be cleaner after"), say so to the owner here, then
   mark it on GitHub so it's visible without you:
   ```bash
   gh issue edit <N> --add-label blocked
   gh issue comment <N> --body "⛔ Blocked on #<M> — <one-line reason>."
   ```
   Keep going if the owner wants to proceed anyway (e.g. spec now, implement once `#<M>` lands) —
   `blocked` is informational, not a hard stop you enforce yourself. Remove the label and post a
   follow-up comment once the dependency actually clears. **This is the one thing auto mode never
   skips past:** a hard dependency is a factual blocker the architect determined, not a stylistic
   decision — label it, comment, and stop for the owner regardless of what
   `.spec-flow/owner-instructions` says for this run. Continuing anyway risks unmergeable work;
   "drive this to completion" isn't licence to override a genuine blocker.

   **Absent a hard dependency, and only if `.spec-flow/owner-instructions` (read fresh at this
   point) explicitly says to auto-approve the design for this run**, skip the wait instead of
   pausing: take the architect's recommended option, and post a comment naming what was chosen and
   why, alongside the debt-item list above:
   `gh issue comment <N> --body "Design auto-approved per this run's instructions: <recommended option, one line>."`
   Then proceed to step 5. Absent that explicit instruction, this is always a real pause.

5. **Check for existing work-in-progress, then explore + propose from the owner's chosen design.**
   Before creating anything, look for what's already in `openspec/changes/`:
   ```bash
   ls openspec/changes/ 2>/dev/null | grep -v '^archive$'
   ```
   - **Nothing there:** proceed fresh, naming the change `issue-<N>`.
   - **`issue-<N>` already there** (re-activation, resuming your own earlier pass): orient
     yourself in it first — read its proposal/design/specs/tasks and the branch's `git log` —
     then assess whether it already reflects the design the owner just chose at step 4. If it
     does, continue from it rather than regenerating from scratch. If it doesn't (the owner picked
     differently this time, or it's stale/partial), say so and regenerate the affected parts.
   - **Something else is there** (an older change predating this naming, or one you don't
     recognize): same orientation — read what's there before deciding whether to continue it,
     rename it to `issue-<N>`, or start fresh. Never silently create a second, competing change
     for the same issue.

   Run the OpenSpec flow for the change (`issue-<N>`) against the issue's scope and acceptance
   criteria, folding in the design the **owner chose** in step 4 — not the architect's raw
   recommendation if they picked differently:
   - Use `openspec-explore` to think through the change if it's non-trivial.
   - Use `openspec-propose` to generate proposal + design + specs + tasks for `issue-<N>`, carrying
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
   git -C <worktree> add openspec/changes/issue-<N>
   git -C <worktree> commit -m "issue-<N>: spec (proposal/design/specs/tasks)"
   ```

7. **Render the spec INLINE for review, then mark spec-review and STOP.**
   ```bash
   gh issue edit <N> --remove-label status:ready --add-label status:spec-review
   gh issue comment <N> --body "📝 Spec committed (\`issue-<N>\`) — awaiting your review to approve implementation."
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

   **Unless `.spec-flow/owner-instructions` (read fresh at this point) explicitly says to
   auto-approve the spec for this run.** If so, still render the spec in full as above (posted as
   a comment, not just shown inline, since there's no owner in the conversation to see it) so the
   decision is auditable after the fact, then proceed directly to `/spec-flow:implement <N>`
   yourself instead of waiting:
   `gh issue comment <N> --body "Spec auto-approved per this run's instructions — proceeding to implement."`
   Absent that explicit instruction, this stop always waits for the owner.

## Rules

- **Show, don't link.** At either stop, render inline in the conversation; never hand back only a
  file path and expect the owner to open it. The owner is not in an editor.
- **Two real stops, in order, by default.** Step 4 (design choice) always precedes step 5
  (generation) — never generate the spec before the owner has picked (or `.spec-flow/owner-instructions`
  auto-picked) among the architect's options. Step 7 (spec approval, Seam 1) always follows step 6
  (commit) — no implementation, no `/spec-flow:implement`, no pushing the branch, until both stops
  have passed or been explicitly auto-approved per that file's current contents.
- Worktree managed by Claude Code's own `EnterWorktree` isolation, scoped to *this session's*
  life — not something this skill creates by hand, and not the Agent tool's throwaway `isolation:
  "worktree"`. Named `issue-<N>` explicitly (both the spawn prompt and step 2's fallback pass that
  as `EnterWorktree`'s `name`) — deterministic, matching the OpenSpec change and PR-body correlator
  below, and it's what makes a fresh spawn resume an existing-but-untracked worktree automatically
  instead of duplicating it (confirmed by test). It's only guaranteed to be where you're standing
  if step 2 actually confirmed it; isolation doesn't happen for free. That isolation is per-
  **session**, not per-issue on its own — it's `scripts/spawn-issue-pm.sh` respawning a past
  session by name instead of always starting fresh, plus the worktree name itself now being
  deterministic, that keeps this issue to one worktree in practice (see **Coordination signals** in
  `docs/workflow.md`). The issue number is the one thing that matters for finding anything — the
  OpenSpec change is named `issue-<N>` directly from it, and `Closes #N` in the PR body (added at
  `implement`) is the durable correlator for the PR — see **Naming** in `docs/workflow.md`.
- One change per issue, named `issue-<N>` — deterministic, never derived from the title.
- Architectural / data-model decisions are the owner's, made at step 4; the architect and any
  domain-expert agent advise only, never decide.
- **Nearby structural debt is a recommendation, not scope creep.** Never bundle a "recommend as a
  separate issue" item into the current change without the owner explicitly saying so, and never
  file that issue on your own initiative — only at the owner's explicit direction (step 4).
- **Re-activation.** When you resume a session that was inside a worktree, Claude Code returns you
  to that same worktree automatically. If `openspec/changes/` already has something for this issue
  (step 5), orient yourself at that work-in-progress before touching anything — don't assume it's
  current, and don't assume it's safe to regenerate; read it, judge whether it still matches the
  owner's step-4 choice, and continue it if so.
- **Never activate an issue assigned to someone else.** This repo may have multiple users; an
  issue's assignee is another person's claim. Stop and say so rather than proceeding.
- **`agent:active` stays on past this skill** — `implement`/`address`/`finalize` inherit it;
  `finalize` is what removes it. If you (this session) end for any other reason before finalize —
  the owner tells you to stop, you're abandoning the issue — remove it yourself rather than
  leaving a stale "active" signal for the next person to trust.
- When you cite an issue/PR number, always pair it with a brief `(description)`.
