## Why

The `blocked` label goes stale. Nothing removes it when the blocking issue closes, so the board
keeps showing work as blocked after its blocker lands. In this repo, issue 79 (activate: audit the
generated spec against the issue before committing it) still carries `blocked`, and its only
blocker, issue 78 (groom: move the architect design stage out of activate and run it as a loop), is
closed. Because 79 is also `status:ready`, the board lists it under READY and can name it as "Next
up" while it also shows under Blocked.

GitHub's native `blocked_by` link already records issue-to-issue dependencies, and it knows when the
blocker closes. "Blocked" must come from that link. The label stays only for blockers that are not
issues, such as an external PR or a person. This reverses the premise of issue 67 (The blocked label
and GitHub's native dependency are only managed inside activate, and drift apart), which created
`blocked-dependency.sh` to keep the label and the link in sync.

## What Changes

All paths are under `plugins/spec-flow/`.

- **`scripts/board.py`**
  - The issue fetch requests `blockedBy`. An issue is blocked if `blockedBy.nodes` holds at least
    one node with `state == "OPEN"`, or it has the `blocked` label. A missing or null `blockedBy`
    means no native blockers.
  - A Blocked row is the issue on one line, then one indented line per blocker:
    `- <number>: <title>` per open native blocker (the same for a blocker in another repo, with no
    repo name), and `- ⛔ Blocked by: <reason>` for the label, taken from the first line of the last
    comment that starts with `Blocked by:` (exact, case-sensitive). With no such comment the label
    line reads `- ⛔ Blocked by: see issue comments`.
  - Rows in IN FLIGHT and BLOCKED ON YOU carry a bare `🔒 BLOCKED` marker, with no blocker details.
  - The Stalled section marks a blocked issue's spawn command `🔒 BLOCKED`.
  - Blocked issues leave READY and are never named as "Next up"; "Next up" falls through to the next
    eligible issue. IN FLIGHT and BLOCKED ON YOU keep their blocked rows.
  - The summary's "N blocked" count includes both kinds.
  - When `gh issue list` fails, the board prints the gh error and exits non-zero, instead of
    rendering an empty board.
- **`scripts/blocked-dependency.sh`**
  - `add <N> <M> <reason>`: native link and a `⛔ Blocked on #M — <reason>` comment. No label. A
    link that already exists counts as success.
  - `add-external <N> <reason>` (new): the `blocked` label and a `Blocked by: <reason>` comment.
  - `clear <N> <M>`: removes the native link to issue M in this repo and posts a comment that the
    dependency was removed. It no longer touches the label and no longer says M landed.
  - `clear-external <N>` (new): removes the label (exact match) and posts `✅ Unblocked`.
  - `sweep <N>`: unchanged.
  - Usage lists all five subcommands; bad arguments exit 2.
- **`scripts/test-board.sh`**: the ~9 copies of the `row(**kw)` helper move to one shared place, and
  a new fixture covers every blocked case, with `blockedBy` in gh's real
  `{"nodes": [...], "totalCount": N}` shape. The fake `gh` fails if the board does not request
  `blockedBy`.
- **`scripts/test-blocked-dependency.sh`** (new): a fake `gh` on PATH that records each call; one
  check per `blocked-dependency.sh` criterion. bash 3.2.
- **Spawn check, `agents/project-manager.md` only**: before spawning an `issue-manager` for a blocked
  issue, `project-manager` reads that issue's lines from the board's Blocked section, shows them to
  the owner as data, and spawns only after the owner confirms. `spawn-issue-manager.sh` gets no gate.
- **`scripts/spawn-issue-manager.sh`**: a behavior-preserving refactor into clear parts, with the
  pre-spawn checks in one preflight function. Every exit path, exit code, message and check order
  stays the same.
- **`scripts/test-spawn-issue-manager.sh`** (new): a fake `gh` and a fake `claude` on PATH; checks
  each existing exit path and the order of the pre-spawn checks. Written and passing against the
  current script before the refactor. bash 3.2.
- **Text updates**: `bin/bootstrap-labels.sh` (label description becomes
  `Blocked by something that is not an issue`), `skills/setup/SKILL.md`,
  `skills/activate/SKILL.md`, `skills/finalize/SKILL.md`, `agents/issue-manager.md`,
  `agents/project-manager.md`, `docs/workflow.md` and `README.md` describe the label as only for
  blockers that are not issues, describe issue-to-issue dependencies as a native link only, drop any
  instruction to set `blocked` for an issue dependency or to call `clear` when a blocker lands, and
  state the `add-external` / `needs-attention` rule for a wait on a person.

## Capabilities

### New Capabilities
- `blocked-dependency`: the `blocked-dependency.sh` subcommand contract and its test script.
- `issue-manager-spawn`: `project-manager`'s pre-spawn blocker confirmation, and the
  behavior-preserving refactor of `spawn-issue-manager.sh` with its test script.

### Modified Capabilities
- `delivery-board`: blocked derivation from native links, Blocked row format, bucket exclusion,
  `🔒 BLOCKED` markers, the Stalled marker, and fail-loud issue fetch.

## Impact

- Code: `scripts/board.py`, `scripts/blocked-dependency.sh`, `scripts/spawn-issue-manager.sh`.
- Tests: `scripts/test-board.sh`, new `scripts/test-blocked-dependency.sh`, new
  `scripts/test-spawn-issue-manager.sh`.
- Docs and agent text: the eight files listed under Text updates.
- Existing `blocked` labels are not migrated; the owner removes the wrong ones by hand, including
  79 here.
- Out of scope: tracking issues for non-issue blockers, a new label, a `migrate` mode, any change to
  `sweep` or to how `finalize` calls it, and removing blocked issues from IN FLIGHT or BLOCKED ON
  YOU.
