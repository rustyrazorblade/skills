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
gh label create "status:spec-review" --color 5319e7 --description "Spec committed; awaiting owner approval (the seam)" --force || true
gh label create "status:in-progress" --color 1d76db --description "Background team implementing"                      --force || true
gh label create "status:in-review"   --color 006b75 --description "PR open; awaiting owner GitHub review"             --force || true
gh label create "status:addressing"  --color e99695 --description "Resolving owner review comments"                   --force || true

echo "Done. The flow workflow labels (P0–P3, status:*) are present."
