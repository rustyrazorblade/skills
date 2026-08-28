# Design

## Context

`spec-flow` 0.36.0 (issue 50, merged as `bee37bb`) removed a hardcoded test/CI policy from five
runtime locations and made the consuming repo own it, at `spec-flow/CI.md` then and
`spec-flow/TESTING.md` after this change renames it. The plugin falls back to
nothing when that file is absent — deliberately, since a warning that does not stop the run is the
silent default being removed.

Five of issue 50's artifacts assert the plugin ships a template for seeding that file. It does not.
One line says the plugin `MAY` ship one. This change resolves the contradiction in favour of
shipping it, and the owner confirmed that reading at activation: the `MAY` is the defect.

The design tension is that the template must simultaneously be a real, complete, copyable policy —
otherwise `specs/test-policy/spec.md:120` still has nothing to point at — and must not become the
hardcoded default issue 50 removed, arriving back through a confirmation prompt the owner
rubber-stamps.

## Goals / Non-Goals

**Goals.** Give `specs/test-policy/spec.md:120` a referent a person can diff a repo's policy
against. Give seeding a canonical baseline for the one shape that has one. Make all six artifacts
agree. Keep the no-runtime-fallback contract exactly as strict as it is today.

**Non-Goals.** No runtime read of the template under any condition. No validation of a repo's
policy file against it. No change to the check's presence-and-readability contract, the local/CI
split itself, `SPEC_FLOW_CONFIG_DIR` resolution, or the exit-code contract.

## Decisions

Citations below give a path and a line. An unprefixed path is relative to `plugins/spec-flow`; a
path beginning with a top-level directory, such as `openspec/`, is relative to the repository root.
So `README.md:66` is the plugin's README, not the repository's.

### D1 — The template ships at `references/TESTING.md.template`, flat

`references/` is already this plugin's home for shipped files a skill or agent reads by
`${CLAUDE_PLUGIN_ROOT}`-relative path. The nearest precedent does exactly this job:
`skills/adopt-tiering/SKILL.md:82` reads `${CLAUDE_PLUGIN_ROOT}/references/ci/github-actions-gradle.yml`
as a starting point it copies into the consuming repo. `agents/tdd-developer.md:56` reads
`references/refactoring-discipline.md` the same way. That directory reasoning is unchanged by
anything below.

**The basename is the destination filename plus a `.template` suffix.** The owner directed this
after the second review pass, and it settles two earlier attempts. The first draft named the file
`seed-policy-tiered.md`, on a grep argument since rewritten in D3; it shipped, the owner went
looking for the policy template, found nothing whose name resembled the file it seeds, and
reasonably concluded it had never landed. The second attempt gave the template the destination's
bare basename, which cured that but made the pair indistinguishable by name alone. The suffix keeps
what the bare basename bought — a reader pairs `TESTING.md.template` with `spec-flow/TESTING.md`
without opening either — and restores the distinction it cost.

The policy file it seeds is renamed in the same pass, from `CI.md` to `TESTING.md`. A file that
states what runs locally, what runs in CI, and what gates merge is a testing policy of which CI is
one part; `CI.md` named the smaller half. The rename is a **clean break**: `repo-config.sh` resolves
one filename, with no alias, no fallback, and no did-you-mean. A repo carrying only `CI.md` is
unconfigured, reports as missing, and stops the pipeline, exactly as one that never had a policy
does. That is asserted by `scripts/test-repo-config.sh`, because "we added no fallback" is otherwise
invisible: nothing else fails if someone adds one later.

The naming property the first draft was protecting was overstated. It was framed as a naming rule —
see D3, rewritten — when the guard is actually containment, and containment survives every one of
these renames untouched.

`setup/SKILL.md` addresses the path plainly as
`${CLAUDE_PLUGIN_ROOT}/references/TESTING.md.template`, with **no fallback clause**. The plugin's two precedents differ for a reason: `agents/tdd-developer.md:57` carries a fallback because an
agent file is not expanded by the skill-invocation context and must resolve the variable at
runtime, whereas a `SKILL.md` is expanded before the agent sees it. `setup` is a skill, so it takes
the `adopt-tiering` form. A fallback clause there would add a branch that can never be taken.

