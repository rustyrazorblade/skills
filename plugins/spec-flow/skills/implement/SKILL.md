---
name: implement
description: Implement an approved issue — run tdd-developer → 5-lens review panel → fix loop → build-engineer → docs polish in the issue's own worktree, then push the branch and open a PR. Defaults to an agent team led by issue-pm (SPEC_FLOW_IMPLEMENT_MODE=team, requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1); falls back automatically, or via SPEC_FLOW_IMPLEMENT_MODE=workflow, to the original Workflow-tool script. A type:docs issue instead runs a single lightweight doc-writing pass with architect available on demand, skipping the review panel/build/polish entirely. A type:tech-debt issue runs the full review panel as normal (behavior-preservation mode, no spec) but works from the issue's own Direction instead of tasks.md, and opens its own draft PR after the first commit since none exists yet. Third stage of the flow delivery workflow (see docs/workflow.md). Requires the owner to have approved the plan first — a committed spec, or for a content-only type:docs/type:tech-debt issue, its scope + acceptance criteria (or Direction). Invoking this skill is the explicit opt-in to that orchestration, whichever mode.
argument-hint: [issue number, with its plan already approved]
---

# implement — build the approved spec, open a PR

You are this issue's `issue-pm`, running as your own dedicated background session. The owner has
**approved the plan** for issue `#N` — a committed spec, or for a content-only `type:docs` issue,
its scope + acceptance criteria, or for a `type:tech-debt` issue, its confirmed Direction (see Input
below). Drive the implementation team to completion and
open a review-ready PR — by default as an **agent team** you lead (see step 4), which is exactly
what running as your own top-level session (not a subagent) makes possible at all: a team needs a
lead, only a top-level session can be one, and a subagent can never spawn its own team. Where
agent teams aren't available or wanted, the same work runs instead as the original `Workflow`-tool
script — same five lenses, same rules, no team. **Invoking this skill is the owner's explicit
opt-in** to that orchestration, whichever mode it resolves to.

