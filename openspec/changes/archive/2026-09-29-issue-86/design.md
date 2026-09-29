## Context

The board derives "blocked" from the `blocked` label alone, and `blocked-dependency.sh` keeps that
label and GitHub's native `blocked_by` link in sync. Nothing removes the label when a blocker
closes, so it goes stale. The native link already knows when its blocker closes. This change makes
the native link the only record of an issue-to-issue dependency and keeps the label only for
blockers that are not issues.

The design was settled at `activate`: one `architect` pass, two `design-critic` passes, and the
owner's decisions after each. Where the owner chose differently from the architect's
recommendation, the owner's choice is the design below, and the recommendation appears only under
Alternatives Considered.

## Goals / Non-Goals

**Goals:**
- An issue is blocked when it has an OPEN native blocker or the `blocked` label, and only then.
- A blocked issue is never offered as ready work, and the board shows why it is blocked.
- `blocked-dependency.sh` gives each kind of blocker its own add and clear.
- A spawn requested through `project-manager` for a blocked issue needs the owner's confirmation.
- The `row(**kw)` test helper and `spawn-issue-manager.sh` are restructured without behavior change,
  each under its own tests.

**Non-Goals:**
- Migrating existing `blocked` labels. The owner removes the wrong ones by hand.
- Gating `spawn-issue-manager.sh` itself, or any spawn route other than `project-manager`.
- Any change to `sweep`, or to how `finalize` calls it.
- Removing blocked issues from IN FLIGHT or BLOCKED ON YOU.

## Decisions

### board.py

- `fetch_issues()` adds `blockedBy` to the `--json` field list and drops `default=[]`. `main()`
  catches the `CalledProcessError` from the issue fetch and calls `fail()` with gh's stderr, which
  exits 1. The PR fetch and the other optional fetches keep their current warn-and-continue
  behavior.
- `build_rows()` sets three fields per row:
  - `blockers`: `(number, title)` for each node in `(issue.get("blockedBy") or {}).get("nodes") or []`
    whose `state == "OPEN"`. A cross-repo node renders from its own `number` and `title`, with no
    repo name.
  - `blocked_label`: `"blocked" in labels`.
  - `blocked`: `bool(blockers) or blocked_label`.
- `prefetch_notes()` fetches a label reason only for `blocked_label` carriers, with the prefix
  `Blocked by:`. `last_comment_matching()` already returns the last matching comment, so the last
  `add-external` wins, and a later `⛔ Blocked on #M — …` comment from `add` never matches. The
  reason is the first line of that comment. With no match, or a failed fetch, the reason is
  `see issue comments`.
- `render_blocked()` renders each blocked row as `  - <number>: <title>`, then
  `    - <number>: <title>` per open native blocker, then `    - ⛔ Blocked by: <reason>` or
  `    - ⛔ Blocked by: see issue comments` when the label is set. The label line renders the
  `Blocked by:` comment's first line after the `⛔ ` prefix.
- `render_row()` appends a bare `🔒 BLOCKED` when `blocked` is set. The reason moves to the Blocked
  section only.
- `render_stalled()` appends `🔒 BLOCKED` to a blocked row's spawn command line.
- `ready_rows` excludes rows with `blocked` set. `compute_next_up()` sees only `ready_rows`, so
  "Next up" falls through with no change to it. IN FLIGHT and BLOCKED ON YOU keep their current
  membership. `blocked_rows` stays keyed on `blocked`, so the summary count covers both kinds.

### blocked-dependency.sh

- `add <N> <M> <reason>`: list N's native `blocked_by` links. If a link to M in this repo is
  already there, count it as present. Otherwise resolve M's id and POST the link. Then post
  `⛔ Blocked on #M — <reason>`. No label. If the link cannot be created, exit 1 and say that
  nothing was applied. If the comment fails after the link exists, exit 1 and say that the link is
  in place and the comment was not posted.
- `add-external <N> <reason>`: add the `blocked` label, then post `Blocked by: <reason>`. On a
  partial failure, exit 1 and name what was applied and what was not.
