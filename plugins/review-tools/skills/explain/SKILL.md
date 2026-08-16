---
name: explain
description: Render an IDE-style single-page HTML view that explains anything the owner needs to see whole — a code diff, a GitHub issue plus everything linked to it, project docs, or any mix — as a file tree on the left, a code/diff/doc editor top-right, and an explanation pane bottom-right. Deterministic by default (no model tokens spent on markup); a hand-authored manifest mode exists for taught narratives. Self-contained output, no server, no CDN. Standalone — works in any repo, no other plugin required. Use whenever the owner wants one visual, walkable view instead of raw diff output or hopping between GitHub tabs — including looking at a plain backlog issue before any worktree or diff exists.
argument-hint: [issue N | base-ref] [doc paths...]
---

# explain — IDE-style HTML view of a change, an issue, or both

Renders a single, self-contained HTML file: a file tree on the left, a diff/code/doc editor
top-right, and an explanation pane bottom-right. No server, no CDN, opens correctly via `file://`.
Not just a diff tool — this is a general way to look at *anything* worth reviewing whole: a code
change, a GitHub issue and everything linked to it, project docs, or any combination, with no
requirement that a diff (or even a worktree) exist yet. Standalone — nothing here depends on any
other plugin. Two modes — pick deterministic unless you have a specific reason to hand-author.

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
  require one. When passed:
  - `--base <ref>` — diff base; default is the merge-base with the default branch.
  - `--head <ref>` — diff head; default is the **working tree** (uncommitted changes included).
  - `--path <path>` — repeatable; scope the diff to this path (passed to `git diff` as `--
    <path>...`). Omit to diff the whole repo. Useful for a "what changed since you last looked at
    just this" view — e.g. `--base <sha-you-last-showed>` scoped to one OpenSpec change dir, so a
    re-review after a redirect shows only what actually moved, not the whole branch.
- `--change <dir>` — repeatable; an OpenSpec change dir. Auto-includes `proposal.md`, `design.md`,
  `tasks.md` (whichever exist) plus any delta-spec markdown under `<dir>/specs/**`.
- `--doc <path>` — repeatable; any extra markdown file, rendered as a markdown node.
- `--code <path>` — repeatable; show a file as plain code (not a diff).
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
    badgeClass?: string,        // "bug" | "store" | "join" | "test" | "add" | "del" | ""
    kind: "diff" | "code" | "markdown",
    patch?: string,             // kind=diff: raw unified-diff text for THIS file
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
