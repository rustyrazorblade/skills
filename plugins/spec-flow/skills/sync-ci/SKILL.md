---
name: sync-ci
description: Pull the branch's latest CI test failures into the issue's local flagged set — download the spec-flow-failures artifact from the most recent CI run and append the failing test ids to .spec-flow/flagged-tests in the worktree, so the local loop runs them for the rest of the branch. Exits cleanly, doing nothing, in a repo whose own policy says CI is not a test gate. Part of the flow delivery workflow (see docs/workflow.md, "Test policy"). Invoked by the owner when they notice CI go red, or by issue-pm itself the moment its own push's CI run reports red (see implement/address) — a single check tied to a specific run, never a standing poll loop.
argument-hint: [issue number, or its PR number]
---

# sync-ci — pull CI failures into the local flagged set

You are this issue's `issue-pm`, running as your own dedicated background session. CI ran tests on
issue `#N`'s branch and something failed. Pull those failures into the branch's
**flagged set** so the local loop (`/spec-flow:implement`'s gate and your own runs) guards
them for the rest of the branch. This skill only applies where the repo's own policy makes CI a
test gate; step 1 checks that first. Run this the moment CI-red on this branch is known — whether the
owner points it out, or you noticed it yourself checking the run tied to a push you just made (see
`implement` step 5 and `address` step 4). Either way this is a single check against a specific run,
never a standing watch loop — **no polling**. Never let a fix for a known CI failure go out on a
guess: sync first, confirm the flagged test(s) pass locally, then push — a blind push-and-wait
turns a ~1-minute local check into a 20-30 minute CI round trip for no reason.

Input: an issue number `#N` (or its PR number). You're already running inside this issue's
worktree — Claude Code's own background-session isolation put you there, on whatever branch it
assigned; resolve it with `git rev-parse --abbrev-ref HEAD` rather than assuming a name. If you
need to recover the PR from scratch, search by issue instead of by branch name:
`gh pr list --search "Closes #<N> in:body" --json number,headRefName`. See **Test policy** in
`docs/workflow.md` for the model: the repo's own policy names the local gate; a CI-caught test is
added here and run locally alongside it until the branch merges, then evaporates.

## Steps

1. **Check the repo's configuration, then read its policy — before any work.** Run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo-config.sh check
   ```
   Non-zero: **stop here**, having done nothing, and relay the script's output **verbatim**. Add no
   rules, no explanation, and no fallback of your own. Do not offer to create the file; that offer
   is `project-manager`'s alone.

   Then read the policy file itself — the path is in the pointer that
   `${CLAUDE_PLUGIN_ROOT}/scripts/repo-config.sh instruction` prints. **If the repo's policy states
   that CI is not a test gate**, this whole skill has nothing to do: say so plainly, naming the
   policy as the reason, and exit cleanly. Do not go looking for a `spec-flow-failures` artifact a
   repo that runs no tests in CI will never produce, and do not report its absence as a failure.
   Where the policy does put a test gate in CI, carry on unchanged.

2. **Resolve the branch and its latest CI run.**
   ```bash
   BR=$(git rev-parse --abbrev-ref HEAD)
   # Most recent completed run for this branch:
   gh run list --branch "$BR" --json databaseId,status,conclusion,workflowName,createdAt \
     --limit 10
   ```
   Pick the most recent **completed** run whose `conclusion` is `failure`. If the latest run is
   still in progress, say so and stop — don't act on a half-finished run. If the latest completed
   run is green, there's nothing to sync: say so and stop.

3. **Download the failures artifact.** The consuming repo's CI uploads failing test ids as an
   artifact named `spec-flow-failures` (the CI contract — see `references/ci/`). Fetch it:
   ```bash
   TMP=$(mktemp -d)
   if ! gh run download <run-id> -n spec-flow-failures -D "$TMP" 2>/dev/null; then
     echo "no spec-flow-failures artifact on this run — nothing to sync (a build/lint break, not a" >&2
     echo "test failure, or CI isn't wired to the contract yet — see references/ci/)." >&2
     exit 1
   fi
   echo "TMP=$TMP"
   ```
   The explicit `exit 1` matters: a run that failed but produced no `spec-flow-failures` artifact
   means the failure wasn't a test failure, so there is nothing to add to the flagged set — stop
   here and report that plainly to the owner rather than continuing into step 5 with an empty
   `$TMP` and no ids to flag. Do not invent entries. **Note the printed `$TMP` path** — like
   `finalize`'s `$TMPWT`, it's from `mktemp` and can't be recomputed; step 5 below uses `<TMP>` as a
   stand-in for the literal path you just saw, not the unset variable, in case it runs as a separate
   Bash call.

4. **Ensure `.spec-flow/` is gitignored** (idempotent, one-time; the flagged set must never commit):
   ```bash
   cd <worktree>
   grep -qxF '.spec-flow/' .gitignore 2>/dev/null \
     || { printf '\n# spec-flow local flagged tests (never commit)\n.spec-flow/\n' >> .gitignore; \
          git add .gitignore && git commit -m "chore: gitignore .spec-flow/ (flagged tests)"; }
   ```

5. **Append the failing ids to the flagged set** (dedup; keep what's already there — the set
   accumulates across the branch's life). Diff the incoming ids against what's already flagged
   *before* merging, so step 6 can tell the owner which are new vs. repeat failures — an id
   failing again after a fix round is either still broken or flaky, worth calling out rather than
   folding silently into the merge:
   ```bash
   mkdir -p <worktree>/.spec-flow
   FLAG=<worktree>/.spec-flow/flagged-tests
   touch "$FLAG"
   INCOMING=$(cat <TMP>/* 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | sort -u)
   NEW=$(comm -23 <(echo "$INCOMING") <(sort -u "$FLAG"))
   REPEAT=$(comm -12 <(echo "$INCOMING") <(sort -u "$FLAG"))
   # Merge new ids in, preserving existing, dropping blanks/duplicates:
   cat "$FLAG" <TMP>/* 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' \
     | sort -u > "$FLAG.new" && mv "$FLAG.new" "$FLAG"
   echo "NEW=$NEW"
   echo "REPEAT=$REPEAT"
   ```
   Each line is a runner-selectable test id in the same form CI emitted (a JUnit `Class.method`, a
   nextest `test(=path)` / test path). The local gate runs these alongside whatever the repo's
   policy names.
   Note the printed `$NEW`/`$REPEAT` — step 6 references them as `<NEW>`/`<REPEAT>`, the literal
   lists you just saw, not shell variables that may not survive to a separate Bash call.

6. **Report.** Tell the owner which test ids are newly flagged (`<NEW>`) and which are repeat
   failures already in the set (`<REPEAT>` — still broken or flaky, call it out explicitly), plus
   the total now in the flagged set, and that the next local run — `/spec-flow:implement`'s gate
   or a manual run — will include them. Then the loop is: fix on the branch (tests stay green
   locally including the flagged ones), push, CI re-runs; when it's green and the
   owner merges, the flagged set evaporates with the worktree at `/spec-flow:finalize`.
   ```bash
   gh issue comment <N> --body "🚨 CI failed — <count of NEW> new test(s) flagged, <count of REPEAT> repeat."
   ```

## Rules

- **Self-invoked on a known red run, never a watch loop.** Run it the moment CI-red on this branch
  is known — you notice it, or `issue-pm` does via a single bounded check of the run tied to its
  own push (`implement` step 5, `address` step 4). Either way there is no polling: one check
  against one specific run, not a standing watch.
- **Never fabricate entries.** Only ids that came from the `spec-flow-failures` artifact go in. A
  failed run with no artifact means "not a test failure" or "CI not wired" — report, don't invent.
- **The flagged set is local and gitignored** — it never commits and never leaves the branch.
- **Additive + idempotent.** Re-running after another red CI run merges new ids without dropping the
  ones already being guarded; running when CI is green is a no-op.
- When you cite an issue or PR, always write it as `<number>: <title>`, on its own line with a `-`
  prefix — never a bare number, and never several run together inline in a sentence.
