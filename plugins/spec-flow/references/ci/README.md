# CI contract for spec-flow test tiering

`/spec-flow:sync-ci` pulls CI test failures into a branch's local **flagged set** (see
`docs/workflow.md`, "Test tiering (unit / integration)"). For that to work, the consuming repo's CI
must honor one contract:

**On test failure, upload the failing test ids as an artifact named `spec-flow-failures`** — a single
text file, one runner-selectable test id per line.

| Runner | Id form | Re-run one locally |
|---|---|---|
| Gradle | `com.example.FooTest.methodName` | `./gradlew integrationTest --tests 'com.example.FooTest.methodName'` |
| cargo nextest | the test's full path (e.g. `mod::sub::test_name`) | `cargo nextest run --ignore-default-filter --run-ignored all -E 'test(=mod::sub::test_name)'` |

Also required: **merge is gated on green CI** (branch protection — the tests check must pass before
merge). This is the invariant that makes the flagged set's blind-append safe: on a branch cut from a
green `main`, any CI failure is a real regression the diff introduced, never a pre-existing one.

## Templates

- `github-actions-gradle.yml` — runs `./gradlew check` (wire `integrationTest` into `check` so the
  integration tier runs in CI), parses JUnit XML under `build/test-results/`, uploads
  `spec-flow-failures` on failure. Cached by default (`gradle/actions/setup-gradle`) — checkpoint
  pushes during `/spec-flow:implement` recur often enough that a cold build defeats "keep CI warm".
- `github-actions-nextest.yml` — runs `cargo nextest run --profile ci --run-ignored all`, parses the
  nextest JUnit report (requires `[profile.ci.junit] path` in `.config/nextest.toml`), uploads
  `spec-flow-failures` on failure. Cached by default (`Swatinem/rust-cache`), same reasoning.

Copy the one matching your runner into `.github/workflows/`, adjust the toolchain versions and any
service containers your integration tier needs, and enable the check in branch protection. These are
starting points, not turnkey — the failing-test extraction assumes standard JUnit output locations.