- `clear <N> <M>`: list N's `blocked_by` links and select the one whose number is M and whose
  repository is this repo. None: exit 0, no comment. Found: DELETE it by id, then post a short
  comment that the dependency on #M was removed, without saying M landed. The label is not
  touched. A failed list or DELETE exits 1 and says the link is still there. A link to an issue in
  another repo is removed by hand.
- `clear-external <N>`: read N's labels and match `blocked` exactly (not as a substring). Absent:
  exit 0, no comment. Present: remove it and post `✅ Unblocked`. If removal fails, exit 1 and say
  the board will keep showing the issue as blocked.
- `sweep <N>`: unchanged.
- Every bad-argument path prints a usage message listing all five subcommands and exits 2.

### Spawn check

`agents/project-manager.md` already checks the board before spawning. Before calling
`spawn-issue-manager.sh` for an issue, `project-manager` looks for that issue in the board's Blocked
section. If it is there, `project-manager` shows the owner that issue's lines from the section, as
data, and asks whether to spawn anyway. It spawns only on a yes. On a no, nothing spawns and no
label changes. An issue that is not blocked spawns as it does today, with no extra question.
`project-manager` does not re-derive "blocked" from gh output. `spawn-issue-manager.sh` gets no
gate.

### spawn-issue-manager.sh refactor

`scripts/test-spawn-issue-manager.sh` is written first, against the current script, with a fake
`gh` and a fake `claude` on PATH that record each call. It checks every existing exit path (code and
message) and the order of the pre-spawn checks. The script is then split into named parts, with the
pre-spawn checks in one preflight function called in the same order. The test passes before and
after.

### test-board.sh

The ~9 copies of the `row(**kw)` factory move to one shared definition first, as its own step, with
every existing check still passing. Only then do fixtures change. A new fixture carries `blockedBy`
in gh's `{"nodes": [...], "totalCount": N}` shape and covers every case in the acceptance criteria.
The fake `gh` fails when the issue-list call does not request `blockedBy`. The existing blocked
fixture, issue 15, moves to the `Blocked by:` form.

## Alternatives Considered

### Blocked row format

- **A: one line per issue, blockers joined inline.** Rejected: several blockers make an unreadable
  line, and the repo's own convention is one item per line.
- **B: the issue on one line, then one indented line per blocker.** Chosen by the owner.
- **C: one row per blocker, repeating the issue.** Rejected: the issue repeats, and the reader must
  regroup rows to see one issue's full set of blockers.

### IN FLIGHT and BLOCKED ON YOU marker

- **Bare `🔒 BLOCKED`.** Chosen by the owner: details live in one place, the Blocked section.
- **Keep `🔒 BLOCKED on <note>`, with the label reason only.** Rejected: it shows only one kind of
  blocker inline and duplicates the Blocked section.

### `blocked` label description

- **"Waiting on something that is not an issue (external PR, a person); see the ⛔ Blocked on:
  comment"** (the architect's recommendation). Rejected: it points at a comment form the owner
  replaced with `Blocked by:`.
- **"Blocked by something that is not an issue. Issue-to-issue waits use the native blocked-by
  link".** Rejected: longer than needed; the docs carry the native-link rule.
- **"Waiting on a non-issue blocker (external PR, a person). Reason: last ⛔ Blocked on: comment".**
  Rejected: same stale comment form as the first.
- **Chosen by the owner:** `Blocked by something that is not an issue`, with the reason in a
  `Blocked by: <reason>` comment, so the label text and the comment read the same way.

### Spawn confirmation

- **A: `spawn-issue-manager.sh` enforces it**, exiting 3 for a blocked issue and spawning only with
  `--confirm-blocked`; `project-manager` asks the owner and re-runs. This was the architect's
  recommendation, because it covers every caller. Rejected by an explicit owner override: the
  owner wants the check in `project-manager`, where the owner is talking, and the script free of a
  gate. The board's Stalled marker covers the route the script gate would have caught.
- **B: `project-manager` checks and asks before calling the script.** Chosen by the owner.
- **C: a separate `check-blocked.sh` that callers run first.** Rejected: it is no more enforced than
  B and costs every caller two calls.

