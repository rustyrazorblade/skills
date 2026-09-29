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

## Confirmation — the before/after examples still match the shipped prose

The examples above are unchanged and still match what was written. AC1's "after" (the retry loop has
no backoff, `C8`) matches `agents/issue-manager.md`'s relay example. AC5's "after" (one canonical
block plus in-place fixes, recommended) matches this change's own design. No example diverged from
the implementation, so none was adjusted.

## Coverage checklist — each acceptance criterion to the file and line that satisfies it

The canonical contract lives in `plugins/spec-flow/docs/workflow.md`, section "Presenting to the
owner" (line 379). Each bound presenter references it and fixes its own emitting instruction in
place.

| AC | Requirement | Canonical rule | Bound emitting instruction(s) |
|---|---|---|---|
| AC1 | Plain terms before any identifier; identifier only as a trailing tag | `docs/workflow.md:389` (rule 1) | `agents/issue-manager.md:90` (0.46.0 sentence reworded); `skills/implement/SKILL.md:437`, `575`; `skills/address/SKILL.md:96` |
| AC2 | One decision at a time by default, wait for an answer | `docs/workflow.md:397` (rule 2) | `agents/issue-manager.md:103` (relay path); `skills/activate/SKILL.md:165` (step 1) |
| AC3 | The owner may override to a batch, for that request only | `docs/workflow.md:400` (rule 3) | `agents/issue-manager.md:103` (relay path); `agents/project-manager.md:324` |
| AC4 | A cited location is described, not just named | `docs/workflow.md:396` (rule 1, last sentence) | `skills/address/SKILL.md:96` (name a thread/comment/test, say what it is) |
| AC5 | Options state cost; recommended one marked, or left to the owner | `docs/workflow.md:403` (rule 4) | `skills/activate/SKILL.md:165` (recommended-default half); `agents/project-manager.md:324` |
| AC6 | A relayed finding is translated, not repeated verbatim | `docs/workflow.md:389` (rule 1, translate clause) | `agents/issue-manager.md:99` (relay-a-review-panel-finding rule) |

Rule split by kind: `docs/workflow.md:408`. Exempt deliberate batches: `docs/workflow.md:414`, with
`groom`'s bulk confirm reconciled at `skills/groom/SKILL.md:189`, `setup`'s check batch noted at
`skills/setup/SKILL.md:14`, and `implement`'s residual list marked exempt at
`skills/implement/SKILL.md:575`. Every-presenter binding: `agents/issue-manager.md`,
`skills/implement/SKILL.md`, `skills/address/SKILL.md`, `skills/activate/SKILL.md`,
`skills/groom/SKILL.md`, `skills/setup/SKILL.md`, and `agents/project-manager.md`.

## Scan — no bound file presents a bare identifier as a referent

A scan of every bound file for identifier-as-referent phrasing (`should I fix C8`, `see C8`, `per
A34`, `cite ... by its identifier`) found only two matches, both inside quoted negative examples in
`agents/issue-manager.md` (line 91 "see C8"/"per A34" both fail; line 103 "should I fix `C8`?" shown
as the wrong form). No instruction directs an agent to present the owner a bare identifier as a
subject or sole referent.
