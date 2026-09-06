## Context

`board.py` renders the delivery board deterministically so the model prints its stdout and never pulls raw GitHub JSON into context. Change d71dd34 bounded the two categories that grow without limit, the ungroomed backlog and the epic list, by reporting them as counts in the summary line. It did so on a stated premise: every bucket rendered as rows is bounded by how many agents can run at once.

READY breaks that premise. `groom` adds `status:ready` issues; only `activate` removes them. A repo that grooms faster than it activates renders an ever-longer READY block, which is the cost the script exists to avoid. The module docstring at `board.py:10-12` and `render_summary`'s comment at `board.py:406-409` both still assert the false premise.

Two constraints shape the design. `compute_next_up` must keep seeing every ready issue, because the board's one recommendation is the highest-priority unclaimed ready issue and a cap must not hide it. And `test-board.sh` must keep passing every pre-existing assertion, because the suite is the only guard on a script nothing else tests.

An `architect` pass produced this design and a `design-critic` pass attacked it. The critic's high finding is folded in below; its full findings are in `.spec-flow/design-critique.md` in the worktree.

## Goals / Non-Goals

**Goals:**

- Bound the board's rendered length against a growing ready queue.
- Keep the board's recommendation unchanged by the cap, structurally rather than by convention.
- Disclose what the cap hides, and name the remedy.
- Reject a nonsensical limit before any GitHub call.
- Break no pre-existing assertion.

**Non-Goals:**

- Capping `IN FLIGHT`, `BLOCKED ON YOU`, `UNRECOGNIZED STATUS`, `Stalled` or `Blocked`. Collapsing their render helpers is in scope; capping them is not.
- Changing the READY sort order or which issues belong to the bucket.
- Changing what `compute_next_up` recommends.
- A separate uncap flag. A large `N` is the uncap.

## Decisions

**D1. The cap lives in `render_ready`, not in `render_board`.**

`render_board` keeps holding the full `ready_rows` list and passes it to both `compute_next_up` and `render_ready`; only `render_ready` slices. This makes the "next up sees everything" rule structural rather than a comment: `render_board` never holds a truncated list, so no future edit can pass one to `compute_next_up` by mistake.

The slice needs no sorting. `staged.sort(key=(priority_key, number))` at `board.py:473` runs before bucketing, so `ready_rows` already arrives in priority order and the first N are the N highest-priority ready issues. The comment must say so; a slice of an unsorted list would be arbitrary.

**D2. The limit threads through as a defaulted fourth parameter.**

```python
def render_board(rows, me, archive_pending, ready_limit=DEFAULT_READY_LIMIT):
```

`DEFAULT_READY_LIMIT = 5` is declared directly above `render_ready`, where the file's own docstring says each rule lives beside the code that implements it.

**D3. `main()` must pass `args.ready_limit` through.**

`board.py:578` is `print(render_board(rows, me, archive_pending))` and becomes `print(render_board(rows, me, archive_pending, args.ready_limit))`. This is the critic's high finding: the original brief counted four call sites, all in `test-board.sh`, and missed this fifth one. Without the edit the flag parses, validates, and is then discarded, so the CLI always renders 5 while every in-process test passes.

**D4. `N < 1` is rejected by an argparse `type=` callable.**

```python
def positive_int(value):
    try:
        n = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected an integer, got {value!r}")
    if n < 1:
        raise argparse.ArgumentTypeError(f"must be 1 or more, got {n}")
    return n
```

Verified by running all four cases: `0` and `-1` exit 2 with empty stdout and `board.py: error: argument --ready-limit: must be 1 or more, got …`; `abc` exits 2 with `expected an integer`; `2` exits 0 and renders. `parse_args()` is the first statement in `main()`, before the binary checks and before any `gh` call, so no board can print on the error path.

**D5. `max(0, …)` is the guard against a negative count, and it stays.**

```python
withheld = count_bit(max(0, len(ready_rows) - limit), "more ready", "more ready")
```

The original brief called `count_bit`'s zero contract the whole guard. The critic disproved that: `count_bit(-3, …)` returns `'-3 more ready'`, because `if not n` is false for a negative. The `max(0, …)` is therefore load-carrying and must not be removed as redundant. Passing the plural explicitly avoids `1 more readys`. An empty ready list never reaches the expression, because `if ready_rows:` short-circuits.

**D6. The withheld line names the remedy.**

