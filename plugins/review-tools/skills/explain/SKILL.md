---
name: explain
description: Render an IDE-style single-page HTML view that explains anything the owner needs to see whole — a code diff, a GitHub issue plus everything linked to it, project docs, or any mix — as a file tree on the left, a code/diff/doc editor top-right, and an explanation pane bottom-right. Deterministic by default (no model tokens spent on markup); a hand-authored manifest mode exists for taught narratives. Self-contained output, no server, no CDN. Standalone — works in any repo, no other plugin required. Use whenever the owner wants one visual, walkable view instead of raw diff output or hopping between GitHub tabs — including looking at a plain backlog issue before any worktree or diff exists.
argument-hint: [issue N | base-ref] [doc paths...]
---

# explain — IDE-style HTML view of a change, an issue, or both

Renders a single, self-contained HTML file: a file tree on the left, a diff/code/doc editor
top-right, and an explanation pane bottom-right. No server, no CDN, opens correctly via `file://`.
The goal is aiding human understanding of what's happening in a change — a walkthrough or
presentation of it, not a raw diff dump — whatever that change actually is: a **worktree**
(uncommitted local work), a **branch** (against the default branch), or an **issue** (before any
code exists at all). Standalone — nothing here depends on any other plugin, and it stays that way
deliberately, since it needs to work on projects that can't or don't adopt spec-flow. Two modes —
pick deterministic unless you have a specific reason to hand-author.

If the `spec-flow` plugin is also installed, its `activate`/`implement` skills call this one
automatically at the owner's two approval seams when `SPEC_FLOW_SEAM_VIEW=explain` — see
`SPEC_FLOW_SEAM_VIEW` in that plugin's `docs/workflow.md`. That integration is optional and
one-directional: this skill has no spec-flow dependency in either direction.

## Mode 1: deterministic (default)

Zero model-authored markup. Run the generator against whichever inputs are relevant — **every
input is independently optional; pass only what applies**:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/explain/scripts/generate-explain.py \
  --issue <N> \
  --diff --base <ref> \
  --change <openspec-change-dir> \
  --doc <path> \
  --title "<title>" --subtitle "<subtitle>" \
  --out <path>
```

- `--issue <N>` — repeatable; a GitHub issue number. Pulls its full body + comment thread, **plus,
  one level out, every issue it's linked to** — via a native GitHub dependency (`blocked_by`/
  `blocking`) or a bare `#N` mention in its body/comments — as separate nodes under `related/`, so
  related work and prior discussion show up without the owner hunting through GitHub by hand.
  Related issues are fetched lighter (no comments) to keep the fetch bounded — only the explicitly
  requested issue(s) get their full discussion. Requires `gh`, authenticated, run from inside the
  target repo.
