## Overrides existing behavior

None — this change only adds new requirements (the new `walkthrough` capability). It contains no
`MODIFIED Requirements` or `REMOVED Requirements` sections against any existing baseline spec.

## Conflicts with other in-flight changes

None found. The only other open change directory is `openspec-aware-explain-view`, which touches
the `explain` capability exclusively — this change touches only the new `walkthrough` capability
and has no delta-spec overlap with it. (This change's `html_shell.py` extraction does modify
`generate-explain.py`'s implementation, but that's not a spec-level change — no requirement of the
`explain` capability is added, modified, or removed by this change; see proposal.md's Capabilities
section.)