### D2 — `setup` opens the template only after it has read the repo

This is the change's central decision, and it narrows what was said when the issue was activated.

The template is never read by the pipeline. It **is** read at seeding time, by an agent that then
proposes a policy. An agent handed a complete, well-written tiered policy and told to start from it
anchors on it. The failure mode is not one badly-seeded repo; it is a portfolio of near-identical
tiered policies, which is precisely the state `openspec/changes/issue-50/proposal.md:5` diagnoses
as "wrong somewhere by construction" — now laundered through a confirmation step.

So: `setup` determines the repo's actual shape first, unaided, exactly as
`skills/setup/SKILL.md:92-98` already directs. If and only if that shape is the tiered split does
it open the template and use its wording. For any other shape it never opens the file.

This still satisfies the issue's acceptance criterion, because that criterion is itself
conditional: "WHEN a repo adopts the previously hardcoded policy, THEN it can start from the
template's content."

Three mechanisms hold the line, and none is sufficient alone:

1. **Sequencing.** The new paragraph is placed after every existing anti-bias instruction in the
   section, so reading order is: read the repo → a no-suite repo is first-class → header
   requirements → the `skills` worked example → and only then the template.
2. **Adjacency.** The paragraph sits beside the sentence naming this repo's own
   `spec-flow/TESTING.md`, a policy with four shell harnesses, no framework, and no CI test gate.
   Two examples, one tiered and one not, cannot both be the default.
3. **A disqualifying test in the header.** See D4.

The risk is contained, not eliminated. Nothing mechanically prevents an agent from opening the
template before reading the repo.

### D3 — Enforcement of the no-runtime-read rule is prose, plus one free structural guard

The guard is **containment**, not the basename. An earlier draft of this section described it as a
naming rule, and that description was wrong; the guard itself was never lost, only misdescribed.

`scripts/repo-config.sh` composes every policy path as `${repo_root}/${config_dir}/${POLICY_FILE}`
(`:290`, `:370`), and `repo_root` comes from `git rev-parse --show-toplevel` (`:114`) — the
**consuming repo's** worktree root. The plugin's root takes no part in it. `:43-45` records that
`CLAUDE_PLUGIN_ROOT` is deliberately never read in that script, so it has no mechanism by which to
name the plugin's directory at all. A template inside the plugin therefore lies outside the tree the
resolution searches, and is unreachable because of its **directory**, whatever its basename. Naming
it after its destination costs nothing here. An accidental runtime read would still need a
hand-written literal path naming the plugin's `references/` directory, which is visible in review.

What the naming does cost is a search. A single grep for the policy filename used to name the
runtime file throughout the plugin and nothing else — `README.md:66`, `docs/workflow.md:885`,
`:895`, `:923`, `scripts/repo-config.sh`, and `scripts/seed-config.sh` among them. Because
`TESTING.md.template` contains `TESTING.md`, `grep -rn "TESTING\.md" plugins/spec-flow` now matches
the template and its documentation too. `grep -rn "TESTING\.md\.template"` isolates the template
cleanly; isolating the runtime file takes a subtraction,
`grep -rn "TESTING\.md" plugins/spec-flow | grep -v "TESTING\.md\.template"`, because a
character-class exclusion drops every mention that ends a line or precedes a sentence-final period.
The one-word search no longer discriminates, and nobody should read a clean result from it as
evidence of anything. That search was a review convenience; the resolution anchor is what carries
the property.

The rule is stated in three places rather than one — the spec (already, at
`openspec/changes/issue-50/specs/repo-config/spec.md:111`), the template's own header, and
`docs/workflow.md`.

### D4 — The header states a disqualifying test, not a hedge

