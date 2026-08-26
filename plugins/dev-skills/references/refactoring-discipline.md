# Refactoring Discipline

Rules for changing structure without changing behavior. Read this when the
work is behavior-preserving: a refactor, a `type:tech-debt` fix, or the
REFACTOR step of a TDD cycle. It does not apply to a behavior change, which
is what tests are supposed to fail for.

## R1 — The definitional rule

A refactor preserves behavior. That is what the word means.

So a test that fails during a refactor has exactly two explanations:

1. The refactor is wrong.
2. The test asserts something that was never part of the contract.

"Edit the test until it goes green" is not a third explanation. It is how a
refactor silently becomes a behavior change that nobody reviewed.

Default to explanation 1. Prove explanation 2 from the spec before acting on
it.

## R2 — Triage before touching any failing test

Never open a failing test file to "fix it." Classify it first, from the spec,
not from reading the test body. The test body tells you what the old code
did; only the spec tells you what the contract is.

The spec is:

- the committed OpenSpec spec, for a normal issue; or
- the issue's `## Direction` and `## Acceptance criteria`, for a
  `type:tech-debt` issue; or
- for untested legacy code, a characterization test you write first (R6).

Three outcomes, and no others:

| Classification | Action |
|---|---|
| Asserts required behavior | The code is wrong. Fix the code. |
| Asserts behavior the spec deliberately removed | Delete the test. Cite the spec line in the commit message. |
| Asserts an implementation detail of a structure that no longer exists | Delete the test. Name the removed structure. |

**Never repair a test whose subject was removed. Only delete it.** Rewriting
such a test re-creates the old design's shape in the test suite and blocks
the refactor you were asked to do.

If you cannot classify a failing test from the spec, stop and report it. An
unclassifiable failure is a spec gap, and the owner decides spec gaps.

## R3 — Revert, do not grind

When an attempt breaks something you did not expect:

1. Revert immediately. Do not start repairing outward from the breakage.
2. Record the breakage as a prerequisite: "X cannot move until Y is done."
3. Recurse on Y. Attempt it. Revert again if it also breaks.
4. Commit only from a leaf: a step small enough to land green on its own.

The revert is the whole method. An attempt held open while you patch what it
broke grows a change nobody can review and nobody can abandon.

Signal you are grinding: you are editing files you did not plan to touch, to
support a change you have not committed.

## R4 — Structural and behavioral changes never share a commit

Make the change easy, then make the easy change, in two commits.

A commit that moves code and alters behavior at the same time cannot be
bisected, cannot be reviewed, and cannot tell you which half broke the test.
Land the structural move green first.

## R5 — Parallel change, for removing an API

To replace something callers depend on, do not edit it in place:

1. **Expand** — add the new API beside the old one. Both work.
2. **Migrate** — move callers one at a time, green between each.
3. **Contract** — delete the old API and its tests, as a deliberate step.

The old path's tests are deleted at contract time. They are never repaired to
pass against the new API. That deletion is the point of the step, and it
belongs in its own commit citing the spec line that removed the behavior.

## R6 — Characterization tests, before touching untested code

If the code you are about to restructure has no tests, you cannot refactor
it. You can only change it and hope.

Write tests that pin what it does now, including behavior that looks wrong.
Assert the observed output, not the intended output. These tests exist to
detect change, not to judge correctness.

They also settle R2's hardest case in advance: with characterization in
place, you know which assertions encode a real requirement and which encode
an accident of the current implementation.

## Stopping condition

Editing the same test file more than twice in one unit of work is a signal, not a crime. It means
the classification was probably wrong, or the step was too big. Treat the third edit as a prompt to
re-read R2 and re-classify, rather than as licence to keep going.

Whether it also **halts the run** is set per repo, by `SPEC_FLOW_REFACTOR_BREAKER` (see **Refactor
circuit breaker** in `docs/workflow.md`). The orchestrating skill states the active mode in your
instructions when it arms the breaker:

- **`ask`** (the default) — stop, leave the tree as it is, and report the blocker with the
  classification you could not make.
- **`revert`** — revert to the last green commit, then report the same thing.

If your instructions say nothing about the breaker, it is `off` for this run, or you were spawned
outside a skill that arms it. Then nothing halts you: re-classify and continue. Do not invent a
stop the orchestrator did not ask for, and do not revert anything on your own initiative.
