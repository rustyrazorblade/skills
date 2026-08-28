---
name: adopt-tiering
description: One-time migration that splits a repo's existing test suite into a fast unit tier and a slow integration tier — for a repo whose own spec-flow/CI.md policy chooses that split, not an assumption the pipeline makes. Classify tests by evidence (container/I-O/timing) and let the compiler + test timings arbitrate, physically separate them (Gradle source set + classpath scoping, or Rust src/ vs tests/ + nextest profiles), wire the CI failures artifact, and open a PR. Run once per repo. See docs/workflow.md ("Test policy"). Never merges.
argument-hint: [optional notes; run from inside the target repo]
---

# adopt-tiering — split an existing suite into unit / integration tiers

You are the PM/lead in the main session. Bring a repo that does **not** yet separate fast unit tests
from slow integration tests onto that split (see **Test policy** in `docs/workflow.md`). This is a
**one-time migration per repo**, and it applies only where the repo's own `spec-flow/CI.md` chooses
the tiered policy. spec-flow assumes no split and ships no runtime default, so that file is the
whole of the policy. Check it first, and say so plainly if it points somewhere else. The migration
produces one review-ready PR and **never merges**.

This is repo **infrastructure**, not a feature — so it is **not** tied to a GitHub issue and does
**not** go through `groom → activate → implement`. Move into a dedicated worktree using Claude
Code's own isolation rather than creating one by hand — call the `EnterWorktree` tool (or simply
ask to "work in a worktree") with a name like `adopt-test-tiering`. All work happens inside that
worktree from here on; its branch name is whatever Claude Code assigns, not something this skill
picks — that's fine, this migration isn't correlated back to anything by branch name the way an
issue's work is.

## Why the split has to be structural

The tiering model only holds if the boundary is enforced, not conventional: the unit tier must be
fast **by construction** (no container, no I/O), so a container test must be *unable* to live in it.
For Gradle that means classpath scoping (Testcontainers/JDBC only on the integration source set);
for Rust it means integration tests live in `tests/` binaries the unit `default-filter` excludes.

## Steps

1. **Detect the runner and current layout.**
   - **Gradle** — `build.gradle.kts`/`build.gradle`, `src/test`. Already tiered if a
     `src/integrationTest` source set / `integrationTest` JVM Test Suite exists.
   - **Rust** — `Cargo.toml`; unit tests in `src/**`, integration in `tests/**`. Already tiered if
     `.config/nextest.toml` defines the tier `default-filter`s (see `references/ci/`).
   If the repo is **already tiered**, say so and stop. In a partially-tiered repo, handle only what's
   still mixed — this skill is **idempotent**.

2. **Classify the existing tests — delegate to the `architect` agent, then let the tooling arbitrate.**
   Static tells give the first cut → integration tier: Testcontainers (`GenericContainer`,
   `@Testcontainers`), JDBC / DB drivers / a real `DataSource`, real sockets / HTTP clients,
   filesystem I/O, process spawning, Docker — anything needing a live external dependency. But you do
   **not** have to get this perfect from static analysis, because two mechanical checks arbitrate and
   make a misclassification either way recoverable:
   - **Compilation is the enforcer.** Once container/JDBC/network deps are scoped to the integration
     source set only (step 4), a dep-requiring test left in the unit tier **won't compile** — it fails
     loudly, it cannot silently sit there. Use this: attempt the split, and let unit-tier compile
     failures reclassify those tests to integration.
   - **Test timings catch the rest.** A test that is slow but *compiles* (heavy pure computation,
     allowed local I/O) shows up in the runner's test-time report; move the slow outliers to
     integration.
   So classify from the tells, then **verify with the compiler and the timings** — don't agonize over
   the static pass. A genuinely ambiguous test can go to unit and be corrected by a compile error /
   its timing, or to integration and be pulled back by CI → `/spec-flow:sync-ci`; both directions are
   recoverable. The architect returns a proposed assignment: each test → `unit | integration`, plus
   the tell that decided it.

3. **Present the plan to the owner — before moving anything.** Show the proposed split: the
   integration-bound tests with the tell for each, and every ambiguous case. This is a large,
   mechanical change; let the owner adjust the classification before any file moves.

4. **Execute the split — delegate to `tdd-developer` / `build-engineer`.**
   - **Gradle** — create the `integrationTest` source set (JVM Test Suite plugin on Gradle 7.3+, or a
     hand-rolled source set + task below it); move the integration-classified tests to
     `src/integrationTest/…`; move Testcontainers/JDBC/network deps to `integrationTestImplementation`
     **only** (so a container test can't compile under `src/test`); wire `check` to depend on
     `integrationTest`. Keep `./gradlew test` (unit) and `./gradlew check` (all) green.
   - **Rust** — ensure integration-classified tests live in `tests/` binaries (move out of `src/`
     unit modules where needed); add `.config/nextest.toml`:
     ```toml
     [profile.default]   # fast local tier
     default-filter = "not (kind(test) or package(integration-tests))"
     [profile.ci]        # full suite
     default-filter = "all()"
     ```
     Confirm `cargo nextest run` (unit) and `cargo nextest run --profile ci --run-ignored all` (all)
     pass. Match the repo's conventions; commit in focused steps.

5. **Wire CI to the contract.** Copy the matching template from
   `${CLAUDE_PLUGIN_ROOT}/references/ci/` (`github-actions-gradle.yml` or `github-actions-nextest.yml`)
   into `.github/workflows/`, adjusting toolchain versions and any service containers the integration
   tier needs. This makes CI run the full suite and upload the `spec-flow-failures` artifact that
   `/spec-flow:sync-ci` consumes.

6. **Gitignore the flagged set.** Add `.spec-flow/` to `.gitignore` if absent — the local flagged set
   must never commit.

7. **Open the PR — never merge.** Push the branch and open a PR summarizing: unit vs integration
   counts, the tells used, anything the owner overrode, and the CI wiring added. Call out two
   **manual owner follow-ups**. This skill performs neither:
   - **Enable branch protection so merge is gated on green CI** — the invariant the whole tiering
     model relies on, and something this skill cannot reliably set itself.
   - **Restate the split in the repo's own `spec-flow/CI.md`.** That file is the whole of the
     policy, and every implementation and review agent reads it on every run. Its choice of tiering
     is what let this migration run, but it was written before the tiers existed. Where it still
     names the pre-split commands, the pipeline reads a policy the repo no longer matches.

8. **Exit the worktree.** Call `ExitWorktree` with `action: "keep"` once the PR is up — `"remove"`
   would delete the branch backing the still-open PR from step 7. You're the central coordinator's
   own session, not a per-issue one meant to live in a worktree indefinitely; don't stay parked in
   this migration's worktree once the work is handed off, but the worktree/branch themselves stay
   on disk until the PR merges.

## Rules

- **One-time, per repo; idempotent.** Safe to re-run on a partially-tiered repo — only move what's
  still mixed.
- **Let the tooling arbitrate; don't agonize over the static pass.** Scope deps so container tests
  can't *compile* under the unit tier, then let compile failures and the runner's test-time report
  place tests correctly. Misclassification is recoverable either way — unit-side by a compile error
  or the timings, integration-side by CI → `/spec-flow:sync-ci`.
- **Structural, not conventional.** For Gradle, scope deps so a container test can't *compile* under
  `src/test` — not merely move files.
- **Classify → present → execute.** Show the owner the split before moving files.
- **Never merge; open a PR.** Enabling the green-CI merge gate (branch protection) and restating
  the split in the repo's `spec-flow/CI.md` are the owner's manual steps — always call both out.
