## Context

spec-flow encodes one test/CI policy — fast tier locally, full suite in CI — in five runtime locations. The architect verified all five in this worktree:

| # | Location | What it holds |
|---|---|---|
| 1 | `docs/workflow.md:881-933` | The "Test tiering (unit / integration)" section |
| 1b | `docs/workflow.md:972-977` | A **second** copy under "Substrate and constraints" |
| 2 | `skills/implement/SKILL.md:82-99` | Step 3's TEST INSTRUCTION blockquote, five stack commands |
| 3 | `skills/implement/implement.workflow.js:70` | `const testInstruction`, an independent second copy |
| 4 | `agents/reviewer.md:127-132`, `:142` | `tests_ran: "unit"` asserted unconditionally |
| 5 | `skills/address/SKILL.md:44-47` | The same gate restated for the fix agent |

Owner-facing prose adds `README.md:66-83` and `skills/implement/SKILL.md:70`, `:224`, `:448`, `:545-546`.

**One correction to the issue's framing, from the architect.** The TEST INSTRUCTION is not the only text duplicated between the two `implement` modes. `GUARDRAILS` (`SKILL.md:224` vs `implement.workflow.js:103`) and `REVIEW_GUARDRAILS` (`SKILL.md:243` vs `:108`) are hand-synced the same way. This change fixes one member of a class; the rest is recorded under Risks as a separate issue.

**The motivating problem is portfolio-wide, not a single counterexample.** The owner works across roughly 20 repos, each with its own rules — different CI cost, suite size, stack, and merge gate. No shipped default fits them, so any default the plugin carries is wrong somewhere by construction. `skills` itself is the extreme case: no test-running CI at all, which the shipped policy does not merely mis-describe but fails to describe.

## Goals / Non-Goals

**Goals:**

- The repo's policy file is the single runtime source of test/CI policy, with no fallback anywhere.
- Neither `implement` mode holds policy text, and the one line they do hold cannot diverge between them.
- A repo with no test suite is a first-class, expressible policy — not a degraded or broken state.
- The startup check costs nothing when the repo is configured.
- The script is structured to host later config files (`PROJECT.md`, `ISSUE_PM.md`, `REVIEWERS.md`) without a rename.

**Non-Goals:**

- The `spec-flow-failures` artifact name and `.spec-flow/flagged-tests` path literals stay hardcoded.
- No merge, precedence, or section-override semantics. The repo's file fully replaces the plugin's default.
- No validation that `CI.md` answers any particular question — that is a schema arriving through the back door, and the owner ruled it out explicitly.
- Issue 38's remaining scope (default branch, review-lens mapping, model overrides) is not designed here. It is rewritten as a child issue **after** this merges, against what actually landed.
- The wider `SKILL.md` / `implement.workflow.js` prompt duplication is not fixed here.

## Decisions

### D1 — Policy transport: the agent reads the file

**Chosen: emit a pointer; the agent reads the repo's policy itself.** Both `implement` modes emit a one-line instruction naming a resolved absolute path. No policy text travels.

This follows the plugin's own precedent: `agents/tdd-developer.md:57` already tells the developer to `cat "$CLAUDE_PLUGIN_ROOT/references/refactoring-discipline.md"`.

**Alternative rejected — thread the file's contents through `args`.** The `implement.workflow.js` script cannot read files (see Domain Facts), so its policy text would have to arrive as a string in its `args` payload and be interpolated into a JS template literal. `CI.md` is markdown containing fenced code blocks and shell commands; any backtick or `${...}` in it would break or inject into that literal. A concrete defect with a plausible trigger.

Read-the-file is also the stronger fit for two acceptance criteria: if neither path contains policy text, divergence is structurally impossible rather than merely unlikely; and a plugin holding no commands has none to leak.

**Owner note:** this was an explicit owner override of the lead's initial preference. The lead favored `args`-threading and was overruled on the escaping hazard.

### D2 — No per-agent missing-file handling

**Chosen: the pointer carries no fallback clause.** By the time any agent reads the policy, the check has already run and refused. Adding "if the file is missing…" to every teammate prompt would re-introduce exactly the per-agent policy prose this change deletes.

**Owner note:** the lead initially specified per-agent refusal handling and was told to drop it as unnecessary defensiveness.

