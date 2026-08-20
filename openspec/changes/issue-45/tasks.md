## 1. Move and generalize the skill

- [x] 1.1 Create `plugins/review-tools/skills/tech-debt/SKILL.md` starting from
      `plugins/spec-flow/skills/tech-debt/SKILL.md`, then rewrite the intro paragraph (currently
      "You are the central `project-manager` (like `groom`/`board`/`archive`...)" plus the
      "`architect`'s 'Nearby structural debt' step during `activate`" mention) to describe the
      skill's own execution shape generically — foreground, standalone, no worktree, no issue
      coupling, no code edits — with zero references to spec-flow's agents/skills/vocabulary.
- [x] 1.2 Step 6 (issue filing): remove the sentences naming `activate`'s tech-debt fast path and
      `/spec-flow:activate` by name; replace with generic prose stating the `## Direction` section
      must stay a distinct heading (some downstream consumer may key off it) — do not touch the
      actual issue-body template (title/labels/body structure) itself, only the surrounding
      provenance prose.
- [x] 1.3 Update the frontmatter `description` to drop the spec-flow-specific
      "`project-manager` recommends... see `docs/workflow.md`" tail; keep the substantive
      description of what the audit does.
- [x] 1.4 Delete `plugins/spec-flow/skills/tech-debt/` (the whole directory).

## 2. Update spec-flow's cross-references

- [x] 2.1 `plugins/spec-flow/README.md` (~line 120): replace the `/spec-flow:tech-debt` command row
      with a pointer noting the audit now lives in review-tools's `/tech-debt`.
- [x] 2.2 `plugins/spec-flow/agents/reviewer.md` (~line 30): reword "`/spec-flow:tech-debt` found
      this..." to name the moved command; no detection logic needed here (this agent only reacts to
      an already-filed issue's shape).
- [x] 2.3 `plugins/spec-flow/agents/project-manager.md` — "Watching for tech-debt review cadence"
      section (~lines 102-134): reword the section's opening to name the moved command; replace the
      unconditional recommendation with conditional prose per `design.md` decision 2 — **no
      `claude plugin list --json`/jq check anywhere in this file.** Add an explicit branch: if the
      agent doesn't have a tech-debt-style audit skill available to it, say so plainly ("the
      periodic-audit feature needs `review-tools` installed") instead of recommending a command
      that might not exist.
- [x] 2.4 `plugins/spec-flow/docs/workflow.md` — update every `/spec-flow:tech-debt` occurrence
      (~15, across the "Tech-debt review cadence" section, the "Tech-debt fast path" section's
      provenance mentions, the label table's two label descriptions, and the reference-list line
      ~477) to name the moved command. The "Tech-debt fast path" section's actual mechanics (how
      `activate`/`implement` consume a `type:tech-debt` issue) stay unchanged — only the filer's
      name updates.
- [x] 2.5 `plugins/spec-flow/skills/activate/SKILL.md` — update every `/spec-flow:tech-debt`
      provenance mention (frontmatter description, step 3's narrowed-charter text, step 4's
      confirmation-comment text, step 7's render text) to name the moved command; no new detection
      logic needed (`activate` only reacts to already-filed issues).
- [x] 2.6 `plugins/spec-flow/bin/bootstrap-labels.sh` (lines 35, 37, 38): update the comment and the
      two `--description` string literals to name the moved command instead of
      `/spec-flow:tech-debt`.

## 3. Repo-root documentation

- [x] 3.1 `README.md` (repo root): add a `/tech-debt` row to the `review-tools` skills table
      (~lines 374-375), matching the existing `/explain`/`/walkthrough` row format, linking to
      `plugins/review-tools/skills/tech-debt/SKILL.md`.

## 4. Versioning

- [x] 4.1 Ask the owner to confirm the exact new version numbers for both plugin pairs (spec-flow's
      and review-tools's `.claude-plugin/plugin.json` + `.codex-plugin/plugin.json`) before changing
      them — propose a minor bump for each by default, per this repo's stated convention. (Neither
      plugin has a `.codex-plugin/` directory in this repo — only `.claude-plugin/plugin.json`
      exists for each; bumped spec-flow 0.29.0 → 0.30.0, review-tools 0.13.0 → 0.14.0, both minor
      per convention. Flagged to the lead to relay to the owner rather than blocking on a direct
      ask.)
- [x] 4.2 If `review-tools`'s `plugin.json` carries a skill-listing `description`/`keywords` field,
      update it to mention `tech-debt` alongside `explain`/`walkthrough`.

## 5. Verification

- [ ] 5.1 Grep the whole repo for `spec-flow:tech-debt` and `skills/tech-debt` (excluding
      `openspec/changes/` historical text and this change's own files) — zero remaining hits outside
      historical/changelog context.
- [ ] 5.2 Confirm `plugins/spec-flow/skills/tech-debt/` no longer exists.
- [ ] 5.3 Read the moved `SKILL.md` once more in isolation to confirm no spec-flow-specific
      vocabulary remains (per `specs/tech-debt/spec.md`'s "Skill instructions carry no dependency on
      another plugin" requirement).