- `--diff` — include a git diff. **Omit this for anything that isn't about a code change** —
  reviewing a backlog issue before it's activated (no worktree, no diff exists yet) must never
  require one.

  **A changed file under OpenSpec's own directory convention never renders as a diff, even here**
  — `openspec/specs/**/*.md`, `openspec/changes/*/specs/**/*.md`, and `openspec/changes/*/
  {proposal,design,tasks}.md` render as content instead (explanation pane only), whichever way
  `--diff` was invoked (`--worktree`, `--branch`, or explicit `--base`/`--head`). A brand-new
  change dir's files are typically 100% green in a raw diff — nothing to review line-by-line — so
  the point is to read the spec, not diff it. This is strictly scoped to OpenSpec's own paths
  (path-based detection only, no content-sniffing) — every other file, including a brand-new
  non-OpenSpec one, keeps the diff view + explanation pane exactly as normal. A matched file whose
  content contains OpenSpec's delta headers (`## ADDED/MODIFIED/REMOVED/RENAMED Requirements`)
  additionally gets: a summary line with per-category counts, jump links to each section, and —
  for each `MODIFIED` requirement — a **"Currently:"/"This change:"** prose comparison against the
  same-titled requirement in that capability's baseline spec (`openspec/specs/<capability>/
  spec.md`, derived from the delta spec's own path), when a match is found; silently omitted,
  never an error, when it isn't (a new capability, or a rename within the same change). A matched
  file with no delta headers (`proposal.md`, `design.md`, `tasks.md`, an unchanged-shape baseline
  spec) renders as plain markdown, same as `--change` mode already did. This enrichment lives in
  the shared node-building logic, so `--change <dir>` mode gets it too, identically — reaching a
  delta spec either way produces the same rendering.

  When passed:
  - `--worktree` — alias for `--diff` with no `--base`/`--head` override: "explain what's
    uncommitted here." This is already `--diff`'s own default behavior (merge-base vs. working
    tree) — the flag exists purely so that intent is discoverable/nameable, not because it adds
    new resolution logic.
  - `--branch <name>` — alias for `--diff --head <name>`: "explain this branch against the
    default branch." Ignored if `--head` is also passed explicitly (`--head` wins). Deliberately
    generic — no issue-number guessing from the branch name, no assumptions about any project's
    branch-naming convention — so this stays usable in any repo, with or without spec-flow.
  - `--base <ref>` — diff base; default is the merge-base with the default branch.
  - `--head <ref>` — diff head; default is the **working tree** (uncommitted changes included).
  - `--path <path>` — repeatable; scope the diff to this path (passed to `git diff` as `--
    <path>...`). Omit to diff the whole repo. Useful for a "what changed since you last looked at
    just this" view — e.g. `--base <sha-you-last-showed>` scoped to one OpenSpec change dir, so a
    re-review after a redirect shows only what actually moved, not the whole branch.
  - `--explain-map <path>` — **the real "why" mechanism.** A JSON file of `{"path": "explanation",
    ...}`, written by a caller that has actually read and understood the diff (an LLM — `git`
    cannot produce this). Applies to any node whose path matches a key, of any kind, and always
    wins over `--blame` for that node. This is the only way to get an explanation of what the
    current diff *does*; nothing else here can.
  - `--blame` — populate each diff node's explanation pane with commit-history context instead: a
    mechanical fallback, opt-in, off by default. For each hunk, `git blame` finds which commit(s)
    last touched the OLD-side lines as of `--base`, then pulls each one's full commit message
    (`git log --format=%B`) — the sha/author render as a small byline, not the headline. **This is
    NOT an explanation of the current diff** — it can only quote what someone wrote about a
    *previous* change to those lines, which may be unrelated, stale, or absent entirely. Reach for
    `--explain-map` first; use `--blame` only as a cheap, zero-model-token substitute when no real
    explanation is available, or layer it in for extra historical context on nodes `--explain-map`
    doesn't cover. When `--blame` is on, it never leaves a node silently blank: a brand-new file, a
    pure-addition hunk, or a hunk `git blame` genuinely can't resolve (shallow clone, binary) each
    get an explicit one-line reason instead of silence, so "no explanation" always reads as a
    deliberate answer. (`--no-blame` is accepted, for backward compatibility — it's a no-op now
    that `--blame` is opt-in again.)
  - `--pr <N>` — overlay this PR's file/line-anchored GitHub review comments onto the diff, right
    at the row each was left on (matched by file path + line + side, same convention GitHub itself
    uses). A comment anchored to a file/line outside this diff's range (outdated, or the diff was
    rescoped since) is never silently dropped — it lands in its own `pr-comments/outside-diff.md`
    node instead. Requires `gh`, authenticated. Ignored (with a warning) if `--diff` wasn't passed
    — there's nothing to overlay comments onto without a diff.
- `--change <dir>` — repeatable; an OpenSpec change dir. Auto-includes `proposal.md`, `design.md`,
  `tasks.md` (whichever exist) plus any delta-spec markdown under `<dir>/specs/**`.
- `--doc <path>` — repeatable; any extra markdown file, rendered as a markdown node.
- `--code <path>` — repeatable; show a file as plain code (not a diff).
- `--symbol <name>` — repeatable; a **blast-radius** view: a word-boundary `git grep` for `name`
  across tracked files in the working tree (uncommitted edits included, untracked files excluded),
  rendered as a callers list under `blast-radius/<name>.md`. Deterministic and language-agnostic —
  a plain-text search, not an AST/language server — so it's exact-name-only (no rename tracking,
  no semantic "who calls this overload") in exchange for working the same way in any language with
  zero setup. Always produces a node, even on zero matches, so "checked, found nothing" is visible
  rather than the symbol silently missing from the tree.
- `--title` / `--subtitle` — header text; if omitted and `--issue` resolved a primary issue, the
  title defaults to that issue's own `#N — title`.
- `--out <path>` — output HTML path; defaults to a generated path under the system temp dir.
- `--open` — additionally open the result in a browser. **Only pass this for an interactive,
  same-machine, foreground invocation** — see the display constraint below.

At least one of `--issue`/`--diff`/`--change`/`--doc`/`--code` is required — the generator refuses
to produce a silent, empty view when called with nothing to render.

On success it always prints two lines: the absolute output path, then a literal `open <path>`
line — regardless of whether `--open` was passed.

**This is the required mode wherever the view feeds an approval decision** (e.g. spec-flow's two
owner seams) — a decision-facing view is generated, never curated, so it stays a faithful, unedited
rendering of the actual content.

## Mode 2: curated (opt-in, for taught narratives)

For a hand-authored walkthrough — e.g. a bug-walkthrough view built for teaching, where you want
to choose exactly which lines get a badge or an explanation — bootstrap a directory, then edit the
manifest by hand:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/explain/scripts/init-explain.sh <target-dir>
```

This copies the viewer shell into `<target-dir>/viewer.html` and writes a skeleton
`<target-dir>/explain.manifest.js` (loaded via `<script src="explain.manifest.js">` so it stays
`file://`-safe and hand-editable without ever touching `viewer.html`). It also prints the manifest
schema to stdout. Edit `explain.manifest.js` directly, then open `viewer.html`.

Use curated mode sparingly — it's for narratives worth hand-crafting, not a substitute for
deterministic mode at a seam.

## Manifest schema

Both modes produce/consume the same shape:

```
title: string
subtitle?: string
meta?: { base?: string, head?: string, generatedFrom?: string }
nodes: [
  {
    path: string,             // tree path; "/" nests folders
    label?: string,            // tree label; defaults to basename(path)
    badge?: string,             // small chip in the tree, e.g. "THE BUG"
    badgeClass?: string,        // "bug" | "store" | "join" | "test" | "add" | "del" | "mod" | ""
    kind: "diff" | "code" | "markdown",
    patch?: string,             // kind=diff: raw unified-diff text for THIS file
    comments?: [{ line: number, side: "LEFT" | "RIGHT", author: string, body: string,
                  createdAt?: string }],  // kind=diff: PR review comments anchored to this file
    code?: string, lang?: string, startLine?: number, highlight?: number[],  // kind=code
    md?: string,                // kind=markdown: raw markdown (issue bodies/comments render here)
    explain?: string            // markdown/html shown in the bottom pane, optional on any kind
  }
]
```

## Display constraint (load-bearing)

A background/headless caller (a spawned agent process, a CI job) cannot reliably open a browser on
the owner's screen — there is no display to open one on. The contract in that case is: **generate
the file, print its absolute path plus an `open <path>` line, never assume a display.** `--open` is
only for an interactive, same-machine, foreground invocation — e.g. the owner directly running
`/explain` themselves. Any headless/background usage must omit `--open` and just report the printed
path/command to the owner.

## Standalone usage

Generate a view on demand, independent of whether any code has changed yet:

```
/explain <issue-N>
/explain <base-ref> [docs...]
```

The first form calls `generate-explain.py --issue <N>` — the primary way to look at a backlog
issue before any work has started on it: no worktree, no diff, no other artifact required. The
second calls it with `--diff --base <base-ref>` and each doc path as a repeated `--doc`. The two
compose — reviewing an in-flight issue's PR can mean asking for both an issue's discussion and its
diff in one view. Since this is a foreground, same-machine invocation, `--open` is reasonable here
if the owner wants the browser to open automatically — ask, or default to just printing the path.

However invoked — via this shorthand, or with explicit flags passed straight through by a calling
skill from another plugin (e.g. spec-flow's seam wiring) — treat any string beginning with `--` as
literal `generate-explain.py` flags and run them as-is; the shorthand above is a convenience for a
human typing `/explain`, not the only supported call shape.

## Referencing a specific section precisely

Every rendered heading gets a stable, slugified `id` (e.g. `### Requirement: Widget deletion` →
`id="requirement-widget-deletion"`, deduplicated with a `-2`/`-3` suffix if a doc repeats a
heading). There is deliberately no comment/annotation UI — `viewer.html` is a static `file://` page
with no server, so it has no channel to send anything back to whoever generated it; adding one
would break the self-contained, no-server design this skill is built around (see **Rules** below).
The anchor ids are what make it possible to reference a specific requirement or scenario precisely
in a URL fragment, or by name in conversation, without needing bidirectional wiring — a caller that
wants to capture structured feedback against a specific section (e.g. spec-flow's own redirect
handling at Seam 1 — see `docs/workflow.md` there) does so on its own side, using these same
heading names as the shared vocabulary, not through this skill.

## Known gap: only what's actually on GitHub

`--issue` mode surfaces the issue's body, its comment thread, and linked/mentioned issues — that's
genuinely everything durable that exists for a not-yet-worked issue today. It does **not** include
any earlier scoping/design conversation that only ever happened in a chat transcript and was never
posted back to the issue as a comment — this skill can only show what's actually persisted on
GitHub. If richer "research trail" coverage matters, the fix is upstream (whatever produced that
reasoning should post it as an issue comment), not here.

## Rules

- Deterministic mode is the default and the only mode allowed wherever the view feeds an approval
  decision. Curated mode is opt-in, for hand-crafted teaching narratives only.
- Never require a diff. `--diff` is opt-in; an issue-only or docs-only view is a first-class use,
  not a degraded one.
- Never pass `--open` from a background/headless caller — there is no display to open a browser
  on. Always print the path + `open <path>` line instead.
- `generate-explain.py` is stdlib-only (no pip dependencies, `git`/`gh` shelled out to as needed)
  and must run on macOS system `python3` and in CI (Linux).
- `viewer.html` is a checked-in static shell — never edit it per-use. The generator injects a
  manifest by replacing its single `<!--MANIFEST-->` marker; don't reproduce that literal marker
  text anywhere else in the file (the generator's replace targets exactly one occurrence).
- No syntax highlighting beyond diff/emphasis coloring, no server, no automatic browser opening
  except via an explicit `--open` flag.

## Testing

`plugins/review-tools/skills/explain/scripts/test-generate-explain.sh` is a structural self-test —
see `scripts/README.md` for what it checks and how to run it.
