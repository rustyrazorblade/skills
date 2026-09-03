# dev-skills

Language developer agents plus generic development skills. Standalone; it works in any repo, with
or without `spec-flow`.

## Why it exists

Files cannot be read across Claude Code plugin roots. `$CLAUDE_PLUGIN_ROOT` resolves to the current
plugin only. So discipline that many languages share, like the refactoring rules, cannot be kept in
one place if each language lives in its own plugin. One plugin holds them all, and each language
agent reads the shared references from the same root.

Skills and agents, unlike files, are addressable by name from anywhere. That is what lets
`spec-flow` delegate to this plugin without depending on it.

## Agents

| Agent | Purpose |
|-------|---------|
| `rust-dev` | Rust developer. Reads the bundled Rust style guide, works test-first with a stated escape hatch, and runs `nextest` with a token-frugal recipe. |
| `cargo` | Cargo expert. Owns `Cargo.toml`, workspaces, features, profiles, dependencies, MSRV, and `.config/nextest.toml`. Never writes application or test code. |
| `kotlin-dev` | Kotlin developer. Reads the bundled Kotlin style guide, works test-first, and never writes `!!`. Loads the house stack only when the build declares it. |
| `gradle-expert` | Gradle expert. Runs builds and tests, interprets results, and owns the build files and the version catalog. Never writes application or test code. |
| `java-dev` | Java developer. Works test-first. Built for OSS contributions: it bundles no style guide, and the project's own conventions override every default it carries. |

Every language follows one boundary: the developer agent owns the code, the build agent owns the
build definition. The developer agent runs its own tests, because delegating a routine test run
would cost an agent round trip per cycle. It hands off only when the failure is in the build, not
the code. `rust-dev` pairs with `cargo`; `kotlin-dev` and `java-dev` both pair with
`gradle-expert`.

Each agent is self-contained. None of them calls an agent this plugin does not ship, so they all
resolve in any repo where the plugin is installed.

## Skills

| Skill | Purpose |
|-------|---------|
| `/refactor [target]` | Behavior-preserving change, in any language. |
| `/tech-debt [path]` | Repo-wide structural audit: review agents find SOLID, duplication, and layering problems, rank the 10 most impactful, drop anything already an open issue, and walk you through the rest one at a time. You decide per finding whether to file it |
| `/complexity-reduction [target] [--refactor]` | Measure cognitive complexity and duplication with PMD (Java) or `rust-code-analysis-cli` (Rust), over a subsystem or a diff. Reports functions at or above 15 and stops; `--refactor` opts into pure-move extraction with a re-measure after every step. |
| `/ide-explain <issue-N \| base-ref> [docs...]` | An IDE-style HTML view of an issue, a diff, docs, or any mix. |
| `/walkthrough [what to walk through]` | A diagram-first, ordered-step presentation. |
| `/prose-review [target] [--fix]` | Grade prose against `prose-style.md`. Reports by default. |

`/refactor` has two parts, because a plan alone enforces nothing. It produces a plan you approve
before anything is deleted, and it carries a standing contract that binds the calling agent for the
whole run: triage a failing test from the spec, never edit one to make it go green, and revert
instead of grinding.

`/prose-review` fans out. It shards the in-scope files across parallel grader agents, and gives
each opt-in artifact its own agent. The main thread resolves the scope, merges the findings, and
is the only writer.

`ide-explain` and `walkthrough` each render one self-contained HTML page. No server, no CDN; it opens
over `file://`.

## References

| File | Read by |
|------|---------|
| `references/refactoring-discipline.md` | The `refactor` skill. Every language agent reaches it by invoking that skill for behavior-preserving work. |
| `references/prose-style.md` | `prose-review`, as the fallback when a repo has no copy of its own. |
| `references/rust/style-guide.md` | `rust-dev`, on every task. |
| `references/rust/nextest.md` | `cargo`. |
| `references/kotlin/style-guide.md` | `kotlin-dev`, on every task. |
| `references/kotlin/house-stack.md` | `kotlin-dev` and `gradle-expert`, only when the build declares one of the libraries it covers. |

A repo's own `prose-style.md` always wins over the bundled copy. `house-stack.md` holds the
author's default JVM libraries; a project's existing choices always win over it.

## Working with spec-flow

The two plugins pair one-directionally. `dev-skills` never calls `spec-flow`.

Set `SPEC_FLOW_DEVELOPER_AGENT` in a repo's `.claude/settings.json` to `rust-dev`, `kotlin-dev`, or
`java-dev`, and `/spec-flow:implement` spawns that agent in place of its bundled `tdd-developer`.
Leave it unset and spec-flow behaves exactly as it did before.

Set `SPEC_FLOW_SEAM_VIEW=explain` and `activate` and `implement` render both owner seams with
`ide-explain`.

## Installation

```
/plugin install dev-skills@rustyrazorblade-plugins
```

## Tests

The two HTML generators carry their own structural self-tests:

```
bash skills/ide-explain/scripts/test-generate-explain.sh
bash skills/walkthrough/scripts/test-generate-walkthrough.sh
```
