---
name: walkthrough
description: Render a diagram-first, ordered-step HTML presentation that teaches how something works — or presents a technical-debt review, an areas-for-improvement pass, a set of recommendations, or a performance analysis. You investigate the code and author every word; a deterministic renderer turns your manifest into one self-contained page (vertical scroll by default, one button away from slide-by-slide). Self-contained output, no server, no CDN. Standalone — works in any repo, no other plugin required. Use when the owner needs to be walked through something in order, one idea at a time, rather than handed a diff or a reference page to navigate themselves.
argument-hint: [what to walk through]
---

# walkthrough — a guided, diagram-first presentation of a subsystem or an analysis

Renders a single, self-contained HTML file: a diagram up top, then an ordered sequence of narrated
steps, each carrying one or more real code excerpts. No server, no CDN, opens correctly via
`file://`. It defaults to vertical scroll and toggles, at runtime, to horizontal slide-by-slide
navigation — the same generated file serves both, so nothing is regenerated to switch.

**This is the sibling of `explain`, not a replacement for it.** `explain` reviews a *change* — a
diff, an issue, a PR — as a file tree the owner navigates themselves. `walkthrough` presents a
*narrative* about a topic, in an order you chose, when there is no diff to open it against. Reach
for `explain` when the subject is "what changed"; reach for this when the subject is "how this
works", "what's wrong with this", or "what we should do about it".

## The load-bearing part: you author everything

`generate-walkthrough.py` derives nothing. It never shells out to `git`, `gh`, or an AST tool; it
validates your manifest and renders it, full stop. The diagram, the ordering, the narration, and
every line of every excerpt are yours. That means the quality of the result is entirely a function
of the investigation you do **before** writing the manifest:

1. **Read the actual code first.** Follow the real path — entry point, the call it makes, where
   state lands. Do not write a step from a filename or a guess.
2. **Copy excerpts verbatim from the file, with their real line numbers.** The `path:startLine`
   reference is a promise that the reader can open that file at that line and see exactly this.
   Nothing checks it for you.
3. **Decide the order deliberately.** A walkthrough's whole value is that step N+1 only makes sense
   once step N has landed. If the steps could be read in any order, you have written a reference
   page, not a walkthrough — use `explain` instead.
4. **Then draw the diagram**, once you understand the shape well enough to draw it honestly.

Keep it short. Five to nine steps is a walkthrough; twenty is a document nobody finishes.

## Generating

```bash
${CLAUDE_PLUGIN_ROOT}/skills/walkthrough/scripts/generate-walkthrough.py \
  --manifest <path.json> \
  --out <path>
```

- `--manifest <path>` — **required**; the manifest JSON, the sole source of content.
- `--out <path>` — output HTML path; defaults to a generated path under the system temp dir.
- `--open` — additionally open the result in a browser. **Only pass this for an interactive,
  same-machine, foreground invocation** — see the display constraint below.

There is deliberately no `--title`/`--subtitle` flag: both live in the manifest, which is the one
place content comes from.

On success it always prints two lines: the absolute output path, then a literal `open <path>`
line — regardless of whether `--open` was passed.

## Manifest schema

```
title: string                   // required
subtitle?: string
diagram: {                       // required — a walkthrough always leads with a picture
  type: "svg" | "html",           // required
  source: string,                 // required, non-empty; inline markup, embedded as-is
  caption?: string
}
steps: [                          // required, at least one
  {
    title: string,                // required
    narration: string,            // required; markdown (headings, lists, code spans, fences, tables)
    kind?: string,                // optional; renders a small badge. Any string is accepted.
    excerpts: [                   // required, at least one
      {
        path: string,             // required; repo-relative path, as the reader would open it
        startLine: number,        // required; the real first line number of this excerpt
        endLine?: number,          // shown in the reference when given
        code: string,              // required; the excerpt itself, verbatim
        lang?: string,             // carried through as data-lang
        highlight?: number[]       // absolute line numbers to visually distinguish
      }
    ]
  }
]
```

Validation is strict and loud — the generator writes no output file at all unless the whole
manifest is valid. A missing/unreadable/empty manifest, a missing `title`, an empty `steps` list, a
missing diagram or empty `diagram.source`, a step missing `title`/`narration`/a non-empty
`excerpts` list, or an excerpt missing `path`/`startLine`/`code` each fail with a non-zero exit and
a specific error. Step- and excerpt-level errors name the offending step by its 1-based position
and title, and an excerpt error names the excerpt within it too.

`kind` is deliberately **not** a closed enum: any string renders a badge, and an unrecognized value
gets a neutral style rather than failing. The five conventional values below — spelled exactly as
in the table — get their own color; anything else renders neutral.

## The five kinds, and what a good one looks like

Same schema, same renderer, no per-kind code path — only your content differs. Set each step's
`kind` to the one it belongs to (a single walkthrough may legitimately mix them, e.g. an
explanation that ends in two recommendations).

| `kind` | The question the walkthrough answers | What the diagram should show | What each step's narration owes the reader |
| --- | --- | --- | --- |
| `explanation` | How does this work? | The real runtime shape: components and the direction data actually flows between them | Why the code does what it does, not a paraphrase of what it plainly says |
| `tech-debt` | What's structurally wrong here? | The current shape, with the strain visible — the coupling, the duplication, the layer being bypassed | The concrete cost being paid today, and what makes it hard to change |
| `improvements` | What could be better? | Current shape beside the shape you're proposing | The specific improvement, and what it buys — not a style preference |
| `recommendation` | What should we do? | The end state being recommended | The recommendation, its trade-off, and what happens if it's skipped |
| `performance` | Why is this slow? | The path with the hot spot marked — where time or allocations actually go | The measured or reasoned cost at that step, and what dominates |

