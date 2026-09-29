# Overrides and conflicts

## Overrides existing behavior

Four `delivery-board` requirements are MODIFIED. None is REMOVED. `blocked-dependency` and
`issue-manager-spawn` are new capabilities with no baseline.

### "Next up" names only unclaimed ready work, in priority order

**Currently:** The system SHALL recommend at most one issue under "next up", and SHALL draw that
recommendation only from issues carrying the `status:ready` label with no assignee.

**This change:** The system SHALL recommend at most one issue under "next up", and SHALL draw that
recommendation only from issues carrying the `status:ready` label with no assignee that are not
blocked, by an open native blocker or by the `blocked` label. Two scenarios are added: a blocked
top-priority ready issue is skipped in favor of the next one, and no line renders when every
unclaimed ready issue is blocked.

### Concurrent comment prefetch preserves existing note content

**Currently:** The system SHALL fetch blocked/needs-attention issues' comment-derived notes
concurrently (not serially) while preserving the exact note content each issue would have received
under the previous serial implementation, and without changing the total number of `gh` calls made.
(In code, the blocked note comes from the last comment starting `⛔ Blocked on`.)

**This change:** The prefetch stays concurrent and makes one fetch per labeled issue. The
`needs-attention` note is unchanged. The `blocked` label note comes from the last comment starting
with `Blocked by:` (exact, case-sensitive), never from a `⛔ Blocked on` comment. An issue blocked
only by a native link triggers no comment fetch.

### Per-row failure isolation during concurrent prefetch

**Currently:** The system SHALL isolate failures in the concurrent comment prefetch so that one
issue's failed `gh issue view --json comments` call (whether a process error or a malformed-JSON
response) falls back to a fixed placeholder note for that issue alone, without aborting the batch or
affecting any other issue's note. (In code, it renders inline as `🔒 BLOCKED on see issue comments`
and as `— see issue comments` in the Blocked section.)

**This change:** The isolation is unchanged. For a `blocked` label carrier the placeholder renders
as the label line `- ⛔ Blocked by: see issue comments` in the Blocked section.

### The board's recommendation considers every ready issue

**Currently:** `compute_next_up` SHALL receive the full, uncapped ready list. A withheld issue SHALL
still be eligible as the board's recommendation.

**This change:** `compute_next_up` SHALL receive the full, uncapped list of ready issues that are
not blocked. A withheld issue that is not blocked SHALL still be eligible. A scenario is added: a
blocked withheld issue is not recommended.

### Behavior changes outside a MODIFIED requirement

These change behavior the baseline does not specify, so they appear as ADDED requirements:

- `board.py` renders `🔒 BLOCKED on <note>` inline today; it becomes a bare `🔒 BLOCKED`, and
  blocked issues leave READY.
- `board.py` warns and renders an empty board when `gh issue list` fails today; it now fails.
- `blocked-dependency.sh clear` removes the link and the label and posts "✅ Unblocked — #M landed."
  today; it now removes only the link in this repo and posts that the dependency was removed.
- `blocked-dependency.sh add` adds the label today; it no longer does.

## Conflicts with other in-flight changes

None found. `openspec/changes/` holds two other change directories, `issue-77` and `issue-82`. Both
are merged on `main` and wait only for archive.

- `issue-77` (`idea-refinement`) specifies `groom`'s refinement loop. It does not touch
  `delivery-board`, blocked handling, or spawning.
- `issue-82` (`owner-presentation`) binds `project-manager` as an owner-facing presenter. The spawn
  check here presents one yes/no question to the owner with the blocker lines as data, which fits
  that contract: one decision at a time, stated in plain terms. The board itself is an exempt batch
  presentation under `issue-82`. No requirement in either change contradicts this one.

Open PRs outside `openspec/changes/` that edit the same files, PR 75 (spec-flow: decide the design at
groom, verify it at activate) and PR 85 (spec-flow 0.48.0 — scheduler skill), are textual merge-order
risks, recorded in `design.md` under Risks.
