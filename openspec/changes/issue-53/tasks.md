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
      **Amended by 9.5**, which adds three more for the same population's remedy message, taking
      the harness to 111.
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
- [x] 8.14 Do not bump the version. It is already 0.37.0 in both manifests and not yet shipped.
- [x] 8.15 Correct `openspec/changes/issue-50/specs/repo-config/spec.md:209`. Its scenario "The
      policy states what is actually true here" required this repository's policy to state it has
      **no automated test suite**, which 8.8 makes false and which contradicts this change's own
      requirement that the policy name its harnesses. Both deltas enter the same `repo-config`
      baseline at archive, so leaving it would publish a contradiction. The THEN clause now asks
      for this repository's actual test tooling. Corrected in place, on the same footing as task
      5.1's `MAY`→`SHALL`: issue 50's deltas were never synced, so this amends a draft. Found by
      the pre-commit review pass, not by the owner's brief, which said references only — recorded
      here and in `overrides.md` as a deliberate exception rather than drift.

## 9. Round-four corrections

**Found by the fourth review pass.** Two majors and five smaller items. Section 8 landed the
rename correctly but overreached in two places: it counted the repo's harnesses wrong, and it
stated the template-naming convention without the qualifier its own scenario already carries.

- [x] 9.1 Correct `spec-flow/TESTING.md`'s count and scope. The repo has **four** harnesses, not
      two: `plugins/dev-skills/skills/walkthrough/scripts/test-generate-walkthrough.sh` (151
      assertions) and `plugins/dev-skills/skills/ide-explain/scripts/test-generate-explain.sh` (88)
      sit outside `plugins/spec-flow/scripts/`, so 8.8's directory-scoped bullet let an agent
      editing `generate-walkthrough.py` conclude it had complied in full while a suite covering
      exactly its change went unrun. Replace the count with wording that cannot go stale, and
      generalise the harness bullet to a repo-wide **Test harnesses** bullet listing all four with
      what each covers. Verify each mapping against the harness's own source, not by guessing. The
      no-harness sentence carries over.
- [x] 9.2 Qualify the `.template` convention in three places: the requirement at
      `specs/repo-config/spec.md`, `plugins/spec-flow/references/README.md`, and `CLAUDE.md`. Task
      8.6 said "binding on any template the plugin ships", which the plugin's own
      `references/ci/github-actions-gradle.yml` and `github-actions-nextest.yml` cannot follow: the
      owner picks one by runner and names the destination file, so there is no single destination
      filename to derive from. The rule now reaches a template whose destination is a single named
      file. The requirement's scenario was already scoped right and is unchanged.
- [x] 9.3 Broaden the scenario "The harnesses are named in the local gate" to match 9.1. It asked
      only about a script under the plugin's scripts directory, which is the narrowing 9.1 removes.
- [x] 9.4 Correct `ac-coverage.md`: the template-naming row overstated its coverage and now states
      what the scenario does and does not verify; the harness rows say four, not two, and give both
      spec-flow harnesses as full paths.
- [x] 9.5 Add one warning to `cmd_check`'s `any_absent` remedy block in
      `plugins/spec-flow/scripts/repo-config.sh`. Both remedies mislead a repo that already used
      spec-flow: its default branch carries the same file, so rebasing changes nothing, and seeding
      writes a second policy beside the one it has. The warning names no previous filename and
      inspects nothing, keeping the owner's clean-break ruling. Add assertions in
      `test-repo-config.sh` covering it; the existing no-did-you-mean assertion must still pass.
      Three assertions land: two on the new warning, and one closing the gap the `spec` and
      `code-review` lenses both judged defensible — the no-did-you-mean check reads stdout alone,
      which proves `check`'s whole-message-on-stdout contract, so the combined-stream check is a
      second assertion beside it rather than a change to it. The harness goes 108 → 111.
- [x] 9.6 Fix `proposal.md`'s and `ac-coverage.md`'s `scripts/test-board.sh`, which does not
      resolve from the repo root; both now write `plugins/spec-flow/scripts/test-board.sh`.
