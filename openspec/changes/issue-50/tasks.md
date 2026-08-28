# Tasks

## 1. The startup-check script

- [x] 1.1 Write `plugins/spec-flow/scripts/repo-config.sh` with two subcommands, `check` and `instruction`, sharing one repo-root and config-dir resolution. Follow `archive-batch-pr.sh`'s shape: header comment stating the contract, `set -euo pipefail`, `usage()` exiting 2, `command -v` dependency check up front. macOS bash 3.2 only — no associative arrays, no `mapfile`, no `${var,,}`.
- [x] 1.2 Self-locate from `BASH_SOURCE` in the manner of `board.py:20-23`. Never read `$CLAUDE_PLUGIN_ROOT` — it is not reliably exported to a subprocess.
- [x] 1.3 Resolve the repo root with `git rev-parse --show-toplevel`. Outside a git repo, exit 2 with the environment-error message.
- [x] 1.4 Resolve the config dir from `SPEC_FLOW_CONFIG_DIR`, defaulting to `spec-flow`. Reject absolute values, values containing `..`, and any character outside `[A-Za-z0-9._/-]`, each with its own exit-2 message. The character restriction is what makes the emitted pointer safe to embed — do not relax it.
- [x] 1.5 Implement the required-file registry as a newline-delimited, pipe-separated string iterated with `while IFS='|' read`, so a later config file is one added line.
- [x] 1.6 Implement `check`: exit 0 printing nothing when all present; exit 1 with the complete message on stdout when missing or unusable; exit 2 on environment/usage errors, on stderr.
- [x] 1.7 Implement "unusable" as: not a regular file, not readable, or empty once whitespace and `#` comment lines are stripped. Inspect nothing else about the content — no marker check, no schema.
- [x] 1.8 Write the exit-1 message in full, including the rebase line for worktrees branched before the file landed. No caller restates any of it.
- [x] 1.9 On a missing file, run `git check-ignore -q` on the missing **file path** and append a line naming that as the likely cause when it matches. (Corrected during implementation: this task originally said to test the config *directory*, which does not match when the directory is absent — exactly when the diagnostic is needed. The file path matches, and also catches a rule written against the file itself.)
- [x] 1.10 Implement `instruction`: emit the one-line pointer naming the resolved absolute path to the policy file, plus the flagged-tests sentence and the requirement to name exact commands run. No tier names, no commands, no missing-file clause.

## 2. Seeding

- [x] 2.1 Write `plugins/spec-flow/scripts/seed-config.sh` for the git/`gh` mechanics: discover the default branch via `gh repo view --json defaultBranchRef` (never assume `main`), check `origin/<default>` for an existing policy file, create a uniquely-named branch off it, commit, push, `gh pr create`. Never merge; never commit or push to the default branch. Check `git` and `gh` availability up front.
- [x] 2.2 When the policy file already exists on the default branch: report that the repo already owns its policy, exit 0, change nothing, open no PR. Check the remote default branch, not the working tree.
- [x] 2.3 Add the seeding item to `skills/setup/SKILL.md`: propose a concrete policy for this repo, present it to the owner, and write nothing until they confirm or amend it. Propose for any stack — a confirmed proposal is not a guess. State plainly what could not be determined.
- [x] 2.4 Rewrite `skills/setup/SKILL.md:159-161` so its local-edits-only rule explicitly carves out this one outward action: it opens a PR and never merges, mirroring `adopt-tiering`. Do not leave the existing rule silently contradicted.
- [x] 2.5 Ensure the seeded file opens with a self-describing header: the repo owns it, spec-flow ships no default and falls back to nothing, every line is the owner's to change including the split itself, and it should stay short because every implementation and review agent reads it.

## 3. The pointer replaces policy text in both implement modes

- [x] 3.1 Delete the TEST INSTRUCTION blockquote at `skills/implement/SKILL.md:82-99`. Replace with: run `repo-config.sh instruction` and append its stdout verbatim to every teammate prompt that runs tests.
- [x] 3.2 Pass that same stdout as `args.testInstruction` in the existing `args` block at `skills/implement/SKILL.md:378-390`.
- [x] 3.3 Delete the `const testInstruction` literal at `implement.workflow.js:70`. Destructure `testInstruction` from `_args` and throw when absent, naming where it comes from and stating the script has no default.
- [x] 3.4 Replace the tier prose at `skills/address/SKILL.md:44-47` with the same generated pointer. Restate no tier, command, or policy.
- [x] 3.5 Verify no teammate prompt anywhere carries a missing-file clause for the policy. The check guarantees presence before any agent spawns.

## 4. The review contract

- [x] 4.1 Change the `tests_ran` enum to `policy | partial | degraded | none` and add `tests_detail` (exact commands run) across all sixteen call sites: `agents/reviewer.md:127-132`, `:142`; `code-reviewer.md:32`, `:35`; `security-reviewer.md:36`, `:39`; `test-rigor-reviewer.md:96`, `:99`; `observability-reviewer.md:73`, `:76`; `implement.workflow.js:44`, `:48`, `:160`, `:283`, `:364`; `skills/implement/SKILL.md:289`.
- [x] 4.2 Rewrite `agents/reviewer.md`'s tests bullet to carry no tier assertion at all — run the gate exactly as the prompt's pointer directs, assume no tier, substitute no convention from another project.
- [x] 4.3 Change the four non-spec lenses' "leave `tests_ran` as `full`" placeholder to `policy`.
- [x] 4.4 Make explicit, everywhere the enum is documented, that running nothing is `policy` — not `none` and not `degraded` — when the repo's policy names nothing to run.
- [x] 4.5 Replace the policy assertions in the draft PR body and final report (`skills/implement/SKILL.md:70`, `:448`, `:545-546`; `implement.workflow.js:147`) with a policy-neutral line quoting `tests_detail`.

