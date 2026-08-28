# Design

## Context

`spec-flow` 0.36.0 (issue 50, merged as `bee37bb`) removed a hardcoded test/CI policy from five
runtime locations and made the consuming repo own it at `spec-flow/CI.md`. The plugin falls back to
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

### D1 — The template ships at `references/seed-policy-tiered.md`, flat

`references/` is already this plugin's home for shipped files a skill or agent reads by
`${CLAUDE_PLUGIN_ROOT}`-relative path. The nearest precedent does exactly this job:
`skills/adopt-tiering/SKILL.md:82` reads `${CLAUDE_PLUGIN_ROOT}/references/ci/github-actions-gradle.yml`
as a starting point it copies into the consuming repo. `agents/tdd-developer.md:56` reads
`references/refactoring-discipline.md` the same way.

The basename carries load. It must differ from `CI.md` — see D3.

`setup/SKILL.md` addresses the path plainly as
`${CLAUDE_PLUGIN_ROOT}/references/seed-policy-tiered.md`, with **no fallback clause**. The plugin's
two precedents differ for a reason: `agents/tdd-developer.md:57` carries a fallback because an
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
2. **Adjacency.** The paragraph sits beside the sentence naming this repo's own `spec-flow/CI.md`,
   a policy with no test suite at all. Two examples, one tiered and one not, cannot both be the
   default.
3. **A disqualifying test in the header.** See D4.

The risk is contained, not eliminated. Nothing mechanically prevents an agent from opening the
template before reading the repo.

### D3 — Enforcement of the no-runtime-read rule is prose, plus one free structural guard

`scripts/repo-config.sh:39` pins `POLICY_FILE='CI.md'`. Because the template's basename differs, no
configuration resolution can reach it; an accidental runtime read would need a hand-written literal
containing `references/seed-policy-tiered.md`, which is one greppable string and visible in review.

That property is why the template is not named `CI.md`. `grep -rn "CI.md" plugins/spec-flow` names
the runtime file throughout the plugin — `README.md:66`, `docs/workflow.md:885`, `:895`, `:920`,
`scripts/repo-config.sh`, and `scripts/seed-config.sh` among them. A second `CI.md` inside the
plugin makes every one of those hits ambiguous and disables the one search that would catch a
future runtime read.

Already true and worth recording rather than building: `scripts/repo-config.sh:43-45` documents
that `CLAUDE_PLUGIN_ROOT` is deliberately never read there, so the check has no mechanism by which
it could reach the template.

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

`docs/workflow.md` states the test policy at `:867`, `:889-935`, and `:1032`. Issue 50's tasks
7.1/7.2 handled a two-copy version; this change touches all three sites anyway, so it consolidates
to one authoritative section with pointers.

`skills/adopt-tiering/SKILL.md` restates the tiered split, which the template now also encodes. The
restatement is deleted, and no pointer to the template replaces it. A pointer would aim a policy
read at the template, which the `repo-config` requirement added here confines to seeding, with the
owner present. The repo's own `spec-flow/CI.md` is the single source any agent reads for policy, so
`adopt-tiering` defers to that file as the whole of the policy. This is scoped narrowly to removing
the duplicate wording; it does not re-open whether tiering is the right policy, which the issue puts
out of scope.

A third item arrived in review round 2, from the `code-review` lens, and the owner directed fixing
it here as well. `skills/adopt-tiering/SKILL.md:11-13` gates the skill on the repo's own
`spec-flow/CI.md` having already chosen the tiered policy, but step 7's manual owner follow-up
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

**Point at this repo's own `spec-flow/CI.md` as the worked example, shipping nothing new.**
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

**Name it `references/CI.md`.** Mirrors the target filename. Rejected on D3's grep argument. The
strongest thing the path can say is that this file is *not* the one the pipeline reads.

**Put it in `references/ci/`.** Rejected: `references/ci/README.md:1` titles that page "CI contract
for spec-flow test tiering", and its "Templates" section means workflow YAML copied into
`.github/workflows/`. A policy document there reads as a third workflow file, and `README.md:98`
sends readers to that directory for exactly that narrow purpose.

**A `references/policy-templates/` subdirectory.** A plural directory name would make "one policy,
not the policy" true at the path level, which is a genuine advantage. Rejected: it is scaffolding
for one file, `references/refactoring-discipline.md` sets the precedent that a single-purpose
document sits flat, and a directory named "templates" invites a future `default.md` — D2's bias
arriving by a route nobody decides on. A flat filename carrying a qualifier has nowhere to grow
into without someone naming the new policy explicitly.

**Name it `example-policy-tiered.md`.** "Example" is the strongest framing against the bias risk,
but inaccurate: this is the wording seeding copies, not an illustration beside it. A misleading
name that happens to push the right way is still misleading.

**`setup` opens the template as every run's starting draft.** The literal reading of what was
decided at activation, and the simplest instruction to write. Rejected in favour of D2. This repo
is the proof: seeded that way, its own `spec-flow/CI.md` would have been a near-total rewrite of
the template, so the template would have contributed nothing but bias.

**A guard in `repo-config.sh` refusing a policy path inside the plugin.** Rejected: the script does
not know the plugin root by design (`:43-45`), and
`openspec/changes/issue-50/specs/repo-config/spec.md:63-68` already refuses a symlink resolving
outside the repository, which is the only realistic route by which a repo's `CI.md` could become
the plugin's template. A template-specific guard duplicates a rule the script is written to keep
singular.

**A test asserting the template is never read at runtime.** Rejected: this repo has no test suite
and no CI test gate (`spec-flow/CI.md:11-12`, `:32`). Inventing a gate for one assertion
contradicts the repo's own policy.

**Adding a task 2.6 to `openspec/changes/issue-50/tasks.md`.** Tempting, since the issue correctly
identifies section 2 as where the gap entered. Rejected: the work is this change's, and an
unchecked task on a merged change misrepresents it permanently. `skills/archive/SKILL.md` does not
gate on unchecked tasks, so this is a representation argument, not a blocking one.

**Correcting `openspec/changes/issue-50/proposal.md:37`'s "New (3)" list.** Rejected: it is
accurate for what issue 50 actually shipped, and amending it would claim issue 50 shipped a file it
did not. The new `ac-coverage.md` row is where a reader learns the file arrived later.

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
