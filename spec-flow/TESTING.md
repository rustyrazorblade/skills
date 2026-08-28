# Test and CI policy

**This repo owns this file.** spec-flow reads it and ships no default of its own; if this file
goes away, the pipeline stops rather than falling back to anything. Every line below is yours to
change, including the local/CI split itself.

Keep it short. Every implementation and review agent reads it on every run.

## What this repo is

`skills` is a plugin repo: markdown, shell, and a little Python. Its tests are hand-rolled
harnesses, each a plain shell script that runs offline and deterministically. The local gate below
lists every one of them. It has **no test-running CI**, and no framework: there is no `cargo`, no
Gradle, no `pytest`, and no `npm test` here. Run a harness by invoking it with `bash`.

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
  - `bash plugins/dev-skills/skills/walkthrough/scripts/test-generate-walkthrough.sh` covers
    `plugins/dev-skills/skills/walkthrough/scripts/generate-walkthrough.py` and
    `plugins/dev-skills/skills/walkthrough/assets/viewer.html`.
  - `bash plugins/dev-skills/skills/ide-explain/scripts/test-generate-explain.sh` covers
    `plugins/dev-skills/skills/ide-explain/scripts/generate-explain.py` and
    `plugins/dev-skills/skills/ide-explain/assets/viewer.html`. It does not cover that directory's
    `init-explain.sh` or `preview.sh`.

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
