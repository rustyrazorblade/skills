# Ship the seeding template issue 50 assumed but never created

## Why

Issue 50 moved spec-flow's test and CI policy out of the plugin and into a repo-owned
`spec-flow/CI.md`. It merged as `bee37bb` asserting, in five separate places, that the plugin
ships a template for seeding that file. No such file exists.

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

**A new template file ships**, at `plugins/spec-flow/references/seed-policy-tiered.md`. It states
the pre-issue-50 policy in full — a fast tier locally, the full suite in CI, merge gated on green
CI — in the same owner-voice register `spec-flow/CI.md` uses. Its header opens with three
disqualifying conditions a repo must meet, and closes with an explicit boundary marker so the
seeding notes are stripped rather than copied into the repo's file.

The basename is deliberately not `CI.md`. `scripts/repo-config.sh:39` pins `POLICY_FILE='CI.md'`,
so a differently-named template cannot be reached by any configuration resolution, and any
accidental runtime read would require a hand-written literal path that `grep` finds. A second
`CI.md` inside the plugin would make `grep -rn "CI.md"` — which today hits `README.md:66`,
`docs/workflow.md:881`, `:891`, `:1032`, and `scripts/seed-config.sh` — stop distinguishing the
runtime file from the template.

**`skills/setup/SKILL.md` gains one paragraph and one sentence.** The new paragraph goes after the
existing anti-bias guidance (currently ending at line 113), not before it, and makes the template
conditional: `setup` reads the repo and determines its shape unaided, exactly as it does today at
lines 92-98; only if that shape is the tiered split does it open the template and use its wording.
For any other shape it never opens the file. Line 92's "not a template with blanks" stays verbatim,
as does the sentence naming this repo's own `spec-flow/CI.md` as a worked example — two examples
sitting together, one tiered and one with no test suite at all, cannot both read as the default.
The added sentence in the "land it" block requires the seeded file to carry neither the template's
seeding notes nor a reference to the template.

**`skills/adopt-tiering/SKILL.md` stops restating the tiered policy** and points at the template as
its single source. This de-duplicates wording that would otherwise live in two unlinked places. It
does not change what `adopt-tiering` does or re-open whether tiering is right.

**`docs/workflow.md`'s test-policy statement consolidates.** It currently states the policy in
three places — `:867`, `:889-935`, and `:1032`. One becomes authoritative; the others point at it.
The authoritative section gains the template's existence and its non-fallback status.

**`README.md:66-72` gains the template**, immediately before the existing "write that plainly
rather than inheriting a template that does not apply" caution, which stays verbatim and gets
sharper once it names a real file.

**A new `references/README.md`** indexes the directory's three unlike contents — `ci/` (workflow
YAMLs the owner copies into `.github/`), `refactoring-discipline.md` (read by `tdd-developer`), and
the template (read only during seeding) — so a contributor browsing the directory learns the
no-runtime-read rule without opening the file.

**Two corrections land in `openspec/changes/issue-50/`, in place.** `specs/repo-config/spec.md:5`'s
`MAY` becomes `SHALL`, and `ac-coverage.md:18`'s false ✅ is corrected with a pointer to this
change. Editing that change in place is correct rather than historical revisionism: its deltas were
never synced. `openspec/specs/` holds only `explain/`, so `repo-config` and `test-policy` remain
pending requirements that enter the baseline when issue 50 is archived.

**The plugin version moves 0.36.0 → 0.37.0** in `.claude-plugin/plugin.json` (spec-flow ships no
`.codex-plugin/` manifest, unlike `cassandra-expert` and `easy-db-lab`, so only the one file moves).

## Scope

**In:** the template file; the `setup`, `adopt-tiering`, `workflow.md`, `README.md`, and
`references/README.md` prose; the two in-place corrections to issue 50's change; the version bump.

**Out:** any runtime fallback — the template is never read at runtime, quoted into a prompt, or
substituted when the repo's file is absent, and `repo-config.sh check` still exits non-zero and
still stops the pipeline. No content validation of the repo's policy file, no schema, and no
comparison of a repo's file against the template. No change to `repo-config.sh` or
`seed-config.sh`. Issue 52's inherited "shipped template" phrase is corrected in issue 52, which is
hard-blocked on this one.

## Impact

One new file, one new README, prose edits in four files, two edits to a pending OpenSpec change,
and a version bump. No script changes and no runtime path changes.

A configured repo sees nothing. A repo being seeded may get a different proposal, which its owner
still confirms before anything is written. Unlike issue 50, no version of this change can stop a
running pipeline.
