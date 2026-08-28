# Tasks

## 1. The template

- [x] 1.1 Write the template. Body states the pre-issue-50 policy in full —
      fast tier locally, full suite in CI, merge gated on green CI — in the same owner-voice
      register the repo's own policy file uses. Frame the commands as per-runner examples, the
      way the pre-issue-50 text in `skills/implement/SKILL.md` did, rather than naming one stack's
      commands as though they were universal.
- [x] 1.2 Write its header: the three conditions a repo must meet (suite already split into a fast
      and a slow tier; CI runs tests; merge gated on green CI); the instruction to close the file
      and write from what the repo does if any condition fails; that this is the policy spec-flow
      used to hardcode and that hardcoding it was the defect issue 50 fixed; that nothing reads
      this file at runtime and a missing repo policy file stops the pipeline rather than falling
      back here.
- [x] 1.3 Close the header with a visible boundary marker (an HTML comment on its own line, not a
      wrapper around the header) stating that everything above it is for the seeding agent and the
      repo's file starts below.
- [x] 1.4 Confirm the template is unreachable by configuration resolution. Read
      `plugins/spec-flow/scripts/repo-config.sh` and check that every policy path is composed from
      the consuming repo's root (`git rev-parse --show-toplevel`, `:114`; composed at `:290` and
      `:370`) and that `CLAUDE_PLUGIN_ROOT` is never read there (`:43-45`). The plugin's copy is
      outside that tree, so no resolved path can name it.
- [x] 1.5 Rename the template from its first draft name, `seed-policy-tiered.md`, to the
      destination's basename with `git mv`, so history follows the file, and update every reference
      to its former path.
      **Owner-directed after the first review pass.** The first draft's name hid what the file was,
      and the owner, finding nothing whose name resembled the file it seeds, concluded the template
      had never shipped. The naming argument behind the first draft's name was overstated: the
      no-runtime-read guard is containment, not the basename, and it survives the rename intact.
      See D1 and D3. **Superseded by 8.1**, which adds the `.template` suffix the plugin now uses
      for every template it ships.

## 2. Seeding

- [x] 2.1 In `plugins/spec-flow/skills/setup/SKILL.md`, insert one paragraph after the sentence
      naming this repo's own policy file as a worked example (currently ending line 113),
      making the template conditional on `setup` having already determined the repo's shape is the
      tiered split, and directing it not to open the file for any other shape.
- [x] 2.2 Address the template by an explicit `${CLAUDE_PLUGIN_ROOT}`-relative path, with no
      fallback clause — matching `skills/adopt-tiering/SKILL.md:82`, not
      `agents/tdd-developer.md:57`.
- [x] 2.3 Leave `setup/SKILL.md:92`'s "not a template with blanks" and the `skills` worked-example
      sentence verbatim. Confirm by diff that neither moved or changed.
- [x] 2.4 Add one sentence to the "Third, land it" block: the seeded file carries neither the
      template's seeding notes nor any reference to the template.

## 3. `adopt-tiering`

- [x] 3.1 In `plugins/spec-flow/skills/adopt-tiering/SKILL.md`, replace its restatement of the
      tiered policy with a pointer to the template as the single source of
      that wording. Do not change what `adopt-tiering` does.
      **Deviation:** the restatement was deleted, but no pointer replaced it. A pointer would have
      directed a policy read at the template, which this change's own `repo-config` requirement
      forbids ("read only during seeding, with the owner present"). The repo's own policy file
      is the single source any agent reads for policy; the template is a seeding artifact, not a
      policy source. `skills/setup/SKILL.md` stays its sole consumer, as
      `references/README.md:11` already records.
- [x] 3.2 In the same file, add one item to step 7's manual owner follow-up list, beside the
      existing branch-protection item: once the migration lands, the repo's own
      `spec-flow/TESTING.md` must restate the split, or the pipeline reads a policy the repo no
      longer matches. Update the
      matching `Rules` bullet to name both manual steps. The skill states the follow-up and still
      never writes the repo's policy file. Do not add a pointer to the template, and leave the
      entry gate at `SKILL.md:11-13` unchanged.
      **Added in review round 2, at the owner's direction:** the `code-review` lens found that
      `adopt-tiering` gates on the repo's policy file having chosen tiering but never asks the owner to
      bring that file up to date once the tiers exist.