A header saying "this is one policy, not the policy" is skimmed past by both audiences. The header
instead names three conditions the policy fits — the suite is already split into a fast and a slow
tier, CI runs tests, and merge is gated on green CI — and states that a repo failing any one of
them should close the file and write its policy from what the repo actually does. It states that
this is the policy spec-flow used to hardcode and that hardcoding it was the defect issue 50 fixed.
It states that nothing reads the file at runtime.

It closes with a visible boundary marker rather than wrapping the header in an HTML comment. The
comment form would hide it from an owner reading the file on GitHub, which is the wrong trade. The
marker exists for correctness as well as bias control:
`openspec/changes/issue-50/specs/repo-config/spec.md:164-173` requires the seeded file to read as
the repo's own choice, so a line saying "seeded from spec-flow's tiered template" would breach that
requirement.

### D5 — Issue 50's change is corrected in place; issue 53 carries a new requirement

Issue 50's deltas were never synced. `openspec/specs/` holds only `explain/`, so `repo-config` and
`test-policy` do not exist as main specs and enter the baseline only when issue 50 is archived. The
`MAY` at `specs/repo-config/spec.md:5` is therefore a pending requirement, and correcting it amends
a draft rather than rewriting a published one. A `## MODIFIED Requirements` delta in this change
would have no valid target, because the requirement it names is not in `openspec/specs/`.

The requirement text for the template itself lives here, as `## ADDED Requirements` in
`repo-config` — a new requirement, not a modification of the one issue 50 adds. Both changes then
carry a `repo-config` delta, but they touch different requirements, so bulk archive
(`skills/archive/SKILL.md:51-53`) sees no content conflict.

A delta-less change was considered and is not available: `openspec validate --strict` errors with
"Change must have at least one delta."

### D6 — Adjacent debt items are folded in, by owner override

The architect recommended deferring both. The owner directed fixing them here.

Before this change, `docs/workflow.md` stated the test policy at `:867`, `:889-935`, and `:1032`.
Issue 50's tasks 7.1/7.2 handled a two-copy version; this change touches all three sites anyway, so
it consolidates to one authoritative section with pointers.

`skills/adopt-tiering/SKILL.md` restates the tiered split, which the template now also encodes. The
restatement is deleted, and no pointer to the template replaces it. A pointer would aim a policy
read at the template, which the `repo-config` requirement added here confines to seeding, with the
owner present. The repo's own `spec-flow/TESTING.md` is the single source any agent reads for
policy, so
`adopt-tiering` defers to that file as the whole of the policy. This is scoped narrowly to removing
the duplicate wording; it does not re-open whether tiering is the right policy, which the issue puts
out of scope.

A third item arrived in review round 2, from the `code-review` lens, and the owner directed fixing
it here as well. `skills/adopt-tiering/SKILL.md:11-13` gates the skill on the repo's own
`spec-flow/TESTING.md` having already chosen the tiered policy, but step 7's manual owner follow-up
named branch protection alone. A migration could therefore land while the one file the pipeline
reads still described the layout the migration replaced. Step 7 now names both follow-ups. The
owner declined the larger option of softening the entry gate into a check-and-reconcile step, so
`:11-13` is untouched, and the skill still never writes the repo's policy file.

## Alternatives Considered

**Delete the claim rather than ship the template.** Correct `proposal.md:12`,
`specs/test-policy/spec.md:120`, `specs/repo-config/spec.md:111`, and `ac-coverage.md:18` so all
five agree with `spec.md:5`'s `MAY`. Smaller. Rejected by the owner at activation: it leaves
seeding with no canonical baseline and gives issue 52, which is hard-blocked on this one, no
pattern to copy. The owner's words were that the spec should have said MUST.

**Point at this repo's own `spec-flow/TESTING.md` as the worked example, shipping nothing new.**
`skills/setup/SKILL.md:112` already half-does this. Rejected: a repo with no test suite and no
test-running CI is a poor baseline for the tiered split that `specs/test-policy/spec.md:120` is
about.

