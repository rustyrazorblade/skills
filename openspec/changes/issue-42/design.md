## Context

`review-tools` already ships `explain`: a deterministic generator (`generate-explain.py`) that
derives content from `git`/`gh` and injects it into a static, self-contained `viewer.html` shell
via a `<!--MANIFEST-->` marker. `walkthrough` is a sibling with a fundamentally different job:
`explain` reviews a *change*; `walkthrough` presents a *guided narrative* about an arbitrary
topic/subsystem, with **no diff, issue, or git history to derive content from at all** — every
byte of content (the diagram, the narration, the code excerpts chosen) is written by the invoking
agent. This was worked out via an `architect` design consult during `/spec-flow:activate 42`, with
the owner choosing among the options presented at each decision point below.

## Goals / Non-Goals

**Goals:**
- One self-contained HTML presentation per walkthrough: diagram first, then ordered steps, vertical
  scroll by default, a runtime toggle to horizontal slide-by-slide navigation with nav chrome.
- A manifest schema and validator specific to this content shape (not reused from `explain`'s
  file-tree/diff schema, which has no meaningful mapping onto an ordered step sequence).
- Reuse `explain`'s proven *pattern* (manifest JSON in, static HTML out, marker injection, loud
  failure, `file://`-safe) without coupling the two tools' schemas or content models together.

**Non-Goals:**
- No code analysis, call-graph extraction, or any other mechanical derivation of diagram/step
  content — `walkthrough` never shells out to `git`/`gh`/an AST tool. If content is wrong or
  low-quality, that's the authoring agent's problem, not this tool's to detect.
- No diagram rendering library (Mermaid or otherwise) — diagrams are agent-authored inline SVG/HTML
  markup, embedded directly.
- No interactivity beyond the vertical/horizontal toggle and its nav chrome (counter, prev/next,
  keyboard arrows) — no in-browser editing, no comment channel, no server, no persistence.
- No broader refactor of `generate-explain.py` — only the three specific helpers named below move
  to the shared module; its remaining structure (issue #43) is out of scope here.

## Decisions

**1. The generator has no data-fetching responsibility — validate + render only.**
Unlike `generate-explain.py`, `generate-walkthrough.py` takes `--manifest <path.json>` and does
nothing but validate it and inject it into the viewer shell. *Alternative considered:* giving it an
optional `--code <path>` convenience to pull excerpt text from disk instead of requiring the agent
to inline it in the manifest — rejected for this change: it would blur "the manifest is the sole
source of truth" and add a second way excerpt content can end up wrong (stale disk read vs. what
the agent actually verified); can be reconsidered later if manifest authoring in practice turns out
to be unwieldy.

**2. Manifest schema is a fresh design, not modeled on `explain`'s tree-node schema.**
```
title: string
subtitle?: string
diagram: { type: "svg" | "html", source: string, caption?: string }   // required
steps: [                                                                // required, >= 1
  {
    title: string
    narration: string        // markdown
    kind?: string             // any string accepted; renders a badge; omitted -> no badge
    excerpts: [               // required, >= 1
      { path: string, startLine: number, endLine?: number, code: string, lang?: string,
        highlight?: number[] }
    ]
  }
]
```
`explain`'s `path`-as-tree-nesting-key / `badge`+`badgeClass` / `kind: diff|code|markdown` schema
has no meaningful analog here — this is a linear sequence, not a file tree. *Alternative
considered:* forcing `walkthrough` steps into `explain`'s existing node shape so both tools share
one schema — rejected: would couple two tools that fail, version, and get tested independently, for
a structural fit that doesn't actually exist (there's no "path" to nest steps under).

**3. Diagram rendering: agent-authored inline SVG/HTML, no rendering library.** *Owner decision,*
architect presented three options (agent-authored-only / vendored Mermaid / support both) with
trade-offs (dependency footprint, artifact size, agent authoring reliability vs. auto-layout). The
owner chose agent-authored-only, on house-style grounds — matches `explain`'s "no framework, no
external library" client-side convention and this environment's own diagramming convention
elsewhere (inline SVG, no framework).