Two rules that apply to all five: **every step points at real code** (that's what `excerpts` is
for — an assertion with no code under it is an opinion), and **name the cost, not just the
smell** — "this is duplicated" is weak; "these two parsers drift, and the second one already
missed the header fix in `ingest.py:20`" is a step worth reading.

## Authoring the diagram

Diagrams are inline markup you write, embedded verbatim. There is no Mermaid, no diagramming
library, and no auto-layout — matching this plugin's "no framework, no external library"
client-side convention.

- **`type: "html"` is usually the easier one to get right**: a flex row of bordered boxes with
  arrow characters between them is legible, hand-authorable, and hard to break. Prefer it unless
  you specifically need geometry.
- **`type: "svg"`** for anything with real layout — a branching flow, a layered stack. Use a
  `viewBox` and keep it responsive; **omit `xmlns`** (inline SVG in HTML doesn't need it, and the
  output must contain no URLs at all — see the self-containment rule below).
- **`diagram.source` is embedded and executes as-is, with no sanitization, the instant the file
  opens — no click required.** This is deliberate (it is the entire content model: agent-authored
  markup, nothing mechanical in between), but it means the markup must be *yours* — never
  interpolate text copied from the code, docs, issues, or dependencies under review into it. If
  you need to show a fragment of real markup as an example, put it in a step's code excerpt
  instead (rendered as inert text, not executed).
- Style with plain inline styles or the shell's own CSS custom properties (`var(--accent)`,
  `var(--text-dim)`, `var(--border)`), so the diagram matches the surrounding dark theme.
- Keep it to the handful of boxes the walkthrough actually visits. The diagram is the map for
  *these* steps, not an architecture poster.

A worked `type: "html"` diagram — this is the pattern to start from, as it appears in the manifest
(JSON, so the markup is one escaped string):

```json
"diagram": {
  "type": "html",
  "source": "<div style=\"display:flex;gap:10px;justify-content:center;align-items:center\"><span style=\"border:1px solid var(--border);border-radius:6px;padding:8px 14px\">Request</span><span style=\"color:var(--text-dim)\">&#8594;</span><span style=\"border:1px solid var(--accent);border-radius:6px;padding:8px 14px\">WidgetStore</span><span style=\"color:var(--text-dim)\">&#8594;</span><span style=\"border:1px solid var(--border);border-radius:6px;padding:8px 14px\">Cache</span></div>",
  "caption": "A read goes through the store, which consults the cache before the database."
}
```

Note the two things that carry the meaning: the box the walkthrough is *about* is bordered in
`var(--accent)` while the supporting ones are in `var(--border)`, and the arrows are HTML entities
(`&#8594;`), not characters that depend on the reader's font. For a branching or layered shape,
switch to `type: "svg"` with a `viewBox` — same colors, same restraint.

## Display constraint (load-bearing)

A background/headless caller (a spawned agent process, a CI job) cannot reliably open a browser on
the owner's screen — there is no display to open one on. The contract in that case is: **generate
the file, print its absolute path plus an `open <path>` line, never assume a display.** `--open` is
only for an interactive, same-machine, foreground invocation — e.g. the owner directly running
`/walkthrough` themselves.

## Rules

- Never derive content mechanically and never guess it — read the code, then write the manifest.
  Excerpts must be verbatim, with real line numbers, from the paths named.
- Never ship a walkthrough whose steps could be read in any order. That's `explain`'s job.
- Never pass `--open` from a background/headless caller — print the path + `open <path>` line
  instead.
- `generate-walkthrough.py` is stdlib-only (no pip dependencies, no `git`/`gh`, no network) and
  must run on macOS system `python3` and in CI (Linux).
- `assets/viewer.html` is a checked-in static shell — never edit it per-use. The generator injects
  the manifest by replacing its single `<!--MANIFEST-->` marker; don't reproduce that literal
  marker text anywhere else in the file (the generator's replace targets exactly one occurrence).
- The output must stay self-contained: no remote images, no linked stylesheets, no fonts, no live
  network reference anywhere. `generate-walkthrough.py` enforces this mechanically for
  `diagram.source` (rejects `http://`/`https://`/`ftp://`/`ws(s)://` there — that is the one
  field whose markup is embedded and executes as-is, so it is the one place a stray remote
  reference would actually be live). Mentioning a URL as plain text in narration or a code
  excerpt is fine — it renders as inert text, not a fetched resource, and is exempt from the
  check on purpose (source code legitimately references URL constants). Nothing outside
  `diagram.source` is mechanically checked, though: if you hand-author markup anywhere else that
  could reference something remote, that is on you, not the tool.
- No interactivity beyond the layout toggle and its nav chrome (counter, prev/next, arrow keys).
  There is no comment channel and no persistence — a static `file://` page has nothing to send
  anything back to.

## Testing

`plugins/dev-skills/skills/walkthrough/scripts/test-generate-walkthrough.sh` is a structural
self-test — see `scripts/README.md` for what it checks and how to run it.
