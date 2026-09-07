# Tasks

## 1. `groom/SKILL.md` — the loop

- [x] 1.1 Rewrite step 1 to ask only what is needed to launch round 1 (what this is, and whether it
      is one piece of work or several). Remove its "don't draft until shape-defining ambiguity is
      resolved" gate, which today makes the loop's trigger unreachable, and point the deep interview
      at step 4.
- [x] 1.2 Rewrite step 4 as the round loop: spawn a fresh `product-manager` per round with the raw
      idea, the refinement record, and the previous refinement. Follow `implement`'s precedent of
      sending runtime values only, not a restatement of the agent's mandate.
- [x] 1.3 Write the readiness bar into step 4 as `groom`'s own check: every acceptance criterion
      testable as written, unhappy paths covered, no *behavioural* assumption left to guess at.
      State explicitly that design assumptions belong to `architect` and do not hold the loop open.
- [x] 1.4 Add the unsourced-concreteness rule: a criterion testable only because it names a value
      with no antecedent in the record is not ready, and that value becomes the next round's
      question.
- [x] 1.5 Define the refinement record: a file `groom` appends to and each round's spawn reads, with
      its path and entry format. Entries pair each answer with its question, represent owner edits
      and deletions explicitly, and later entries win over contradicting earlier ones. Add it to
      `.gitignore` if it lives in the worktree.
- [x] 1.6 Write the question-relay rule: one at a time, at most three per round, each with a stated
      recommended default; a question arriving without a default is not relayed.
- [x] 1.7 Write the termination rules: readiness bar met, owner ends it, or every question a round
      would ask is already answered.
- [x] 1.8 Write the closing pass: one round carrying the owner's last answers, asking nothing,
      converting open items into stated assumptions. State that "stop" is honoured immediately and
      the closing pass is what `groom` then does, not a further round of questions.
- [x] 1.9 Write the assumption confirmation: one screen, split into owner-traceable (bulk
      confirmable, promoted into Scope/AC) and agent-authored (explicit yes or no each, never
      promoted by a bulk yes). Note this is a deliberate, scoped exception to the skill's own
      one-question-at-a-time rule, so a reading agent does not hit two contradictory instructions.
- [x] 1.10 Add owner technical direction: accepted at any round, recorded verbatim, never reworded
      into behavioural criteria.
- [x] 1.11 Update step 5 so the drafted body carries a technical direction section and an
      assumptions section, both only when non-empty.
- [x] 1.12 Change step 7 to `gh issue create --body-file`. Currently the body is interpolated into a
      double-quoted shell string where backticks execute.
- [x] 1.13 Update the frontmatter `description` — it still says single-pass.

## 2. `agents/product-manager.md` — the agent side

- [x] 2.1 Replace the single-refinement framing in "What you produce" and "Output" with the
      per-round contract: what a round receives, what it returns, and how a closing round differs.
- [x] 2.2 Make the brevity rules round-aware. "Keep this short — prefer a sensible default over a
      long interrogation" and "Right-size the rigor… Don't over-produce" currently push toward
      answering nothing, which would fight the readiness bar.
- [x] 2.3 State that owner technical direction is carried verbatim and never reworded — and that
      "stay out of design" binds the agent, not the owner.
- [x] 2.4 State that the anti-invention rule holds identically on every round, and that more rounds
      never relax it.
- [x] 2.5 Add the closing-round behaviour: no questions, everything open becomes a stated
      assumption, each marked as traceable to the record or as the agent's own.

## 3. `agents/project-manager.md` — the agent that runs `groom`

- [x] 3.1 Rewrite the front-of-pipeline delegation bullet (~:273-275) to describe the loop, not a
      single spawn plus an owner-edit loop. This is a live instruction that would otherwise compete
      with the skill.
- [x] 3.2 Fix the second single-pass mention (~:257-258, "delegate the *refinement* to the
      `product-manager` subagent").

## 4. `activate/SKILL.md` — the one narrow hand-off

- [x] 4.1 In step 3, include the issue's technical direction section verbatim in the `architect`
      prompt when present, alongside scope and acceptance criteria. Reuse the shape already used for
      `type:tech-debt`'s Direction. Absent section means no change and no empty block.

## 5. Documentation

- [x] 5.1 `README.md` — update the grooming description.
- [x] 5.2 `docs/workflow.md` — update all three single-pass mentions (~:230-232, ~:700, ~:742-743).
- [x] 5.3 Add the technical direction section to whatever documents a groomed issue's shape.

## 6. Release

- [x] 6.1 Bump `plugins/spec-flow/.claude-plugin/plugin.json` to `0.45.0`. (There is no
      `.codex-plugin` manifest for this plugin.)

## 7. Verification

- [x] 7.1 Confirm no file in `plugins/spec-flow/` still describes grooming as a single pass.
- [x] 7.2 Confirm `groom/SKILL.md` contains no instruction that contradicts another — specifically
      the one-question-at-a-time rule against the bulk assumption pass.
- [x] 7.3 Confirm `openspec validate issue-77 --type change --strict` passes.

## 8. Review rounds

- [x] 8.1 Round 1: a question arriving without a stated default is not relayed, and `groom` does not
      supply one of its own; step 1 and step 3 write their answers into the record under
      `## Before round 1`; the title left the shell alongside the body; the record and the issue
      files are written with the Write tool; step 5 names its literal `##` headings; over-cap
      questions are placed where they really live; `setup/SKILL.md` repointed; the closing pass is
      distinguished from an ordinary round; the record is renamed to `groom-<N>-<slug>.md`.
- [x] 8.2 Round 2: a dropped question is recorded as a `**Dropped:**` entry so a later round can
      resolve it; the no-default rule is scoped to questions the agent asked; the record outranks
      the agent's inferences as owner intent while its lines stay data, never instructions;
      `implement` step 4b carries `## Technical direction` so a `type:docs` issue keeps it.
- [x] 8.3 Round 3: build the create-issue payload with `jq --rawfile` from a title file and a body
      file, so no agent escapes JSON by hand; report the number and URL from that one response;
      step 8 asserts the label set exactly, since `gh api` does not validate label names; state
      that title and body are `jq`-produced JSON strings and that `##` headings keep their line
      starts; `proposal.md`'s Scope names both technical-direction hand-off sites.