- [x] 9.7 Fix two stale citations in `design.md` D3. The template paragraph this round inserted at
      `docs/workflow.md:915-923` shifted a target: `:920` now reads as a statement about the
      template, so it supported the opposite of D3's point. The nearest runtime-file mention is
      `:923`. `README.md:98` is off by one; the `references/ci/` pointer is at `:99`.
- [x] 9.8 State `design.md`'s citation base once, under Decisions: an unprefixed path is relative
      to `plugins/spec-flow`. Two rounds running, the mixed base produced a stale or ambiguous
      pointer, and this change edits both READMEs.
- [x] 9.9 Swap tasks 8.14 and 8.15 into numerical order.
- [x] 9.10 Re-run the local gate this round triggers, per `spec-flow/TESTING.md`: `shellcheck -x`
      on the two edited scripts, all four harnesses, and both `openspec validate --strict` runs.

## 10. Round-five corrections

**Found by the fifth review pass.** Four lenses approved and `spec` rejected. Two items were each
found independently by two lenses; a third came from one lens that declined to gate on it. Section
9 fixed the covers-mapping one level up, at the scripts a harness runs; this round reaches the
library those scripts import.

- [x] 10.1 Add `plugins/dev-skills/lib/html_shell.py` to **both** dev-skills harness entries in
      `spec-flow/TESTING.md`, and state that it is shared, so a change to it means running both
      harnesses rather than one. **Found by `spec` (F1, major) and `test-rigor` (TR-6, minor).**
      Both generators import `default_out_path`, `inject_manifest`, and `fail` from it
      (`generate-walkthrough.py:21-22`, `generate-explain.py:23-24`), both harnesses drive those
      generators end to end, and `test-generate-explain.sh:1186-1210` carries a regression written
      for its `inject_manifest` escaping, naming the file in its comment. No covers-mapping named
      it, so an agent editing it matched no bullet, then read the no-harness sentence — which tells
      it to stop — and ran `py_compile` while 239 assertions covering its change went unrun. This
      is task 9.1's failure mode one dependency level down, and `plugins/dev-skills/lib/` sits in
      neither harness's directory: exactly the shape task 9.3 broadened the scenario to reach. Each
      mapping verified against the harness's own source rather than asserted.
- [x] 10.2 Name `preview-fixture/` in the ide-explain entry. **Found by `spec`, in the same
      finding.** `test-generate-explain.sh:1087-1121` exercises the shipped `preview-fixture/` tree
      through `--change`, but the entry's negative clause named only `init-explain.sh` and
      `preview.sh`, which reads as though nothing else in that directory is covered. The entry is
      scoped to the fixture's OpenSpec content, which is what the harness reaches; `preview.sh`'s
      own invocation stays uncovered, as that harness's comment already records. Name the
      walkthrough harness's own `fixtures/` tree in its entry for the same reason: 26 checked-in
      manifests drive it, and a JSON fixture triggers neither the `shellcheck -x` nor the
      `py_compile` fallback, so an unlisted fixture is the 10.1 gap with no backstop at all. Found
      by the pre-commit review pass, which flagged the asymmetry of naming one harness's fixture
      tree and not the other's.
- [x] 10.3 Replace the release-notes pointer in `cmd_check`'s remedy block in
      `plugins/spec-flow/scripts/repo-config.sh`. **Found by `observability` (OBS-4) and
      `code-review` (R5-1), independently.** The repo has no `CHANGELOG`, no releases file, and no
      git tags, so "Check the plugin's release notes" sent an operator out of the terminal to
      nothing, while the answer sat four paragraphs above it: the "Missing or unusable" block
      prints the absolute expected path. The remedy now says to rename the existing policy file to
      the path named above. That names only the new filename, which the message already emits, so
      the clean-break ruling is untouched — nothing is inspected and the previous name is still
      never mentioned. The wording replaced was introduced by task 9.5.
- [x] 10.4 Give the rebase remedy its own why-clause. **Found by `observability`, which declined to
      gate on it.** The seeding remedy was defused specifically — "rather than seeding a second
      one" names and rejects its exact outcome — while the rebase remedy was defused only by the
      blanket "neither remedy below applies as written". The reason it actually fails, that the
      reader's default branch carries the same file, lived in a code comment and never reached the
      operator. That asymmetry matters because the rebase remedy describes a spec-flow issue
      worktree almost exactly. The output now states the reason and the comment drops the sentence
      the output took over. No previous filename is named. The why-clause is anchored — "Rebasing
      does not help **in that case**" — and the anchor is inside the asserted needle: the rebase
      remedy two paragraphs later is the correct fix for the reader most likely to reach this
      output, a worktree branched before the policy landed, and an unanchored sentence would tell
      that reader to skip their own remedy. Anchor found missing by the pre-commit review pass.
