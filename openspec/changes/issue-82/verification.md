# Verification — issue 82: worked before/after examples

Prose has no unit test. Each acceptance criterion below shows a bad presentation and its compliant
rewrite. These pairs are the definition of done: the contract is correct only if it produces the
"after" in each case.

## AC1 — plain terms before any identifier

**Before:** "Should I fix C8 and SEC-3 before Build?"

**After:** "The review found two things. The retry loop has no backoff, so it can hammer a failing
service (C8). And the auth token is written to the log in plaintext (SEC-3). Want me to fix the
logging one first?"

## AC2 — one decision at a time

**Before:** a single message listing five findings, each with options, all at once.

**After:** the first finding and its options, then a wait for the owner's answer, then the second.

## AC3 — the owner may override to a batch

**Before:** the agent decides on its own to dump the whole set.

**After:** the owner says "show me all five." The agent presents all five for that request, then
returns to one-at-a-time for the next set without being asked again.

## AC4 — a cited location is described

**Before:** "See `reviewer.md:120`."

**After:** "In `reviewer.md`, the lens is told to cite the rule or scenario for each finding (around
line 120). That is the text we would change."

## AC5 — options state cost, recommended one marked

**Before:** "Option A, Option B, or Option C?"

**After:** "Option A: one canonical block plus in-place fixes — most surface to touch, but no drift
(recommended). Option B: restate in each file — no hop, but duplication drift. Option C: pointers
only — cheapest, but likely will not change behavior."

## AC6 — a relayed finding is translated

**Before:** the lead repeats the lens's phrasing "F1: contract violation in the caller/callee
boundary."

**After:** "The review found the function returns null where the caller expects a value, which would
crash the caller (F1)."

## Boundary check — deliberate batches are not broken

The board still lists many issues at once. Seam 1 still renders the whole coverage table. A PR body
still lists all residual findings. None of these is split into one item at a time.
