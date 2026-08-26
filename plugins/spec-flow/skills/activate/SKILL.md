---
name: activate
description: Activate a groomed GitHub issue for development — claim it, review it with the owner (scope/acceptance-criteria freshness + backlog overlap, up to 5 issue-specific questions, skippable via owner-instructions), run architect + domain-expert design concurrently, stop for the owner's design choice before generating anything, then OpenSpec explore+propose and stop again for spec approval (Seam 1). Second stage of the flow delivery workflow (see docs/workflow.md). Both stops auto-approvable per this run's `.spec-flow/owner-instructions`; never implements itself regardless. A `type:docs` issue always skips the design stop; a content-only one (the common case) also skips spec generation, going straight to a lightweight scope + acceptance-criteria review at Seam 1 instead (see docs/workflow.md's Docs fast path). A `type:tech-debt` issue always skips OpenSpec generation and, by default, the owner design-choice wait too — architect still runs but auto-adopts the Direction already confirmed when the issue was filed, stopping only for a hard dependency, a material deviation, or if the fix can't be done behavior-preserving — then goes to the same lightweight Seam 1 review (see docs/workflow.md's Tech-debt fast path). Marks a hard architect-flagged dependency with both the `blocked` label and a native GitHub issue dependency.
argument-hint: [issue number — omit to take the highest-priority status:ready issue]
---

# activate — decide the design, spec the work, then stop for approval

You are this issue's `issue-pm`, running as your own dedicated background session. Take a
`status:ready` issue and produce an owner-approvable plan on an isolated worktree — normally a
committed OpenSpec change, but a content-only `type:docs` issue (the common case) skips that
artifact entirely and the plan is just its own scope + acceptance criteria (see step 5), and a
`type:tech-debt` issue skips it too — its plan is the Direction already confirmed when the issue
was filed, plus whatever existing specified behavior nearby must be preserved (see step 5's
tech-debt branch). Right after claiming, step 1 also reviews the issue with the owner — scope/
acceptance-criteria freshness plus a backlog overlap check, up to five issue-specific questions —
unconditionally, for every issue type; skippable only via `.spec-flow/owner-instructions` for this
run, not one of the stops below. This skill stops for the owner **twice** in the normal case: once
at step 4 to pick the design, before anything is generated, and again at step 7 — **Seam 1** — to
approve
whatever step 5 produced. Step 4's wait is skipped for every `type:docs` issue (no design to
choose) and, by default, for `type:tech-debt` too (the architect still runs at step 3, but
auto-adopts the issue's confirmed Direction instead of waiting — see step 4's tech-debt branch);
Step 7 always still applies, in whichever lightweight form matches what was actually produced.
Neither applicable stop is optional by default beyond that; you hand back once the plan is
committed (if applicable) and approved — you do not implement, and you do not start
`/spec-flow:implement`. The only exception: if `.spec-flow/owner-instructions` at the worktree root
(read fresh at each stop, not just once from your spawn prompt — see `agents/issue-pm.md`)
explicitly says to auto-approve the design and/or the plan for this run, follow that instead of
waiting — see steps 4 and 7 below for exactly how.

Input: an issue number `#N`. If omitted, pick the highest-priority `status:ready` issue that is
unassigned or already assigned to you (`gh issue list --label status:ready --json
number,title,labels,assignees,subIssuesSummary` and choose `P0` over `P1` …, skipping any issue
assigned to someone else — that's their claim, not yours to take — **and skipping any epic**
(`subIssuesSummary.total > 0`; see step 1's epic guard below — pick its highest-priority
`status:ready` sub-issue instead, or the next `status:ready` issue if none of its sub-issues
qualify), and confirm the choice with the owner.

## Steps

1. **Load the issue and claim it.** `gh issue view <N> --json
   number,title,body,labels,assignees,subIssuesSummary`. The OpenSpec change for this issue is
   named `issue-<N>` — deterministic, nothing to derive from the title.

   **Announce it clearly, first thing.** Before anything else, output a one-line header —
   `Issue #N: <title>` — as your first visible text. This is what the owner sees first when they
   attach; with several `issue-pm` sessions possibly running at once, it's how they tell this tab
   apart from the others and rename it.

   **Epic guard.** If `subIssuesSummary.total > 0`, this is a parent/epic issue — its own scope is
   just a rollup of its sub-issues, nothing to spec or implement directly. `scripts/spawn-issue-pm.sh`
   already refuses to spawn against one, so reaching this point on a real epic should be rare (a
   respawn of a stale session, or activate invoked some other way) — refuse here too rather than
   claiming it: list its sub-issues (`gh issue view <N> --json subIssues --jq '.subIssues.nodes[] |
   "#\(.number) \(.title)"'`) and tell the owner to activate one of those instead. Do not proceed
   to the multi-user guard or claim below.

   **Multi-user guard.** Check `assignees` against the authenticated user
   (`gh api user --jq .login`). If the issue is already assigned to someone else, **stop** — tell
   the owner it's claimed and let them pick a different issue or coordinate with whoever has it;
   do not proceed. Otherwise claim it before doing anything else — hand off to a script that only
   posts the "claimed" comment on a **genuinely fresh** claim, not a re-activation (the issue was
   already assigned to you): re-running this on your own in-flight issue shouldn't repost it every
   time.
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/claim-issue.sh <N>
   ```
   Resolves everything from the issue number alone (re-derives the authenticated user itself); safe
   to re-run. The full reasoning — why `--jq` gets the expression interpolated rather than passed
   via `--arg`, why `any(...)` and not `contains([...])` — lives in the script's own comments; never
   reimplement it inline.

   This is what makes "who's working on what" visible to other users of this repo — claim before
   anything else. `agent:active` and the comment are the only things that make you visible to
   *another* user's `project-manager` (or your own, from a different machine) — nothing else about
   this session is; see **Coordination signals** in `docs/workflow.md`.

   **Review the issue with the owner, right after claiming, before anything else runs.** Skip this
   entirely if `.spec-flow/owner-instructions` (already written by your first actions, before this
   skill started — see `agents/issue-pm.md`) says to skip the review for this run; absent that, it
   always runs, for every issue type — `type:docs` and `type:tech-debt` included, since their fast
   paths only ever skip the design/spec machinery further down in this skill, never this. Not a
   third seam alongside the two below — a lighter, unconditional check before either of them (see
   **Owner review, right after claiming** in `docs/workflow.md`).

   Two things are worth confirming before design work starts: whether the scope and acceptance
   criteria written at `groom` still hold — this issue may have sat in the backlog a while — and
   whether anything else open in the backlog overlaps, duplicates, or depends on it, which `groom`
   had no way to check since it only ever saw the backlog as it stood when this issue was filed.
   Search for that overlap yourself before drafting anything:
   ```bash
   gh issue list --state open --json number,title,labels,body --limit 100
   ```
   Scan titles and bodies for the same subject matter, touched files/modules, or capability — not
   just keyword overlap in the title. Then draft **up to five** issue-specific questions from what
   you actually find — never a fixed checklist recited regardless of the issue, and never more than
   the ambiguity actually calls for; a straightforward issue with no backlog overlap may earn zero
   questions, and saying so plainly and moving on is the right outcome, not a shortfall. Typical
   shapes, only when the issue or the backlog search actually raises them: does the scope/acceptance
   criteria in front of you still match what the owner wants; is this still the right priority given
   what else is in flight; a backlog hit that looks like the same area — ask whether it's related, a
   duplicate, or a dependency, or just coincidentally similar; anything that's changed since this
   was filed that the acceptance criteria doesn't capture.

   Ask them **one at a time** — never dump the whole list on the owner at once — and follow up on
   whatever the answer actually raises rather than moving mechanically to the next scripted
   question. If the owner confirms a backlog hit is a genuine hard dependency, handle it exactly like
   the architect-flagged case at step 4 below (`blocked` label + native GitHub issue dependency +
   comment) — don't invent a second mechanism for the same fact. If an answer changes the scope or
   acceptance criteria, update the issue body before continuing so the change is durable, not just
   live in this conversation:
   ```bash
   gh issue edit <N> --body "<updated body>"
   ```
   Close with one comment either way, so the review is visible to anyone reading the issue without
   attaching to this session:
   ```bash
   gh issue comment <N> --body "🔎 Reviewed with owner — confirmed as filed."
   # or, if anything changed:
   gh issue comment <N> --body "🔎 Reviewed with owner — updated: <what changed, one line>."
   ```
   **If `.spec-flow/owner-instructions` skips this review for the run**, post that plainly instead,
   same auditability as every other auto-approved step: `gh issue comment <N> --body "Owner review
   skipped per this run's instructions."`

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

   **If `SPEC_FLOW_AUTO_INDEX=1`, index this worktree now.** claude-context indexes by absolute
   path, and this worktree is a distinct path from every other worktree of this repo (including the
   primary checkout) — it never inherits another worktree's index. Call the `mcp__claude-context__
   index_codebase` tool with `path` set to this worktree's absolute root (from
   `git rev-parse --show-toplevel`, just confirmed above). Fire-and-forget — don't block this step
   on indexing finishing; if it fails (e.g. `claude-context` not actually reachable despite the flag
   being set), note it in passing and move on, never treat it as a blocker. This is `issue-pm`'s own
   responsibility, once, right after isolating — never repeated later in the run, and never done by
   `project-manager` itself (see **Startup checks** in `agents/project-manager.md`, which only asks
   about and records the preference — the indexing action itself always happens here).

3. **Design first — delegate to the `architect` agent, concurrently with a domain expert.** **Skip
   this step and step 4 entirely if the issue carries `type:docs`** — a docs-only change has no
   architecture to decide, structural or not. Go straight to step 5, which further decides whether
   this particular docs change needs a spec at all (see **Docs fast path** in `docs/workflow.md`);
   the doc-writing pass in `implement` can still consult `architect` on demand if it hits a real
   question about whether the documentation matches the intended design — available, just not a
   mandatory gate here.

   **For a `type:tech-debt` issue, this step still runs — narrowed, never skipped** (see
   **Tech-debt fast path** in `docs/workflow.md`). The issue body already carries a `## Direction`
   from `/tech-debt` (dev-skills) — a concrete shape, not a design brief — so spawn `architect` with a
   **narrowed charter** instead of the normal design-from-scratch mandate: *"Direction (already
   confirmed by the owner when this issue was filed): `<the issue's Direction section, verbatim>`.
   Don't design from scratch — verify this specific fix still applies (the finding's file:line
   evidence may be stale — an intervening change may already have addressed it, or shifted the
   right shape) and turn it into a brief: confirmed shape (or a corrected one, if the code moved),
   risks & blast radius, and whether it can be done **without changing any observable behavior**
   (public signatures, error contracts, CLI/config/serialized output, or any existing test's
   asserted behavior) — if not, say so plainly rather than forcing a behavior-preserving frame onto
   a fix that isn't one."* No domain-expert consult needed here — this is a structural read, not a
   domain-facts question. If the `architect` reports the finding is stale/already-fixed or genuinely
   can't be done behavior-preserving, that's exactly what step 4's tech-debt branch escalates to the
   owner.

   Otherwise (a normal issue): before generating anything, spawn
   the `architect` subagent with the issue's scope + acceptance
   criteria. If a domain-expert agent is available in the consuming repo (e.g. a database or
   domain expert), spawn it **at the same time** — one message, two tool calls — with the same
   scope + acceptance criteria; both are independent read-only advisors working from the same
   input, so there's no reason to serialize them. The architect returns a design proposal —
   approach, structure/boundaries (SOLID), data model, key interfaces, risks & impact, and
   **trade-offs framed as owner decisions** (recommended option + alternatives + why). The
   domain-expert returns the domain facts behind those trade-offs. If the architect's design
   raises a specific domain question neither agent already answered, follow up with a second,
   targeted domain-expert consult before step 4. Both agents **advise**; neither makes the call.

