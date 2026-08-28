# Overrides and conflicts

## Overrides existing behavior

None — this change only adds new requirements. It carries no `## MODIFIED Requirements` and no
`## REMOVED Requirements` section.

That is a deliberate consequence of D5, and it needs stating plainly, because this change *does*
edit two files belonging to another change. `openspec/changes/issue-50/specs/repo-config/spec.md:5`
and `openspec/changes/issue-50/ac-coverage.md:18` are corrected in place rather than overridden by
a delta here. Those corrections are not overrides of the current baseline, because issue 50's
deltas were never synced: `openspec/specs/` holds only `explain/`, so `repo-config` and
`test-policy` are pending requirements that enter the baseline when issue 50 is archived. Amending
a pending requirement is amending a draft.

A `## MODIFIED Requirements` delta targeting `spec.md:5` was considered and is not available — the
requirement it would name does not exist in `openspec/specs/` for a delta to modify.

## Conflicts with other in-flight changes

Three other changes are open: `issue-42`, `issue-50`, and `openspec-aware-explain-view`.

- `issue-42` touches `specs/walkthrough/` only. No overlap.
- `openspec-aware-explain-view` touches `specs/explain/` only. No overlap.
- `issue-50` also touches `repo-config` — **no actual conflict.** It adds eight requirements to
  that capability; this change adds four more, with distinct titles. Neither modifies or removes a
  requirement the other adds, so a bulk archive syncing both into
  `openspec/specs/repo-config/spec.md` has no content to reconcile. This is the condition
  `skills/archive/SKILL.md:51-53` pauses a batch for, and it is not met here.

### Adjacency worth a reviewer's attention, though not a conflict

Two of this change's requirements sit next to issue 50's and tighten them. Recorded here so a
reviewer sees the relationship rather than discovering it at archive time:

- This change's "Seeding reads the repo before it reads the template" adds an ordering constraint
  to the seeding flow that issue 50's "Seeding proposes, confirms with the owner, and lands through
  the repo's normal review flow" (`spec.md:131`) does not describe. It does not relax anything
  there: the propose-and-confirm requirement stands unchanged, and this change explicitly restates
  that nothing is written until the owner confirms.
- This change's "Seeding notes never reach the repo's file" scenario is a specific case of issue
  50's "The seeded file reads as the repo's own editable choice" (`spec.md:164`). It names one way
  that requirement could be breached once a template exists. Additive, not contradictory.

### Archive ordering

Both changes must be archived together or with issue 50 first. Archiving this change alone would
sync a `repo-config` capability whose baseline requirements — the ones this change's requirements
sit alongside — are not yet published.