### D3 — `SPEC_FLOW_CONFIG_DIR` is repo-relative only

**Chosen: repo-relative; absolute values rejected with an error.** The finding that `.claude/settings.json` performs no interpolation settles this: an absolute value there is a literal, machine-specific path, wrong on every other clone. `scripts/spawn-issue-pm.sh` already carries the in-repo ruling on that exact pattern.

Disambiguation is a leading slash. The script additionally rejects `..` and any character outside `[A-Za-z0-9._/-]`.

**That character restriction is load-bearing, not fussiness.** It is what makes the emitted pointer provably free of backticks, `$`, and braces — so embedding it in a string literal is safe by construction rather than by escaping at the point of use.

### D3a — The repo root is guarded too, and the guard is narrow

**Added during implementation, in response to review.** D3 character-validates `SPEC_FLOW_CONFIG_DIR`, but the repo root is chosen by whoever cloned the repo and is not validated by that rule — yet it is the larger half of the path the pointer carries. Both subcommands now refuse a root they cannot describe safely, so `check` and `instruction` can never disagree about the same repository.

**The list is deliberately narrow, and a wider one is worse rather than safer.** The first implementation rejected `( ) & ; | < > * ? { }` as well, and that refused `Dropbox (Personal)` and `R&D` — directory names macOS creates by default — offering no remedy but re-cloning the repo elsewhere. The reasoning that settles it: **a space is allowed**, and a space already breaks an unquoted shell command, so every consumer must quote the path regardless; once quoted, none of those characters can hurt it. What remains is the set that breaks a consumer even when quoted — backtick and `$` interpolate into a JS template literal, `"` and `\` terminate or escape a JSON string, `'` breaks the shell quoting itself — plus every control character, unconditionally, because a newline would split the one-line pointer and the second line would reach every agent prompt as an instruction.

This does not contradict "Everything present costs nothing": that scenario governs a repo the pipeline can serve, and a root it cannot describe is an environment error (exit 2), the same class as running outside a git repository — not an unconfigured repo (exit 1).

### D3b — Containment is enforced on the resolved path, not merely claimed

**Added during implementation; reverses an earlier decision, on review.** An earlier round softened the "must stay inside the repository" wording rather than enforcing it, reasoning that the threat was a repo owner pointing at their own symlink. That was wrong on two counts. Symlinks are **committable**, so the party in control is the branch under review, not the owner; and every test that decides usability (`-f`, `-r`, and the read itself) follows links, so a committed `spec-flow/CI.md` pointing at `~/.ssh/id_rsa` passed the check while `instruction` emitted an innocent in-repo path that every panel agent then opened.

That is a strict escalation over the branch-controlled-**content** risk this design already accepts: content control lets an attacker assert what they already know; this lets them extract what they do not. The bounding clause in the emitted line does not reach it, because the read happens before anything in the clause is evaluated — the clause governs what the file may direct, never which file is opened.

**This is a path check, not a content check.** The owner's ruling that the check never inspects the policy's text is untouched; nothing here reads the file. `resolve_repo_root` takes the physical root with `pwd -P`, both subcommands resolve the policy directory physically and require it to be inside, and a symlinked policy file is refused whether or not it points outward, because there is no legitimate use for one and allowing it would mean trusting the target to stay put.

### D4 — One script, two subcommands: `repo-config.sh check` and `repo-config.sh instruction`

**Chosen: `plugins/spec-flow/scripts/repo-config.sh`.** The name describes the class of repo config it owns, not the one file it checks today; `CI.md` never appears in it. Adding a later config file is one line in a registry.

Both subcommands need identical repo-root and config-dir resolution; one script keeps that in exactly one place. Two scripts would duplicate it — the failure mode this change exists to remove.

Bash, not Python: the work is two path resolutions and a readability test. `board.py` is Python because it performs a multi-source join and formats a table; this does neither. macOS bash 3.2 throughout — no associative arrays, no `mapfile`, no `${var,,}`. The registry is a newline-delimited, pipe-separated string iterated with `while IFS='|' read`.

**Alternatives rejected:** `check-ci-policy.sh` (renames on the first new config file); `spec-flow-config.sh` (redundant inside the spec-flow plugin).

### D5 — Exit codes distinguish "unconfigured repo" from "broken environment"