**Two files — a structural skeleton plus a worked tiered example.** Separates the two jobs this
change conflates: giving seeding a canonical shape, and giving `spec.md:120` a referent. Rejected
by the owner in favour of one file. Cost avoided: two paths to document and two files to keep in
step.

**A skeleton only, with no policy content.** Cleanest against issue 50's thesis, and directly
compatible with `setup/SKILL.md:92`'s "not a template with blanks" — which is also why it fails.
Rejected: it would not satisfy the acceptance criterion, and `spec.md:120` would still have no
referent, so that requirement would need rewording too.

**Give the template a name unrelated to its destination.** The first draft did, as
`seed-policy-tiered.md`, on the grep argument now rewritten in D3. Rejected by the owner after the
first review pass: the argument was overstated, and a name that hides what the file becomes is what
actually cost time. See D1.

**Give the template the destination's bare basename, with no suffix.** The second attempt did, as
`references/CI.md`. It cured the first draft's defect but introduced the opposite one: two files
with the same name, one shipped and one written per repo, indistinguishable in a file listing or a
review diff header. Rejected by the owner after the second review pass, in favour of the
`<destination-filename>.template` convention now recorded in `CLAUDE.md`.

**Keep the policy file called `CI.md`.** Rejected by the owner: the file states what runs locally,
what runs in CI, and what gates merge, so CI is one clause of it rather than its subject. The name
misdescribed the file to every agent that opened it.

**Accept `CI.md` as an alias during a deprecation window.** Rejected by the owner. An alias means
two filenames resolve, which is the ambiguity the single-source design exists to prevent, and a
window has to be closed by someone remembering to close it. The clean break gives an unmigrated
repo the same clear, actionable stop a never-configured repo gets, on its next run rather than
silently later.

**Put it in `references/ci/`.** Rejected: `references/ci/README.md:1` titles that page "CI contract
for spec-flow test tiering", and its "Templates" section means workflow YAML copied into
`.github/workflows/`. A policy document there reads as a third workflow file, and `README.md:99`
sends readers to that directory for exactly that narrow purpose.

**A `references/policy-templates/` subdirectory.** A plural directory name would make "one policy,
not the policy" true at the path level, which is a genuine advantage. Rejected: it is scaffolding
for one file, `references/refactoring-discipline.md` sets the precedent that a single-purpose
document sits flat, and a directory named "templates" invites a future `default.md` — D2's bias
arriving by a route nobody decides on. A second policy has to be named, and placed, by someone who
decides to add it.

**Name it `example-policy-tiered.md`.** "Example" is the strongest framing against the bias risk,
but inaccurate: this is the wording seeding copies, not an illustration beside it. A misleading
name that happens to push the right way is still misleading.

**`setup` opens the template as every run's starting draft.** The literal reading of what was
decided at activation, and the simplest instruction to write. Rejected in favour of D2. This repo
is the proof: seeded that way, its own `spec-flow/TESTING.md` would have been a near-total rewrite of
the template, so the template would have contributed nothing but bias.

**A guard in `repo-config.sh` refusing a policy path inside the plugin.** Rejected: the script does
not know the plugin root by design (`:43-45`), and
`openspec/changes/issue-50/specs/repo-config/spec.md:63-68` already refuses a symlink resolving
outside the repository, which is the only realistic route by which a repo's `TESTING.md` could become
the plugin's template. A template-specific guard duplicates a rule the script is written to keep
singular.

**A test asserting the template is never read at runtime.** Rejected, but not for the reason an
earlier draft gave. That draft said this repo has no test suite; it has four shell harnesses, and
correcting `spec-flow/TESTING.md` to say so is part of this change. The real reason is that the
assertion has no executable surface. A runtime read of the template would be an agent following a
prose instruction, not a script opening a path, so no harness can observe it; that is why D3 rests
on containment plus prose. What *is* mechanically checkable is the resolution anchor, and
`scripts/test-repo-config.sh` now asserts it from the outside: a repo holding only the previous
`CI.md` reports as missing, so a fallback added later fails a test.

