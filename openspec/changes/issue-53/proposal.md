# Ship the seeding template issue 50 assumed but never created

## Why

Issue 50 moved spec-flow's test and CI policy out of the plugin and into a repo-owned policy file,
which it called `spec-flow/CI.md`. It merged as `bee37bb` asserting, in five separate places, that
the plugin ships a template for seeding that file. No such file exists.

The five assertions:

- `openspec/changes/issue-50/proposal.md:12` — "The plugin ships a seeding template and **no
  runtime fallback**."
- `openspec/changes/issue-50/specs/test-policy/spec.md:120` — a Requirement titled "A repo matching
  the shipped template behaves exactly as before."
- `openspec/changes/issue-50/specs/repo-config/spec.md:111` — "No caller SHALL ... read, quote, or
  substitute the plugin's shipped template."
- `openspec/changes/issue-50/ac-coverage.md:18` — marks the criterion "Repo's policy matches the
  shipped template unchanged" as ✅ Covered.
- `bee37bb`'s own commit message — "the plugin's copy is a seeding template, never a fallback."

One line dissents, and it is the outlier: `openspec/changes/issue-50/specs/repo-config/spec.md:5`
says the plugin "**MAY** ship a template."

Three consequences follow. `specs/test-policy/spec.md:120`'s requirement names nothing, so nobody
can verify it. `ac-coverage.md:18`'s ✅ is false. And seeding has no canonical baseline, so two
repos that both want the split spec-flow hardcoded before issue 50 get two differently-worded files
with nothing to diff either against.

The gap entered through `openspec/changes/issue-50/tasks.md` section 2 ("Seeding"): tasks 2.1
through 2.5 include none that creates the template, and task 2.3 instructs `skills/setup/SKILL.md`
to author a policy per repo instead. The task breakdown dropped the artifact while every other
document continued to assert it.

## What Changes

**The repo-owned policy file is renamed**, from `spec-flow/CI.md` to `spec-flow/TESTING.md`. The
file states what runs locally, what runs in CI, and what gates merge, so CI is one clause of it
rather than its subject; `CI.md` named the smaller half. The rename is a **clean break**:
`scripts/repo-config.sh` resolves one filename, with no alias, no fallback, and no did-you-mean. A
repo carrying only `CI.md` is unconfigured, reports as missing, and stops the pipeline, exactly as a
repo that never had a policy does. `scripts/test-repo-config.sh` asserts that.

**A new template file ships**, at `plugins/spec-flow/references/TESTING.md.template`. It states the
pre-issue-50 policy in full — a fast tier locally, the full suite in CI, merge gated on green CI —
in the same owner-voice register `spec-flow/TESTING.md` uses. Its header opens with three
disqualifying conditions a repo must meet, and closes with an explicit boundary marker so the
seeding notes are stripped rather than copied into the repo's file.

The basename is the destination filename plus a `.template` suffix, the convention every template
this plugin ships now follows, so a reader pairs the template with the file it seeds without opening
either. It stays unreachable at runtime by containment, not by its name: `scripts/repo-config.sh`
composes every policy path from the consuming repo's root, which it gets from
`git rev-parse --show-toplevel`, and never knows the plugin's root at all. The plugin's copy is
outside the tree that resolution searches, so no resolved path can name it whatever it is called.
The cost is that `grep -rn "TESTING\.md" plugins/spec-flow` matches the template as well as the
runtime file, since the template's name contains it, so isolating the runtime file now takes a
subtraction; that search was a review convenience, and the resolution anchor is what carries the
guarantee.

**`skills/setup/SKILL.md` gains one paragraph and one sentence.** The new paragraph goes after the
existing anti-bias guidance (currently ending at line 113), not before it, and makes the template
conditional: `setup` reads the repo and determines its shape unaided, exactly as it does today at
lines 92-98; only if that shape is the tiered split does it open the template and use its wording.
For any other shape it never opens the file. Line 92's "not a template with blanks" stays verbatim,
as does the sentence naming this repo's own `spec-flow/TESTING.md` as a worked example — two
examples sitting together, one tiered and one not, cannot both read as the default.
The added sentence in the "land it" block requires the seeded file to carry neither the template's
seeding notes nor a reference to the template.

**`skills/adopt-tiering/SKILL.md` stops restating the tiered policy**, and nothing replaces the
restatement. No pointer to the template goes in its place. The consuming repo's own
`spec-flow/TESTING.md` is the single source any agent reads for policy, and the template is a seeding
artifact that this change's own `repo-config` requirement confines to seeding, with the owner
present. A pointer would aim a policy read at it and contradict that requirement, so
`adopt-tiering` defers to the repo's `spec-flow/TESTING.md` as the whole of the policy instead. Step
7's manual owner follow-up list gains a second item to match: once the migration lands, the repo's
own `spec-flow/TESTING.md` must restate the split, or the pipeline reads a policy the repo no longer
matches. The skill names that follow-up; it never writes the repo's policy file. None of this
changes what `adopt-tiering` does or re-opens whether tiering is right.