**Chosen:** `0` = all present, prints nothing. `1` = missing or unusable, complete message on **stdout**. `2` = environment or usage error, on stderr.

Stdout for exit 1 because the message is the product and the relaying agent prints it; `board.py` uses the same split. The 1-versus-2 distinction drives caller behavior: `implement` and `sync-ci` stop on both, but `project-manager` offers seeding only on 1 — it must not offer to seed a policy file into a directory that is not a repository.

### D6 — Hard cutover, no graced release

**Chosen by the owner: hard.** Every repo already using spec-flow stops at its next `implement` until it seeds a policy.

**Alternative rejected:** one release where the check prints its message and exits 0. A warning that does not stop the run *is* the silent fallback being removed.

### D7 — Seeding lives in `/spec-flow:setup`, and proposes rather than guesses

**Chosen by the owner: a new item in `/spec-flow:setup`,** with git and `gh` mechanics in `scripts/seed-config.sh`. A repo missing `CI.md` is by definition not set up, and `setup` already is the once-per-repo interview that edits `.gitignore` and `.claude/settings.json`. It will host the later config files too.

**Accepted departure:** `setup`'s own rules (`SKILL.md:159-161`) say it makes only local edits and never acts outward. Opening a PR is its first outward action. The owner accepted this on condition it is **written into `setup`'s rules deliberately**, not quietly broken.

**Seeding confirms with the owner before writing anything.** This collapsed a design question rather than answering it. The architect had proposed a `<!-- spec-flow:FILL-IN -->` marker for undetectable stacks, plus a check treating that marker as "unusable". The owner's ruling — everything is confirmed with the owner anyway — removes the need:

- No marker, and no marker check. The startup check stays presence-and-readability only, keeping the "no schema" line absolute.
- The narrow Gradle/Rust detector stops being a constraint. Seeding can propose for any stack, because a proposal the owner confirms is not a guess. Detection only makes the proposal better or worse.
- One less condition for the pipeline to refuse on.

Guessing is only dangerous when it is silent.

### D8 — `tests_ran` becomes policy-relative

**Settled by the acceptance criteria, not open.** The criterion requires the report to reflect the repo's policy rather than assert the unit tier, which the alternative (keep the enum, add only `tests_detail`) fails.

```
"tests_ran": "policy | partial | degraded | none"
"tests_detail": "the exact commands you ran"
```

- `policy` — ran exactly what the policy names, plus the flagged set.
- `partial` — ran some of it; `tests_detail` says which.
- `degraded` — the policy's command could not run; ran something weaker.
- `none`.

The enum stays machine-checkable, so the workflow script's schema validation and result merge keep their shape. Human-readable truth moves to `tests_detail`.

**Running nothing can be full compliance.** Where the policy names nothing to run, running nothing is `policy` — not `none`, not `degraded`. This is what makes a no-test-suite repo a first-class case rather than a permanently-degraded one.

**Amended during implementation, with the owner's approval: a fifth value, `unknown`.** The four values above all describe a test *outcome*, and the workflow script has three positions where it must fill this field with no review having happened at all — the refactor breaker tripped, the spec lens never reported, or no round completed. There is no reviewer report to copy from, and every one of the four is a false statement there: `none` asserts that nothing needed running, `policy` asserts compliance nobody verified. The script reports `unknown` in those three positions, with a `tests_detail` naming why. This follows the existing precedent of the neighbouring `spec_conformance` field, which already reports `unknown` in exactly those spots.

**`unknown` lives in the run summary only, never in the lens-report schema.** `REVIEW_SCHEMA.tests_ran` keeps exactly the four values above, deliberately: a review lens always either ran something or did not, so letting a lens claim ignorance would be worse than the problem it solves. Only the assembled run summary — which can exist without any lens having reported — can be `unknown`. The four-value schema is not a mismatch with this section; it is the point.

`agents/reviewer.md` is a static definition and cannot run the script at definition time, so it carries **no** tier assertion at all and defers entirely to its prompt.

Call sites, verified: twelve files, sixteen lines — `agents/reviewer.md:127-132`, `:142`; `code-reviewer.md:32`, `:35`; `security-reviewer.md:36`, `:39`; `test-rigor-reviewer.md:96`, `:99`; `observability-reviewer.md:73`, `:76`; `implement.workflow.js:44`, `:48`, `:160`, `:283`, `:364`; `skills/implement/SKILL.md:289`.

