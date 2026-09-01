# Review policy

**This repo owns this file.** spec-flow reads it and ships no default of its own; if this file goes
away, the pipeline stops rather than falling back to anything. Every line below is yours to change.

Keep it short. `implement` reads it on every run.

## The panel

These lenses run **concurrently** on the branch diff, after implementation and before build:

- **`reviewer`** — does the code do what the approved spec says, and does it follow this repo's own
  conventions (`CLAUDE.md`, the plugin layout rules, the house writing style).
- **`code-reviewer`** — correctness only: logic errors, boundary and edge cases, unhandled error
  paths, ordering, resource leaks.
- **`security-reviewer`** — self-gating. Most changes here are markdown and shell with no
  security-relevant surface, and it approves those without findings. It earns its place on the
  shell scripts, which interpolate issue titles and other people's text into commands.
- **`test-rigor-reviewer`** — whether the change has tests worth their cost. This repo's harnesses
  are cheap to write and easy to write vacuously, so this lens matters more here than the line
  count suggests: it has repeatedly been the thing that noticed a test passing with the fix
  reverted.
- **`observability-reviewer`** — the weakest fit for a plugin repo, since almost nothing here runs
  as a service. Kept because the shell scripts do have failure paths that must not fail silently,
  and that is exactly what it checks. Drop it if it stops earning its slot.

A lens may be any agent this repo can resolve, including one defined in `.claude/agents/`. A named
agent that cannot be resolved stops the run by name — never dropped, never substituted.

## The gate

- **Must-fix** is every finding of severity `blocker` or `major`. `minor` and `nit` never block;
  they go on the pull request for the owner to read.
- The panel **approves** only when every lens reported, every lens approved, and must-fix is empty.
  A lens that returns no result is never counted as an approval.
- A lens that declines **without** naming a `blocker` or `major` earns a synthesized `major`
  finding, `unexplained-non-approval`. Declining is a verdict and has to be justified.
- The panel runs at most **3 rounds**. The last round has no fix pass after it, so that is up to
  two rounds of fixes: review, fix, review, fix, review. If the panel has not approved by then, the
  pull request stays a draft, the outstanding findings go to the owner, and build and polish do not
  run.

## Exemptions

- A **content-only `type:docs`** change skips the panel entirely — a single doc-writing pass runs
  instead. Most changes in this repo are markdown, but a skill or agent file is behavior, not
  content: it is only a docs change if nothing reads it as an instruction.
- A **`type:tech-debt`** change runs the full panel in behavior-preservation mode: there is no
  spec, so `reviewer` checks the diff against the issue's confirmed Direction and the existing
  harnesses rather than against generated scenarios.