- [x] 10.5 Update `test-repo-config.sh` for 10.3 and 10.4. The assertion named "and is sent to the
      release notes rather than to a second policy file" pinned the dead-end string, so both its
      name and its expectation change with the message; two more land, one on 10.4's why-clause and
      one `expect_not_contains "release notes"` closing the gap the pre-commit review pass found —
      nothing pinned the *removal*, so the dead-end sentence could be re-added beside the working
      one and the suite would still pass. That is the reasoning the paired no-did-you-mean
      assertions already use. The harness goes 111 → 113. Both `expect_not_contains "CI.md"`
      assertions still pass: neither new string contains it.
- [x] 10.6 Add this round's rows to `ac-coverage.md`, and correct the assertion count it gives for
      `test-repo-config.sh`.
- [x] 10.7 Re-run the local gate this round triggers, per `spec-flow/TESTING.md`: `shellcheck -x` on
      the two edited scripts, all four harnesses, and both `openspec validate --strict` runs.

**Found by a Fable review, after the five-lens panel.** Three more, folded into the same round.

- [x] 10.8 Fix two sentences in `plugins/spec-flow/references/TESTING.md.template` that its own
      examples contradict. The body asserted "The boundary is enforced by the build" and "An
      integration test cannot compile or run inside the unit tier", then "The command is the
      runner's default fast selection" — all true for the Gradle and nextest layouts, all false for
      `go test -short ./...` and `pytest -m 'not integration'`, which the same body lists. Those are
      explicit narrowing flags, not a default selection, and neither stops an integration test
      running in the fast tier. The header's tag-or-flag paragraph told the seeder to write the
      enforcing mechanism into the seeded file but never to amend these sentences, so a seeder
      following the instructions literally landed a policy in a Go or pytest repo asserting a
      structural guarantee that repo does not have. **This file is copied verbatim into repos we
      never see**, which is what makes it the round's highest-value fix at low-medium severity.

      The body now states the **property** — the boundary is mechanical, an integration test cannot
      be selected into the unit tier — and the header names the two mechanisms that deliver it,
      where the test lives or a marker the fast command excludes, and tells the seeder which one to
      write in. Stating the property rather than a mechanism keeps the body true for every runner
      and keeps a seeding instruction out of the copyable text, which an earlier draft of this fix
      got wrong: it put "keep the sentence that describes this repo and drop the other" below the
      boundary marker, where the scenario "Seeding notes never reach the repo's file" forbids it and
      nothing told the seeder to delete the instruction itself.

      Two more instances of the same false claim sat in the same block and go with it: "separates
      its tests into two tiers, **structurally**" and the unit bullet's "The runner selects it by
      default". Fixing only the two sentences named would have fixed the symptom, not the claim.

      `go test -short ./...` is replaced, not rephrased. It is a **cooperative** flag: each slow
      test must call `testing.Short()` and skip itself, so one that forgets runs in the fast tier
      and nothing excludes it. That is not a mechanism, it is a convention, and a repo whose only
      separation is that flag genuinely **fails condition 1** — it should close the template at the
      header, not seed from it. Listing it was wrong from the start rather than worded wrong, and no
      rephrasing of the body could rescue it while it stayed. The Go example is now the build-tag
      form, `go test ./...` with the integration tests behind `//go:build integration`, which the
      compiler enforces and which does satisfy condition 1; the header states the exclusion
      explicitly, naming the flag, so a Go seeder relying on it is turned away rather than left to
      match against sentences none of which describe it. Its CI counterpart,
      `go test -tags=integration ./...`, joins the CI list so the example is whole.

      The per-runner examples stay, per task 1.1 — one is corrected, none removed. The three header
      conditions and the boundary marker are untouched.