## 5. `sync-ci` yields to the policy

- [x] 5.1 Run `repo-config.sh check` first and stop on non-zero, relaying its output.
- [x] 5.2 When the repo's policy states CI is not a test gate, report that and exit cleanly rather than failing to find a `spec-flow-failures` artifact the repo never produces. Leave behavior unchanged for a repo whose policy does gate on CI.

## 6. Callers run the check

- [x] 6.1 `agents/project-manager.md`: run `repo-config.sh check` at session start; offer seeding on exit 1 only, never on exit 2. Carry no prose rules about the policy file and no restatement of the script's message.
- [x] 6.2 `skills/implement/SKILL.md` and `skills/sync-ci/SKILL.md`: run the check before any work, stop on non-zero, relay output verbatim, add nothing.
- [x] 6.3 Confirm no other caller — `issue-pm`, `archive-batch`, or any skill — offers seeding. They stop and relay.

## 7. Documentation

- [x] 7.1 Convert `docs/workflow.md:881-933` and `:972-977` from mandate to mechanism-plus-pointer. Both copies, or the second becomes the new hardcoded source.
- [x] 7.2 Convert `README.md:66-83` and the CI-contract bullet the same way. Both copies.
- [x] 7.3 Add a two-row table to `docs/workflow.md` distinguishing `.spec-flow/` (gitignored, per-branch runtime state, dies with the branch) from `spec-flow/` (committed, repo-owned policy, lives with the repo).
- [x] 7.4 Add an explicit warning to `setup`'s gitignore item and the README's Prerequisites bullet: add `.spec-flow/` with the leading dot; never add `spec-flow/`. In this repo the undotted form would match `plugins/spec-flow/` and erase the plugin's source from git.
- [x] 7.5 Add a positive check to `setup`: confirm `spec-flow/` is not ignored, and offer to fix it if it is.

## 8. This repo's own policy

- [x] 8.1 Write `spec-flow/TESTING.md` at this repo's root, stating plainly that `skills` has no automated test suite and no test-running CI; that the local gate is plugin validation and shellcheck where applicable; and that merge is gated on the owner's review. Name no test command this repo does not run.
- [x] 8.2 Confirm the file is committed and not gitignored (`git check-ignore -v spec-flow/TESTING.md` must find no match).

## 9. Verification

- [x] 9.1 Verify the check exits 0 and prints nothing in this repo once `spec-flow/TESTING.md` exists.
- [x] 9.2 Verify the check exits 1 with the full message when the file is absent, and exits 2 outside a git repo and on each rejected `SPEC_FLOW_CONFIG_DIR` form.
- [x] 9.3 Verify `repo-config.sh instruction` emits a single line containing no backtick, `$`, or brace, so it embeds safely in a JS template literal.
- [x] 9.4 Verify `SPEC_FLOW_CONFIG_DIR` relocation reads the policy from the new location.
- [x] 9.5 Grep the tree to confirm the plugin's five former default commands (`cargo nextest run`, `./gradlew test`, `npm test`, `go test -short ./...`, `pytest -m 'not integration'`) survive only in documentation as examples, never in a runtime prompt path.
- [x] 9.6 Confirm both `implement` modes derive the instruction from the same generated line, with no second copy anywhere.

- [x] 9.7 Run this repo's own local gate against every script this change adds or edits, using the exact invocation `spec-flow/TESTING.md` prescribes and from the repo root — not a variant that happens to pass. `shellcheck -x plugins/spec-flow/scripts/repo-config.sh plugins/spec-flow/scripts/seed-config.sh plugins/spec-flow/scripts/test-repo-config.sh` must exit 0 with zero findings. The gate the change defines has to be run against the change; its absence here is why a failing script shipped in round 1.
- [x] 9.8 Run `bash plugins/spec-flow/scripts/test-repo-config.sh`; it must exit 0. The harness builds throwaway git repos and fakes `gh` on PATH, so it needs no network, no GitHub account, and opens no pull request — which is what makes seeding's git/gh path testable at all. It covers what a live run never reaches: every unusable-config state, hostile repo roots refused by both subcommands, and the seeding rollback that stops a failed PR creation stranding a branch. It cleans up its temp directory on EXIT, INT, and TERM.
## 10. Release

- [x] 10.1 Ask the owner for the version number before changing it, then bump `plugins/spec-flow/.claude-plugin/plugin.json` and `plugins/spec-flow/.codex-plugin/plugin.json` together. Current version is `0.34.0`. **Bumped to `0.35.0`, owner-approved. Only `.claude-plugin/plugin.json` exists; this plugin ships no `.codex-plugin/` directory, so one file moved, not two. That absence is pre-existing and out of scope here.**
