# Tasks

All paths are under `plugins/spec-flow/`. Every shell script runs on bash 3.2 (macOS default): no
associative arrays, no `mapfile`, no GNU-only flags.

## 1. `spawn-issue-manager.sh`: pin behavior, then refactor

- [ ] 1.1 Write `scripts/test-spawn-issue-manager.sh` against the CURRENT script: a fake `gh` and a
      fake `claude` on PATH that record each call and return scripted results. Cover every existing
      exit path (exit code and message) and the order of the pre-spawn checks.
- [ ] 1.2 Run it against the unmodified script; it must pass before any edit to the script.
- [ ] 1.3 Refactor `scripts/spawn-issue-manager.sh` into clearly named parts, with every pre-spawn
      check in one preflight function called in the existing order. Change no exit code, message,
      or check order.
- [ ] 1.4 Re-run `test-spawn-issue-manager.sh`; it must pass unchanged.

## 2. `test-board.sh`: consolidate the row helper

- [ ] 2.1 Move the ~9 copies of the `row(**kw)` helper in `scripts/test-board.sh` to one shared
      definition, and point every check at it. Change no fixture and no assertion in this task.
- [ ] 2.2 Run `test-board.sh`; every existing check must pass.

## 3. `board.py`: tests first

- [ ] 3.1 Make the fake `gh` in `test-board.sh` fail when the issue-list call does not request
      `blockedBy`.
- [ ] 3.2 Move the existing blocked fixture (issue 15) to a `Blocked by:` comment, and update its
      assertions to the new Blocked row and the bare `🔒 BLOCKED` marker.
- [ ] 3.3 Add a fixture, with `blockedBy` in the `{"nodes": [...], "totalCount": N}` shape, and a
      check for each case: open native blocker only; several open native blockers with one closed;
      closed native blocker (released); blocker closed as not planned (released); label only with a
      `Blocked by:` comment; label and open native blocker together; an `add-external` comment
      followed by a later `add` comment; label with no `Blocked by:` comment (older `⛔ Blocked on`
      forms only); a blocked ready issue absent from READY and "Next up", with "Next up" falling
      through; a blocked in-flight issue in IN FLIGHT with the bare marker; a blocked issue in
      BLOCKED ON YOU with the bare marker; a blocked stalled issue with its spawn command marked; a
      cross-repo native blocker; a missing or null `blockedBy`; the summary counting both kinds; a
      failing `gh issue list` (non-zero exit, gh error on stderr, no board).
- [ ] 3.4 Run `test-board.sh`; the new checks fail against the current `board.py`.

## 4. `board.py`: implementation

- [ ] 4.1 `fetch_issues()`: add `blockedBy` to the field list and drop `default=[]`; in `main()`,
      catch the issue-fetch failure and `fail()` with gh's stderr.
- [ ] 4.2 `build_rows()`: set `blockers` (open native nodes as `(number, title)`), `blocked_label`,
      and `blocked = bool(blockers) or blocked_label`; treat a missing or null `blockedBy` as empty.
- [ ] 4.3 `prefetch_notes()`: fetch only for `blocked_label` carriers, with the prefix `Blocked by:`;
      replace the `⛔ Blocked on #` reason regex with the first line of the matched comment.
- [ ] 4.4 `render_blocked()`: the issue on one line, then `- <number>: <title>` per open native
      blocker, then `- ⛔ Blocked by: <reason>` or `- ⛔ Blocked by: see issue comments`.
- [ ] 4.5 `render_row()`: bare `🔒 BLOCKED`; `render_stalled()`: mark a blocked row's spawn command
      `🔒 BLOCKED`.
- [ ] 4.6 `render_board()`: exclude blocked rows from `ready_rows`; leave IN FLIGHT and BLOCKED ON
      YOU membership unchanged.
- [ ] 4.7 Update the module docstring and comments that describe "blocked" as label-only.
- [ ] 4.8 Run `test-board.sh`; every check passes.

## 5. `blocked-dependency.sh`: tests first

- [ ] 5.1 Write `scripts/test-blocked-dependency.sh`: a fake `gh` on PATH that records each call and
      returns scripted results. One check per criterion: `add` (new link, existing link, link
      failure, comment failure, no label); `add-external` (label and comment, newer reason, partial
      failure); `clear` (link removed with the removal comment that does not say landed and leaves
      the label, no link in this repo, same number in another repo, delete failure); `clear-external`
      (labeled, unlabeled, substring-only label, removal failure); `sweep` (same calls as today);
      usage (missing and non-numeric arguments, unknown subcommand, all five listed, exit 2).
- [ ] 5.2 Run it; the new-behavior checks fail against the current script.

## 6. `blocked-dependency.sh`: implementation

- [ ] 6.1 Rewrite `add`: list existing links, POST only when M is absent, post
      `⛔ Blocked on #M — <reason>`, no label; report partial failures as designed.
- [ ] 6.2 Add `add-external`: label, then `Blocked by: <reason>`; report partial failures.
- [ ] 6.3 Rewrite `clear`: find the link to M in this repo, DELETE it, post the removal comment; no
      label change; exit 0 with no comment when absent; exit 1 saying the link is still there on a
      failed list or delete.
- [ ] 6.4 Add `clear-external`: exact label match, remove it, post `✅ Unblocked`; exit 0 with no
      comment when absent; exit 1 saying the board will keep showing it blocked on failure.
- [ ] 6.5 Leave `sweep` unchanged; update `usage()` to list all five subcommands; update the header
      comment to the new premise.
- [ ] 6.6 Run `test-blocked-dependency.sh`; every check passes.

## 7. Spawn check in `agents/project-manager.md`

- [ ] 7.1 In the spawn instructions, add: before calling `spawn-issue-manager.sh`, look for the
      issue in the board's Blocked section; if present, show its lines to the owner as data, ask
      whether to spawn, and spawn only on a yes; on a no, spawn nothing and change no label; if
      absent, spawn as today. State that the blocker list comes from the board, not from `gh`.

## 8. Text updates

- [ ] 8.1 `bin/bootstrap-labels.sh`: set the `blocked` description to
      `Blocked by something that is not an issue`.
- [ ] 8.2 `skills/activate/SKILL.md`: step 4 records an issue dependency with `add` (native link
      only) and an external blocker, found by the architect or confirmed by the owner, with
      `add-external`; the "auto mode never skips past" rule covers both kinds.
- [ ] 8.3 `agents/issue-manager.md`: the hard-dependency-outside-`activate` section uses `add` for an
      issue and `add-external` for an external blocker; state the `add-external` / `needs-attention`
      rule for a wait on a person; remove the "hard dependency on another issue" definition of
      `blocked`.
- [ ] 8.4 `docs/workflow.md`: the label is only for blockers that are not issues; issue dependencies
      are a native link; the `add-external` / `needs-attention` rule; remove the "hard dependency on
      another issue" definition; describe the new Blocked row and markers.
- [ ] 8.5 `skills/finalize/SKILL.md`, `skills/setup/SKILL.md`, `agents/project-manager.md`,
      `README.md`: describe the label as only for blockers that are not issues. Leave `finalize`'s
      `sweep` call as it is.
- [ ] 8.6 Search every listed file for an instruction to set `blocked` for an issue dependency or to
      call `clear` when a blocker lands; remove any found.

## 9. Final check

- [ ] 9.1 Run `test-board.sh`, `test-blocked-dependency.sh` and `test-spawn-issue-manager.sh` under
      `/bin/bash` (3.2); all exit 0.
