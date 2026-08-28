# Tasks

## 1. The template

- [x] 1.1 Write `plugins/spec-flow/references/seed-policy-tiered.md`. Body states the pre-issue-50
      policy in full — fast tier locally, full suite in CI, merge gated on green CI — in the same
      owner-voice register `spec-flow/CI.md` uses. Frame the commands as per-runner examples, the
      way the pre-issue-50 text in `skills/implement/SKILL.md` did, rather than naming one stack's
      commands as though they were universal.
- [x] 1.2 Write its header: the three conditions a repo must meet (suite already split into a fast
      and a slow tier; CI runs tests; merge gated on green CI); the instruction to close the file
      and write from what the repo does if any condition fails; that this is the policy spec-flow
      used to hardcode and that hardcoding it was the defect issue 50 fixed; that nothing reads
      this file at runtime and a missing `spec-flow/CI.md` stops the pipeline rather than falling
      back here.
- [x] 1.3 Close the header with a visible boundary marker (an HTML comment on its own line, not a
      wrapper around the header) stating that everything above it is for the seeding agent and the
      repo's file starts below.
- [x] 1.4 Confirm the basename is not `CI.md` and that `grep -rn "CI.md" plugins/spec-flow` still
      returns only references to the runtime file.

## 2. Seeding

- [x] 2.1 In `plugins/spec-flow/skills/setup/SKILL.md`, insert one paragraph after the sentence
      naming this repo's own `spec-flow/CI.md` as a worked example (currently ending line 113),
      making the template conditional on `setup` having already determined the repo's shape is the
      tiered split, and directing it not to open the file for any other shape.
- [x] 2.2 Address the template as `${CLAUDE_PLUGIN_ROOT}/references/seed-policy-tiered.md`, with no
      fallback clause — matching `skills/adopt-tiering/SKILL.md:82`, not
      `agents/tdd-developer.md:57`.
- [x] 2.3 Leave `setup/SKILL.md:92`'s "not a template with blanks" and the `skills` worked-example
      sentence verbatim. Confirm by diff that neither moved or changed.
- [x] 2.4 Add one sentence to the "Third, land it" block: the seeded file carries neither the
      template's seeding notes nor any reference to the template.

## 3. `adopt-tiering`

- [x] 3.1 In `plugins/spec-flow/skills/adopt-tiering/SKILL.md`, replace its restatement of the
      tiered policy with a pointer to `references/seed-policy-tiered.md` as the single source of
      that wording. Do not change what `adopt-tiering` does.
      **Deviation:** the restatement was deleted, but no pointer replaced it. A pointer would have
      directed a policy read at the template, which this change's own `repo-config` requirement
      forbids ("read only during seeding, with the owner present"). The repo's own `spec-flow/CI.md`
      is the single source any agent reads for policy; the template is a seeding artifact, not a
      policy source. `skills/setup/SKILL.md` stays its sole consumer, as
      `references/README.md:11` already records.
- [x] 3.2 In the same file, add one item to step 7's manual owner follow-up list, beside the
      existing branch-protection item: once the migration lands, the repo's own `spec-flow/CI.md`
      must restate the split, or the pipeline reads a policy the repo no longer matches. Update the
      matching `Rules` bullet to name both manual steps. The skill states the follow-up and still
      never writes the repo's policy file. Do not add a pointer to the template, and leave the
      entry gate at `SKILL.md:11-13` unchanged.
      **Added in review round 2, at the owner's direction:** the `code-review` lens found that
      `adopt-tiering` gates on `spec-flow/CI.md` having chosen tiering but never asks the owner to
      bring that file up to date once the tiers exist.

## 4. Documentation

- [x] 4.1 Consolidate `plugins/spec-flow/docs/workflow.md`'s test-policy statement. It currently
      appears at `:867`, `:889-935`, and `:1032`. Make the "Test policy" section authoritative and
      turn the other two into pointers.
- [x] 4.2 In that authoritative section, state that one seeding template ships, where it lives, and
      that nothing reads it at runtime — without implying it is a default. Amend `:867`'s thesis
      sentence so a reader who stops there does not hold a belief the plugin contradicts.
- [x] 4.3 In `plugins/spec-flow/README.md`, amend the `/spec-flow:setup` sentence in the
      `spec-flow/CI.md` prerequisite bullet (`:66-72`) to name the template and its non-fallback
      status. Keep the existing "write that plainly rather than inheriting a template that does not
      apply" caution verbatim, immediately after. Leave `:95` alone — it points at
      `references/ci/`, which is a different thing.
- [x] 4.4 Add `plugins/spec-flow/references/README.md`: three entries naming `ci/`,
      `refactoring-discipline.md`, and `seed-policy-tiered.md`, each with the consumer that reads
      it. The template's entry states it is read only during seeding, never at runtime.

## 5. Correct issue 50's pending change

- [x] 5.1 `openspec/changes/issue-50/specs/repo-config/spec.md:5` — `MAY ship a template` becomes
      `SHALL ship a template`, and the connective changes from "but" to "and". The concessive "but"
      only made sense alongside `MAY`.
- [x] 5.2 `openspec/changes/issue-50/ac-coverage.md:18` — replace the false `✅ Covered` with an
      entry naming both the defect and its resolution, pointing at this change and the template's
      path. Not `❌`: the scenario does cover the criterion once the artifact exists.
- [x] 5.3 Add a row to `openspec/changes/issue-50/ac-coverage.md` in the style of its existing
      `Amendment (owner-approved, mid-implementation)` row, recording that the change's artifacts
      asserted a file that was never created.
- [x] 5.4 Confirm no other edit to issue 50's change. `proposal.md:12`, `proposal.md:37`,
      `specs/test-policy/spec.md:120`, `specs/repo-config/spec.md:111`, and `tasks.md` all stand
      as written.
- [x] 5.5 Run `openspec validate issue-50 --type change --strict` and
      `openspec validate issue-53 --type change --strict`. Both must pass.

## 6. Version

- [x] 6.1 Bump `version` to `0.37.0` in `plugins/spec-flow/.claude-plugin/plugin.json` and
      `plugins/spec-flow/.codex-plugin/plugin.json`. Both files move together.
      **Deviation:** `plugins/spec-flow/.codex-plugin/plugin.json` does not exist. `spec-flow` has
      no `.codex-plugin/` directory, unlike `cassandra-expert` and `easy-db-lab`, which do. No new
      manifest was invented.
      **Added during the docs polish pass, at the owner's direction:** the `spec-flow` entry in
      `plugins/spec-flow/.claude-plugin/marketplace.json` carries a `version` too, and it had
      drifted to `0.10.0`. It moves to `0.37.0` here, so both of the plugin's manifests agree.
      `CLAUDE.md`'s version-bump procedure names only the two `plugin.json` files, which is why the
      drift went uncaught; correcting that procedure governs every plugin in the repo and is not
      done here. The repo-root `.claude-plugin/marketplace.json` lists `spec-flow` by path and pins
      no version, so it needs nothing.

## 7. Local gate

- [x] 7.1 Per `spec-flow/CI.md`: no test runner exists in this repo. Confirm both manifests this
      change edits still parse as JSON — `plugins/spec-flow/.claude-plugin/plugin.json` and
      `plugins/spec-flow/.claude-plugin/marketplace.json`. No shell scripts and no Python are
      touched by this change, so `shellcheck` and `py_compile` do not apply.