**Leaving issue 50's "no automated test suite" scenario as written.** Its
`specs/repo-config/spec.md:209` required this repository's policy to state that it has no automated
test suite. Rejected: this change makes that false, and the two deltas enter the same `repo-config`
baseline at archive, so leaving it would publish a requirement contradicting the one this change
adds. Corrected in place, like task 5.1's `MAY`→`SHALL`, because issue 50's deltas were never
synced. See task 8.15.

**Adding a task 2.6 to `openspec/changes/issue-50/tasks.md`.** Tempting, since the issue correctly
identifies section 2 as where the gap entered. Rejected: the work is this change's, and an
unchecked task on a merged change misrepresents it permanently. `skills/archive/SKILL.md` does not
gate on unchecked tasks, so this is a representation argument, not a blocking one.

**Adding the template to `openspec/changes/issue-50/proposal.md:37`'s "New (3)" list.** Rejected:
the count is accurate for what issue 50 actually shipped, and adding the template would claim issue
50 shipped a file it did not. The new `ac-coverage.md` row is where a reader learns the file
arrived later. The policy file already in that list is renamed with every other reference, per task
8.9; renaming a file issue 50 did ship is not the same as adding one it did not.

## Domain Facts

From a Claude Code plugin-conventions consult, recorded because D1 rests on it:

- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's root directory and is available in `SKILL.md`
  bodies, agent definition markdown, bash blocks, and shell scripts. Files cannot be read across
  plugin roots; it always resolves to the current plugin only.
- Claude Code scans `skills/` and `agents/` at plugin load time, and treats `.claude-plugin/` and
  `.codex-plugin/` as metadata. `scripts/`, `references/`, `docs/`, and `bin/` get no special
  treatment and are reachable only by explicit path. Any other directory name at plugin root is
  inert. So the placement decision is a legibility choice, not a mechanical constraint.
- No Claude Code convention governs template/asset files at plugin root. The consult found
  `scaffold/` used in one other plugin and `assets/` used inside skill directories. Neither
  outranks this plugin's own established use of `references/`.
- The examined `plugin.json` manifests carry no `files`, `include`, or `exclude` fields, so all
  files under a plugin root appear to ship on marketplace install. The consult flagged this as
  inferred from four manifests, not verified against Claude Code source. This change adds no
  packaging step on that basis; if the inference is wrong, the template would not ship and the
  acceptance criterion "`find`ing for it succeeds" would catch it.

## Risks / Trade-offs

**Anchoring, contained but not eliminated.** D2's three mechanisms are prose. Nothing prevents an
agent from opening the template before reading the repo. Recorded in the same terms
`openspec/changes/issue-50/ac-coverage.md:27` uses for its own residual risk, rather than claiming
more.

**The template rots.** Nothing runs it, nothing tests it, and no repo's behavior depends on it. The
pre-issue-50 text in `skills/implement/SKILL.md` already framed its commands as per-runner
examples; reproducing that framing faithfully limits the staleness. The risk is inherited from
encoding a policy at all, not newly introduced.

**`specs/test-policy/spec.md:120` becomes verifiable, not verified.** Having a referent is not the
same as having something check it. Nothing compares a repo's seeded file to the template, which is
correct per the issue's out-of-scope list. Read the criterion's "verifiable for the first time" as
"a person can now verify it", not "the pipeline does."

**Git history will read oddly.** `bee37bb` asserts a template ships; a later commit makes it true.
The rule against editing an archived change does not apply, since issue 50's change is unarchived,
but the PR body should say this plainly.

## Deferred

`skills/adopt-tiering/SKILL.md` bakes in the tiered split as an assumption, already recorded as
deferred at `openspec/changes/issue-50/ac-coverage.md:41`. This change de-duplicates the *wording*
between it and the template (D6) but does not revisit the assumption itself.