**`docs/workflow.md`'s test-policy statement consolidates.** It currently states the policy in
three places — `:867`, `:889-935`, and `:1032`. One becomes authoritative; the others point at it.
The authoritative section gains the template's existence and its non-fallback status.

**`README.md:66-72` gains the template**, immediately before the existing "write that plainly
rather than inheriting a template that does not apply" caution, which stays verbatim and gets
sharper once it names a real file.

**A new `references/README.md`** indexes the directory's three unlike contents — `ci/` (workflow
YAMLs the owner copies into `.github/`), `refactoring-discipline.md` (read by `tdd-developer`), and
the template (read only during seeding) — so a contributor browsing the directory learns the
no-runtime-read rule without opening the file. It also states the
`<destination-filename>.template` naming convention as a convention, binding on any template whose
destination is a single named file rather than on this one file. The qualifier is necessary: the
workflow YAMLs in `ci/` have no single destination, because the owner picks one by runner and names
the copied file, so the convention cannot reach them and does not claim to.

**`CLAUDE.md` records that convention** for the repository, with the worked example
`plugins/spec-flow/references/TESTING.md.template` → `spec-flow/TESTING.md`.

**This repository's own `spec-flow/TESTING.md` is corrected while it moves.** It claimed the repo
has no automated test suite and told agents not to look for a test runner. Four shell harnesses
exist — `plugins/spec-flow/scripts/test-repo-config.sh`,
`plugins/spec-flow/scripts/test-board.sh`,
`plugins/dev-skills/skills/walkthrough/scripts/test-generate-walkthrough.sh`, and
`plugins/dev-skills/skills/ide-explain/scripts/test-generate-explain.sh` — and all four pass.
The claim is replaced with what is true, and the local gate gains a repo-wide bullet requiring the
harness covering a changed file to run and exit 0. What stays: CI is not a test gate here, nothing
produces a `spec-flow-failures` artifact, and an agent whose change triggers no clause of the gate
has complied in full.

**Corrections land in `openspec/changes/issue-50/`, in place.** `specs/repo-config/spec.md:5`'s
`MAY` becomes `SHALL`, `ac-coverage.md:18`'s false ✅ is corrected with a pointer to this change,
and every reference to the policy file's old name is renamed. Editing that change in place is
correct rather than historical revisionism: its deltas were never synced. `openspec/specs/` holds
only `explain/`, so `repo-config` and `test-policy` remain pending requirements that enter the
baseline when issue 50 is archived.

**The plugin version reaches 0.37.0 in both of the plugin's manifests.**
`.claude-plugin/plugin.json` moves 0.36.0 → 0.37.0. The `spec-flow` entry in
`.claude-plugin/marketplace.json` moves 0.10.0 → 0.37.0, having drifted well behind. spec-flow
ships no `.codex-plugin/` manifest, unlike `cassandra-expert` and `easy-db-lab`, so those two files
are the whole of the bump.

## Scope

**In:** the template file; the `CI.md` → `TESTING.md` rename of the policy file, in
`repo-config.sh`, `seed-config.sh`, and `test-repo-config.sh`; the correction to this repository's
own policy; the `setup`, `adopt-tiering`, `workflow.md`, `README.md`, `references/README.md`, and
`CLAUDE.md` prose; the in-place corrections to issue 50's change; the version bump across both of
the plugin's manifests.

**Out:** any runtime fallback — the template is never read at runtime, quoted into a prompt, or
substituted when the repo's file is absent, and `repo-config.sh check` still exits non-zero and
still stops the pipeline. Any alias for the old filename, any deprecation window, and any
did-you-mean: the rename is a clean break. No content validation of the repo's policy file, no
schema, and no comparison of a repo's file against the template. No change to the check's
presence-and-readability contract, its exit codes, or `SPEC_FLOW_CONFIG_DIR` resolution. Issue 52's
inherited "shipped template" phrase is corrected in issue 52, which is hard-blocked on this one.

## Impact

One new file, one new README, two renames, the resolved filename changed in three scripts, prose
edits in six files, edits to a pending OpenSpec change, and a version bump in the plugin's two
manifests.

**BREAKING for consuming repos.** A repo that already owns `spec-flow/CI.md` stops at its next
entry point until it renames the file to `spec-flow/TESTING.md`. The check reports the file as
missing and names the fix, so the stop is loud and actionable rather than silent; there is no
fallback, by the owner's ruling. A repo being seeded may get a different proposal, which its owner
still confirms before anything is written.
