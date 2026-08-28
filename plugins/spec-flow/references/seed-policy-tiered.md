# Seeding template — the tiered policy

Read this only during seeding, and only after you have read the repo. It is one policy, for one
shape of repo. It is not a default, and nothing in the pipeline reads it.

**This policy fits a repo that meets all three of these conditions:**

1. The test suite is already split into a fast tier and a slow tier, and the split is structural —
   the build enforces it, so a slow test cannot run in the fast tier.
2. CI runs the tests.
3. Merge is gated on green CI.

**If the repo fails any one of them, close this file.** Write the policy from what the repo
actually does. A repo with no test suite, or with CI that runs no tests, has a first-class policy
of its own; it is not a repo waiting to be brought onto this one.

Condition 1 asks for a structural split, and some runners select the fast tier by a tag or a flag
rather than by where the test lives. Where the repo does that, write into the seeded file the
mechanism that keeps a slow test out of the fast tier; a convention alone does not enforce the
boundary the body below states.

This is the policy spec-flow used to hardcode in five places. Hardcoding it was the defect that
issue 50 fixed: test policy is shaped by each repo's CI cost, suite size, stack, and merge gate, so
one policy shipped for every repo is wrong somewhere by construction.

**Nothing reads this file at runtime.** The pipeline reads the repo's own `spec-flow/CI.md` and
nothing else. If that file is absent, the check exits non-zero and the pipeline stops. It does not
fall back here.

<!-- Everything above this line is for the seeding agent. The repo's file starts below. Copy from the next line down, adjust it to the repo, and never carry this notice or the notes above it into the repo's file. The seeded file names only this repo's own commands, so the per-runner example lists below collapse to the one runner the repo actually uses. -->

# Test and CI policy

**This repo owns this file.** spec-flow reads it and ships no default of its own; if this file
goes away, the pipeline stops rather than falling back to anything. Every line below is yours to
change, including the local/CI split itself.

Keep it short. Every implementation and review agent reads it on every run.

## What this repo is

This repo separates its tests into two tiers, structurally:

- **unit** — fast, no container, no I/O. The runner selects it by default.
- **integration** — slow, needs a live dependency: a container, a database, a socket, the
  filesystem, another process.

The boundary is enforced by the build, not by convention. An integration test cannot compile or
run inside the unit tier.

## The local gate

Run the **unit** tier, and only the unit tier. It runs on **every** TDD cycle, so keep it fast.
The command is the runner's default fast selection. Examples, per runner:

- **Gradle** — `./gradlew test`.
- **cargo nextest** — `cargo nextest run`.
- **Go** — `go test -short ./...`.
- **pytest** — `pytest -m 'not integration'`.
- **npm** — `npm test`.

Also run any test id listed in `.spec-flow/flagged-tests` at the worktree root, when that file
exists. Those are tests CI caught on this branch, guarded locally for the rest of it.

**Do not run the integration tier locally.** That is CI's gate, not yours. Waiting on it here costs
the fast loop the speed the split exists to buy.

## CI

CI **is** a test gate here. It runs the full suite — both tiers — on every pushed increment.
Examples, per runner:

- **Gradle** — `./gradlew check`, with `integrationTest` wired into `check`.
- **cargo nextest** — `cargo nextest run --profile ci --run-ignored all`.

On a red run, CI uploads the failing test ids as an artifact named `spec-flow-failures`, one
runner-selectable id per line. `/spec-flow:sync-ci` pulls that artifact into the branch's
`.spec-flow/flagged-tests`, so the local loop guards the same break for the rest of the branch.

## What gates merge

Green CI, through branch protection, plus the owner's review. A branch is cut from a green default
branch, so any CI failure on it is a regression the branch introduced.

## Push cadence

Open the draft PR early and push the issue branch at checkpoints — after a completed task group, or
a few working commits. Not on every commit. CI then runs the full suite alongside the local loop
instead of once at the end.
