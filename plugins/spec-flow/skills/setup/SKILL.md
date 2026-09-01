---
name: setup
description: Interactively bring a repo onto spec-flow's Prerequisites — OpenSpec init, gh auth, the label vocabulary, the agent-teams env var, the seam-visualization preference, the refactor circuit breaker, the .gitignore entries, the repo's own spec-flow/TESTING.md test and CI policy (proposed, confirmed with the owner, then landed on a branch as a PR — the one outward action this skill takes), and CI test-tiering state. Explores what's already true first, then walks through only what's still missing, one item at a time with a recommended default. Run once per repo, before relying on the rest of the pipeline; safe to re-run any time (skips whatever's already satisfied). See docs/workflow.md.
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
     `needs-attention`, `type:docs`, `merge-on-green`, `type:tech-debt`, `tech-debt-review`).
   - **Agent teams**: read `.claude/settings.json` in this repo (if it exists) for
     `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.
   - **Seam visualization**: read `.claude/settings.json` for `env.SPEC_FLOW_SEAM_VIEW`, and
     whether the standalone `dev-skills` plugin is installed/enabled:
     `claude plugin list --json | jq -e '[.[] | select(.id | startswith("dev-skills@")) | select(.enabled)] | length > 0'`.
   - **Developer agent**: read `.claude/settings.json` for `env.SPEC_FLOW_DEVELOPER_AGENT`, and
     detect the project's language (a `Cargo.toml` for Rust; a `build.gradle.kts`/`.kt` sources for
     Kotlin; a `pom.xml`/`.java` sources for Java). Reuse the same `dev-skills` availability check
     as **Seam visualization** above; do not run it twice.
   - **Refactor circuit breaker**: read `.claude/settings.json` for
     `env.SPEC_FLOW_REFACTOR_BREAKER`.
   - **Gitignore**: read `.gitignore` (if it exists) for `.claude/worktrees/` and `.spec-flow/`
     entries. Also run `git check-ignore -v spec-flow/TESTING.md spec-flow/WORKFLOWS.md` — it must
     find **no** match. A match
     means the repo is ignoring its own committed configuration directory, which is a bug, not a
     preference.
   - **Repo policy**: run the check that every other entry point runs —
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo-config.sh check
     ```
     Exit 0 means this repo already owns its policy and the seeding item below is skipped. Exit 1
     means it does not. Exit 2 means the environment is wrong (not a git repo, or a bad
     `SPEC_FLOW_CONFIG_DIR`); relay the script's message and fix that first — never offer seeding
     on exit 2.
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
     **Add `.spec-flow/` with the leading dot. Never add `spec-flow/`.** They differ by one
     character and mean opposite things: `.spec-flow/` is gitignored per-branch runtime state,
     while `spec-flow/` is the repo's **committed** configuration. Worse, a trailing-slash pattern
     with no interior slash matches at any depth, so `spec-flow/` in this plugin's own repo would
     match `plugins/spec-flow/` and erase the plugin's entire source from git.
   - **`spec-flow/` is matched by a gitignore rule** (step 1's `git check-ignore -v` found one) →
     say so plainly, name the rule and the file it lives in, and recommend removing it, default
     yes. The repo cannot commit its own configuration while that rule stands, so the check will
     keep failing no matter how many times seeding runs.
   - **No repo policy** (step 1's `repo-config.sh check` exited 1) → this is the one item that acts
     outward: it opens a PR. See the carve-out in **Rules** below. Work it in three moves.

     **The check names every config file the repo is missing, and they seed together** — one
     proposal, one confirmation, one branch, one PR. Today that is `TESTING.md` (the test and CI
     policy) and `WORKFLOWS.md` (the review panel and its gate). Propose each file the check named,
     show them together, and land them in a single `seed-config.sh` call. Never seed one and leave
     the other: the check keeps failing either way, and the owner would confirm twice for one
     outcome.

     **First, propose.** Read the repo and write a concrete policy for it — not a template with
     blanks. Say what runs locally on every TDD cycle, what CI runs, whether CI is a test gate at
     all, and what gates merge. Reuse step 1's tiering detection, and read the repo's own
     `.github/workflows/` (or equivalent) rather than assuming. **Propose for any stack**, however
     little you recognized: a proposal the owner confirms is not a guess, and detection only makes
     the proposal better or worse, never mandatory. **State plainly what you could not determine**
     and what you inferred instead, so the owner knows which lines to check hardest.

     A repo with no test suite and no test-running CI is a **first-class policy**, not a gap. Write
     that plainly when it is true. Never invent a test command the repo does not run.

     Open the proposed file with a header that says, in the repo's own voice:
     - This repo owns this file.
     - spec-flow reads it and ships no default; if it goes away, the pipeline stops rather than
       falling back to anything.
     - Every line is the owner's to change, including the local/CI split itself.
     - Keep it short: every implementation and review agent reads it on every run.

     Then state the local gate, what CI does, what gates merge, and the push cadence. Say plainly
     that the local gate runs on **every** TDD cycle, so the owner sees the cost of what they are
     choosing. `spec-flow/TESTING.md` in this plugin's own repo is a worked example of a policy
     nothing like the old shipped default.

     **For `WORKFLOWS.md`**, the same rules apply with a different subject: it states which review
     lenses run, what counts as must-fix, and the round cap. Read the repo first — a repo with an
     established review culture may want fewer lenses, or none at all. A policy of "no automated
     panel; the owner's review is the gate" is first-class, exactly like a repo with no test suite,
     and the pipeline supports it directly: no lens runs, no fix loop runs, and the PR says plainly
     that no panel ran. `${CLAUDE_PLUGIN_ROOT}/references/WORKFLOWS.md.template` holds the panel
     spec-flow has always run, as a starting point — the same "open it only if it fits" rule as
     the test template below. `spec-flow/WORKFLOWS.md` in this plugin's own repo is a worked
     example that keeps the default and says why each lens earns its slot.

     Only where you have **already** determined that the repo has the tiered shape — a suite split
     structurally into a fast tier and a slow tier, CI that runs the tests, and merge gated on
     green CI — open `${CLAUDE_PLUGIN_ROOT}/references/TESTING.md.template` and use its wording.
     That is the policy spec-flow used to hardcode, so a repo adopting it gets one canonical
     baseline instead of a fresh paraphrase. **For any other shape, do not open that file.** Read
     the repo first and let it decide the shape; never let the template decide it. It is one
     policy, not the policy, and nothing in the pipeline reads it at runtime.

     **Second, confirm.** Show the owner the full proposed file and wait. If the proposal uses the
     template's wording, say so alongside the file and name the evidence for each of the three
     conditions — where the structural split is enforced, which workflow runs the tests, and what
     makes merge gated on green CI — so the owner can check the shape came from the repo. **Write
     nothing until they confirm or amend it** — not a draft file, not a branch, nothing. If they
     amend it, show the amended version and confirm again.

     **Third, land it.** What you write carries neither the seeding notes above the template's
     boundary marker nor any reference to the template — the file reads as the repo's own policy.
     Write each confirmed file to its own temporary file, then pass them all in one call as
     `<target>=<content-file>` pairs:
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/seed-config.sh \
       TESTING.md=<content-file> WORKFLOWS.md=<content-file>
     ```
     Pass only the files the check named as missing. The script discovers the default branch,
     checks it for each existing policy, skips any already present and usable, and puts the rest in
     one branch, one commit and one PR. It never commits or pushes to the default
     branch, never merges, and never touches the owner's working tree. Relay its output. Tell the
     owner the check keeps failing until that PR merges and their branch carries it.
   - **Agent teams env var unset** → explain the tradeoff in one line (richer team-led `implement`
     vs. the automatic `workflow`-mode fallback, which works fine without it) and recommend
     enabling it, default yes **but genuinely optional** — unlike the label/gitignore items, this
     is a real preference, not just a missing mechanical setup step; if the owner says no, that's a
     fully supported, unremarkable choice. If yes, add to `.claude/settings.json`:
     ```json
     { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
     ```
     merging into whatever's already there rather than overwriting the file.
   - **Seam visualization preference unset, AND the `dev-skills` plugin is installed/enabled**
     (skip this item entirely if `dev-skills` isn't installed — don't offer a preference for a
     plugin the owner doesn't have; they can install it and re-run `setup` any time) → explain the
     choice in one line: at both owner seams (design approval, in-review), `activate`/`implement`
     can either generate an interactive HTML view via `dev-skills`'s `ide-explain` skill — file tree,
     diff view, docs, all in one place — or render the same content as plain text in the terminal,
     same as before that plugin existed. Recommend the HTML view, default yes, but genuinely
     optional — like agent teams, a real preference, not a mechanical default. If yes:
     ```json
     { "env": { "SPEC_FLOW_SEAM_VIEW": "explain" } }
     ```
     If the owner prefers terminal-only:
     ```json
     { "env": { "SPEC_FLOW_SEAM_VIEW": "terminal" } }
     ```
     merging into whatever's already there. `activate`/`implement` read this fresh at each seam,
     and re-check `dev-skills`'s availability every time rather than trusting this one-time
     detection — see **Seam visualization** in `docs/workflow.md`.
   - **Developer agent unset, AND the `dev-skills` plugin is installed/enabled, AND the project
     is a language it covers** (Rust, Kotlin, and Java today) → explain the choice in one line:
     `implement` spawns spec-flow's own `tdd-developer` by default, which is language-neutral;
     `dev-skills` ships an agent that knows the language. For Rust, `rust-dev` reads the full Rust
     style guide, carries a token-frugal `nextest` recipe, and hands build problems to its `cargo`
     agent. For Kotlin, `kotlin-dev` reads the full Kotlin style guide and hands builds to its
     `gradle-expert` agent. For Java, `java-dev` matches the project's own conventions exactly,
     which is what an OSS contribution needs. Recommend the language agent, default yes. Name the
     agent that matches the language you detected. If yes, for Rust:
     ```json
     { "env": { "SPEC_FLOW_DEVELOPER_AGENT": "rust-dev" } }
     ```
     Use `kotlin-dev` or `java-dev` in place of `rust-dev` for those languages.
     merging into whatever's already there. If the owner declines, write nothing; unset already
     means `tdd-developer`. Skip this item entirely if `dev-skills` isn't installed, or if the
     project's language has no agent in it yet; don't offer a preference the owner can't use. See
     **Developer agent** in `docs/workflow.md`.
   - **Refactor circuit breaker unset** → explain the choice in one line: on a `type:tech-debt`
     run (behavior-preserving work), `implement` stops a developer agent that has edited the same
     test file more than twice, because three edits to one test file means the classification was
     wrong or the step was too big. It does not arm on ordinary feature work, where repeated edits
     to one test file are normal. Ask what should happen at that point. Recommend `ask`, the default —
     the run stops and the owner decides whether to continue or revert:
     ```json
     { "env": { "SPEC_FLOW_REFACTOR_BREAKER": "ask" } }
     ```
     For a repo that wants the strict Mikado reflex instead, `"revert"` reverts to the last green
     commit automatically. For a repo that wants no breaker at all, `"off"`. Merge into whatever's
     already there. Leaving it unset is fine too; `ask` applies either way — see **Refactor
     circuit breaker** in `docs/workflow.md`.
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
- **Local edits only, with exactly one carve-out.** Everything else this skill does — labels
  aside — edits files in the owner's checkout and stops there. Seeding the repo policy is the one
  deliberate exception: it opens a PR, mirroring `adopt-tiering`. It still never commits or pushes
  to the default branch and never merges, and it writes nothing at all until the owner has
  confirmed the proposed policy. That is the whole of the exception; do not read it as licence for
  any other outward action.
- Safe to re-run any time — step 1's exploration is what makes every subsequent run only ever ask
  about what's still actually missing.
