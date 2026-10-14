# Test and CI policy

**This repo owns this file.** spec-flow reads it and ships no default of its own; if this file
goes away, the pipeline stops rather than falling back to anything. Every line below is yours to
change, including the local/CI split itself.

Keep it short. Every implementation and review agent reads it on every run.

## What this repo is

`skills` is a plugin repo: markdown, shell, and a little Python. Its tests are hand-rolled
harnesses, each a plain shell script that runs offline and deterministically. The local gate below
lists every one of them. It has **no test-running CI**, and no framework: there is no `cargo`, no
Gradle, no `pytest`, and no `npm test` here. Run a harness by invoking it with `bash`, or, for the
one `.mjs` check, with `node`.

## The local gate

Run these on a change, and only where the change touches them:

- **Shell scripts** — `shellcheck -x <script>` on each script you added or edited. It must be
  clean: zero findings, exit 0. Run it from the repo root, and use `-x` so it follows any
  `source`d file rather than reporting SC1091 for one it declined to read.
- **Plugin manifests** — when you edit a `plugin.json` or `marketplace.json`, confirm it parses as
  JSON.
- **Python scripts** — when you edit one, run it, or run `python3 -m py_compile <script>` if it
  cannot be run standalone.
- **Test harnesses** — when a change touches a file a harness covers, run that harness from the
  repo root. It must exit 0. Every harness in the repo is listed here; paths are repo-relative.
  - `bash plugins/spec-flow/scripts/test-repo-config.sh` covers
    `plugins/spec-flow/scripts/repo-config.sh` and `plugins/spec-flow/scripts/seed-config.sh`.
  - `bash plugins/spec-flow/scripts/test-board.sh` covers `plugins/spec-flow/scripts/board.py`.
  - `bash plugins/spec-flow/scripts/test-blocked-dependency.sh` covers
    `plugins/spec-flow/scripts/blocked-dependency.sh`.
  - `bash plugins/spec-flow/scripts/test-close-on-merge.sh` covers
    `plugins/spec-flow/scripts/close-on-merge.sh`. It also runs the real
    `plugins/spec-flow/scripts/blocked-dependency.sh sweep` against its fake `gh`, so a change to
    `blocked-dependency.sh` means running this harness too.
  - `bash plugins/spec-flow/scripts/test-issue-body.sh` covers
    `plugins/spec-flow/scripts/issue-body.sh`.
  - `node plugins/spec-flow/scripts/test-implement-workflow.mjs` covers the `closingLines`
    function in `plugins/spec-flow/skills/implement/implement.workflow.js`: the `alsoCloses` guard
    and the `Closes #` lines. It covers nothing else in that file.
  - `bash plugins/dev-skills/skills/walkthrough/scripts/test-generate-walkthrough.sh` covers
    `plugins/dev-skills/skills/walkthrough/scripts/generate-walkthrough.py`,
    `plugins/dev-skills/skills/walkthrough/assets/viewer.html`, the manifest fixtures in
    `plugins/dev-skills/skills/walkthrough/scripts/fixtures/`, and the shared
    `plugins/dev-skills/lib/html_shell.py`.
  - `bash plugins/dev-skills/skills/ide-explain/scripts/test-generate-explain.sh` covers
    `plugins/dev-skills/skills/ide-explain/scripts/generate-explain.py`,
    `plugins/dev-skills/skills/ide-explain/assets/viewer.html`, the shared
    `plugins/dev-skills/lib/html_shell.py`, and the OpenSpec content under
    `plugins/dev-skills/skills/ide-explain/scripts/preview-fixture/`. It covers nothing else in
    that scripts directory: not `init-explain.sh`, not `preview.sh`, and not the fixture's `src/`,
    `baseline-src/`, `docs/`, `fake-gh/`, or `explain-map.json`, which are `preview.sh`'s own
    inputs. Editing one of those and getting a green run proves nothing about the edit.
  - `bash plugins/easy-db-lab/tests/test-report.sh` covers the easy-db-lab lab report:
    `plugins/easy-db-lab/bin/setup-cluster.sh`, `plugins/easy-db-lab/bin/detect-cluster-layout.sh`,
    `plugins/easy-db-lab/bin/report-graph.py`, `plugins/easy-db-lab/bin/report-check.py`,
    `plugins/easy-db-lab/bin/report-export.py`, the redaction patterns both share in
    `plugins/easy-db-lab/bin/report_redaction.py`, every file in `plugins/easy-db-lab/scaffold/`, and
    its own fixtures under `plugins/easy-db-lab/tests/fixtures/`. Those fixtures include a stub
    Mimir (`fixtures/mimir/stub.py`) for `fetch` and a stub Grafana (`fixtures/grafana/stub.py`)
    for `render`; both are local HTTP servers on `127.0.0.1`.  A stub SOCKS5 forwarder
    (`fixtures/socks/forwarder.py`) carries the `--proxy` cases of `fetch`, `render`, and the
    "### Render" and "### Overlay render" blocks; a dead proxy on port 1 carries the failure cases. Of
    `plugins/easy-db-lab/bin/configure-multi-dc-seeds.sh` it covers only the arms-marker guard. It
    also runs text checks on `plugins/easy-db-lab/skills/{run,explore,plan}/SKILL.md`,
    `plugins/easy-db-lab/references/{report,report-upload,journal,issues}.md`, the Multi-DC Setup
    section of `plugins/easy-db-lab/references/cassandra.md`, and the repo `README.md`: no old
    report file names, no plotting instruction, and the required sections. A `journal_lint`
    function applies the entry format of `references/journal.md` (blank lines between blocks, 160
    characters per line, commands only in fenced blocks, every fence closed) to each `markdown`
    example in `journal.md` and `issues.md`, and to `fixtures/journal/good.md`, `bad.md`, and the
    `bad-fence-*.md` fixtures. Those checks prove the
    text, not the skill behavior. It also runs some `bash` blocks as written, under bash, against
    stubs: in `references/report.md`, the blocks under "### The SOCKS proxy" (against a stub
    wrapper and `.socks5-proxy-state`), "### Render" (the single-cluster render), and
    "### Overlay render" (window-variable detection, the whole-run fallback, and `PROXY`), the last two
    against the stub Grafana; in `references/report-upload.md`, the image and CSV probe (against
    a stub binary) and the block under "## The AWS SSO Session" (against a stub `aws` and a temp
    `HOME`). An edit to one of these blocks is covered; the other commands in those files are not. It needs `mdbook`, `uv`,
    `jq`, and `curl` on `PATH`; the first run needs network for uv to fetch pypandoc-binary and
    requests.
  - `bash plugins/easy-db-lab/bin/export-workload-metrics.test.sh` covers `plugins/easy-db-lab/bin/export-workload-metrics` and `plugins/easy-db-lab/bin/metrics-catalog.jq`.  These two files and the harness are verbatim copies of easy-db-lab's `bin/`: re-copy them, do not edit them, until easy-db-lab replaces them with a first-class command.

  `plugins/dev-skills/lib/html_shell.py` is **shared**: both generators import it. A change to it
  means running **both** dev-skills harnesses, not one.

  `plugins/cassandra-expert/skills/training/scripts/` holds verification scripts rather than
  harnesses in the sense above: they check training claims against a live Cassandra 5.0+ cluster,
  so they cannot run in this offline gate and are not part of it. `CLAUDE.md` governs when to write
  and run them.

  A script with no harness of its own still gets the `shellcheck -x` or `py_compile` bullet above;
  there is nothing further to run for it.

An agent that runs nothing because nothing above applies to its change has complied with this
policy in full.

## CI

CI is **not a test gate** in this repo. `.github/workflows/` holds Claude review workflows only.
Nothing here produces a `spec-flow-failures` artifact, so there are no CI failures to sync back
into a branch.

## What gates merge

The owner's review. A PR merges when the owner squash-merges it, and not before.

## Push cadence

Push the issue branch at checkpoints — after a completed task group, or a few working commits.
Not on every commit.