- [x] 10.9 Correct `design.md:96` and `design.md:263`, which still said this repo has **two** shell
      harnesses. Both are present-tense factual claims and both were false. Neither carries a count
      now — "hand-rolled harnesses", matching `spec-flow/TESTING.md:11`, which names no count and
      defers to the list below it. That is the "wording that cannot go stale" task 9.1 called for,
      applied here rather than "four", which is the same claim one harness away from being wrong
      again. Nothing in D2's adjacency argument needed the number: the contrast it draws is
      qualitative — tiered against not tiered, no framework, no CI test gate. Round four corrected
      the count everywhere else — 9.1 in the shipped policy, 9.4 in `ac-coverage.md`, and 9.3 by
      removing the scenario's count rather than fixing it. `proposal.md:102` was corrected in
      `68c41c9` too, without a numbered task claiming it. That same commit touched `design.md` for
      the D3 citations and did not catch these two. Unlike `tasks.md`,
      whose stale mentions sit in a chronological log that later sections supersede, `design.md` is
      the standing design record that archives, and D2's adjacency argument rested on a false
      description of its own worked example. Sections 8 and earlier still say "two"; they are left
      as written, being the record of what was believed then.
- [x] 10.10 Narrow the scenario "The policy is stated once, not three times" to the workflow
      document, rather than trimming `plugins/spec-flow/README.md:66-76`. The requirement reached
      all plugin documentation while the proposal scoped the consolidation to `workflow.md`'s three
      internal sites, and the README restates the model at length before pointing. **The scenario is
      the side that moves, because trimming the README would break its own sibling scenario**: "A
      reader learns both facts together" names the README explicitly and requires the template's
      existence and its non-fallback status to be stated *there*. A bare pointer satisfies neither.
      The README is also the front door — a reader who never opens `workflow.md` still needs the
      no-default, no-fallback fact, which is the whole point of the design. The narrowing is honest
      rather than convenient: the triplication the scenario was written for was `workflow.md`'s
      three sites, and the README states the *mechanism*, naming which dimensions a repo must
      decide, without stating a policy for any of them. `workflow.md:678`, `:683`, and `:1047` all
      point at **Test policy** rather than restating it, so the narrowed scenario still holds.

## 11. Round-six corrections

**Round six approved unanimously, `spec_conformance: full`.** These five were non-blocking findings
the owner asked to land before the PR. Two of them are second visits to sentences earlier rounds
already touched, which is the signal that those sentences needed fixing rather than qualifying.

- [x] 11.1 Make the rename paragraph's rebase clause conditional in
      `plugins/spec-flow/scripts/repo-config.sh`. **Found by `code-review` (R6-1, minor).** Task
      10.4 wrote "Rebasing does not help in that case, because your default branch carries the same
      file" — an assertion about a branch the script cannot observe, and false for a third
      population **this change itself creates**. A consumer upgrading to 0.37.0 renames the policy
      file on their default branch; every branch cut before that rename satisfies the guard exactly
      (used spec-flow before, filename differs from what the tree carries) but its default branch
      carries the *new* path, so rebasing is precisely its fix. Sending it to rename instead writes
      a divergent second policy on a stale branch and buys an add/add conflict on the eventual
      rebase. That population is the intersection of the two already handled, and at upgrade time it
      is the more common of them, the rename being what the upgrade consists of. The message now
      states the sub-case as a condition rather than asserting it: if the default branch carries the
      older filename, rename; if it already carries the path named above, the rebase remedy below is
      the right one. No tree inspection, no filename named, so the clean-break ruling stands.

      The paragraph's opening goes with it. It had said "neither remedy below applies as written",
      which the new second sub-case makes false in the same breath — for that reader the rebase
      remedy applies exactly as written, and the message now says so. It opens by naming what the
      answer depends on instead. Found by the pre-commit review pass, which also caught that the
      assertion block's comment still carried the removed claim verbatim.
