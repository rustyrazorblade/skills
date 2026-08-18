| Source | Requirement | Covering scenario(s) | Status |
|--------|-------------|----------------------|--------|
| AC | Valid manifest (diagram + N steps) → one self-contained HTML file, diagram before all steps, steps in order | `walkthrough: Valid manifest renders in order` | ✅ Covered |
| AC | Rendered file has no `http://`, `https://`, or `fetch(` | `walkthrough: No network references in rendered output` | ✅ Covered |
| AC | Presentation defaults to vertical-scroll layout | `walkthrough: Default layout is vertical` | ✅ Covered |
| AC | Runtime toggle switches to horizontal and back, no regeneration, single artifact | `walkthrough: Toggle switches to horizontal and back` | ✅ Covered |
| AC | Code excerpts + `file:line` references render inside their step | `walkthrough: Excerpt and reference render together` | ✅ Covered |
| AC | Same manifest schema/renderer for non-"how it works" walkthroughs (tech-debt/improvements/recommendations/performance) | `walkthrough: Non-"how it works" walkthrough uses the same renderer` | ✅ Covered |
| AC | Optional `kind` field renders a badge; omitted → no badge | `walkthrough: Kind present renders a badge`, `walkthrough: Kind omitted renders no badge` | ✅ Covered |
| AC | No/empty manifest → fails loudly, non-zero exit, no empty presentation | `walkthrough: No manifest fails loudly` | ✅ Covered |
| AC | Manifest step missing a required field → fails naming the step | `walkthrough: Step missing a required field` | ✅ Covered |
| AC | Manifest omits diagram entirely → fails loudly with a clear error | `walkthrough: Missing diagram fails loudly` | ✅ Covered |
| AC | Horizontal mode provides a step counter, prev/next buttons, and keyboard arrow navigation | `walkthrough: Nav chrome available in horizontal mode` | ✅ Covered |
| Design | Excerpt missing a required field (`path`/`startLine`/`code`) → fails naming both step and excerpt (design.md decision on validation, not a literal issue AC bullet but part of the same "loud, specific failure" contract) | `walkthrough: Excerpt missing a required field` | ✅ Covered |
| Risk | Reopened "no interactivity beyond the toggle" scope line could keep expanding past what the owner actually approved | `walkthrough: Nav chrome available in horizontal mode` (requirement text bounds chrome to exactly counter + prev/next + keyboard — nothing more) | ✅ Covered |
| Risk | Agent-authored inline SVG is harder to author correctly than a diagramming DSL, so early diagrams may be rough | — | ⚠️ Excluded — not mechanically testable; mitigated via `SKILL.md` guidance and the `diagram.type: "html"` lower-friction alternative, not a rendering behavior this spec can assert on |
| Risk | `html_shell.py` extraction touches `generate-explain.py`, which has its own recent regression history | — | ⚠️ Excluded — this is a process safeguard (tasks.md 1.3/4.4: re-run `explain`'s own test suite, must stay 85/85), not a `walkthrough` capability requirement; covered by `explain`'s existing spec/tests, not a new scenario here |
| Risk | `kind` accepting any string means a typo silently renders a slightly-wrong badge instead of failing | `walkthrough: Optional per-step kind badge` (requirement text explicitly states any string SHALL be accepted — this is the accepted, intended behavior per design.md decision 4, not a gap) | ✅ Covered |
