---
name: refactor
description: >
  Plan and execute a behavior-preserving structural change, then hold the refactoring contract for the whole run.  Use this skill when the user says "refactor this", "clean up this code", "restructure", "extract this", "split this up", "pay down tech debt", or "the tests are fighting me"; when the work is a `type:tech-debt` issue; or at the REFACTOR step of a TDD cycle.  It produces a written plan for the owner to approve before anything is deleted or moved, and it governs every failing test after that.  It is for behavior-preserving work only.  Do not use it for a behavior change; tests are supposed to fail for those.
argument-hint: "[target to refactor]"
---

# Refactor

Structure changes; behavior does not.  This skill has two parts, because a plan alone enforces nothing.

**Part 1 is the plan.** You write it before you delete or move anything, and the owner approves it.

**Part 2 is the standing contract.** Rules R1, R2, and R3 bind you for the whole run.

## Do not use this skill for a behavior change

A behavior change is supposed to break tests.  This skill treats a broken test as evidence of a mistake, so it gives the wrong answer for feature work.  Use ordinary TDD instead.

If the work mixes both, split it.  Land the structural half first, under this skill.  Then make the behavior change as its own commit.  That split is R4, and Part 1 sequences it for you.

## The contract is live, not advisory

This text is in your context right now, and it stays there.  So the triage gate below applies at the moment a test actually goes red, not only while you plan.  Read R2 again at that moment.  Do not act from memory of it.

The full rules live in `references/refactoring-discipline.md` in this plugin.  That file is the source of truth.  This skill carries what you need, because you may not be able to read that file from another plugin root.

## Part 1 — Write the plan first

Produce a written, reviewable plan.  Do not delete, move, or rename anything until the owner approves it.

### 1. Name the target and the spec

State what you restructure, and state the spec that defines its contract.  The spec is one of these:

- the committed OpenSpec spec, for a normal issue;
- the `## Direction` and `## Acceptance criteria` sections, for a `type:tech-debt` issue;
- characterization tests you write **first**, for untested legacy code.

If the code has no tests, you cannot refactor it.  You can only change it and hope.  Write characterization tests first.  Pin what the code does now, including behavior that looks wrong.  Assert the observed output, not the intended output.  These tests detect change; they do not judge correctness.  That is R6, and it settles R2's hardest cases in advance.

If you cannot identify the spec, stop.  Report it to the owner as a spec gap.

### 2. Sequence the work by R4 and R5

R4: a structural change and a behavioral change never share a commit.  Make the change easy, then make the easy change, in two commits.  A commit that moves code and alters behavior cannot be bisected or reviewed.  Land the structural move green first.

R5: to remove an API that callers depend on, use parallel change.  Do not edit it in place.

1. **Expand** — add the new API beside the old one.  Both work.
2. **Migrate** — move callers one at a time.  Go green between each one.
3. **Contract** — delete the old API and its tests, as a deliberate step.

The old path's tests die at contract time.  Never repair them to pass against the new API.  That deletion is the point of the step, and it gets its own commit citing the spec line.

Write the sequence as an ordered list of commits.  Mark each one structural or behavioral.

### 3. List every test you expect to die

For each test, give three things:

- the test's name and file;
- the spec line that kills it;
- the R2 classification that applies.

A test you cannot classify in advance is a spec gap.  Raise it in the plan.  The owner decides spec gaps.

### 4. Name the prerequisites

Write each dependency in this form: "X cannot move until Y is done."  These become the leaves you commit from later.

### 5. Stop and present the plan

Give the plan to the owner.  Wait for approval.  Do not begin execution until you have it.

## Part 2 — The standing contract

### R1 — A refactor preserves behavior

That is what the word means.  So a failing test has exactly two explanations:

1. The refactor is wrong.
2. The test asserts something that was never part of the contract.

"Edit the test until it goes green" is not a third explanation.  It is how a refactor silently becomes a behavior change that nobody reviewed.

Default to explanation 1.  Prove explanation 2 from the spec before you act on it.

### R2 — Triage before you touch any failing test

Never open a failing test file to "fix it."  Classify it first, from the spec.  Do not classify it from the test body.  The test body tells you what the old code did; only the spec tells you what the contract is.

There are three outcomes, and no others.

| Classification | Action |
|---|---|
| Asserts required behavior | The code is wrong.  Fix the code. |
| Asserts behavior the spec deliberately removed | Delete the test.  Cite the spec line in the commit message. |
| Asserts an implementation detail of a structure that no longer exists | Delete the test.  Name the removed structure. |

**Never repair a test whose subject was removed.  Only delete it.**  A rewrite re-creates the old design's shape in the test suite, and it blocks the refactor you were asked to do.

If you cannot classify a failing test from the spec, stop and report it.  An unclassifiable failure is a spec gap, and the owner decides spec gaps.

### R3 — Revert, do not grind

When an attempt breaks something you did not expect:

1. Revert immediately.  Do not start repairing outward from the breakage.
2. Record the breakage as a prerequisite: "X cannot move until Y is done."
3. Recurse on Y.  Attempt it.  Revert again if it also breaks.
4. Commit only from a leaf: a step small enough to land green on its own.

The revert is the whole method.  An attempt held open while you patch what it broke grows a change nobody can review and nobody can abandon.

Here is the signal that you are grinding: you are editing files you did not plan to touch, to support a change you have not committed.  When you see it, revert.

## Language-specific hazards

Some changes look structural but alter the public contract.  Each language has its own set.  Load your language's style guide and check its hazards before you plan.  Every language agent supplies its own list.

Rust is the worked example:

- a trait-bound change, which reads as a tidy-up but narrows what callers can pass;
- a lifetime change, which reads as a signature detail but alters what callers can hold;
- a feature-gated path, whose tests never run in the default build;
- a `#[cfg(test)]` helper that pins an internal shape you just removed;
- a doctest that breaks when a signature moves.

Treat each hazard as a test you expect to die, and list it in the plan.

## The stopping condition

Editing the same test file more than twice in one unit of work is a signal, not a crime.  It means the classification was probably wrong, or the step was too big.

Treat the third edit as a prompt to re-read R2 and re-classify.  It is not a licence to keep going.

If your instructions name a refactor circuit breaker mode, obey that mode.  If they say nothing about one, nothing halts you.  Re-classify and continue.  Do not invent a stop the owner did not ask for, and do not revert anything on your own initiative.