- [x] 11.2 Fix condition 1 in `plugins/spec-flow/references/TESTING.md.template` rather than
      reconciling it a third time. **Found by `spec` (F1, minor).** It said "the split is structural
      — the build enforces it", which is literally true for only two of the five runners the body
      lists: Gradle source sets and Go build tags. `pytest` selects by marker at collection time,
      `cargo nextest` by a `.config/nextest.toml` `default-filter` — runner config, not the build,
      and confirmed as what the plugin's own migration installs at
      `plugins/spec-flow/skills/adopt-tiering/SKILL.md:70-79` — and npm is whatever the script does.
      Task 10.8's paragraph fixed this by *restating* the condition as "cannot be selected", the
      correct test, in different words four lines below it. **The ordering is what made that
      insufficient**: "If the repo fails any one of them, close this file" sits above the
      clarification, so a seeding agent in a pytest or nextest repo can disqualify itself and never
      read the paragraph that would re-admit it, while the same file's local gate then blesses both
      runners. Condition 1 now carries the test itself: "the split is enforced by the tooling, not
      by convention — the fast command cannot select a slow test." The paragraph below drops its
      restating opening and keeps the rest, opening "Two mechanisms satisfy condition 1" rather than
      the "Two mechanisms do that" the finding proposed: with the test moved four lines up and the
      close-this-file paragraph in between, "that" had no clear antecedent left.

      **This reverses the earlier instruction not to touch the three header conditions**, at the
      owner's explicit direction, and it was checked against the committed scenario `The header
      disqualifies a repo that does not match` before being written. That scenario requires the
      header to *name* the conditions, to route a repo failing any of them to writing its own
      policy, and to state that nothing reads the file at runtime. All three still hold. What
      condition 1 requires is unchanged — task 10.8's paragraph had already made "cannot be
      selected" the operative test — so this moves the test into the condition rather than altering
      it.
- [x] 11.3 Extend the ide-explain exclusion in `spec-flow/TESTING.md` to the fixture subtrees.
      **Found by `observability` (OBS-5, minor).** The entry made a partial-directory claim for
      `preview-fixture/` and then listed an exclusion covering only two scripts, and an explicit
      exclusion list invites the inference that everything absent from it is covered. The fixture
      also holds `src/`, `baseline-src/`, `docs/`, `fake-gh/`, and `explain-map.json`, none of which
      the harness reaches — its own comment at `test-generate-explain.sh:1089-1094` says so. An
      agent editing `preview-fixture/explain-map.json`, exactly the checked-in-JSON population task
      10.2's `fixtures/` line was added to route, would run the harness, get a green, and believe
      the edit verified. **That fails toward false confidence rather than toward running nothing**,
      which is the worse direction for a gate whose job is making a change verifiable, so the entry
      now names the subtrees and says a green run proves nothing about them.
- [x] 11.4 Qualify "Every harness in the repo is listed here". **Found by `spec` (F2, minor).**
      `plugins/cassandra-expert/skills/training/scripts/verify-sai-capabilities.py` runs PASS/FAIL
      cases and exits non-zero unless every one matches, so on the plain reading it qualifies and
      the claim was absolute. The omission is right — its `README.md` requires a reachable Cassandra
      5.0+ cluster, so it cannot be an offline local-gate item — but that carve-out was two
      paragraphs away, and `CLAUDE.md` tells an agent to verify mechanically what it can. A sentence
      after the list now names the directory, says why those scripts are not part of this gate, and
      points at `CLAUDE.md` for when to run them.
- [x] 11.5 Spell out two paths in `spec-flow/TESTING.md`. **Found by `code-review` (R6-2, nit).**
      "that directory's `fixtures/`" and "that directory's `preview-fixture/`" left the antecedent
      to the reader, and the nearest preceding directory in each bullet is `assets/`, where neither
      exists. Every other entry gives a full repo-relative path; these two now do too.
- [x] 11.6 Extend `test-repo-config.sh` for 11.1. The assertion pinning "in that case" is replaced
      by two, one per sub-case, so neither branch of the new condition can be dropped silently. Both
      needles carry the **consequent**, not the condition alone: a regression keeping both
      conditions and swapping the remedy each routes to would pass a condition-only check. Both
      therefore span a wrapped output line, which the glob match crosses. The harness goes
      113 → 114.
- [x] 11.7 Add this round's rows to `ac-coverage.md`, and correct the assertion count it gives for
      `test-repo-config.sh`.
- [x] 11.8 Re-run the local gate this round triggers, per `spec-flow/TESTING.md`: `shellcheck -x` on
      the two edited scripts, all four harnesses, both `openspec validate --strict` runs, and both
      manifests.
