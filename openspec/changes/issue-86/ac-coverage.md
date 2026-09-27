# Acceptance criteria coverage

| Source | Requirement | Covering scenario(s) | Status |
|--------|-------------|----------------------|--------|
| AC | Open native blocker puts the issue under Blocked as `<number>: <title>` | `delivery-board: An open native blocker blocks the issue` | ✅ Covered |
| AC | Several open native blockers all listed, closed ones left out | `delivery-board: Several open native blockers, one closed` | ✅ Covered |
| AC | Cross-repo native blocker renders as `<number>: <title>`, no repo name | `delivery-board: A cross-repo native blocker` | ✅ Covered |
| AC | Every native blocker CLOSED (completed or not planned), no label → not blocked | `delivery-board: Every native blocker is closed` | ✅ Covered |
| AC | Label, no open native blocker → Blocked with `- ⛔ Blocked by: <reason>` from last `Blocked by:` comment | `delivery-board: The label alone blocks the issue`; `The label reason comes from an add-external comment`; `The newest Blocked by: comment wins` | ✅ Covered |
| AC | `add-external` comment then later `add` comment → label reason stays external | `delivery-board: A later add comment does not replace the external reason`; `A blocked label note comes from the Blocked by: comment` | ✅ Covered |
| AC | Label with no `Blocked by:` comment (incl. older forms) → `- ⛔ Blocked by: see issue comments` | `delivery-board: The label with no Blocked by: comment`; `One issue's comment fetch fails during the concurrent prefetch` | ✅ Covered |
| AC | Both native blocker and label → issue line, one line per open native blocker, one label line | `delivery-board: Both kinds of blocker on one issue` | ✅ Covered |
| AC | Blocked row in IN FLIGHT or BLOCKED ON YOU carries bare `🔒 BLOCKED`, no details | `delivery-board: A blocked in-flight row`; `A blocked row waiting on the owner` | ✅ Covered |
| AC | Blocked stalled issue's spawn command marked `🔒 BLOCKED` | `delivery-board: A blocked stalled issue`; `An unblocked stalled issue` | ✅ Covered |
| AC | `gh issue list` fails → prints gh error, exits non-zero, no empty board | `delivery-board: gh issue list fails` | ✅ Covered |
| AC | Blocked `status:ready` issue absent from READY, never "Next up"; "Next up" falls through | `delivery-board: A blocked ready issue`; `The highest-priority ready issue is blocked`; `Every unclaimed ready issue is blocked`; `A blocked withheld issue is not recommended` | ✅ Covered |
| AC | Blocked issue past ready stays in IN FLIGHT and also under Blocked | `delivery-board: A blocked in-flight issue` | ✅ Covered |
| AC | Blocked issue qualifying for BLOCKED ON YOU stays there and also under Blocked | `delivery-board: A blocked issue waiting on the owner` | ✅ Covered |
| AC | Summary "N blocked" counts both kinds | `delivery-board: The summary counts both kinds` | ✅ Covered |
| AC | `test-board.sh` has a fixture and passing check for each of the 12 listed cases | `delivery-board: The suite passes` (requirement "The test suite covers blocked derivation with a shared row helper" names all 12 cases) | ✅ Covered |
| AC | Fixtures use real `{nodes, totalCount}` shape; fake `gh` fails if `blockedBy` not requested | `delivery-board: The fetch requests blockedBy`; `The fake gh guards the field list` | ✅ Covered |
| AC | `row(**kw)` helper in one shared place; every existing check still passes | `delivery-board: One shared row helper`; `The suite passes` | ✅ Covered |
| AC | `add` → native link and `⛔ Blocked on #M — <reason>` comment, no label | `blocked-dependency: A new dependency` | ✅ Covered |
| AC | `add` cannot create the link → non-zero, says what was and was not applied | `blocked-dependency: The link cannot be created`; `The comment fails after the link lands` | ✅ Covered |
| AC | `add` with existing link → counts as present, posts comment, exits 0 | `blocked-dependency: The link already exists` | ✅ Covered |
| AC | `add-external` → label and `Blocked by: <reason>`; board shows `⛔ Blocked by: <reason>` | `blocked-dependency: An external blocker is recorded` | ✅ Covered |
| AC | `add-external` again → board shows the newer reason | `blocked-dependency: A second external reason`; `delivery-board: The newest Blocked by: comment wins` | ✅ Covered |
| AC | `clear` removes link, posts removal comment not saying M landed, label unchanged | `blocked-dependency: An existing link is removed` | ✅ Covered |
| AC | `clear` with no link to M in this repo → exit 0, no comment | `blocked-dependency: No such link`; `A same-numbered issue in another repo` | ✅ Covered |
| AC | `clear` cannot delete → non-zero, says the link is still there | `blocked-dependency: The link cannot be deleted` | ✅ Covered |
| AC | `clear-external` on labeled issue → label removed, `✅ Unblocked` posted | `blocked-dependency: A labeled issue` | ✅ Covered |
| AC | `clear-external` with no label → exit 0, no comment | `blocked-dependency: No label` | ✅ Covered |
| AC | `clear-external` cannot remove label → non-zero, says board will keep showing it blocked | `blocked-dependency: The label cannot be removed` | ✅ Covered |
| AC | Missing or non-numeric issue numbers → usage listing all five subcommands, exit 2 | `blocked-dependency: A missing issue number`; `A non-numeric issue number` | ✅ Covered |
| AC | `sweep <N>` behaves exactly as today | `blocked-dependency: Sweep on a closed issue` | ✅ Covered |
| AC | `test-blocked-dependency.sh` runs on bash 3.2 with fake `gh`, a passing check per criterion | `blocked-dependency: The test runs on macOS bash`; `A regression is caught` | ✅ Covered |
| AC | Label description and every listed file: label only for non-issue blockers; issue dependencies native link only | `blocked-dependency: The label description`; `No listed file sets the label for an issue dependency` | ✅ Covered |
| AC | No listed file tells an agent to set `blocked` for an issue dependency | `blocked-dependency: No listed file sets the label for an issue dependency` | ✅ Covered |
| AC | No listed file requires `clear` when a blocker lands | `blocked-dependency: No listed file requires clear when a blocker lands` | ✅ Covered |
| AC | `docs/workflow.md` and `issue-manager.md` state the `add-external` / `needs-attention` rule; old definition gone | `blocked-dependency: A wait on a third party`; `The old definition is gone` | ✅ Covered |
| AC | `activate` step 4 and `issue-manager.md` hard-dependency section: external blocker uses `add-external` | `blocked-dependency: An external blocker at activate`; `An external blocker found later` | ✅ Covered |
| AC | "Auto mode never skips past" applies to both kinds of blocker | `blocked-dependency: Auto mode meets either kind of blocker` | ✅ Covered |
| AC | Spawn via `project-manager` for a blocked issue → shows Blocked-section lines as data, spawns only on confirm | `issue-manager-spawn: A blocked issue, owner confirms` | ✅ Covered |
| AC | Owner does not confirm → no spawn, no label change | `issue-manager-spawn: A blocked issue, owner declines` | ✅ Covered |
| AC | Issue not blocked → spawn as today, no extra question | `issue-manager-spawn: An issue that is not blocked` | ✅ Covered |
| AC | `project-manager.md` gets blocker list from the board, does not re-derive from `gh` | `issue-manager-spawn: The blocker list comes from the board` | ✅ Covered |
| AC | Pre-spawn checks in one preflight function; script split into clear parts | `issue-manager-spawn: The preflight function holds every pre-spawn check` | ✅ Covered |
| AC | Every exit path, code, message and check order unchanged | `issue-manager-spawn: Exit paths are unchanged`; `Check order is unchanged` | ✅ Covered |
| AC | `test-spawn-issue-manager.sh` on bash 3.2 with fake `gh` and `claude`; checks exit paths and order; passes before and after | `issue-manager-spawn: The test passes on the current script`; `The test passes after the refactor`; `A reordered check is caught` | ✅ Covered |
| Risk | Merge-order textual conflicts with PR 75 (spec-flow: decide the design at groom, verify it at activate) | — | ⚠️ Excluded — a textual merge conflict in shared doc files, resolved by whichever PR lands second; no behavior a scenario can assert. |
| Risk | Merge-order textual conflicts with PR 85 (spec-flow 0.48.0 — scheduler skill) | — | ⚠️ Excluded — same as PR 75; any scheduler handling of blocked issues belongs on PR 85. |
| Risk | Transition display: old `add`-marked issues carry label and link with no `Blocked by:` comment | `delivery-board: Both kinds of blocker on one issue`; `The label with no Blocked by: comment` | ✅ Covered |
| Risk | `clear` changes meaning (no longer drops the label or says the blocker landed) | `blocked-dependency: An existing link is removed`; `No listed file requires clear when a blocker lands` | ✅ Covered |
| Risk | `blockedBy` is `{nodes, totalCount}`, not a list; may be missing or null | `delivery-board: A missing or null blockedBy`; `The fake gh guards the field list`; `The suite passes` | ✅ Covered |
| Risk | GraphQL cost of nested `blockedBy` on a 400-issue fetch, and `nodes` truncation | — | ⚠️ Excluded — a cost and gh-paging property, not board behavior; no scenario can assert an acceptable cost, and an issue with any returned open node still shows as blocked. |