**4. `kind` badge: forward-compatible, not a closed enum.** Any string value renders a badge
(unrecognized values get a generic/neutral style); omission renders no badge. *Alternative
considered:* hard-failing validation on an unrecognized `kind` (matching a closed
`explanation|tech-debt|performance|recommendation` enum) — rejected: the acceptance criteria only
require "present → badge, absent → no badge," and a closed enum would break the moment a fifth kind
is wanted, for no testable benefit.

**5. Nav chrome beyond the toggle: counter + prev/next + keyboard arrows.** *Owner decision* — the
issue's original scope excluded "any interactivity beyond the toggle"; the architect flagged this
as in direct tension with also being asked for nav-chrome options, and the owner resolved it by
explicitly reopening that scope line (see the issue's own updated Scope section). Implemented as: a
step counter, prev/next buttons, and left/right keyboard navigation, active in horizontal mode.

**6. Horizontal toggle implementation: CSS `scroll-snap-type`, no JS animation.** A button toggles a
`.horizontal` class on the steps container; CSS handles the layout switch via
`scroll-snap-type: x mandatory` for horizontal slide-by-slide snapping. *Alternative considered:*
a JS-driven animated transition between modes — rejected: no dependency, no hand-rolled animation
code to maintain, and `explain`'s own viewer has no precedent for JS-driven layout animation either
(its file-tree collapse/expand is a plain classList toggle, same idiom).

**7. Code sharing with `explain`: pattern reuse only, plus one small shared module.** No shared
schema, no shared viewer.html, no shared generator. The one exception: `fail()`, the
`<!--MANIFEST-->` marker-injection helper, and the temp-output-path helper are genuinely identical
between the two tools' current implementations — extracted into `plugins/review-tools/lib/
html_shell.py`, imported by both. *Owner decision* between this and "duplicate, keep fully
independent" (matching `explain`'s own "standalone, no other plugin required" philosophy applied
one level down within `review-tools`) — the owner chose extraction, since the duplication really is
byte-for-byte identical logic with zero schema coupling risk. `generate-explain.py`'s own test
suite (currently 85/85) must stay green after this refactor — pure extraction, no behavior change.

**8. Markdown rendering for step narration reuses `explain`'s existing `renderMarkdown`/`inlineMD`
JS logic, copied into the new `viewer.html`.** *Alternative considered:* writing a second,
independent markdown renderer — rejected as pointless duplication of already-working logic; not
extracted into a shared JS file since these are two separate static HTML shells with no build step
or module system to share client-side code through (Python has a real import system for the
shared-helpers case above; a `file://`-safe static HTML shell does not).

## Risks / Trade-offs

- **[Risk] The reopened "no interactivity beyond the toggle" scope line could keep expanding** (a
  counter suggests pagination, which suggests jump-to-step, which suggests...) **→ [Mitigation]**
  the owner drew the line explicitly at counter + prev/next + keyboard arrows; anything beyond that
  is a new idea, not an extension of this change.
- **[Risk] Agent-authored inline SVG is harder to get right than a diagramming DSL like Mermaid, so
  early walkthroughs may have rough/broken diagrams** **→ [Mitigation]** `SKILL.md` gives the
  invoking agent concrete guidance and a worked example; `diagram.type: "html"` is also accepted (a
  plain styled `<div>`-based diagram is often easier to hand-author correctly than raw SVG path
  data) as a lower-friction alternative to full SVG.
- **[Risk] The `html_shell.py` extraction touches `generate-explain.py`, a file with its own recent
  history of subtle regressions (fence-masking, root-anchoring bugs fixed in 0.11.0/0.12.0)** **→
  [Mitigation]** pure extraction only (move these three functions verbatim, change only the import
  site) — no logic changes bundled into the same commit; `explain`'s full test suite re-run and
  must stay 85/85 before this change is considered done.
- **[Risk] `kind` accepting any string means a typo (`"tech-dept"`) silently renders a slightly
  wrong-looking badge instead of failing** **→ [Mitigation]** accepted trade-off (decision 4) —
  forward-compatibility was judged more valuable than typo-catching for a field with no fixed enum;
  `SKILL.md` documents the conventional four values so an agent is likely to get it right anyway.