Input: an issue number `#N`, normally with an OpenSpec change `issue-<N>` — deterministic, from
`activate`. You're already running inside this issue's worktree — Claude Code's own
background-session isolation put you there, on whatever branch it assigned; resolve it with `git
rev-parse --abbrev-ref HEAD` rather than assuming a name. If `openspec/changes/issue-<N>` isn't
there: for a `type:docs` issue this is expected (a content-only docs change generates no spec —
see step 4's docs fast path); for a `type:tech-debt` issue this is **always** expected — the fast
path never generates one (see step 4's tech-debt handling); otherwise, list `openspec/changes/`
(excluding `archive/`) and orient yourself in whatever is — it may predate this naming.

## Steps

1. **Confirm the precondition.** The issue must be `status:spec-review` AND the owner must have
   approved — either in the conversation, or, if `.spec-flow/owner-instructions` (read fresh here)
   explicitly auto-approved the spec/plan for this run, that counts too (the normal case when
   `activate` launched you directly per its own auto-approve path). If you can't confirm either,
   ask before proceeding. Flip the label to in-progress:
   ```bash
   gh issue edit <N> --remove-label status:spec-review --add-label status:in-progress
   ```

2. **Open a draft PR early — keep CI warm.** **Skip this step entirely if `openspec/changes/issue-<N>`
   doesn't exist AND the issue carries `type:docs` or `type:tech-debt`** — neither fast path commits
   a spec, so the branch has no commits ahead of the default branch yet and `gh pr create` would
   fail outright (GitHub rejects a PR with no diff). For `type:docs`, step 4c opens the PR itself,
   using this exact mechanics, right after its own first commit lands. For `type:tech-debt`, step
   4a's Implement teammate/agent makes the first commit — **you** (the lead) open the PR yourself,
   same mechanics, right after it reports back and before moving to step 4b's review panel, in Team
   mode; in Workflow mode the script's Implement-phase agent opens it itself (the one narrow
   exception to its own GUARDRAILS — see `implement.workflow.js`), since nothing outside the script
   regains control mid-run to do it the way the Team-mode lead can.
   (A missing `openspec/changes/issue-<N>` on an issue carrying **neither** label means something
   else — most likely a legacy change predating this naming; see the Input note above — not
   "nothing to push yet," so don't skip this step for that case.) **Otherwise** push the branch (it already
   carries the committed spec) and open a **draft** PR *now*, before
   implementation runs. CI triggers on `pull_request` and runs on draft PRs, so from here every
   checkpoint push during implementation exercises the full suite in parallel with local work — CI
   is the slow backstop the tiering model relies on, and this keeps it busy instead of idle until
   the end. **Re-running this skill is normal** (resuming after a crash, after residual findings, or
   after the owner sends you back) — check for an existing PR first and reuse it rather than
   erroring on a duplicate:
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   DEFAULT_BR=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   git -C <worktree> push -u origin "$BR"
   PR=$(gh pr list --head "$BR" --json number --jq '.[0].number // empty')
   if [ -z "$PR" ]; then
     gh pr create --draft --head "$BR" --base "$DEFAULT_BR" \
       --title "<issue title>" \
       --body "Closes #<N>

   Draft — implementation in progress. The unit tier runs locally; the full suite runs in CI on each push."
     PR=$(gh pr list --head "$BR" --json number --jq '.[0].number // empty')
     gh issue comment <N> --body "🚀 Draft PR #$PR opened — implementation starting."
   fi
   echo "DEFAULT_BR=$DEFAULT_BR"
   echo "PR=$PR"
   ```
   Steps 4/5 use `<DEFAULT_BR>` and `<PR>` as the literal values printed here, never as shell
   variables — variables don't survive separate Bash calls, and the `Workflow` tool's JSON `args`
   isn't shell-interpolated. Resolve `$DEFAULT_BR` from the repo, never assume `main`: it must
   match what `EnterWorktree` branched this worktree from.

3. **Test tiering — the local gate is the unit tier, not the full suite.** The team runs the fast
   **unit** tier locally (plus the branch's `.spec-flow/flagged-tests`, if any); the full/integration
   suite is CI's gate and is never run locally. See **Test tiering (unit / integration)** in
   `docs/workflow.md`. No stack probe, no full-vs-degraded decision — every teammate below just
   follows the instruction verbatim. If the repo hasn't split its tests into unit/integration tiers
   yet, the team runs the repo's default test command and says so; the tiering degrades gracefully.

   Every teammate you spawn below gets this **TEST INSTRUCTION** appended to its prompt whenever
   it runs tests:
   > Run the UNIT tier locally as your gate — the repo's fast, no-container / no-I/O unit tests,
   > i.e. the runner's default fast selection (e.g. `cargo nextest run`, `./gradlew test`,
   > `npm test`, `go test -short ./...`, `pytest -m 'not integration'`). ALSO run any tests listed
   > in `.spec-flow/flagged-tests` at the worktree root if that file exists (one runner-selectable
   > test id per line; `#` and blank lines ignored) — these are tests CI flagged on this branch,
   > guarded locally. Do NOT run the full/integration suite locally — that is CI's gate. State
   > plainly in your summary that the unit tier (plus any flagged tests) ran locally and the full
   > suite runs in CI. If the repo has not split its tests into unit/integration tiers yet, run its
   > default test command and say so.

4. **Resolve the implement mode, then drive Implement → Review → Fix (bounded) → Build → Polish.**

   **Docs fast path.** If the issue carries `type:docs` (set at `groom`, carried through
   `activate` — see **Docs fast path** in `docs/workflow.md`), skip everything else in this step —
   Team/Workflow mode, the five-lens panel, the fix loop, Build, Polish — entirely and run this
   instead. **Mode-independent**: it's one plain subagent spawn (the Agent tool, `tdd-developer`
   agent type, same mechanism `activate` step 3 uses for `architect`), not an agent-team teammate,
   so `SPEC_FLOW_IMPLEMENT_MODE`/`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` don't apply here.
   a. Spawn ONE `tdd-developer` subagent, in `<worktree>`. **Check for a spec first** —
      `ls openspec/changes/issue-<N> 2>/dev/null`: **present** (a structural/tech-accompanying
      `type:docs` issue, per `activate` step 5) → work `tasks.md`, updating exactly the
      documentation the spec describes. **Absent** (the common case — `activate` skipped spec
      generation for a content-only docs change) → work directly from the issue's own scope and
      acceptance criteria instead (`gh issue view <N> --json title,body`) — there is no `tasks.md`
      for this issue, and there won't be one; that's expected, not a sign something's missing.
      Either way: updating exactly the documentation described (README, a docs/mdBook tree,
      comments — no behavior change). Append the implementer GUARDRAILS (below). **If it hits a
      real question about whether the documentation matches the intended architecture/design**
      (not just wording), have it stop and report the specific question back to you rather than
      guessing — it should not try to reach `architect` itself.
   b. **If it reports back with an architecture question**, spawn `architect` yourself — read-only,
      same as `activate` step 3 — with that specific question, then spawn a **fresh**
      `tdd-developer` subagent with the answer plus everything from step a's prompt to finish the
      work (spawn fresh — plain subagents can't be resumed). Architect-on-demand, not a mandatory
      gate; most `type:docs` runs never trigger it.
   c. Once the docs pass reports done: **re-resolve `BR` fresh here** — `BR=$(git -C <worktree>
      rev-parse --abbrev-ref HEAD)` — variables from step 2's Bash call don't survive to this one,
      and step 2 may not have run at all on this path. **First confirm the branch is pushed** — the
      GUARDRAILS only say the teammate *may* push, not must, so `git -C <worktree> push -u origin
      "$BR"` yourself if it hasn't happened. **If step 2 was skipped** (no spec existed when this
      run started), open the draft PR now using step 2's *full* mechanics — including its
      existing-PR reuse check (`gh pr list --head "$BR" --json number`; only `gh pr create --draft`
      if none found), since this may be a re-run where 4c already opened it once — there's a real
      commit to open it against now. Then
      comment `gh issue comment <N> --body "📚 Docs updated."`, note a one-line summary of what was
      documented (step 5 uses it in place of `review_summary`), then go straight to step 5 — no
      review panel, no build step. A docs-only change has no code to lint/build/review through five
      lenses built for behavior.
   This is the ONLY thing that skips the five-lens panel — every other issue, however small, still
   goes through it in full. **A `type:tech-debt` issue does NOT take this docs branch** — it still
   needs real code review, so it goes through the normal Implement → Review → Fix → Build → Polish
   sequence below like any other issue; the only difference is what `CHANGE_PARAM` resolves to.
   Otherwise, for every non-`type:docs` issue:

   **Resolve `CHANGE_PARAM` before anything else in this step** (used in step 4a's Implement prompt
   and step 4b's identical review-panel prompt below, both modes): `ls openspec/changes/issue-<N>
   2>/dev/null`. **Present** → `CHANGE_PARAM = "issue-<N>"`, the normal case. **Absent** — only ever
   valid for a `type:tech-debt` issue (see the Input note above; any other issue with no change
   directory is the legacy-naming case, not this) — `CHANGE_PARAM = "none — type:tech-debt fast
   path"`, the literal sentinel `agents/reviewer.md` and `implement.workflow.js` both key off of to
   switch into behavior-preservation mode.

   `SPEC_FLOW_IMPLEMENT_MODE` — `team` (default) or `workflow`. `team` is an agent team led by
   you, spawned fresh each run — richer (teammates message each other, self-claim work) but
   experimental and token-heavier. `workflow` is the original bounded `Workflow`-tool script
   (`implement.workflow.js`) — the same five lenses and the same merge/approve/fix-loop rules,
   just scripted instead of reasoned through, for when agent teams aren't available or wanted. If
   the env var is unset or `team` and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is **not** set, fall
   back to `workflow` automatically and say so — don't fail the run over a missing opt-in flag.
   Then follow **either** "Team mode" **or** "Workflow mode" below, never both.

   **Team mode (default).** Every teammate is spawned from this plugin's own subagent definitions
   — reference them by name (`tdd-developer`, `reviewer`, `code-reviewer`, `security-reviewer`,
   `test-rigor-reviewer`, `observability-reviewer`, `build-engineer`) so each teammate gets that
   agent's tools/model, with your spawn prompt appended as additional instructions. **If a
   bare-name spawn fails "not found"**
   (no repo/user override registered under that name, and the plugin's own bundled agent isn't
   reachable by its bare name in this environment — Claude Code does not fall back to the plugin's
   namespaced form on its own), retry as `spec-flow:<name>` yourself; see the README's Override
   note and `implement.workflow.js`'s `agentNS()`, which applies this same fallback automatically
   in Workflow mode. Give every teammate a **GUARDRAILS** block —
   two variants, below — so none of them push to `main`, touch another issue, or take outward
   GitHub action; that's yours alone. `base` = `origin/<DEFAULT_BR>` — the literal branch name
   printed in step 2, not a shell variable (don't assume `main`); the review lenses diff
   `base...HEAD` in the worktree, so a wrong base reviews
   the wrong range. Track `tests_ran`, `spec_conformance`, `approve`, `review_rounds`,
   `residual_findings`, `non_blocking_findings`, and `review_summary` as you go — step 5's PR body
   needs them; there's no script returning them for you now.

   **GUARDRAILS (implementer teammates — tdd-developer, build-engineer):**
   > GUARDRAILS (strict): Operate ONLY inside the worktree, on the issue branch. You MAY `git
   > push` the issue branch to its own remote at checkpoints — usually so CI runs the full suite on
   > an already-open draft PR (push somewhat frequently — after a completed task or a few green
   > cycles — not on every commit); on your very first push there may be no PR yet (the lead opens
   > it right after), which is expected, not an error. Do NOT create or edit GitHub issues, do NOT
   > create/modify/mark-ready any PR yourself even if none exists yet — that's the lead's job, not
   > yours — do NOT post GitHub comments, do NOT push to `main` or any branch other than the issue
   > branch, and do NOT take any other outward or destructive action. If you discover follow-up
   > work, related bugs, or
   > candidate new issues, LIST them in your final report for the owner to triage — never file
   > them yourself. Backlog creation and prioritization are the owner's job, not yours.

   **REVIEW GUARDRAILS (review-lens teammates — everyone else in step b):**
   > GUARDRAILS (strict): You are reviewing, not implementing. Operate ONLY inside the worktree.
   > Running the repo's own format/lint/build/test commands to verify your findings is fine — the
   > `spec` lens needs that to honestly report `tests_ran`/`spec_conformance` (the other four
   > lenses leave those two fields as their own agent file directs) — but you may not change the
   > tree: do NOT commit, do NOT `git push`, do NOT create or edit GitHub issues, do NOT create/modify/mark-ready any PR,
   > do NOT post GitHub comments, and do NOT take any other outward or destructive action — your
   > output is the JSON review contract, nothing else. If you discover follow-up work, related
   > bugs, or candidate new issues, LIST them in your
   > findings/summary for the owner to triage — never file them yourself.

   a. **Implement.** Spawn one teammate, `tdd-developer`, named `implement`.

      **`CHANGE_PARAM = "issue-<N>"` (normal case):** work `tasks.md` test-first
      (RED→GREEN→REFACTOR) in `<worktree>`, honoring the repo's documented conventions (CLAUDE.md /
      CONTRIBUTING / style guide — TDD, SOLID, whatever hard rules the repo documents), marking each
      task `- [x]` as completed and committing with focused messages. Append the TEST INSTRUCTION
      (step 3) and the implementer GUARDRAILS. **Also instruct it to message you (the lead) at each
      checkpoint push**, naming which `tasks.md` item(s) it just completed — not only in its final
      report — so you can post a GitHub comment (`gh issue comment <N> --body "✅ Implement:
      <task(s)> done, pushed \`<sha>\`."`) for each one as it arrives, giving the owner a live trail
      instead of one comment at the very end.

      **`CHANGE_PARAM = "none — type:tech-debt fast path"`:** there is no `tasks.md` — work directly
      from the issue's own body instead (`gh issue view <N> --json title,body`): its `## Direction`
      is the shape of the fix, its `## Acceptance criteria` states the behavior-preservation bar
      explicitly, and its `## Adjacent specified behavior (must be preserved)` section (if present)
      names existing `openspec/specs/**` requirements this surface touches — don't contradict them.
      Implement exactly that Direction, test-first wherever you touch anything non-trivial. **This
      is behavior-preserving** — append this explicit instruction on top of the TEST INSTRUCTION:
      *"If achieving the Direction cleanly would require changing any observable behavior (a public
      signature, an error contract, CLI/config/serialized output, or an existing test's asserted
      behavior), STOP and report the specific behavior delta instead of implementing it — do not
      silently make the change."* Append the implementer GUARDRAILS as normal (this teammate does
      NOT open the PR itself — you do, right below, since Team mode's lead can).

      Either way: wait for it to report and mark its task complete before moving on — nothing else
      can start yet. **Then, only for the tech-debt case, if step 2 was skipped** (no PR yet — this
      is always true the first time through for a `type:tech-debt` issue): open the draft PR
      yourself now, using step 2's full mechanics (existing-PR reuse check included) — there's a
      real commit to open it against. Do this before moving to step b, so CI starts running while
      the panel reviews.

   b. **Review — five lenses, spawned together, every round.** Once Implement's task is complete,
      spawn all five teammates in one message so they run in parallel, each depending on
      Implement's task in the shared task list (so none can start early), each told to reply to
      you with **exactly** this JSON contract in its final message before marking its task
      complete — and nothing else:
      ```
      {"summary":"…","spec_conformance":"full|partial|failing","tests_ran":"full|unit|degraded|none",
       "findings":[{"id":"…","severity":"blocker|major|minor|nit","location":"…","rule":"…","problem":"…","fix":"…"}],
       "approve":true|false}
      ```
      Append the REVIEW GUARDRAILS to every one of these. The five, named `spec`, `code-review`,
      `security-review`, `test-rigor`, `observability`:

      All five are backed by this plugin's own agent definitions (`agents/reviewer.md`,
      `code-reviewer.md`, `security-reviewer.md`, `test-rigor-reviewer.md`,
      `observability-reviewer.md`). Spawning by that agent type already applies its full mandate,
      process, and output contract as the teammate's system prompt, so every spawn prompt below
      only supplies the concrete runtime values — restating the mandate here would just be a second
      copy that could drift from the agent file. `code-reviewer`/`security-reviewer` need Skill-tool
      access to invoke the built-in `/code-review`/`/security-review` skills, which their agent
      files grant by omitting a restrictive `tools:` line (unlike `reviewer`'s Read/Bash/Grep/Glob):

      Spawn each with the identical prompt — *"Panel mode. worktree: `<worktree>`. base: `<base>`.
      change: `<CHANGE_PARAM>`. issue: #N. Follow your agent definition's process and output
      contract exactly (JSON only)."* — `<CHANGE_PARAM>` is exactly the value resolved at the top of
      this step (`"issue-<N>"`, or the tech-debt sentinel), never hardcoded as `issue-<N>` — that
      sentinel is what switches `reviewer` into its behavior-preservation mode (see
      `agents/reviewer.md`'s "Tech-debt fast path mode"); the other four lenses just treat it as
      informational context, same as any other diff-review run. Only the teammate name and backing
      agent type vary otherwise:

      | Teammate | Agent |
      |---|---|
      | `spec` | `reviewer` |
      | `code-review` | `code-reviewer` |
      | `security-review` | `security-reviewer` |
      | `test-rigor` | `test-rigor-reviewer` |
      | `observability` | `observability-reviewer` |

   c. **Merge and gate.** Once every review task is complete — or a teammate goes idle without
      reporting, which counts exactly like a missing lens, never silently dropped from the vote —
      parse each teammate's JSON from its message to you. Merge `findings` across all five.
      **Before computing `mustFix`: any lens that reported `approve: false` with NO blocker/major
      finding among what it reported** (the spec lens can do this — it requires
      `spec_conformance: "full"` to approve, so a `"partial"` verdict alone sets `approve: false`
      with nothing to point at; a lens can also decline with only minor/nit findings, which is
      just as unexplained since those never enter `mustFix` on their own) —
      **synthesize a finding for it** so its non-approval has something to work from instead of
      silently reaching the round cap with no must-fix findings and no visible reason: `{id:
      "unexplained-<lens>", severity: "major", location: "(<lens> lens report)", rule:
      "unexplained-non-approval", problem: "<lens> lens returned approve=false with no findings
      (summary: <its summary>)", fix: "Re-review and either approve, or report a specific blocking
      finding."}`. Add these to `findings` alongside whatever each lens actually reported, THEN
      compute `mustFix` = every `blocker`/`major` finding (including synthesized ones). **Approve**
      only if every one of the five reported AND every `approve` is `true` AND `mustFix` is empty.
      Either way, post the round's result as a comment:
      `gh issue comment <N> --body "✅ Review panel approved (round <R>)."` or
      `gh issue comment <N> --body "🔁 Review round <R>: <M> must-fix finding(s), fixing…"`.

   d. **Fix — bounded, max 3 rounds.** Not approved and a round remains (start at round 1, cap at
      3): `mustFix` non-empty → message the `tdd-developer` teammate (respawn it, named `fix-N`,
      if it already shut down) with the consolidated `mustFix` list (severity, location, rule,
      problem, suggested fix for each), the TEST INSTRUCTION, and the implementer GUARDRAILS —
      resolve each, test-first where behavior changes, commit, push at checkpoints. Then go back
      to step b for a fresh review round. `mustFix` empty but a lens is simply missing → skip
      straight back to step b, nothing to fix yet. At round 3 with still no approval: stop,
      collect the outstanding `mustFix` findings (plus which lens(es) never reported) as
      **residual**, and skip straight to step 5 — do not run Build/Polish on a tree that's going
      through another round regardless.

   e. **Build** (only once approved). Spawn `build-engineer`, named `build`: get format/lint/build
      clean in `<worktree>` — *"Discover and run the repo's format, lint, and build steps
      (examples: Rust `cargo fmt` → `cargo clippy --all-targets -- -D warnings` → `cargo build`;
      Node the repo's lint+build scripts; Gradle `./gradlew spotlessApply build`; Go `gofmt -l .` →
      `go vet ./...` → `go build ./...` — use whatever the repo actually configures). Resolve
      formatting/lint/build issues WITHOUT changing behavior, commit, push. Return the final
      format/lint/build status."* Append the implementer GUARDRAILS. When it reports, comment:
      `gh issue comment <N> --body "🔧 Build clean."`.

   f. **Polish.** Spawn a `tdd-developer`-type teammate, named `polish`: *"Final documentation
      polish for OpenSpec change `issue-<N>` in `<worktree>`. Ensure new modules/behaviors are
      documented consistently with the repo's conventions (module/responsibility comments,
      architecture/index docs, doc comments on public items). If this change alters user-facing
      behavior (public API, CLI, config, how the service runs), update the repo's user-facing docs
      accordingly (README, a docs/ tree, an mdBook, a docs site) — keep pages/examples current. No
      user-facing docs or no user-facing surface → skip and say so. Documentation/comment edits
      only; commit, push. Return a one-line note on what you documented."* Append the implementer
      GUARDRAILS. When it reports, comment: `gh issue comment <N> --body "📚 Docs polished."`.

   g. **Shut down the team.** Once Build and Polish report back, ask every teammate still running
      to shut down — don't leave idle teammates running into step 5 or the owner's next round.

   If the panel never approved within the bounded loop, skip straight from step d to step 5 —
   no Build, no Polish. Shut down any teammates still running before you do (same as step g);
   leave the PR a draft and surface the residual findings to the owner.

   **Workflow mode (fallback).** Invoke the `Workflow` tool with the script bundled in this
   plugin and pass `args`:
   ```json
   {
     "scriptPath": "${CLAUDE_PLUGIN_ROOT}/skills/implement/implement.workflow.js",
     "args": {
       "worktree": "<abs path — $(git rev-parse --show-toplevel), Claude Code's own isolated checkout for this session>",
       "change":   "<CHANGE_PARAM — resolved at the top of this step: \"issue-<N>\", or the tech-debt sentinel>",
       "issue":    <N>,
       "base":     "origin/<DEFAULT_BR>",
       "buildSystem": "auto"
     }
   }
   ```
   The script runs the identical sequence as Team mode above — tdd-developer implements test-first
   → the same five-lens panel reviews the diff in parallel, each lens the same prompt and JSON
   contract as Team mode's step b → the same bounded (3-round) fix loop → build-engineer gets the
   build clean → docs polish — as a scripted `agent()`/`parallel()` loop instead of you reasoning
   through it as a team lead. It returns a summary object (`tests_ran`, `spec_conformance`,
   `approved`, `review_rounds`, `residual_findings`, `non_blocking_findings`, `review_summary`,
   `polish`) — use those fields directly for step 5, instead of the ones you tracked yourself in
   Team mode. `base`/`buildSystem` have the same meaning as Team mode's `base` and the Build
   step's hint.

   **Progress comments are coarser in this mode.** The script has no hook back out to you
   mid-run, so you only know what it did once it returns — you can't relay per-task or per-round
   comments the way Team mode does. When it returns, post one comment summarizing the whole
   pass: `gh issue comment <N> --body "✅ Implemented, reviewed (round <review_rounds>), and
   built — see PR for details."` (or, if `approved` is false, the residual findings instead). Say
   so plainly if the owner asks why this run's issue history is sparser than a Team-mode run's.

5. **Mark the PR ready and report.** When step 4 approved (either mode) or the docs fast path
   reported done (using its one-line summary from step 4c in place of
   `review_summary`/`tests_ran`/`non_blocking_findings` below), finalize the already-open draft PR
   (outward-facing — done here in this session, narrated). Re-resolve `$BR` fresh here — cheap, and
   this may be a separate Bash call from step 2's, which wouldn't have carried it over:
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   git -C <worktree> push origin "$BR"                     # ensure the final state is pushed
   gh pr ready <PR>                                        # un-draft — ready for your review (Seam 2)
   gh pr edit <PR> --body "Closes #<N>

   <the review_summary from step 4 (tracked yourself in Team mode, or the script's return value in Workflow mode), INCLUDING the note that the unit tier ran locally and the full suite runs in CI>

   <if non_blocking_findings is non-empty, a 'Surfaced, non-blocking' section listing each one — these never blocked approval but the owner should still see them at Seam 2>"
   gh issue edit <N> --remove-label status:in-progress --add-label status:in-review
   gh pr view <PR> --json url --jq .url
   ```
   Use the printed URL as `<PR_URL>` below — same convention as `<DEFAULT_BR>`/`<PR>` above,
   a literal value from this output, not a shell variable carried across separate Bash calls:
   ```bash
   gh issue comment <N> --body "👀 PR #<PR> ready for your review: <PR_URL>"
   ```
   **Always the full URL, never a bare PR number** — `<PR_URL>` resolved above, both in this
   comment and whenever you tell the owner directly (in this conversation, not just GitHub) that
   the PR is ready for review, further down in this step.
   Check whether to auto-merge — the `merge-on-green` label (checked fresh, not assumed) or
   `.spec-flow/owner-instructions` (also read fresh, not from memory of the spawn prompt) saying so:
   ```bash
   gh issue view <N> --json labels --jq '[.labels[].name] | any(. == "merge-on-green")'
   ```
   **If that printed `true`, or the file says so — don't stop here:**
   ```bash
   gh pr checks <PR> --required --watch
   ```
   `--required` scopes this to the PR's *required* status checks, not every check reported;
   `--watch` blocks until they finish and exits non-zero if any failed — treat a non-zero exit as
   a stop-and-surface-to-the-owner case, not a merge. **If it reports no required checks at all,
   don't conclude that immediately** — `gh` can't tell "nothing's configured" apart from "required
   checks are configured but haven't posted a check run yet" (e.g. right after this session's own
   push, before CI has started). Wait a short interval and re-check once before deciding; still
   none → **that's a configuration gap, not a green light** — refuse to auto-merge and tell the
   owner (e.g. "no required checks configured — configure branch protection for auto-merge to be
   safe, or merge this one manually"). Only once required checks are confirmed to have actually run
   and passed:
   ```bash
   gh pr merge <PR> --squash --delete-branch=false
   gh issue comment <N> --body "Merged automatically (merge-on-green, CI green)."
   ```
   and continue straight to `/spec-flow:finalize <N>` yourself — there's no review round to wait
   on. **Absent either trigger, this is always the stop:** give the owner the full PR URL
   (`<PR_URL>` resolved above — never just `#<PR>` or "the PR") for GitHub review (Seam 2) and
   wait. When they leave comments, the next step is `/spec-flow:address <N>`;
   after they squash-merge, `/spec-flow:finalize <N>`.

## Rules

- **Never merge, never push to `main` — by default.** This skill pushes only the issue branch,
  opens a *draft* PR, and later marks it ready. It merges on its own only when the `merge-on-green`
  label is set, or `.spec-flow/owner-instructions` explicitly said to — and even then only after
  the PR's required checks report green, via a squash-merge of that one PR — never a direct push
  to `main`.
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
