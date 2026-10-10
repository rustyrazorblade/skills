# Overrides and conflicts: issue-96

## Overrides existing behavior

None — no baseline spec under `openspec/specs/` covers the easy-db-lab plugin.  The existing specs (`backlog-overlap`, `blocked-dependency`, `delivery-board`, `explain`, `idea-refinement`, `issue-body-edits`, `issue-closure`, `issue-manager-spawn`, `owner-presentation`, `repo-config`, `test-policy`, `walkthrough`) cover spec-flow and dev-skills, not easy-db-lab.  Both capabilities in this change, `easy-db-lab-report-upload` and `easy-db-lab-tool-discovery`, are new, with only ADDED requirements.

This change still alters existing *skill* behavior that no baseline spec records:

- The plan skill no longer tells authors to add teardown steps.  It loses the gap-check bullet at `plan/SKILL.md:138`, the "Tear down (if applicable)" outline step at `:231`, and the quality-gate bullet at `:281`.  Teardown moves to the run skill's Completion gate.
- `plugins/easy-db-lab/references/commands.md` is deleted.  The run and plan skills lose their fallback to it (`run/SKILL.md:46`, `:220`; `plan/SKILL.md:66`, `:272`, `:301`).  A skill with no binary now stops instead of reading a stale copy.
- Run Completion Option 2 changes from a bare `$EDB down` to an upload-gated `$EDB down --auto-approve`, and an unattended run with no teardown intent now stops with "cluster still up".
- Explore Teardown gains an upload gate and loses the `--clickhouse.backup` example.
- Explore resolves `$EDB` through `detect-cluster-layout.sh` and discovers help-first.

## Conflicts with other in-flight changes

None — `ls openspec/changes | grep -v archive` lists only `issue-96`.  No other open change touches the easy-db-lab plugin.
