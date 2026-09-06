## Why

The READY bucket grows without bound. `groom` adds `status:ready` issues and only `activate` removes them, so a repo that grooms faster than it activates renders an ever-longer board. The owner hit this live: an agent's board run printed a large READY block and burned context, which is the exact cost `board.py` was written to avoid.

Change d71dd34 (46: board.py: report unbounded categories as counts, recommend only unowned work) bounded the ungroomed backlog and the epic list on the premise that every remaining bucket is bounded by how many agents can run at once. That premise is false for READY, and both the module docstring and `render_summary`'s comment still assert it.

## What Changes

- `board.py` gains a `--ready-limit N` flag, default 5. The READY bucket renders at most N rows, taken from the front of the already priority-sorted list.
- When rows are withheld, one line inside the READY block, directly under the rendered rows, reports the count: `  … 4 more ready — raise --ready-limit to see the rest`. The line is absent when nothing is withheld.
- `compute_next_up` keeps receiving the full, uncapped list, so the board still recommends an unclaimed low-priority ready issue that the cap hides. The cap lives in `render_ready` alone; `render_board` never holds a truncated list.
- `N < 1` is a usage error. An argparse `type=` callable rejects it before any `gh` call, so no board prints on the error path.
- The module docstring and `render_summary`'s comment stop claiming only two categories are unbounded.
- `skills/board/SKILL.md` documents the flag and its default beside `--user`.
- `test-board.sh` grows assertions for the cap, the withheld line, the usage errors, and the invariants the cap must not break.
- **Folded-in structural work, at the owner's direction.** `section()` in `test-board.sh` splits into `section_in "$text" "$hdr"` so a fixture can extract a block from its own render. The four bucket-render helpers collapse into one `render_section(header, rows)`. The `r not in blocked_on_you` linear scans become a set of issue numbers. The stale `sub_issues`, `sub_total` and `sub_completed` keys leave the `row()` factory copies in the tests.

No flag is breaking. Live behavior changes for any repo holding more than five ready issues, with no opt-in; the withheld line is the disclosure.

## Capabilities

### New Capabilities
- `delivery-board`: how the board bounds its own rendered length, and what it still recommends from the rows it does not render. `openspec/specs/` holds only `explain/` today; `delivery-board` exists solely in the un-archived `openspec/changes/issue-46/`, so this change adds a requirement rather than modifying one.

### Modified Capabilities

None. "Unbounded categories report as counts, never as rows" stays true as written about the ungroomed backlog and the epic list. READY's withheld count is a different mechanism in a different place.

## Impact

- `plugins/spec-flow/scripts/board.py`: `render_ready`, `render_board`, `render_summary`'s comment, the module docstring, `main()`'s argparse block and its `render_board` call, and the three bucketing expressions at lines 502, 507 and 515.
- `plugins/spec-flow/scripts/test-board.sh`: `section()`, fixture 4, the `row()` factory copies, and new in-process assertion blocks.
- `plugins/spec-flow/skills/board/SKILL.md`: the invocation block's flag documentation.
- No external consumer parses the board text. `SKILL.md` instructs the model to print stdout verbatim, and no document embeds a sample render the new line would make stale.
