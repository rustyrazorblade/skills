#!/usr/bin/env bash
# Bootstrap the flow workflow's GitHub label vocabulary in the current repo.
# Idempotent — safe to re-run (uses --force to update existing labels).
# Prerequisite: `gh` authenticated and the cwd inside the target GitHub repo.
set -euo pipefail

echo "Creating flow workflow labels in $(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo 'the current repo')…"

# `|| true` on every create defeats `set -e` entirely: unauthenticated, outside a repo, or against
# a repo the token can't write, every call fails, the script exits 0, and the final line reports
# success. The first symptom is then an --add-label failure much later, far from the cause.
# Count instead, and keep gh's own message — a name collision or a transient API error is only
# diagnosable from it, and swallowing stderr just moves the mystery.
failed=0
label() {
  local err
  if ! err=$(gh label create "$@" --force 2>&1); then
    failed=$((failed + 1))
    echo "bootstrap-labels: failed to create '$1': ${err}" >&2
  fi
}

# Priority — exactly one per issue.
label "P0" --color b60205 --description "Priority 0 — drop everything"
label "P1" --color d93f0b --description "Priority 1 — high"           
label "P2" --color fbca04 --description "Priority 2 — normal"         
label "P3" --color 0e8a16 --description "Priority 3 — low / someday"  

# Lifecycle.
label "status:ready"       --color 0052cc --description "Groomed; awaiting activation"                     
label "status:spec-review" --color 5319e7 --description "Spec committed; awaiting owner approval (Seam 1 of 2)"
label "status:in-progress" --color 1d76db --description "Background team implementing"                     
label "status:in-review"   --color 006b75 --description "PR open; awaiting owner GitHub review"            
label "status:addressing"  --color e99695 --description "Resolving owner review comments"                  

# Cross-machine, cross-user coordination — not derivable from any one machine's local session state.
label "agent:active"     --color 0e8a16 --description "An issue-manager is currently claimed/running on this issue"
label "blocked"          --color b60205 --description "issue-manager identified a hard dependency on another unmerged issue"
label "needs-attention"  --color e11d21 --description "issue-manager hit something only the owner can resolve — see issue comments"

# Fast-path trigger — set by groom, read by activate/implement to skip the architect consult,
# design-choice stop, and 5-lens review panel for documentation-only work.
label "type:docs" --color c5def5 --description "Documentation-only change — fast-tracked by activate/implement"

# Owner-approval signal, set directly by the owner (in GitHub or via project-manager) any time —
# this is metadata about how to handle the issue, so it lives in GitHub, not a worktree file.
label "merge-on-green" --color 0e8a16 --description "Merge this PR automatically once required CI checks pass — no review wait"

# Backlog item filed by /tech-debt (dev-skills), and the closed marker issue each of its runs logs
# (the durable timestamp project-manager reads to compute the once-a-week/20-merges cadence).
label "type:tech-debt"    --color fef2c0 --description "Structural improvement filed by /tech-debt (dev-skills) — SOLID, duplication, or layering"
label "tech-debt-review"  --color ededed --description "Marks a closed log issue for a completed /tech-debt (dev-skills) run — audit trail, not a work item"

if [[ $failed -gt 0 ]]; then
  echo "bootstrap-labels: ${failed} label(s) could not be created. The flow pipeline will fail" >&2
  echo "later when it tries to apply one — check 'gh auth status', that you're inside the right" >&2
  echo "repo, and that your token can write labels there. Re-run this script once fixed." >&2
  exit 1
fi
echo "Done. The flow workflow labels (P0–P3, status:*, agent:active, blocked, needs-attention, type:docs, merge-on-green, type:tech-debt, tech-debt-review) are present."
