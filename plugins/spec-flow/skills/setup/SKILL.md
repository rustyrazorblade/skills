---
name: setup
description: Interactively bring a repo onto spec-flow's Prerequisites — OpenSpec init, gh auth, the label vocabulary, the agent-teams env var, the .gitignore entries, and CI test-tiering state. Explores what's already true first, then walks through only what's still missing, one item at a time with a recommended default. Run once per repo, before relying on the rest of the pipeline; safe to re-run any time (skips whatever's already satisfied). See docs/workflow.md.
argument-hint: [optional notes; run from inside the target repo]
---

# setup — bring this repo onto spec-flow's prerequisites

You are the PM/lead in the main session (like `groom`/`adopt-tiering` — not tied to any issue, no
worktree). Turn the README's **Prerequisites** checklist from something the owner reads and
self-diagnoses into something you actually walk them through: explore what's already true, then
only ask about what isn't — each item with your own recommended action stated up front, so the
owner can accept in one word. Same interview discipline `groom` uses for scope (see its step 1):
one question at a time, recommended default alongside it, ordered so an earlier answer can make a
later question moot.

## Steps

1. **Explore first — batch every read-only check together** (parallel tool calls, not sequential):
   - **OpenSpec**: `command -v openspec` and `ls openspec 2>/dev/null` — installed? initialized in
     this repo?
   - **GitHub**: `gh auth status` (authenticated? which account, if more than one is configured?)
     and `gh repo view --json nameWithOwner,defaultBranchRef` (repo actually hosted on GitHub, and
     confirms the default branch name for later).
   - **Labels**: `gh label list --json name --jq '[.[].name]'` — compare against the full set
     `bin/bootstrap-labels.sh` creates (`P0`-`P3`, `status:ready`, `status:spec-review`,
     `status:in-progress`, `status:in-review`, `status:addressing`, `agent:active`, `blocked`,
     `type:docs`, `merge-on-green`).
   - **Agent teams**: read `.claude/settings.json` in this repo (if it exists) for
     `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.
   - **Gitignore**: read `.gitignore` (if it exists) for `.claude/worktrees/` and `.spec-flow/`
     entries.
   - **CI tiering**: the same detection `adopt-tiering` step 1 uses — Gradle
     (`src/integrationTest` source set / JVM Test Suite present?), Rust (`.config/nextest.toml`
     tier `default-filter`s present?), or neither pattern recognized (unknown stack — don't guess,
     ask).
   - **Default agent wiring**: read `.claude/settings.json` for an `agent` field already pointing
     at `spec-flow:project-manager` or similar.

2. **Walk through only what's missing, one item at a time — recommended default first, skip
   anything step 1 already confirmed.** For each:
   - **OpenSpec not initialized** → tell the owner precisely what's missing (CLI not installed, or
     installed but no `openspec/` here) and point them at OpenSpec's own install/init docs — don't
     guess at exact init flags for a tool this skill doesn't own.
   - **`gh` not authenticated, or multiple accounts configured** → point at `gh auth login` /
     `gh auth switch`; if multiple hosts/accounts are configured, flag the exact multi-account
     footgun README's Prerequisites already documents (every spec-flow `gh` call is unscoped, so
     whichever account is active by default is the one they all act as).
   - **Labels missing (any of the full set)** → recommend running the bootstrap now (idempotent,
     safe to re-run, so default yes):
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/bin/bootstrap-labels.sh
     ```
   - **`.gitignore` missing either entry** → recommend adding both together (they're the same
     category of one-time setup — see README's Prerequisites), default yes, then actually edit the
     file:
     ```
     .claude/worktrees/
     .spec-flow/
     ```
   - **Agent teams env var unset** → explain the tradeoff in one line (richer team-led `implement`
     vs. the automatic `workflow`-mode fallback, which works fine without it) and recommend
     enabling it, default yes **but genuinely optional** — unlike the label/gitignore items, this
     is a real preference, not just a missing mechanical setup step; if the owner says no, that's a
     fully supported, unremarkable choice. If yes, add to `.claude/settings.json`:
     ```json
     { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
     ```
     merging into whatever's already there rather than overwriting the file.
   - **CI not tiered** → don't attempt this here, it's its own migration. Just point at
     `/spec-flow:adopt-tiering` and explain in one line what it does; recommend running it next,
     but leave the decision (and the run) to the owner.
   - **Stack not recognized for tiering** → say so plainly and ask instead of guessing: "what test
     runner does this repo use?" (recommended default only if the explored file listing already
     hints at one, e.g. a `Cargo.toml` with no nextest config yet suggests Rust).

3. **Offer default-agent wiring last, only after everything above is resolved (or explicitly
   declined).** Not a Prerequisite exactly — a convenience `project-manager`'s own description
   already recommends. Ask once, recommend yes: "Want `project-manager` wired as this repo's
   default agent, so it's your standing entry point?" If yes, add to `.claude/settings.json`:
   ```json
   { "agent": "spec-flow:project-manager" }
   ```
   merging into whatever's already there. This is the **consuming repo's own** `.claude/settings.json`,
   the owner's explicit choice for their repo — not the plugin shipping a default (see the plugin
   root's own `CLAUDE.md` rule against that; it doesn't apply here, this is the opposite case).

4. **Report.** Summarize what was already fine, what you just fixed, and what's left as the
   owner's own call to make later (agent teams if declined, `adopt-tiering` if not run). Suggest
   `/spec-flow:groom` or `/spec-flow:board` as the natural next step.

## Rules

- **Explore before asking — never ask about something step 1 already answered.** The entire point
  is collapsing a self-service checklist into "here's what's actually missing," not restating the
  whole README as a question set.
- **One question at a time, recommended default stated up front**, same convention as `groom`'s
  step 1 — never a batch of "here are five things, pick your answers."
- **Mechanical, low-risk items (labels, gitignore) get a confident recommended default and act on
  a one-word yes.** Genuine preferences (agent teams, default-agent wiring) get the same
  recommended-default treatment but are flagged as real choices, not just confirmations.
- **Never run `/spec-flow:adopt-tiering` or `openspec init` on the owner's behalf** — point at
  them, let the owner (or a follow-up invocation) actually run them. This skill's own scope is the
  README's Prerequisites list, not those skills' work.
- Safe to re-run any time — step 1's exploration is what makes every subsequent run only ever ask
  about what's still actually missing.