`  … 4 more ready — raise --ready-limit to see the rest`, on its own line inside the READY block, directly under the rendered rows. The two-space indent is fixed by the block: `render_row` prefixes every row with two spaces, and `section()` in `test-board.sh` selects a block by exactly that indent.

**D7. Row counts are taken inside the extracted READY block.**

`grep -cE '^  ready +#[0-9]+'` over the whole board also matches a ready row rendered under BLOCKED ON YOU — fixture 1's live render contains exactly such a row. Counting inside the extracted block removes the trap. This is what makes the `section()` split worth folding in.

**D8. The OpenSpec delta ADDs rather than MODIFIEs.**

`openspec/specs/` holds only `explain/`; `delivery-board` exists solely in the un-archived `openspec/changes/issue-46/specs/delivery-board/spec.md`, whose first line is `## ADDED Requirements`. There is no base requirement to modify. Both archive orders work, because both deltas are pure ADDs of distinct requirements. "Unbounded categories report as counts, never as rows" stays true as written about the backlog and epics.

## Alternatives Considered

**For D2, the plumbing.** All three options came from the architect; the owner did not override the recommendation.

- **A module-level constant reassigned in `main()`.** Rejected. It makes the render depend on hidden process state, so an in-process test cannot render two limits in one block, and `render_board` stops being a pure function of its arguments.
- **A `RenderOptions` dataclass.** Rejected for now. One option does not earn a type, and it would change the signature for every existing caller. It becomes the right move at the second or third option; note it then, not now.
- **A defaulted parameter.** Recommended and chosen. It is explicit, keeps `render_board` pure, and — decisively — the four in-process `board.render_board(rows, "me", 0)` calls in `test-board.sh` keep working untouched, so every pre-existing assertion survives without an edit.

**For D4, rejecting `N < 1`.**

- **A manual check after `parse_args` calling the file's own `fail()`.** Rejected. It gives exit 1 and drops the usage line, filing a usage error under the same exit code as a runtime failure.
- **`parser.error()` after parse.** Rejected. Same exit 2, but without argparse's `argument --ready-limit:` prefix, and it duplicates validation the `type=` callable does for free on the non-numeric case.

**For D6, the withheld line's text.** This one was the owner's call, not the architect's.

- **`  … 4 more ready (--ready-limit 5)`.** Rejected by the owner. It names the current value but not the remedy. The board pairs a fact with its remedy everywhere else: `🔴 STALLED — no agent:active label`, `🗄️  2 specs pending archive → /spec-flow:archive`.

**For the withheld count's placement**, settled at the step 1 owner review before design began.

- **Folding the count into the summary line via `count_bit`,** reading `(15 ungroomed, 4 more ready)`. Rejected by the owner, because it separates the count from the block it describes. The issue body was updated to record the choice.

**For the folded-in structural work.** The architect marked three of the four items "recommend as a separate issue" and one "fold into this change". The owner overrode that and folded in all four. This is an explicit owner override of the advisor's recommendation, and it widens the diff well beyond the issue as filed; the issue body and its acceptance criteria were updated to match.

## Risks / Trade-offs

- **Live behavior changes for any repo holding more than five ready issues, with no opt-in.** → That is what the issue asks for. The withheld line is the disclosure, and it names the flag that restores the old behavior.
- **The withheld line reports a count, not which issues.** → An owner hunting a specific ready issue must raise the limit. Accepted; the alternative is rendering the rows the cap exists to suppress.
- **The signature change reaches five call sites.** → Four are satisfied by the default. The fifth is `main()`, covered by D3 and by the spec scenario "A valid value reaches the render", which exercises the CLI rather than the in-process function.
- **The refactors fold in behavior-preserving changes to code the cap does not otherwise touch.** → The pre-existing `test-board.sh` assertions are the guard, including fixture 3's whole-render comparison. The suite must be green before and after each refactor step, not only at the end.
- **`--ready-limit -1e3` errors with `expected one argument` rather than the `must be 1 or more` message.** → Still exit 2, still no board. Not an acceptance criterion; noted so the difference is not mistaken for a defect.
- **If issue 71 is archived and issue-46 never is,** the archived `delivery-board` capability carries the cap requirement but not the "Unbounded categories report as counts" requirement the rewritten docstring describes. → Both are currently queued for the same bulk archive pass, along with `issue-42`, `issue-50` and `issue-53`.

## Open Questions

None. The three decisions that were the owner's — the withheld line's placement, its text, and how much structural debt to fold in — were all settled before generation.
