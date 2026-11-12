# Test strategy

Plan the tests before you write the first one.  A test written to cover one situation catches that situation and nothing else.  A test written from the behavior's general shape catches the situations nobody thought of.

This guide applies to all work: features, bug fixes, and behavior-preserving work.  It does not replace the repo's own test policy.  The repo's policy still decides which tier runs where and which libraries the repo uses.

## The rule

Before the first RED step, write a short test strategy.  Zoom out from the case in front of you.  Ask what general statement is true of this behavior for every valid input, and what the input space looks like.  Then choose the form of each test from that answer, not from the first example that comes to mind.

A one-off example test is the last choice, not the first.  Use it only when no general form fits.

## Step 1: find the invariants

An invariant is a statement that holds for every input in a class.  Look for these first:

- **Round-trip.** `decode(encode(x)) == x`.  Serialize and parse, compress and expand, write and read back.
- **Equivalence to a model.** The fast, complex code gives the same answer as a slow, obvious version, or as the old implementation.  This is the strongest oracle for an optimization or a rewrite.
- **Idempotency.** Doing it twice is the same as doing it once.
- **Commutativity or order independence.** The result does not depend on the order of the inputs.
- **Monotonicity and bounds.** The output never exceeds a limit, never goes negative, or never shrinks as the input grows.
- **Conservation.** Nothing is lost or created: counts, sums, and sizes balance across the operation.
- **Total behavior.** For any input, the code returns a result or a typed error.  It never panics, hangs, or corrupts state.
- **State-machine consistency.** After any sequence of operations, the system agrees with a simple model of the same sequence.

If you find an invariant, the test is a property over generated inputs, not a list of examples.

## Step 2: choose the form

Choose from the shape of the input space.  Go down this list and stop at the first form that fits.

| Input space | Form | Example |
|---|---|---|
| Large, structured, or unbounded, with an invariant from step 1 | **Property-based test** | A codec round-trips any value a generator builds. |
| Untrusted bytes or text, such as a parser, a decoder, or a protocol handler | **Fuzz test** | A parser never panics on any byte string. |
| A sequence of operations against stateful code | **Stateful property test** | Random put, get, and delete calls agree with a `HashMap`. |
| A finite, known set of cases, such as the members of an enum, each error class, or each boundary | **Parameterized table** | One row per error class, each with its input and its expected error. |
| One specific scenario with no general form | **Example test** | A regression for one reported bug, with the issue number in the name. |

Fuzz testing and property testing are both in scope.  They differ in cost and in where they run:

- A **property test** runs in the normal test command, with a bounded case count.  It is a unit test.
- A **fuzz target** runs for a long time, guided by coverage.  Put it where the repo's policy puts long-running work, such as a nightly job or a separate CI job.  Also add a short, bounded run of each target to the normal suite, or a seed-corpus replay, so that the target cannot rot.

## Step 3: collapse the near-duplicates

If three or more tests differ only in their data, they are one test.  Make them a parameterized table, or a property if an invariant covers them.  A list of near-identical tests hides the rule they share, and it misses the cases between them.

The reverse also applies.  Do not force unrelated cases into one table just to make it shorter.  Each row in a table must test the same rule.

## Step 4: pin every counterexample

When a property or a fuzz target finds a failure, keep the failing input:

1. Shrink it to the smallest input that still fails.  Most property libraries shrink for you.
2. Add it as a fixed regression case: a table row, a seed in the corpus, or the library's regression file.
3. Then fix the code.

A counterexample that is not pinned can stop being generated, and the bug can come back unseen.

## Step 5: keep it deterministic

A generated test must give the same result on every run of the same seed:

- Log the seed on failure, so the failure can be reproduced.
- Bound the case count and the size of generated values, so that the test stays fast.
- Do not generate real time, real randomness, or real network calls inside a property.  Inject them.

## Generators are design work

A good generator is the hard part.  It must produce valid inputs across the whole space, including the edges: empty, one element, the maximum size, unicode, negative numbers, and duplicates.  A generator that only makes "nice" values tests nothing more than an example does.

Build generators from the domain types, not from raw primitives.  If the domain has a constructor that validates, generate through it, so that every generated value is a legal one.  Then write a second generator for invalid input when the error path matters.

## TDD still applies

A property or a table can be the RED step.  Write it, run it, and watch it fail for the right reason before you write the code.  A property that never failed is no more trustworthy than an example that never failed.

When a property fails at RED, the library prints a counterexample.  That counterexample is often a better first example than the one you would have picked by hand.

## What not to generalize

Generalization serves regression-catching value.  It is not a goal of its own.

- Do not write a property that re-states the implementation.  `f(x) == f_impl(x)` tests nothing.  A model must be simpler than the code it checks.
- Do not property-test a dependency.  Test your code around it, as the rest of the test guidance says.
- Do not fuzz code that never sees untrusted or structured input.
- A single real-scenario example test is still right for a reported bug.  Keep it beside the property that covers its class.

## Tools by stack

Use what the repo already declares.  If it declares none, propose one and say so; do not add a dependency silently.

| Stack | Property-based | Fuzzing | Parameterized |
|---|---|---|---|
| Rust | `proptest`, `quickcheck` | `cargo-fuzz` (libFuzzer), `bolero` | `rstest`, `test-case` |
| JVM (Java, Kotlin) | jqwik, Kotest property testing | Jazzer | JUnit 5 `@ParameterizedTest`, Kotest data tests |
| Python | Hypothesis | Atheris, Hypothesis with a high example count | `pytest.mark.parametrize` |
| Go | `testing/quick`, `rapid` | native `go test -fuzz` | table-driven tests |
| JavaScript and TypeScript | `fast-check` | Jazzer.js | `test.each` |

## The strategy note

Write the strategy as a short note before the first test.  Put it in your narration, or in the plan if the work has one.  Keep it to a few lines:

```
Test strategy:
- Invariant: decode(encode(v)) == v for any Value. Property, proptest, generator from Value's constructors.
- Error classes: truncated, bad tag, oversized length. Parameterized table, one row each.
- Untrusted input: Decoder::decode. Fuzz target, bounded run in the suite, long run per TESTING.md.
- Example: issue 412 regression, nested empty map.
```

Report the strategy in your final summary, beside the tests you wrote.  A reviewer checks the tests against it.