### D9 — `sync-ci` yields to the policy

**Added during design, from the owner's clarification.** `sync-ci` downloads a `spec-flow-failures` artifact from the latest CI run. In a repo whose policy says CI is not a test gate, that artifact never exists, so as written it would fail looking for something the policy says is not there. It reads the policy first and exits cleanly, reporting why.

Not in the issue's original acceptance criteria; folded in because the owner's driving case makes it reachable immediately.

### D10 — The gitignore hazard is prospective, not present

**Verified by running the checks, not inferred:**

- `git check-ignore -v spec-flow/CI.md` → exit 1, no match. **Not ignored today.**
- `git check-ignore -v .spec-flow/flagged-tests` → matches `.gitignore:7`.

Gitignore treats `.` as a literal, so `.spec-flow/` matches only the dotted directory. **There is no risk from the entry that exists today** — the issue's concern was backwards.

**The prospective hazard is real and, in this repo, severe.** A trailing-slash pattern with no interior slash matches at any depth. If anyone writes `spec-flow/` into this repo's `.gitignore`, it matches `plugins/spec-flow/` and the plugin's entire source disappears from git. The two names differ by one character at the same level, and `setup`'s gitignore item currently hands a model a bare block to add.

Mitigations: an explicit warning in `setup`'s gitignore item and the README; a `git check-ignore` diagnostic in the check when the file is missing; a two-row table in `docs/workflow.md`; and a positive check in `setup` that `spec-flow/` is not ignored.

Rejected: anchoring the existing entry to `/.spec-flow/`. Correct but changes a working line in every consuming repo for no gain.

### D11 — This repo's own policy states there is no test suite

**Chosen by the owner.** `skills` has no Gradle, no Rust, no CI test artifact. Its local gate is plugin validation and shellcheck where applicable; merge is gated on review. Writing that plainly beats inheriting a template that does not apply — and makes this repo a working example of a policy nothing like the former default, which is the point of the change.

## Alternatives Considered

Transcribed from the architect's proposal (`.spec-flow/architect-proposal.md` in this worktree) and the owner's decisions, including options the owner rejected.

| # | Option | Disposition |
|---|---|---|
| D1 | Thread `CI.md` contents through `args` into the JS template literal | **Rejected** — fenced code and `${...}` in the repo's markdown would break or inject into the literal. Owner overrode the lead's initial preference for this. |
| D1 | Accept two one-line copies rather than one generated line | **Rejected** — defensible, and one sentence drifts far less than a nine-line block, but the criterion asks for structural impossibility over improbability, and one `args` field closes it. |
| D2 | Per-agent missing-file handling in every teammate prompt | **Rejected by the owner** as unnecessary defensiveness; the check already guarantees presence. |
| D4 | `check-ci-policy.sh` / `spec-flow-config.sh` as the script name | **Rejected** — the first renames on the first new config file; the second is redundant inside the plugin. |
| D4 | Python rather than bash | **Rejected** — no multi-source join and no table to format, unlike `board.py`. |
| D6 | One graced release where the check warns and exits 0 | **Rejected by the owner** — a warning that does not stop the run is the fallback being removed. |
| D7 | A dedicated `/spec-flow:seed-config` skill | **Rejected by the owner** — costs a command for a single file; later config files would fold back into `setup` anyway. |
| D7 | Setup writes the file locally only, no PR | **Rejected** — drops the branch+PR shape the acceptance criteria specify. |
| D7 | `<!-- spec-flow:FILL-IN -->` marker plus a check treating it as unusable | **Collapsed by the owner's ruling** that seeding confirms with the owner anyway — nothing lands unconfirmed, so the marker has nothing to catch. |
| D8 | Keep the `full \| unit \| degraded \| none` enum, add only `tests_detail` | **Rejected** — the artifact the owner reads would still say `"unit"` in a repo whose policy is the opposite, which the criteria forbid. |
| D8 | Reserve a `## Local gate` first line in `CI.md` for a terse restatement | **Rejected by the architect** as a schema arriving by the back door. |
| D10 | Anchor the existing gitignore entry to `/.spec-flow/` | **Rejected** — correct but changes a working line in every consuming repo for no gain. |
| — | File the three flagged debt items as issues now | **Deferred by the owner** — recorded here; filed after this merges, alongside the 38 rewrite. |

