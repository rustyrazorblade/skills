---
name: deck
description: Render an IDE-style single-page HTML walkthrough of a change — file tree on the left, a code/diff editor top-right, an explanation pane bottom-right — either deterministically from a git diff + docs (default, and the required mode at the two pipeline seams), or from a hand-authored manifest for a taught narrative. Self-contained output, no server, no CDN. Use when the owner wants to visually review a change, or when a seam needs a walkable artifact instead of a raw diff.
argument-hint: [base-ref] [doc paths...]
---

# deck — IDE-style HTML walkthrough of a change

Renders a single, self-contained HTML file: a file tree on the left, a diff/code editor
top-right, and an explanation pane bottom-right. No server, no CDN, opens correctly via `file://`.
Two modes — pick deterministic unless you have a specific reason to hand-author.

## Mode 1: deterministic (default, required at pipeline seams)

Zero model-authored markup. Run the generator against a git diff plus any docs/code you want
alongside it:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/deck/scripts/generate-deck.py \
  --base <ref> \
  --change <openspec-change-dir> \
  --doc <path> \
  --title "<title>" --subtitle "<subtitle>" \
  --out <path>
```

- `--base <ref>` — diff base; default is the merge-base with the default branch.
- `--head <ref>` — diff head; default is the **working tree** (uncommitted changes included).
- `--change <dir>` — repeatable; an OpenSpec change dir. Auto-includes `proposal.md`, `design.md`,
  `tasks.md` (whichever exist) plus any delta-spec markdown under `<dir>/specs/**`.
- `--doc <path>` — repeatable; any extra markdown file, rendered as a markdown node.
- `--code <path>` — repeatable; show a file as plain code (not a diff).
- `--title` / `--subtitle` — header text.
- `--out <path>` — output HTML path; defaults to a generated path under the system temp dir.
- `--open` — additionally open the result in a browser. **Only pass this for an interactive,
  same-machine, foreground invocation** — see the display constraint below.

On success it always prints two lines: the absolute output path, then a literal `open <path>`
line — regardless of whether `--open` was passed.

**This is the required mode at both pipeline seams** (spec approval and review+merge) — a seam
deck is generated, never curated, so it stays a faithful, unedited rendering of the actual diff.

## Mode 2: curated (opt-in, for taught narratives)

For a hand-authored walkthrough — e.g. a bug-walkthrough deck built for teaching, where you want
to choose exactly which lines get a badge or an explanation — bootstrap a directory, then edit the
manifest by hand:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/deck/scripts/init-deck.sh <target-dir>
```

This copies the viewer shell into `<target-dir>/viewer.html` and writes a skeleton
`<target-dir>/deck.manifest.js` (loaded via `<script src="deck.manifest.js">` so the deck stays
`file://`-safe and hand-editable without ever touching `viewer.html`). It also prints the manifest
schema to stdout. Edit `deck.manifest.js` directly, then open `viewer.html`.

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
    md?: string,                // kind=markdown: raw markdown
    explain?: string            // markdown/html shown in the bottom pane, optional on any kind
  }
]
```

## Display constraint (load-bearing)

A background `issue-pm` (or the archive worker) cannot reliably open a browser on the owner's
screen — there is no display to open one on. The contract at a seam is: **generate the file, print
its absolute path plus an `open <path>` line, never assume a display.** `--open` is only for an
interactive, same-machine, foreground invocation — e.g. the owner directly running
`/spec-flow:deck` themselves. Any seam usage (from `activate` or `implement`) must omit `--open`
and just report the printed path/command to the owner.

## Standalone usage

The owner (or an `issue-pm`) can generate a deck on demand, independent of either seam:

```
/spec-flow:deck <base-ref> [docs...]
```

This calls `generate-deck.py` with `--base <base-ref>` and each doc path as a repeated `--doc`.
Since this is a foreground, same-machine invocation, `--open` is reasonable here if the owner
wants the browser to open automatically — ask, or default to just printing the path.

## Rules

- Deterministic mode is the default and the only mode allowed at a pipeline seam. Curated mode is
  opt-in, for hand-crafted teaching narratives only.
- Never pass `--open` from a background session (`issue-pm`, archive worker) — there is no display
  to open a browser on. Always print the path + `open <path>` line instead.
- `generate-deck.py` is stdlib-only (no pip dependencies) and must run on macOS system `python3`
  and in CI (Linux).
- `viewer.html` is a checked-in static shell — never edit it per-use. The generator injects a
  manifest by replacing its single `<!--MANIFEST-->` marker; don't reproduce that literal marker
  text anywhere else in the file (the generator's replace targets exactly one occurrence).
- No syntax highlighting beyond diff/emphasis coloring, no server, no automatic browser opening
  except via an explicit `--open` flag.

## Testing

`plugins/spec-flow/skills/deck/scripts/test-generate-deck.sh` is a structural self-test — see
`scripts/README.md` for what it checks and how to run it.
