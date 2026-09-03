| Source | Requirement | Covering scenario(s) | Status |
|--------|-------------|----------------------|--------|
| AC | 15 ungroomed issues report as a count, with no ungroomed row rendered | `delivery-board: A large ungroomed backlog` | ✅ Covered |
| AC | Board length does not vary with backlog size | `delivery-board: Backlog size does not change board length` | ✅ Covered |
| AC | No BLOCKED ON YOU header when nothing is blocked on the owner | `delivery-board: No issues are waiting on the owner` | ✅ Covered |
| AC | No archive line and no `specs pending archive: 0` when nothing is pending | `delivery-board: Nothing is pending archive` | ✅ Covered |
| AC | "Next up" names the P0 issue when unclaimed ready issues exist at P0 and P2 | `delivery-board: Several ready issues at different priorities` | ✅ Covered |
| AC | No "next up" line when no unclaimed ready issue exists, even with a non-empty backlog | `delivery-board: No ready issues exist`; `delivery-board: The backlog is the only work available` | ✅ Covered |
| AC | "Next up" never recommends merging a green in-review PR, in any liveness state | `delivery-board: A green PR is waiting on the owner's review` | ✅ Covered |
| AC | A parked `needs-attention` issue renders under BLOCKED ON YOU but is not named by "next up" | `delivery-board: An agent is stopped waiting on the owner` | ✅ Covered |
| AC | Archive suggestion renders with its count when specs are pending | `delivery-board: Specs are pending archive` | ✅ Covered |
| AC | A `P1` row shows `1️⃣`, not the text `P1` | `delivery-board: A prioritized issue renders` | ✅ Covered |
| AC | Prioritized and unprioritized rows in one section stay column-aligned | `delivery-board: An unprioritized issue renders alongside prioritized ones` | ✅ Covered |
| AC | Blocked/needs-attention notes render with the same content as before the prefetch change | `delivery-board: Blocked/needs-attention notes render unchanged` | ✅ Covered |
| AC | A failed `gh issue view --json comments` call falls back to `"see issue comments"` for that row alone | `delivery-board: One issue's comment fetch fails during the concurrent prefetch` | ✅ Covered |
| AC | `test-board.sh` exits 0 after the change | `delivery-board: Test suite passes after the change` | ✅ Covered |
| Retained scope | `render_board()` structured as one function per section | `delivery-board: A section with no content contributes no lines` | ✅ Covered |
| Risk (re-scope) | The original invariance requirement — "next up reads the full backlog, never the capped view" — was unfalsifiable: `backlog` is sorted by (priority, number) before any cap applies, so the top row is always inside it | — | ⚠️ Removed — the requirement, its scenario and its two assertions are deleted. "Next up" no longer reads the backlog at all, so the property has nothing left to describe |
| Risk (re-scope) | Deleting the BACKLOG section leaves no view of ungroomed work until a backlog agent exists | — | ⚠️ Accepted — owner is grooming interactively for now; a backlog agent and its view are explicitly out of scope for this issue |
| Risk (rendering) | A keycap emoji is three codepoints but renders in ~2 cells, so `f"{p:3}"` padding misaligns every row | `delivery-board: An unprioritized issue renders alongside prioritized ones` (tasks.md 6.2 states the mechanism) | ✅ Covered |
| Risk (rendering) | Removing sections could leave stray blank lines where a section used to emit its trailing `""` | `delivery-board: No issues are waiting on the owner` (asserts absence of the header, not just its rows) | ✅ Covered |
| Risk (regression) | `main`'s `test-board.sh` is shellcheck-clean; the branch's was not | — | ✅ Covered — tasks.md 7.11 makes a clean `shellcheck` run part of the definition of done |