4. **Stop and route the decision to the owner — before generating anything.** (Skipped entirely for
   `type:docs`, per step 3.)

   **For a `type:tech-debt` issue, auto-adopt by default — don't wait for the owner** unless one of
   three specific problems fires, each of which stops exactly like the hard-dependency case below
   always has:
   - **Architect flagged a hard dependency** on another unmerged issue — handled identically to the
     normal case further down this step (label, comment, native link, stop for the owner). Never
     skipped, tech-debt or not.
   - **Architect reports a material deviation** from the issue's confirmed Direction (the code moved
     enough that the original shape no longer fits, or the "corrected" shape from step 3 changes
     what the fix actually does, not just where it touches).
   - **Architect reports the fix can't be done without changing observable behavior.** This is the
     single most important check in the whole fast path — it's what stops a "pure refactor" that
     turns out not to be one from silently proceeding without ever going through spec approval.
   Any of the three → **stop and present it to the owner** exactly like a real design decision (what
   architect found, why it changed the picture, and the owner's options — proceed anyway with the
   corrected shape, narrow the fix to what *is* behavior-preserving, or treat this as a real feature
   change and route it through the full pipeline instead, generating a real spec for the behavior
   delta). **None of these three ever auto-approve, even if `.spec-flow/owner-instructions` says to
   auto-approve this run** — they're facts architect determined, not a stylistic choice, same as the
   hard-dependency rule below.

   **None of the three fired** → adopt architect's confirmed (or corrected) shape without waiting,
   and post a comment naming what was adopted, same auditability as the docs/design auto-approve
   comments elsewhere in this step:
   `gh issue comment <N> --body "🔧 Tech-debt fix confirmed — proceeding with: <shape, one line>."`
   Then go straight to step 5's tech-debt branch. This is the *default* for `type:tech-debt`, not
   conditional on `.spec-flow/owner-instructions` — the owner already made this decision once, item
   by item, when they confirmed the finding in `/tech-debt` (dev-skills); step 4 here is a safety check
   against staleness/scope-creep, not a second design-choice gate.

   **Otherwise (a normal issue):** every consequential
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
   mark it on GitHub so it's visible without you — both the `blocked` label (queryable, what
   `board` filters on) and GitHub's **native issue dependency** (renders directly in the GitHub UI,
   which the label alone doesn't — the two are additive, not a replacement for each other):
   ```bash
   gh issue edit <N> --add-label blocked
   gh issue comment <N> --body "⛔ Blocked on #<M> — <one-line reason>."
   # Native blocked_by link (verified live). issue_id = the BLOCKING issue's database `.id`, NOT
   # its `.number` — different values. -F, not -f: the API wants an integer, not a string.
   BLOCKING_ID=$(gh api "repos/{owner}/{repo}/issues/<M>" --jq .id)
   DEP_ERR=$(gh api "repos/{owner}/{repo}/issues/<N>/dependencies/blocked_by" -F issue_id="$BLOCKING_ID" -X POST 2>&1) || \
     echo "spec-flow: couldn't create the native blocked_by link — the blocked label + comment above still stand regardless, but don't assume this was transient: ${DEP_ERR}" >&2
   ```
   Keep going if the owner wants to proceed anyway (e.g. spec now, implement once `#<M>` lands) —
   `blocked` is informational, not a hard stop you enforce yourself. Once the dependency actually
   clears, remove the label, remove the native link, and post a follow-up comment:
   ```bash
   gh api "repos/{owner}/{repo}/issues/<N>/dependencies/blocked_by/$BLOCKING_ID" -X DELETE 2>/dev/null || true
   gh issue edit <N> --remove-label blocked
   gh issue comment <N> --body "✅ Unblocked — #<M> landed."
   ```
   (`$BLOCKING_ID` won't survive a separate Bash call — re-resolve it with the same `gh api
   .../issues/<M> --jq .id` command if this runs later than the block above.) **This is the one thing auto mode never
   skips past:** a hard dependency is a factual blocker the architect determined, not a stylistic
   decision — label it, comment, and stop for the owner regardless of what
   `.spec-flow/owner-instructions` says for this run.

   **Absent a hard dependency, and only if `.spec-flow/owner-instructions` (read fresh at this
   point) explicitly says to auto-approve the design for this run**, skip the wait instead of
   pausing: take the architect's recommended option, and post a comment naming what was chosen and
   why, alongside the debt-item list above:
   `gh issue comment <N> --body "Design auto-approved per this run's instructions: <recommended option, one line>."`
   Then proceed to step 5. Absent that explicit instruction, this is always a real pause.

5. **For a `type:docs` issue, first decide whether it needs a spec at all — most don't.** A
   generated OpenSpec spec that just restates the book's own content in `#### Scenario:` blocks is
   pure duplication; only generate one when there's an actual structural or technical decision to
   record:
   - **Content edit (the default — assume this unless the issue clearly says otherwise):**
     expanding, correcting, or clarifying existing pages, adding examples, fixing wording — the
     docs' own organization isn't changing and nothing behavioral is being documented for the first
     time. **Skip OpenSpec entirely for this issue** — no `openspec/changes/issue-<N>` directory,
     nothing to commit at step 6. Say so plainly in the conversation (step 7 posts the one GitHub
     comment for this decision — no need to duplicate it here), then skip to step 7's lightweight
     form below.
   - **Structural, or documenting an accompanying tech change:** the docs' own layout/organization
     is changing (new chapter, reorganized `SUMMARY.md`/table of contents, splitting or merging
     sections) — that's a real decision worth a committed, reviewable record, same as any other
     issue. Continue below exactly as normal, but keep what you generate **surface-level**:
     describe the structural approach and which pages/sections are affected; never transcribe the
     prose that's actually going into the book into the spec itself.

   **For a `type:tech-debt` issue: always skip OpenSpec entirely** — no `openspec/changes/issue-<N>`
   directory, nothing to commit at step 6, unconditionally (unlike docs, there's no structural
   sub-case that generates one; a fix that turns out to need a real spec was already routed there by
   step 4's escalation, before reaching this step at all). In its place, do the one piece of real
   work this step contributes for a tech-debt issue — a **read-only surface listing**, not a spec:
   grep `openspec/specs/**` for requirement titles/sections whose subject matter overlaps the
   finding's touched files/modules (match on the module/capability name, not just filename — a spec
   describes behavior, not file layout), and append what you find directly to the issue body so it's
   durably available to `implement`'s review panel later, not just this conversation:
   ```bash
   gh issue edit <N> --body "$(gh issue view <N> --json body --jq .body)

   ## Adjacent specified behavior (must be preserved)
   <matching requirement titles + spec file paths, one per line — or 'None found — no committed spec covers this surface.' if the grep turns up nothing>"
   ```
   Say so plainly in the conversation (step 7 posts the one GitHub comment for this decision — no
   need to duplicate it here), then skip to step 7's tech-debt branch below.

   If it's not `type:docs` or `type:tech-debt`, or it is `type:docs` but needs a spec per the above,
   run the OpenSpec flow below. Before creating anything, look for what's already in
   `openspec/changes/`:
   ```bash
   ls openspec/changes/ 2>/dev/null | grep -v '^archive$'
   ```
   - **Nothing there:** proceed fresh, naming the change `issue-<N>`.
   - **`issue-<N>` already there** (re-activation, resuming your own earlier pass): orient
     yourself in it first — read its proposal/design/specs/tasks and the branch's `git log` —
     then assess whether it already reflects the design the owner just chose at step 4. If it
     does, continue from it rather than regenerating from scratch. If it doesn't (the owner picked
     differently this time, or it's stale/partial), say so and regenerate the affected parts.
     **If `ac-coverage.md` and/or `overrides.md` are missing** (a change dir from before these
     files existed) — build and write whichever is missing now, even when nothing else about the
     change needs touching; step 7 depends on both being present, and re-activation is exactly the
     moment to retrofit them.
   - **Something else is there** (an older change predating this naming, or one you don't
     recognize): same orientation — read what's there before deciding whether to continue it,
     rename it to `issue-<N>`, or start fresh. Never silently create a second, competing change
     for the same issue.

   Run the OpenSpec flow for the change (`issue-<N>`) against the issue's scope and acceptance
   criteria, folding in the design the **owner chose** in step 4 — not the architect's raw
   recommendation if they picked differently:
   - Use `openspec-explore` to think through the change if it's non-trivial.
   - Use `openspec-propose` to generate proposal + design + specs + tasks for `issue-<N>`.
   - **Require `design.md` to actually carry what step 3/4 produced, not a compressed memory of
     it three steps later.** `openspec-propose`'s own template doesn't know this pipeline's
     step 3/4 exists, so after it runs, directly edit `design.md` (or write these sections
     yourself if `openspec-propose` left them thin) to guarantee both are present:
     - **`## Alternatives Considered`** — one entry per option the architect actually presented
       at step 4, not just the one chosen: the option, why it was rejected, and — if the owner
       picked differently than the architect's own recommendation — a note that this was an
       explicit owner override, not the advisor's pick. This is a transcription job, not
       synthesis: the full architect output is already in context from step 3, so copy it in
       faithfully rather than re-summarizing from memory.
     - **`## Domain Facts`** — when a domain-expert agent was consulted at step 3, its supporting
       facts, attributed to it, not folded anonymously into the architect's own reasoning. Omit
       this section entirely (not a stub) when no domain-expert was available.
   - **Require `proposal.md`'s `## What Changes` to be concrete, not a one-liner.** It should name
     the actual shape of the change — which files/capabilities are touched, what the user-facing
     or API-visible behavior will be — not just restate the issue's title in different words.
   - **Before committing (step 6), confirm none of the above are thin or missing** — an empty or
     single-sentence `## Alternatives Considered`, a `## Domain Facts` section that's a stub
     instead of omitted, or a `## What Changes` that doesn't actually describe the change's shape
     all mean going back and filling them in properly before proceeding, the same discipline as
     `ac-coverage.md`'s "every row must resolve" rule below. This is what makes Seam 1 (step 7's
     render) actually informative instead of forcing the owner to reconstruct the architect's
     reasoning from a comment history or their own memory of the step-4 conversation.
   - If the owner agreed at step 4 to fold in any nearby structural-debt item, add it as an
     explicit task in `tasks.md` alongside the feature's own tasks — don't let it get lost between
     the decision and the generated plan.
   - Translate the issue's acceptance criteria into spec `#### Scenario:` blocks.
   - **Validate the generated specs structurally before doing anything else with them.**
     ```bash
     openspec validate issue-<N> --type change --strict --json
     ```
     Any `ERROR`-level issue (a requirement with no scenario, a missing/malformed delta header,
     etc.) means the spec is structurally broken — fix it and re-validate before continuing to any
     bullet below. Never carry a failing validation into the owner's review; this is a mechanical
     pre-flight gate, not a judgment call, so there's nothing for the owner to weigh in on here.
     `openspec validate` does NOT check the internal shape of a scenario, though — confirmed live:
     a `#### Scenario:` written as free prose instead of `- **WHEN** ... / - **THEN** ...` bullets
     passes it clean. So also confirm every `#### Scenario:` block is immediately followed by at
     least one `- **WHEN**` bullet and one `- **THEN**` bullet; rewrite any that aren't — a prose
     scenario isn't the testable contract the AC→scenario mapping below assumes it is.
   - **Check whether this change overrides the current baseline, or conflicts with another
     in-flight change — write `openspec/changes/issue-<N>/overrides.md`, always, even when there's
     nothing to report** (an explicit "none found" is a checked answer; a missing file would leave
     the owner unable to tell "checked, clean" from "never checked"):
     - **Overrides existing behavior.** For every `## MODIFIED Requirements` / `## REMOVED
       Requirements` section this change's delta specs contain, find the corresponding requirement
       in the CURRENT baseline — `openspec/specs/<capability>/spec.md`, the already-merged,
       currently-true spec (not another open change's delta) — and show the actual before → after:
       the baseline requirement's existing text against what this change replaces it with, or
       "removed entirely, no replacement" for a `REMOVED` section. Don't make the owner infer this
       from a `MODIFIED` header; spell out exactly what's changing from what's true today:
       ```markdown
       ## Overrides existing behavior
       ### <capability>: <requirement title>
       **Currently:** <baseline requirement text>
       **This change:** <new requirement text, or "Removed — no replacement">
       ```
       No `MODIFIED`/`REMOVED` sections at all → write `## Overrides existing behavior\n\nNone —
       this change only adds new requirements.` rather than omitting the section.
     - **Conflicts with other in-flight changes.** List every OTHER open change directory —
       `ls openspec/changes/ 2>/dev/null | grep -v '^archive$' | grep -v '^issue-<N>$'` — that
       touches the same capability (same `specs/<capability>/` path) as this one. For each, read
       its delta spec for that capability and judge whether it actually modifies/removes the SAME
       requirement this change touches, or otherwise asserts something incompatible — not just
       that the folder names overlap:
       ```markdown
       ## Conflicts with other in-flight changes
       - `issue-<M>` also touches `<capability>` — <either "modifies the same '<requirement
         title>' requirement, incompatibly: <one-line why>" or "no actual conflict — touches a
         different requirement in the same capability">
       ```
       No other open change touches any of this change's capabilities → `## Conflicts with other
       in-flight changes\n\nNone found.`
     - **A genuine hard conflict is a real blocker** — the same class as an architect-flagged hard
       dependency (step 4): if another in-flight change modifies the same requirement in a way this
       change can't cleanly coexist with, that always stops Seam 1 for the owner, even under a full
       `.spec-flow/owner-instructions` auto-approve for this run. Say so plainly when it happens —
       don't silently proceed past a real conflict because the run was told to auto-approve.
   - **Build an explicit AC→scenario mapping, as a real committed artifact — not just a claim made
     in prose at step 7.** A coverage summary that only ever exists as the model's own narrated
     paragraph is unverifiable — the owner has no way to tell "this criterion is covered" from
     "the model believes this criterion is covered." Make it a table instead, so a gap is something
     the owner (or a future reviewer) can see directly, not something they have to take on faith:
     write `openspec/changes/issue-<N>/ac-coverage.md` as a markdown table with one row per
     acceptance criterion from the issue AND per risk/failure-mode the architect's design surfaced
     ("Risks & impact"):
     ```markdown
     | Source | Requirement | Covering scenario(s) | Status |
     |--------|-------------|----------------------|--------|
     | AC     | <criterion text, or a short paraphrase> | `<capability>: <scenario title>` | ✅ Covered |
     | Risk   | <architect risk text>                   | `<capability>: <scenario title>` | ✅ Covered |
     | AC     | <criterion text>                        | —                                | ⚠️ Excluded — <one-line reason> |
     ```
     **Every row must resolve to ✅ Covered or ⚠️ Excluded (with a reason) before this step is
     done** — never write a row as unresolved/missing and move on. If a criterion has no covering
     scenario and no good reason to exclude it, that means the spec is incomplete: go back and add
     the scenario (or, for a genuinely ambiguous case, surface it as a question rather than guessing
     at an exclusion reason). The file, once written, IS the coverage claim — step 7 renders it
     directly instead of re-summarizing it in prose.

6. **Commit the spec on the branch** — **skip this step entirely for a content-only `type:docs`
   issue, or any `type:tech-debt` issue** (step 5 above), since there's no `openspec/changes/issue-<N>`
   to commit either way:
   ```bash
   git -C <worktree> add openspec/changes/issue-<N>
   git -C <worktree> commit -m "issue-<N>: spec (proposal/design/specs/tasks)"
   ```

7. **Render for review, then mark spec-review and STOP.** **First, determine whether this is a
   fresh look or a re-review** — read `.spec-flow/seam1-last-shown-sha` in the worktree (gitignored,
   same category of file as `.spec-flow/owner-instructions`; this step both reads and, at the end,
   writes it):
   - **Missing** → fresh look. Render the full spec below, exactly as this step already describes.
   - **Present and equal to the current `git rev-parse HEAD`** → nothing has changed since the
     owner's last look (a resumed/crashed session re-entering this step with no regeneration in
     between) — the labels/comment below were already posted last time this step ran, so skip
     re-posting them too, not just the content render; say in one line that nothing's changed since
     your last review and stop there.
   - **Present and different from current HEAD** → the spec was regenerated since the owner last
     saw it (they redirected you, or this is a later re-activation). Render **only what changed
     since then**, not the whole spec again — the owner already reviewed the unchanged parts once;
     re-showing them wastes their attention and buries what actually moved. This applies to the
     "a spec exists" branch below, in both `explain` and terminal mode — it notes exactly how. The
     content-only `type:docs` and `type:tech-debt` branches are already a quick, lightweight
     confirmation (scope + acceptance criteria, or Direction + adjacent-behavior list, not a full
     generated spec) — diffing isn't worth the added complexity there; they always render in full,
     same as today.

   Either way, after rendering (once the STOP below is reached), write the current
   `git rev-parse HEAD` to `.spec-flow/seam1-last-shown-sha` (`mkdir -p .spec-flow` first if
   needed) — this is what makes a *later* re-review, if any, diff-only again instead of a full
   re-dump.

   **Then check `SPEC_FLOW_SEAM_VIEW`**
   (set once, repo-wide, by `/spec-flow:setup` — see **Seam visualization** in `docs/workflow.md`).
   Unset or `terminal` → skip straight to the branches below; each one's inline text render is the
   whole deliverable, exactly as written. `explain` → resolve the `dev-skills` plugin's installed
   root (it's a separate, standalone plugin — spec-flow calls its `explain` skill, never vendors or
   assumes its files live alongside spec-flow's own):
   ```bash
   EXPLAIN_ROOT=$(claude plugin list --json 2>/dev/null | jq -r '
     [.[] | select(.id | startswith("dev-skills@")) | select(.enabled)]
     | sort_by(.installedAt) | last.installPath // empty')
   ```
   `EXPLAIN_ROOT` empty (the preference is set but `dev-skills` isn't installed/enabled on this
   machine — e.g. set on a different machine than this one) → fall back to the branches below
   exactly as if `SPEC_FLOW_SEAM_VIEW` were unset, and mention once, in passing, that the seam-view
   preference is set but the `dev-skills` plugin isn't available here. Otherwise, generate an
   explain view **in addition to** doing whichever branch below's labeling/comment step, and
   present its path/open line **as** that branch's render instead of the inline text dump (the
   branch's own comment-posting and STOP still apply unchanged either way). Always include
   `--issue <N>` — the issue itself (body, comments, related/linked issues) belongs in the same
   view as the spec, not a second lookup:
   - A spec exists (the non-docs/non-tech-debt branch, or a structural/tech-accompanying
     `type:docs` one), **fresh look or nothing changed** → `"$EXPLAIN_ROOT/skills/explain/scripts/
     generate-explain.py" --issue <N> --change openspec/changes/issue-<N> --doc
     openspec/changes/issue-<N>/ac-coverage.md --doc openspec/changes/issue-<N>/overrides.md
     --title "issue-<N>" --subtitle "<issue title>" --out <path>`. The two `--doc` flags are
     deliberate, not redundant with `--change` — `ac-coverage.md`/`overrides.md` are spec-flow-
     specific artifacts (see step 5), not among the generic OpenSpec files `--change` auto-includes
     (`proposal.md`/`design.md`/`tasks.md`/`specs/**`), and `dev-skills` stays unaware of
     spec-flow's own file conventions.
   - A spec exists, **re-review** (the marker SHA differs from current HEAD) → same command, but
     add `--diff --base <the recorded SHA> --path openspec/changes/issue-<N>` — this scopes the
     view to an actual diff of just this change dir since the owner's last look, using
     `generate-explain.py`'s path-scoping (see its `SKILL.md`), rather than re-rendering the whole
     spec as if it were new. Still include `--change`/the two `--doc` flags too — the AC-coverage
     and overrides tables reflect the CURRENT state, not a diff, since those are conclusions to
     re-check as a whole, not line-by-line deltas.
   - No spec (content-only `type:docs`, or `type:tech-debt`) → there's no change dir to point at,
     so first write the branch's own rendered substance (scope + acceptance criteria, or Direction +
     adjacent-behavior list) to `.spec-flow/seam1-review.md` inside the worktree (gitignored, same
     entry every worktree already inherits), then `"$EXPLAIN_ROOT/skills/explain/scripts/
     generate-explain.py" --issue <N> --doc .spec-flow/seam1-review.md --title "issue-<N>"
     --subtitle "<issue title>" --out <path>`.
   Neither branch passes `--diff` — there's no code change to show at this seam, only the spec/scope
   and the issue itself. Either way: never pass `--open` (this is a background session — see the
   display constraint in `dev-skills`'s own `skills/explain/SKILL.md`); tell the owner the view's
   absolute path plus
   the printed `open <path>` line, and still state plainly that nothing will be implemented until
   they approve — the explain view satisfies "render the spec at the seam," it doesn't relax the
   approval gate itself.

   **For a content-only `type:docs` issue**
   (step 5 decided no spec is needed, so step 6's commit never ran) render the issue's own scope +
   acceptance criteria instead of a spec — it was already scoped once at `groom`, so this is a
   quick confirmation, not a first
   read — then mark spec-review the same way:
   ```bash
   gh issue edit <N> --remove-label status:ready --add-label status:spec-review
   gh issue comment <N> --body "📝 Content-only docs change — no spec, ready for a quick review of the plan."
   ```
   State plainly that nothing will be written until they approve, same as the full form below, then
   skip the rest of this step (there's no spec to render) and go straight to the auto-approve
   paragraph.

   **For a `type:tech-debt` issue** (step 5's tech-debt branch — no spec, no step-6 commit), render
   instead: the issue's `## Direction` (as confirmed or corrected by step 3's architect brief), the
   `## Adjacent specified behavior (must be preserved)` section step 5 appended, and architect's
   risks/blast-radius from its brief. This is genuinely quick — the owner already confirmed this
   exact Direction, item by item, in `/tech-debt` (dev-skills); this stop exists to catch staleness and
   let them see the adjacent-behavior list before implementation starts, not to re-litigate the
   fix:
   ```bash
   gh issue edit <N> --remove-label status:ready --add-label status:spec-review
   gh issue comment <N> --body "📝 Tech-debt fix confirmed (\`type:tech-debt\`) — no spec; ready for a quick review before implementation."
   ```
   State plainly that nothing will be written until they approve, then skip the rest of this step
   and go straight to the auto-approve paragraph. **Otherwise** (a spec was generated — either a
   non-docs, non-tech-debt issue, or a structural/tech-accompanying `type:docs` one):
   ```bash
   gh issue edit <N> --remove-label status:ready --add-label status:spec-review
   gh issue comment <N> --body "📝 Spec committed (\`issue-<N>\`) — awaiting your review to approve implementation."
   ```
   **On a re-review** (per this step's opening check — the marker SHA differs from current HEAD),
   render differently: `git diff <the recorded SHA> HEAD -- openspec/changes/issue-<N>` and show
   only the sections that actually changed, explicitly noting what didn't (e.g. "proposal and tasks
   are unchanged from what you already saw; here's what changed in the design and specs") — never
   re-paste content the owner already reviewed once. The `ac-coverage.md`/`overrides.md` tables
   still render in full (current state, not a diff — see the `explain`-mode branch above for why).
   **On a fresh look or when nothing changed**, the rest of this paragraph is the full render:

   **Show the spec in the conversation — do NOT just point at the worktree path.** The owner
   reviews here, not in an editor. This is confirmation that step 5 faithfully translated the
   design already **chosen at step 4** into a concrete spec — not the first time the owner sees
   the decision. Render the substance inline: the **proposal** (why + what changes + scope), the
   **design the owner chose at step 4** — `design.md`'s `## Alternatives Considered` and (when
   present) `## Domain Facts` sections, verbatim, not re-narrated — so the owner can confirm this
   is still what they meant and see exactly what the architect actually said, not a compressed
   retelling of it, the **delta-spec requirements + their
   `#### Scenario:` blocks** (the testable contract), the **`ac-coverage.md` table** and
   **`overrides.md`** committed at step 5, both verbatim — render the actual files, not a fresh
   paraphrase of them, so what the owner reads here is exactly the durable artifacts, not a second,
   potentially-drifted retelling — so the owner can catch a dropped criterion, an unnoticed
   override of existing behavior, or a conflict with another in-flight change before approving, not
   after implementation — the **tasks** in order, including any folded-in
   structural-debt task from step 4 — and, if any nearby structural debt was recommended as a
   separate issue, a one-line reminder of its disposition (filed as `#<M>`, or left for later).
   Summarize faithfully — it must be enough to approve or redirect without opening a file. You may
   also give the path as a secondary reference, but the inline render is the deliverable. State
   that nothing will be implemented until they approve. **Do not proceed to implementation.** When
   the owner approves, the next step is `/spec-flow:implement <N>`.

   **For a structural/tech-accompanying `type:docs` issue** (steps 3/4 skipped), there's no step-4
   design to restate — omit that part of the render and show the rest as normal: proposal,
   requirements/scenarios, tasks, kept surface-level per step 5. (A **content-only** `type:docs`
   issue, or any `type:tech-debt` issue, never reaches this paragraph at all — both took a
   lightweight branch above instead.)

   **Unless `.spec-flow/owner-instructions` (read fresh at this point) explicitly says to
   auto-approve the spec for this run — and step 5's `overrides.md` didn't find a hard conflict**
   (same exception as step 4's hard dependency: a genuine hard conflict always stops here for the
   owner regardless of what this run's instructions say). If auto-approving, still render in full
   as above — the spec for a
   structural/tech-accompanying `type:docs` issue or any other, or the scope + acceptance criteria
   (or, for tech-debt, the Direction + adjacent-behavior list) for a content-only/tech-debt one —
   posted as a comment, not just shown inline, since there's no owner in the conversation to see it,
   so the decision is auditable after the fact, then proceed directly to `/spec-flow:implement <N>`
   yourself instead of waiting:
   `gh issue comment <N> --body "Spec auto-approved per this run's instructions — proceeding to implement."`
   (for a content-only docs issue, `"Docs plan auto-approved per this run's instructions —
   proceeding to implement."`; for a tech-debt issue, `"Tech-debt fix auto-approved per this run's
   instructions — proceeding to implement."`) Absent that explicit instruction, this stop always
   waits for the owner. Note this is a **separate** auto-approve gate from step 4's tech-debt
   auto-adopt above — step 4 auto-adopts *by default*, unconditionally; this one (Seam 1 itself)
   still needs an explicit `.spec-flow/owner-instructions` opt-in, same as every other issue.

   **Handling a redirect — capture it as a structured record, not just a reaction.** When the owner
   objects instead of approving, don't just regenerate from a fresh read of their chat message —
   append a durable entry to `.spec-flow/seam1-feedback.md` in the worktree (gitignored, same
   category as `.spec-flow/owner-instructions`; **append, never overwrite** — this is a running
   history across possibly several redirects) before touching anything:
   ```markdown
   ## Redirect — HEAD was <sha from `git rev-parse HEAD` right now>
   **Targeting:** <capability>/spec.md — Requirement: <title>  (or "(whole change)" if it's not
   about one specific requirement)
   **Owner said:** "<their objection, close to verbatim>"
   ```
   Reference the SAME requirement identifiers `ac-coverage.md` and `overrides.md` already use, so
   all three files stay cross-referenceable. Then go back to step 5: **read
   `.spec-flow/seam1-feedback.md` first**, if it exists, before regenerating anything, and treat
   every entry as a concrete item to address — not a vague prompt to reinterpret from memory. This
   is what makes a redirect survive a crashed/resumed session (chat context can be lost; a file
   can't) and keeps a *second* redirect on the same requirement precise instead of the model
   re-deriving "what did they mean" from scratch each time. Once addressed, continue through steps
   5–7 again as normal — regenerate, re-validate, rebuild `ac-coverage.md`/`overrides.md`, re-render
   (as a **re-review**, per this step's opening check, so the owner sees a diff, not the whole spec
   again).

## Rules

- **Show, don't link.** At either stop, render inline in the conversation; never hand back only a
  file path and expect the owner to open it. The owner is not in an editor.
- **Two real stops, in order, by default.** Step 4 (design choice) always precedes step 5
  (generation) — never generate the spec before the owner has picked (or `.spec-flow/owner-instructions`
  auto-picked) among the architect's options. Step 7 (spec approval, Seam 1) always follows step 6
  (commit) — no implementation, no `/spec-flow:implement`, no pushing the branch, until both stops
  have passed or been explicitly auto-approved per that file's current contents. **Two structural
  exceptions**, each triggered by a distinct label — never combine, see the collision rule below:
  - **`type:docs`**: always skips step 4 (there's no design to choose) entirely, not just
    auto-approves it; a **content-only** one also skips the OpenSpec-generation portion of step 5
    and all of step 6 (no spec generated or committed — see step 5's docs branch).
  - **`type:tech-debt`**: step 4 still runs, but auto-adopts the confirmed Direction by default
    instead of waiting — a real (if narrower) safety check, not a full skip, and it still stops for
    a hard dependency, a material deviation, or infeasibility (see step 4's tech-debt branch); step
    5's OpenSpec-generation portion and all of step 6 are always skipped, unconditionally (see step
    5's tech-debt branch).
  Either way, step 7 (Seam 1) still always applies, in whichever lightweight form (spec, scope +
  acceptance criteria, or Direction + adjacent-behavior list) matches what was actually produced —
  neither exception ever removes Seam 1 itself.
- **`type:docs` and `type:tech-debt` never combine.** If an issue somehow carries both (hand-edited
  in GitHub — `/tech-debt` (dev-skills) and `groom` each only ever apply one), don't silently pick
  either fast path: say so to the owner and fall back to the full pipeline (design stop + real
  spec) — the safer default when the labeling itself is ambiguous about what kind of change this
  actually is.
- Worktree managed by Claude Code's own `EnterWorktree` isolation, scoped to *this session's*
  life — not something this skill creates by hand, and not the Agent tool's throwaway `isolation:
  "worktree"`. Named `issue-<N>` explicitly (both the spawn prompt and step 2's fallback pass that
  as `EnterWorktree`'s `name`) — deterministic, matching the OpenSpec change (when one exists — see
  below) and PR-body correlator, and it's what makes a fresh spawn resume an existing-but-untracked
  worktree automatically instead of duplicating it (confirmed by test). It's only guaranteed to be
  where you're standing if step 2 actually confirmed it; isolation doesn't happen for free. That
  isolation is per-**session**, not per-issue on its own — it's `scripts/spawn-issue-pm.sh`
  respawning a past session by name instead of always starting fresh, plus the worktree name itself
  now being deterministic, that keeps this issue to one worktree in practice (see **Coordination
  signals** in `docs/workflow.md`). The issue number is the one thing that matters for finding
  anything — `Closes #N` in the PR body (added at `implement`) is the durable correlator for the
  PR regardless — see **Naming** in `docs/workflow.md`.
- One change per issue, named `issue-<N>` — deterministic, never derived from the title. **Not
  every issue gets one** — a content-only `type:docs` issue, or any `type:tech-debt` issue (step 5),
  generates no OpenSpec change at all, by design; don't treat its absence as a skipped step.
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
