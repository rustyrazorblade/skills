---
name: implement
description: Implement an approved issue — run tdd-developer → 5-lens review panel → fix loop → build-engineer → docs polish in the issue's own worktree, then push the branch and open a PR. Defaults to an agent team led by issue-pm (SPEC_FLOW_IMPLEMENT_MODE=team, requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1); falls back automatically, or via SPEC_FLOW_IMPLEMENT_MODE=workflow, to the original Workflow-tool script. Third stage of the flow delivery workflow (see docs/workflow.md). Requires the owner to have approved the committed spec first. Invoking this skill is the explicit opt-in to that orchestration, whichever mode.
argument-hint: [issue number, with its spec already approved]
---

# implement — build the approved spec, open a PR

You are this issue's `issue-pm`, running as your own dedicated background session. The owner has
**approved the committed spec** for issue `#N`. Drive the implementation team to completion and
open a review-ready PR — by default as an **agent team** you lead (see step 4), which is exactly
what running as your own top-level session (not a subagent) makes possible at all: a team needs a
lead, only a top-level session can be one, and a subagent can never spawn its own team. Where
agent teams aren't available or wanted, the same work runs instead as the original `Workflow`-tool
script — same five lenses, same rules, no team. **Invoking this skill is the owner's explicit
opt-in** to that orchestration, whichever mode it resolves to.

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
   `SPEC_FLOW_IMPLEMENT_MODE` — `team` (default) or `workflow`. `team` is an agent team led by
   you, spawned fresh each run — richer (teammates message each other, self-claim work) but
   experimental and token-heavier. `workflow` is the original bounded `Workflow`-tool script
   (`implement.workflow.js`) — the same five lenses and the same merge/approve/fix-loop rules,
   just scripted instead of reasoned through, for when agent teams aren't available or wanted. If
   the env var is unset or `team` and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is **not** set, fall
   back to `workflow` automatically and say so — don't fail the run over a missing opt-in flag.
   Then follow **either** "Team mode" **or** "Workflow mode" below, never both.

   **Team mode (default).** Every teammate is spawned from this plugin's own subagent definitions
   — reference them by name
   (`tdd-developer`, `reviewer`, `test-rigor-reviewer`, `observability-reviewer`, `build-engineer`,
   or the built-in `general-purpose`) so each teammate gets that agent's tools/model, with your
   spawn prompt appended as additional instructions. Give every teammate a **GUARDRAILS** block —
   two variants, below — so none of them push to `main`, touch another issue, or take outward
   GitHub action; that's yours alone. `base` = `origin/main` (or whatever `activate` actually
   branched from — same substitution caveat as step 2's `--base`); the review lenses diff
   `base...HEAD` in the worktree, so a wrong base reviews the wrong range. Track `tests_ran`,
   `spec_conformance`, `approve`, `review_rounds`, `residual_findings`, and `non_blocking_findings`
   as you go — step 5's PR body needs them; there's no script returning them for you now.

   **GUARDRAILS (implementer teammates — tdd-developer, build-engineer):**
   > GUARDRAILS (strict): Operate ONLY inside the worktree, on the issue branch. You MAY `git
   > push` the issue branch to its own remote at checkpoints so CI runs the full suite on the
   > already-open draft PR (push somewhat frequently — after a completed task or a few green
   > cycles — not on every commit). Do NOT create or edit GitHub issues, do NOT create/modify/
   > mark-ready any PR (it is already open as a draft — leave it draft), do NOT post GitHub
   > comments, do NOT push to `main` or any branch other than the issue branch, and do NOT take
   > any other outward or destructive action. If you discover follow-up work, related bugs, or
   > candidate new issues, LIST them in your final report for the owner to triage — never file
   > them yourself. Backlog creation and prioritization are the owner's job, not yours.

   **REVIEW GUARDRAILS (review-lens teammates — everyone else in step b):**
   > GUARDRAILS (strict, READ-ONLY): You are reviewing, not implementing. Operate ONLY inside the
   > worktree, read-only. Do NOT commit, do NOT `git push`, do NOT create or edit GitHub issues, do
   > NOT create/modify/mark-ready any PR, do NOT post GitHub comments, and do NOT take any other
   > outward or destructive action — your output is the JSON review contract, nothing else. If you
   > discover follow-up work, related bugs, or candidate new issues, LIST them in your
   > findings/summary for the owner to triage — never file them yourself.

   a. **Implement.** Spawn one teammate, `tdd-developer`, named `implement`: work `tasks.md`
      test-first (RED→GREEN→REFACTOR) in `<worktree>`, honoring the repo's documented conventions
      (CLAUDE.md / CONTRIBUTING / style guide — TDD, SOLID, whatever hard rules the repo
      documents), marking each task `- [x]` as completed and committing with focused messages.
      Append the TEST INSTRUCTION (step 3) and the implementer GUARDRAILS. Wait for it to report
      and mark its task complete before moving on — nothing else can start yet.

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

      - **`spec`** (agent: `reviewer`) — *"Review the implementation of OpenSpec change `issue-<N>`
        for issue #N. worktree: `<worktree>`. base: `<base>`. Diff is `base...HEAD` in that
        worktree. Follow your output contract exactly (JSON only). ALSO enforce spec-scenario →
        test traceability: enumerate every `#### Scenario:` in the change's `specs/**/spec.md`,
        map each to the diff's test(s), and emit a `major` finding (rule `scenario→test
        traceability`, location = the spec file + scenario name) for EVERY scenario with no
        backing test — one finding per uncovered scenario, no nitpick spray. A `major` finding
        withholds approval and feeds the fix loop. You MAY add a one-line scenario-coverage
        summary to `summary`."*
      - **`code-review`** (agent: `general-purpose`) — *"Run a CORRECTNESS review of the diff
        `base...HEAD` in the git worktree at `<worktree>`. Invoke the built-in `/code-review`
        skill on that diff (cwd `<worktree>`) and have it hunt correctness defects ONLY: logic
        errors, off-by-one / boundary / edge-case mistakes, unhandled error paths, panics / unwrap
        on fallible values, incorrect concurrency or async ordering, resource leaks, and contract
        violations between caller and callee. Do NOT re-review spec conformance or style — the
        other lenses own those. If you find no correctness defect, return `approve=true` with an
        empty findings array. Map the skill's result into exactly the JSON contract above and
        output nothing else (leave `spec_conformance`/`tests_ran` `"full"` — the spec lens owns
        them; a blocker/major finding MUST set `approve=false`). If `/code-review` isn't invokable
        here, perform the same correctness pass yourself by reading the diff and emit the
        identical contract."*
      - **`security-review`** (agent: `general-purpose`) — *"Run a SECURITY review of the diff
        `base...HEAD` in the git worktree at `<worktree>`. Invoke the built-in `/security-review`
        skill on that diff (cwd `<worktree>`). This lens SELF-GATES: first enumerate whether the
        change touches ANY of (1) input parsing / untrusted-input handling, (2) multi-tenant
        isolation / cross-tenant data access, (3) authentication or authorization, (4) external
        endpoints / network surfaces, (5) secrets, credentials, or sensitive-data exposure. Touches
        none → `approve=true`, empty findings, say so in `summary`. Touches one or more → review
        for missing/weak input validation, injection (SQL/CQL/command/log), tenant-isolation
        bypass, broken authz, unsafe external calls, leaked secrets/data; emit a blocker/major
        finding for any real exposure. Map into exactly the JSON contract above (same
        `spec_conformance`/`tests_ran`/`approve` rules as `code-review`). If `/security-review`
        isn't invokable here, perform the same pass yourself and emit the identical contract."*
      - **`test-rigor`** (agent: `test-rigor-reviewer`) — *"Audit TEST RIGOR for the diff
        `base...HEAD` in the git worktree at `<worktree>` (change `issue-<N>`, issue #N). Scope to
        the public surface the diff adds/changes (HTTP/gRPC API, CLI, library/public API) and any
        observable side effects (emitted events, DB writes, published messages, files). For each,
        judge whether the tests would FAIL on a regression, not merely exercise the happy path.
        Flag (rule `test-rigor`) any missing antagonistic case: malformed/oversized/wrong-type
        input, boundary/limit, error-contract honesty, concurrency conflicts, auth/tenant isolation
        where applicable, already-exists/not-found, idempotency/replay. Flag (rule
        `side-effect-coverage`) any write/op whose tests assert the direct result but not its
        observable side effect. A happy-path-only surface, or one with no side-effect assertion, is
        a `major` gap. ALSO run the brake, the other direction: flag (rule `over-testing`)
        over-built tests — a fake reconstructing a well-tested dependency, a test that only
        re-verifies a library/framework, trivial-glue tests, pure duplicates — and (rule
        `test-practicality`) avoidable test-infrastructure churn (a Testcontainers test restarting
        a container per test where shared/reused would do). These default to `minor`
        (surfaced, non-blocking); escalate to `major` only for egregious, objective waste — this
        brake is for high-confidence waste, not taste. If the diff touches no public surface,
        observable side effect, or tests, `approve=true`, empty findings. `spec_conformance`/
        `tests_ran` stay `"full"`."*
      - **`observability`** (agent: `observability-reviewer`) — *"Audit OBSERVABILITY for the diff
        `base...HEAD` in the git worktree at `<worktree>` (change `issue-<N>`, issue #N). First
        learn the repo's existing observability stack and judge against THAT, not a foreign one.
        Scope to new code paths and failure modes: new operations, new I/O, new error/Result/
        exception branches, new async/concurrent work. Flag (rule `observability`): a significant
        path/transition with no log at an appropriate level; a log missing structured context
        (id/operation/outcome); a new failure branch swallowed/mapped-away with NO telemetry (lean
        blocker); a new SLI-relevant operation or failure class with no metric, or unbounded label
        cardinality; new I/O with no span/trace coverage or dropped context propagation across new
        async boundaries; any secret/credential/PII emitted to logs/spans/metrics (blocker). A
        silently-swallowed failure or logged secret is `blocker`; a new operation/error path with
        no telemetry where the repo's conventions expect one is `major`. If the diff introduces no
        new code path, I/O, or failure mode, `approve=true`, empty findings. `spec_conformance`/
        `tests_ran` stay `"full"`."*

   c. **Merge and gate.** Once every review task is complete — or a teammate goes idle without
      reporting, which counts exactly like a missing lens, never silently dropped from the vote —
      parse each teammate's JSON from its message to you. Merge `findings` across all five.
      `mustFix` = every `blocker`/`major` finding. **Approve** only if every one of the five
      reported AND every `approve` is `true` AND `mustFix` is empty.

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
      format/lint/build status."* Append the implementer GUARDRAILS.

   f. **Polish.** Spawn a `tdd-developer`-type teammate, named `polish`: *"Final documentation
      polish for OpenSpec change `issue-<N>` in `<worktree>`. Ensure new modules/behaviors are
      documented consistently with the repo's conventions (module/responsibility comments,
      architecture/index docs, doc comments on public items). If this change alters user-facing
      behavior (public API, CLI, config, how the service runs), update the repo's user-facing docs
      accordingly (README, a docs/ tree, an mdBook, a docs site) — keep pages/examples current. No
      user-facing docs or no user-facing surface → skip and say so. Documentation/comment edits
      only; commit, push. Return a one-line note on what you documented."* Append the implementer
      GUARDRAILS.

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
       "repoRoot": "<abs repo root>",
       "change":   "issue-<N>",
       "issue":    <N>,
       "base":     "origin/main",
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

5. **Mark the PR ready and report.** When step 4 approved (either mode), finalize the already-open
   draft PR (outward-facing — done here in this session, narrated):
   ```bash
   git -C <worktree> push origin "$BR"                     # ensure the final state is pushed
   gh pr ready <PR>                                        # un-draft — ready for your review (Seam 2)
   gh pr edit <PR> --body "Closes #<N>

   <the review_summary from step 4 (tracked yourself in Team mode, or the script's return value in Workflow mode), INCLUDING the note that the unit tier ran locally and the full suite runs in CI>

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
