#!/usr/bin/env bash
# Bootstrap the flow workflow's GitHub label vocabulary in the current repo.
# Idempotent — safe to re-run (uses --force to update existing labels).
# Prerequisite: `gh` authenticated and the cwd inside the target GitHub repo.
set -euo pipefail

echo "Creating flow workflow labels in $(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo 'the current repo')…"

# Priority — exactly one per issue.
gh label create "P0" --color b60205 --description "Priority 0 — drop everything" --force || true
gh label create "P1" --color d93f0b --description "Priority 1 — high"            --force || true
gh label create "P2" --color fbca04 --description "Priority 2 — normal"          --force || true
gh label create "P3" --color 0e8a16 --description "Priority 3 — low / someday"   --force || true

# Lifecycle.
gh label create "status:ready"       --color 0052cc --description "Groomed; awaiting activation"                      --force || true
gh label create "status:spec-review" --color 5319e7 --description "Spec committed; awaiting owner approval (Seam 1 of 2)" --force || true
gh label create "status:in-progress" --color 1d76db --description "Background team implementing"                      --force || true
gh label create "status:in-review"   --color 006b75 --description "PR open; awaiting owner GitHub review"             --force || true
gh label create "status:addressing"  --color e99695 --description "Resolving owner review comments"                   --force || true

# Cross-machine, cross-user coordination — not derivable from any one machine's local session state.
gh label create "agent:active"     --color 0e8a16 --description "An issue-pm is currently claimed/running on this issue" --force || true
gh label create "blocked"          --color b60205 --description "issue-pm identified a hard dependency on another unmerged issue" --force || true
gh label create "needs-attention"  --color e11d21 --description "issue-pm hit something only the owner can resolve — see issue comments" --force || true

# Fast-path trigger — set by groom, read by activate/implement to skip the architect consult,
# design-choice stop, and 5-lens review panel for documentation-only work.
gh label create "type:docs" --color c5def5 --description "Documentation-only change — fast-tracked by activate/implement" --force || true

# Owner-approval signal, set directly by the owner (in GitHub or via project-manager) any time —
# this is metadata about how to handle the issue, so it lives in GitHub, not a worktree file.
gh label create "merge-on-green" --color 0e8a16 --description "Merge this PR automatically once required CI checks pass — no review wait" --force || true

# Backlog item filed by /spec-flow:tech-debt, and the closed marker issue each of its runs logs
# (the durable timestamp project-manager reads to compute the once-a-week/20-merges cadence).
gh label create "type:tech-debt"    --color fef2c0 --description "Structural improvement filed by /spec-flow:tech-debt — SOLID, duplication, or layering" --force || true
gh label create "tech-debt-review"  --color ededed --description "Marks a closed log issue for a completed /spec-flow:tech-debt run — audit trail, not a work item" --force || true

echo "Done. The flow workflow labels (P0–P3, status:*, agent:active, blocked, needs-attention, type:docs, merge-on-green, type:tech-debt, tech-debt-review) are present."
