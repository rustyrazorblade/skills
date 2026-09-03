---
name: complexity-reduction
description: >
  Measure cognitive complexity and duplicate code with PMD (Java) or rust-code-analysis-cli
  (Rust), then reduce both by pure-move extraction, re-measuring after every step.  Runs over a
  subsystem or over a PR diff.  Use this when the user asks to simplify, refactor, clean up, or
  reduce the complexity of a subsystem, asks "how complex is X", asks to find duplicate code, asks
  to make code "beautiful", or asks for a complexity check on a diff or PR.  It measures before it
  edits and re-measures after; it never accepts an unmeasured claim that a change helped.  It
  reports only, unless the user passes `--refactor`.  It is not `/simplify`, which reads the
  current diff and has no metric.
---

# Complexity reduction, measured

Reduce cognitive complexity and duplication in a **subsystem** or in a **diff**.  Every claim is a
number from a tool.  Every edit is a pure move: behaviour identical, only the shape changes.

Cognitive complexity **at or above 15** for one function marks a potential problem, in every
language below.  It is a threshold to report, not a rule to enforce.

## 1. Tools

Pick the tool by language.  Never report a number you did not measure.

### Java: `pmd`

`pmd` (Homebrew: `brew install pmd`).  Two of its commands matter.

```bash
pmd check -R <skill dir>/pmd-complexity.xml --file-list <list> -f csv -r <out>.csv --no-progress
pmd cpd --minimum-tokens 45 --language java --file-list <list> --format csv
```

`pmd-complexity.xml` beside this file enables CognitiveComplexity (report level 15),
CyclomaticComplexity and NPathComplexity, and nothing else.

### Rust: `rust-code-analysis-cli`

Install it with cargo.  **`--locked` is required**: without it, v0.0.25 fails to compile, because
the dependency graph resolves two different `tree-sitter` versions (0.20 expected, 0.27 found).

```bash
cargo install --locked rust-code-analysis-cli
```

Measure, then pull out every function at or above the threshold:

```bash
rust-code-analysis-cli -m -p <path> -O json --pr > <out>.json
```

Scores live in a **recursive** `spaces[]` tree, at `metrics.cognitive.sum`.  A flat filter misses
nested functions and closures, so recurse:

```bash
jq -r '
  def scores($file):
    (if .kind == "function" then
       "\($file):\(.start_line)\t\(.name)\t\(.metrics.cognitive.sum)"
     else empty end),
    (.spaces[]? | scores($file));
  . as $r | $r | scores($r.name)' <out>.json \
  | awk -F'\t' '$3 >= 15'
```

`-p` takes a file or a directory.  For a list of files, **repeat the flag** — `-p a.rs -p b.rs`.
A space-separated list after one `-p` fails, which is exactly the case diff mode hands you.  Pass
`-I '*.rs'` to include and `-X` to exclude by glob.

There is no `cpd` equivalent here, so duplication in Rust is a read, not a measurement.  Say so
rather than implying a tool checked it.

### Reading the metric

Cognitive Complexity is the SonarSource metric.  It charges for nesting depth, so a triply-nested
condition costs far more than three flat ones.  That is why extraction of a deeply nested region
buys more than extraction of a long flat one, and it is why you always attack the deepest nesting
first.

`cpd` finds only near-identical token runs.  It cannot see a repeated *decision* whose branches
differ.  Read for that yourself; it is usually the more valuable finding.

## 2. Pick the mode, then define the file set

Two modes.  Ask the user which one if the request does not say.

| Mode | File set | Ends at |
|---|---|---|
| **Subsystem** (default) | The files a feature owns | Section 4, unless `--refactor` |
| **Diff** | The files a diff or PR changes | Section 4, unless `--refactor` |

The mode picks the file set.  `--refactor` decides whether anything gets edited, and it is the
only thing that does.

### Diff mode