## 4. Documentation

- [x] 4.1 Consolidate `plugins/spec-flow/docs/workflow.md`'s test-policy statement. It currently
      appears at `:867`, `:889-935`, and `:1032`. Make the "Test policy" section authoritative and
      turn the other two into pointers.
- [x] 4.2 In that authoritative section, state that one seeding template ships, where it lives, and
      that nothing reads it at runtime — without implying it is a default. Amend `:867`'s thesis
      sentence so a reader who stops there does not hold a belief the plugin contradicts.
- [x] 4.3 In `plugins/spec-flow/README.md`, amend the `/spec-flow:setup` sentence in the
      policy-file prerequisite bullet (`:66-72`) to name the template and its non-fallback
      status. Keep the existing "write that plainly rather than inheriting a template that does not
      apply" caution verbatim, immediately after. Leave `:95` alone — it points at
      `references/ci/`, which is a different thing.
- [x] 4.4 Add `plugins/spec-flow/references/README.md`: three entries naming `ci/`,
      `refactoring-discipline.md`, and the template, each with the consumer that reads it. The
      template's entry states it is read only during seeding, never at runtime.

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
      **Amended by 8.9 and 8.15.** Section 8 renames every reference to the policy file across
      issue 50's artifacts, and corrects one scenario whose content assertion this change makes
      false. Their substance is otherwise untouched.
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

- [x] 7.1 Confirm both manifests this change edits still parse as JSON —
      `plugins/spec-flow/.claude-plugin/plugin.json` and
      `plugins/spec-flow/.claude-plugin/marketplace.json`.
      **Amended by section 8.** As first written this task also recorded that no shell scripts were
      touched, and cited `spec-flow/CI.md`'s claim that no test runner exists here. Section 8
      touches three shell scripts, and corrects that claim: two harnesses exist. See 8.8.

## 8. Rename the policy file to `TESTING.md` and correct this repo's own policy

**Owner-directed after the second review pass.** Two decisions, taken together. First, the
repo-owned policy file is renamed `CI.md` → `TESTING.md`: it states what runs locally, what runs in
CI, and what gates merge, so CI is one clause of it rather than its subject. Second, a shipped
template is named `<destination-filename>.template`, so its relationship to the file it becomes is
visible without opening it. The rename is a **clean break** — no alias, no fallback, no
did-you-mean — and section 8 also corrects this repository's own policy, which claimed a test
tooling situation that was never true. See D1, D3, and the two requirements this round adds to
`specs/repo-config/spec.md`.

- [x] 8.1 `git mv plugins/spec-flow/references/CI.md
      plugins/spec-flow/references/TESTING.md.template` and
      `git mv spec-flow/CI.md spec-flow/TESTING.md`, so history follows both files.
- [x] 8.2 In `plugins/spec-flow/scripts/repo-config.sh`, change `REQUIRED_CONFIG` (`:35`) and
      `POLICY_FILE` (`:39`) to `TESTING.md`, and sweep the file for message and comment text naming
      the old filename. Add no fallback, no alias, and no check for the previous name.
- [x] 8.3 Sweep `plugins/spec-flow/scripts/seed-config.sh` for the old filename. It derives the
      name from `repo-config.sh`, so only comment text changes.
- [x] 8.4 Update every assertion and fixture path in
      `plugins/spec-flow/scripts/test-repo-config.sh`. It must still exit 0.
- [x] 8.5 Add a case to `test-repo-config.sh` asserting the clean break: a repo holding only
      `spec-flow/CI.md` and no `TESTING.md` reports the policy as missing and exits 1, the message
      names `TESTING.md`, and the message does not name `CI.md` — the last covering the
      did-you-mean the exit code alone would not exclude. "We added no fallback" is otherwise
      invisible: nothing else fails if someone adds one later. This raises the harness from 105 to
      108 assertions, the only intended count change.
