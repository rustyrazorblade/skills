# nextest: minimizing token usage in agent loops

Reference for running `cargo nextest` inside an AI coding agent. Goal is to emit a
fixed, small amount of output on success and only actionable detail on failure.

Verified against nexte.st docs as of 2026-08.

## Profile

Put this in `.config/nextest.toml`:

```toml
[profile.agent]
status-level = "fail"
failure-output = "immediate-final"
fail-fast = false
```

Only these three change behavior. `success-output = "never"` and
`final-status-level = "fail"` are already the defaults, so setting them is a no-op.

| Setting | Default | Why set it |
| --- | --- | --- |
| `status-level = "fail"` | `pass` | Suppresses the per-test `PASS` lines. This is the single biggest win. A 5000-test passing run drops to about three lines. |
| `failure-output = "immediate-final"` | `immediate` | Repeats failure output in the final summary, so the agent sees it even if earlier output scrolled past a truncation boundary. |
| `fail-fast = false` | `true` | One full picture per invocation instead of an iterative one-failure-at-a-time loop. Each rerun costs a fresh round trip. Equivalent to `--max-fail=all`. |

Status levels are cumulative like log levels:
`none, fail, retry, slow, leak, pass, skip, all`. Each level implies all earlier ones.

## Command-line flags

```bash
cargo nextest run \
  --profile agent \
  --show-progress=none \
  --no-output-indent \
  --cargo-quiet --cargo-quiet \
  --color never
```

### `--show-progress=none`

Important and easy to miss. The default is `auto`, which resolves to `bar` in an
interactive terminal but to `counter` when output is piped. `counter` prints a
line per completed test, which is exactly the noise `status-level = "fail"` was
supposed to remove.

Do **not** use `--show-progress=only`. It looks correct but only applies in
interactive terminals; in non-interactive contexts (piped output, CI) it falls
back to `auto` behavior and successful test output is shown normally.

`--hide-progress-bar` is deprecated and only ever affected interactive terminals.

### `--no-output-indent`

Drops the 4-space indent nextest adds to captured output. Small but free.
No effect under `--no-capture`.

### `--cargo-quiet`

Suppresses cargo log messages. Specify twice for no cargo output at all.
Compiler warnings are often a large fraction of total output on an incremental
build.

### `--color never`

Or `CARGO_TERM_COLOR=never`. ANSI escape codes tokenize badly and carry no
information the model can use.

### `RUST_BACKTRACE=1`

Not `full`. A panicking test with a `full` backtrace can eat a context window
on its own.

## Rerun only what failed

The largest saving in an agent loop. With run recording enabled:

```bash
cargo nextest run -R latest
```

Runs only tests that, in the previous recorded run, failed, did not complete
because the run was cancelled, or are newly added since. The agent fixes one
thing and reruns two tests instead of five thousand.

Accepts a run ID (full UUID, short prefix, or `latest`) or a path to a portable
recording:

```bash
cargo nextest run -R my-run.zip
```

Portable recordings mean a CI failure can be rerun locally against the same
test set.

Exit code 5 (`RERUN_TESTS_OUTSTANDING`) means the selected tests passed but
previously-failing tests remain. Exit code 0 in rerun mode means no tests
remained to run, which is success.

Reruns work purely at the test level and do not track code or build changes,
so a full run is still needed before merging.

## Wrapper script

Hard byte caps matter more than clever filtering. A single panicking test can
produce a 40k-line backtrace.

```bash
#!/usr/bin/env bash
# scripts/test.sh
set -o pipefail
export RUST_BACKTRACE=1
export CARGO_TERM_COLOR=never
cargo nextest run \
  --profile agent \
  --show-progress=none \
  --no-output-indent \
  --cargo-quiet --cargo-quiet \
  "$@" 2>&1 | tail -c 8000
exit ${PIPESTATUS[0]}
```

## Machine-readable output

Optional. Useful if you want structured control rather than a byte cap.

```bash
NEXTEST_EXPERIMENTAL_LIBTEST_JSON=1 \
cargo nextest run --message-format libtest-json-plus
```

The env var is required; the flag does nothing without it.

Caveats:

- The format is experimental. The nextest docs' format specification section is
  currently a TODO, and the format may change to fix issues or track upstream.
- The stream emits `started` and `ok` events per test, so at the source it is
  **more** volume than human output with `status-level = "fail"`. Savings only
  exist because you filter before it reaches context.
- Confirmed fields from nextest's own doc examples: `type`, `event`, `name`,
  `exec_time`. Failure-specific field names are not documented; verify against
  your nextest version before depending on them.

Pin the version for stability:

```bash
--message-format-version 0.1
```

## JUnit XML

More stable than the JSON format, and the right choice when aggregating across
distributed runners.

```toml
[profile.agent.junit]
path = "junit.xml"
store-success-output = false
store-failure-output = true
```

Written to `target/nextest/agent/junit.xml`. Have a separate step merge and
summarize; point the agent at the summary, not at raw runner logs.

## Distributed runs

If tests are sharded across machines or pods, do not stream per-runner logs into
the agent. Merge the JUnit XMLs into one compact failure summary and let the
agent read only that file. Per-shard log tailing across 32 partitions is the
worst case for token usage.

Partition syntax for reference: `--partition hash:1/2`, `count:2/3`, or
`slice:1/3`.

## Related tools

- **cargo-limit** (`cargo lcheck`, `cargo lbuild`): reverses compiler message
  order and suppresses warnings until errors are fixed. Wraps `cargo test`, not
  nextest, so it does not compose with the above. Useful for the build step only.
- **RTK** (Rust Token Killer): shell-level proxy that compresses output for many
  commands (git, grep, cargo, kubectl). Broader coverage than nextest flags, but
  redundant for nextest specifically since it compresses output nextest already
  produced. Can over-compress; `rtk proxy <cmd>` bypasses filtering. Note the
  crates.io name collision with an unrelated "Rust Type Kit" package.

## Quick checklist

- [ ] `status-level = "fail"` in an agent profile
- [ ] `--show-progress=none` (not `only`, not `--hide-progress-bar`)
- [ ] `--color never` / `CARGO_TERM_COLOR=never`
- [ ] `--cargo-quiet --cargo-quiet`
- [ ] `RUST_BACKTRACE=1`, never `full`
- [ ] Hard byte cap on the wrapper script
- [ ] Run recording enabled so `-R latest` is available
- [ ] Aggregated summary file for distributed runs, not raw logs
