# Examples

## explain-preview.html

A sample output of the `ide-explain` skill (`plugins/dev-skills/skills/ide-explain/`) — a
self-contained, single-file HTML view combining a code diff, an OpenSpec delta spec (with a
Currently:/This change: baseline comparison), docs, blast-radius search, and GitHub issue/PR
review comments, all in one page.

**To view it:** download this file (or clone the repo) and open it directly in a browser —
`open examples/explain-preview.html` or double-click it. It's fully self-contained (no server, no
CDN, no network calls), so it renders correctly straight off disk via `file://`. GitHub's own file
viewer shows `.html` files as raw source rather than rendering them, so viewing it *directly on
github.com* isn't possible without downloading first (or a third-party proxy like
htmlpreview.github.io).

**To regenerate it:**

```bash
plugins/review-tools/skills/ide-explain/scripts/preview.sh
```

then copy the generated file here. (`preview.sh` opens it in a browser and writes it to a temp
path — it does not write into this directory itself.)