Score **whole changed files**, not only the functions the diff touched.  A small edit can push a
neighbouring function past the threshold, and touched-only scoring hides that.  Mark which
findings the diff introduced and which were already there, so the author sees what they own.

```bash
git diff --name-only --diff-filter=d <base>...HEAD -- '*.java'   # or '*.rs'
```

Use the PR's merge base as `<base>`, not `HEAD~1`: a branch of several commits is one unit of
review.  `--diff-filter=d` drops deleted files, which no tool can measure.

### Subsystem mode

Ask the user what the subsystem is if it is not obvious.  Do not guess, and do not default to the
diff.

In a git repo, the reliable way to find the files a feature owns:

```bash
git log --format='%H' --grep='<feature>' -i | while read -r c; do
  git show --diff-filter=A --name-only --format='' "$c" -- 'src/**/*.java'
done | sort -u
```

Beware false positives: an unrelated old commit whose subject contains the same word.  Read the
commit subjects and drop the ones that do not belong.

Add the files the branch modifies.  Then say plainly which files the feature **owns** and which are
pre-existing, because that changes what is safe to touch.

## 3. Baseline, before any edit

Record all four.  Without them you cannot prove the work helped.

1. The complexity tool: total points, function count at or over threshold, and the per-file
   breakdown.  PMD reports all three directly; for Rust, sum `metrics.cognitive.sum` yourself.
2. Duplication: the CPD blocks.  Rust has no CPD, so record "not measured" rather than "none".
3. Tests: the subsystem's tests, run on a clean build, and the passing count.
4. Any performance guard the project already has, for example an allocation test that prints
   measured bytes.  Record the numbers it prints, not just that it passed.

**Read the test verdict from the runner's structured output, never from its exit code.**  For a
JUnit result XML, treat `tests="0"` as a failure: it means the class never started.  For
`cargo nextest`, read the summary line, and treat a zero-test run the same way.

## 4. Report before you edit

Group the findings.  For each, give the location, the measured cost, and the concrete change.  Say
which findings are in code the feature owns and which are pre-existing.

Do not rank findings by urgency and do not recommend an order of work.  State the facts and let the
user choose.

**Stop here unless the user passed `--refactor`.**  Reporting is the default in both modes.
Sections 5 through 8 edit code; run them only on `--refactor`.  Never start extracting because a
score looks bad, and never treat a bad score as the user asking you to fix it.

## 5. The constraints that outrank tidiness

Read the subsystem's own documentation first.  A hot path usually carries promises that a naive
extraction breaks.

- **Allocation-free means allocation-free.**  If a class documents that it allocates nothing per
  row or per cell, an extraction may not return a new object.  Use a reusable holder field.
- **No extra copying.**  A buffer swap must stay a reference swap.  Never turn an alias into a copy
  to make a signature nicer.
- **Pure move only.**  If an extraction changes behaviour, it is not this skill's work.  Stop and
  raise it.
- **Coverage must not shrink.**  A deleted or skipped test is a finding, not a simplification.

Extraction changes JIT inlining in both directions.  Never claim smaller is faster.  Measure.

## 6. Work order

Deepest nesting first.  Extract the innermost region before the region containing it, or the outer
extraction simply inherits the score.

Re-run the complexity tool after **each** extraction, not once at the end.  Then you can say which
extraction bought what, and you notice immediately when one buys nothing.

## 7. Commit discipline

One commit per kind of change.  Duplication removal and complexity extraction are separate commits;
their diffs are unreadable when mixed.

Never amend unless the user says to.  Never push.

If the repo uses a rebased branch stack, a new commit on a lower branch invalidates every branch
above it.  Say so, and rebase when the user asks.

## 8. Verify, then report

Clean build.  Run the subsystem's tests.  Compare against the Section 3 baseline:

- test count must not drop
- performance guard numbers must not regress
- the complexity total must fall, and no function may rise

Report the before and after side by side.  If a number moved the wrong way, say so plainly rather
than reporting the ones that improved.