- [x] 8.6 Rename every reference in the plugin's prose: `docs/workflow.md`, `README.md`,
      `references/README.md`, `skills/setup/SKILL.md`, `skills/adopt-tiering/SKILL.md`,
      `skills/implement/SKILL.md`, `skills/implement/implement.workflow.js`, and the repo-root
      `README.md`. In `references/README.md`, state the `<destination-filename>.template`
      convention as a convention, binding on any template the plugin ships, not as a fact about
      this one file.
- [x] 8.7 Add the template-naming convention to `CLAUDE.md`, with the worked example
      `plugins/spec-flow/references/TESTING.md.template` → `spec-flow/TESTING.md`.
- [x] 8.8 Correct `spec-flow/TESTING.md` while it moves. It claimed the repo has **no automated
      test suite** and told an agent not to look for a test runner. Two harnesses exist and both
      pass: `plugins/spec-flow/scripts/test-repo-config.sh` covers `repo-config.sh` and
      `seed-config.sh`; `plugins/spec-flow/scripts/test-board.sh` covers `board.py`. Replace the
      false claim, and add a local-gate bullet requiring the harness covering a changed script
      under `plugins/spec-flow/scripts/` to run and exit 0, alongside the existing `shellcheck -x`,
      JSON-parse, and `py_compile` bullets. Keep what is still true: CI is not a test gate here,
      nothing produces a `spec-flow-failures` artifact, and an agent triggering no clause has
      complied in full. Keep the owner-voice header. Say precisely that there is no `cargo`,
      Gradle, `pytest`, or `npm test` here, rather than "do not look for a test runner".
- [x] 8.9 Rename every reference in `openspec/changes/issue-50/`: `specs/repo-config/spec.md`,
      `proposal.md`, `design.md`, `tasks.md`, `ac-coverage.md`, and `overrides.md`. References only
      — the `MAY`→`SHALL` correction and the `ac-coverage` defect rows this change already landed
      stay as they are. `specs/test-policy/spec.md` names no filename, so it needs nothing.
- [x] 8.10 Bring this change's own artifacts in line: `proposal.md`, `design.md` (D1, D3, and the
      alternatives all argue about the name), `ac-coverage.md`, and `overrides.md`.
- [x] 8.11 Run the local gate this round's own change triggers, from the repo root:
      `shellcheck -x` on the three edited scripts, `bash plugins/spec-flow/scripts/test-repo-config.sh`,
      and `bash plugins/spec-flow/scripts/test-board.sh`. All must exit 0. Confirm both plugin
      manifests still parse.
- [x] 8.12 Run `openspec validate issue-50 --type change --strict` and
      `openspec validate issue-53 --type change --strict`. Both must pass.
- [x] 8.13 Confirm `grep -rn "CI\.md" --exclude-dir=.git .` returns no live path reference. What
      remains is deliberate: the historical and rejected-alternative passages in this change's own
      artifacts, the spec scenario naming the previous filename, and the clean-break case in
      `test-repo-config.sh`. `.memsearch/` and `.spec-flow/` are session and per-branch runtime
      state, neither committed nor ours to edit.
- [x] 8.15 Correct `openspec/changes/issue-50/specs/repo-config/spec.md:209`. Its scenario "The
      policy states what is actually true here" required this repository's policy to state it has
      **no automated test suite**, which 8.8 makes false and which contradicts this change's own
      requirement that the policy name its harnesses. Both deltas enter the same `repo-config`
      baseline at archive, so leaving it would publish a contradiction. The THEN clause now asks
      for this repository's actual test tooling. Corrected in place, on the same footing as task
      5.1's `MAY`→`SHALL`: issue 50's deltas were never synced, so this amends a draft. Found by
      the pre-commit review pass, not by the owner's brief, which said references only — recorded
      here and in `overrides.md` as a deliberate exception rather than drift.
- [x] 8.14 Do not bump the version. It is already 0.37.0 in both manifests and not yet shipped.