## Domain Facts

From the `claude-code-guide` consult, with two items independently re-verified by the lead in this worktree. These constrained the design rather than merely informing it.

- **Workflow-tool JS scripts have no filesystem access.** No `require`, no `fs`, no `child_process`, no shell. Everything the script knows arrives through its `args` object — `implement.workflow.js` already destructures exactly that way. *This is what forced D1's option set: the script cannot read `CI.md` itself under any design.*
- **`CLAUDE_PLUGIN_ROOT` is not reliably exported to a Bash subprocess.** *Independently verified by the lead:* `printenv CLAUDE_PLUGIN_ROOT` exits 1 here. It is expanded by the skill-invocation context when a `SKILL.md` writes `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh`, so the script is invoked by absolute path — but a script cannot assume the variable is set in its own environment. `agents/tdd-developer.md:57` already hedges for exactly this. Hence the script self-locates from `BASH_SOURCE` in the manner of `board.py:20-23`.
- **`CLAUDE_PROJECT_DIR` does not exist.** *Independently verified by the lead:* `printenv CLAUDE_PROJECT_DIR` exits 1. No published env var names the consuming repo's root, so `git rev-parse --show-toplevel` is the only route — already the precedent in `scripts/spawn-issue-pm.sh`.
- **`env` values in `.claude/settings.json` are not interpolated.** `"${HOME}/config"` stays a literal string. *This is what settles D3:* an absolute `SPEC_FLOW_CONFIG_DIR` in checked-in settings is a machine-specific literal, wrong on every other clone.
- **`git rev-parse --show-toplevel` returns the worktree root**, not the primary checkout — so an issue worktree reads the policy its own branch carries, which is the desired behavior.
- **`claude plugin list --json` is an undocumented de-facto API** with no published stability contract, though `installPath` and `enabled` are already relied on in `setup` and at the Seam 1 render. *Noted as a standing fragility;* this change deliberately reaches for neither, depending only on `git` and `gh`.

## Risks / Trade-offs

**Stale worktrees — the highest risk.** Every issue worktree branched before this merges lacks `spec-flow/CI.md`, so `implement` and `sync-ci` refuse inside it even though the default branch has the file. This will happen on merge day to every in-flight issue. The script's message names the rebase. There is no way to avoid it without a fallback, and the fallback is the thing being removed.

**A skipped read is silent.** Read-the-file means an agent that never opens the policy has no gate and says nothing. Contained, not eliminated, by requiring the exact commands in `tests_detail`: an agent that did not read the policy cannot name the policy's commands, so the omission surfaces in the review contract rather than vanishing.

**Contract change mid-flight.** A run starting before the merge and finishing after could mix old and new enum values, and the JS `enum` validation would reject the review. Runs are short, so this is minor, but it argues for merging when nothing is in flight.

**A slow policy is now expressible.** A repo whose `CI.md` says "run the 40-minute suite locally" makes every TDD cycle slow. That is the point of the change and it is the repo's choice, but the seeded file should state plainly that the local gate runs on every cycle.

**Workflow mode is structurally weaker.** *(Inferred, from the absence of `require`/`fs` and the script's own comment that it cannot read the environment.)* A script that can read neither files nor the environment can only be handed things. Every future repo-owned config file needs a new `args` field and a new `SKILL.md` line to populate it — another chance for the two modes to drift. This design makes the marginal cost one path-bearing string per file, the cheapest version of that tax, but it is still a tax.

**Nearby structural debt — folded in:** `docs/workflow.md` and `README.md` each state the policy twice; both copies convert together, or the second becomes the new hardcoded source. The four non-spec lenses' "leave `tests_ran` as `full`" line is corrected while those files are already being edited.

**Nearby structural debt — deferred to separate issues, none filed:**

- The wider `SKILL.md` / `implement.workflow.js` duplication (`GUARDRAILS`, `REVIEW_GUARDRAILS`, panel and fix-loop prompts, all hand-synced). The general fix is either extracting every shared prompt or retiring Workflow mode once agent teams stabilize — its own decision, not a rider on this one.
- The dead `spec_conformance` / `tests_ran` fields on the four non-spec lenses, which carry two fields they are told to hardcode and ignore.
- `adopt-tiering` bakes in the same split assumption this change makes configurable.