### Where `project-manager` gets the blocker list

- **Read the board's Blocked section.** Chosen: `project-manager` already checks the board before any
  spawn, and the board is the single authority on what counts as blocked.
- **Query `gh issue view <N> --json blockedBy,labels` plus the label reason comment itself.**
  Rejected: it duplicates the board's classification rule in agent prose, where it would drift.

### Old gh without `blockedBy`, and any issue-fetch failure

- **Fail loud: print gh's error and exit non-zero.** Chosen: an empty board looks like a clean
  repo, which is worse than no board.
- **No change (warn and render an empty board).** Rejected for that reason.

### Script tests for `blocked-dependency.sh`

- **New `test-blocked-dependency.sh` with a fake `gh` on PATH.** Chosen: every criterion is checked
  mechanically, on bash 3.2.
- **Manual verification only.** Rejected: the partial-failure paths cannot be reproduced by hand
  against live GitHub.

### `clear` scope for cross-repo links

- **This repo only; a cross-repo link is removed by hand.** Chosen: the command takes a bare issue
  number, which names an issue in this repo.
- **Also match links to other repos.** Rejected: a bare number is ambiguous across repos, and a
  wrong DELETE removes a real dependency.

### `add` when the link already exists

- **Count it as present, post the comment, exit 0.** Chosen: re-running `add` with a new reason is
  a normal act.
- **Treat it as a failure.** Rejected: it would report failure for the desired end state.

### Structural debt near the change

- **Fold both in: the `row(**kw)` consolidation and the `spawn-issue-manager.sh` refactor, each with
  its own tests.** Chosen by the owner.
- **File separate issues.** Rejected: both files are open in this change already, and the fixtures
  this change adds would otherwise add more copies of the helper.

### `Blocked by:` match rule and rendered label line

- **Exact, case-sensitive `Blocked by:` at the start of the comment; rendered as
  `- ⛔ Blocked by: <reason>`, or `- ⛔ Blocked by: see issue comments` with no match.** Chosen: only
  `add-external` writes that form, so nothing else can match.
- **A looser match (case-insensitive, or also the older `⛔ Blocked on:` forms).** Rejected: the
  older forms include `add`'s `⛔ Blocked on #M` comments, which are not label reasons, and a later
  `add` would replace the external reason.

### Test for the `spawn-issue-manager.sh` refactor

- **New `test-spawn-issue-manager.sh`, written against the current script before the refactor.**
  Chosen: it is the only evidence that the refactor preserved behavior.
- **No test.** Rejected: a 640-line script with many exit paths cannot be checked by reading.

## Risks / Trade-offs

- **Merge order with PR 75 (spec-flow: decide the design at groom, verify it at activate).** It
  rewrites `skills/activate/SKILL.md` steps 1 and 4, `agents/issue-manager.md`,
  `agents/project-manager.md`, `docs/workflow.md` and `bin/bootstrap-labels.sh`. Whichever lands
  second resolves textual conflicts. No semantic dependency.
- **Merge order with PR 85 (spec-flow 0.48.0 — scheduler skill).** It touches
  `agents/project-manager.md` and `docs/workflow.md`. Textual conflicts only. Any scheduler-side
  handling of blocked issues belongs on PR 85.
- **Transition display.** Issues marked by the old `add` carry both the label and a native link, and
  no `Blocked by:` comment. Until the owner removes the label by hand, their Blocked rows show the
  native blocker line and `- ⛔ Blocked by: see issue comments`.
- **`clear` changes meaning.** It no longer removes the label and no longer says the blocker landed.
  A caller that relied on the old `clear` to drop the label now needs `clear-external`. The text
  updates remove every instruction to call `clear` when a blocker lands.
- **`blockedBy` is `{nodes, totalCount}`, not a list.** Code that iterates it as a list sees the two
  keys. Fixtures use the real shape, and a missing or null `blockedBy` means no blockers.
- **Fetch cost.** Nested `blockedBy` on a 400-issue list adds GraphQL cost, and gh may truncate
  `nodes`. An issue with a truncated open blocker still shows as blocked if any returned node is
  open.
