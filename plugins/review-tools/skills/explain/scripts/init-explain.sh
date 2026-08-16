#!/usr/bin/env bash
# Bootstrap a curated (hand-authored) explain view: copy the static viewer shell into <target-dir>
# and write a skeleton explain.manifest.js next to it, loaded via <script src>, so it stays
# file://-safe and editable without ever touching viewer.html itself. See ../SKILL.md's "curated"
# mode. macOS bash 3.2 compatible (no associative arrays, no mapfile).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: init-explain.sh <target-dir>" >&2
  exit 1
fi
target="$1"

command -v sed >/dev/null 2>&1 || {
  echo "init-explain: 'sed' is required but not on PATH." >&2
  exit 1
}

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
viewer_src="$script_dir/assets/viewer.html"

if [[ ! -f "$viewer_src" ]]; then
  echo "init-explain: viewer shell not found at $viewer_src — was assets/viewer.html removed?" >&2
  exit 1
fi

mkdir -p "$target"

# generate-explain.py injects the manifest inline at this same marker; a curated view instead
# loads it from an external file so the owner can hand-edit explain.manifest.js without
# regenerating or touching viewer.html.
sed 's#<!--MANIFEST-->#<script src="explain.manifest.js"></script>#' "$viewer_src" > "$target/viewer.html"

manifest_file="$target/explain.manifest.js"
cat > "$manifest_file" <<'EOF'
// explain manifest schema:
//   title: string
//   subtitle?: string
//   meta?: { base?: string, head?: string, generatedFrom?: string }
//   nodes: [
//     {
//       path: string,              // tree path; "/" nests folders
//       label?: string,            // tree label; defaults to basename(path)
//       badge?: string,            // small chip in the tree, e.g. "THE BUG"
//       badgeClass?: string,       // "bug" | "store" | "join" | "test" | "add" | "del" | ""
//       kind: "diff" | "code" | "markdown",
//       patch?: string,            // kind=diff: raw unified-diff text for THIS file
//       code?: string, lang?: string, startLine?: number, highlight?: number[],  // kind=code
//       md?: string,               // kind=markdown: raw markdown
//       explain?: string           // markdown/html shown in the bottom pane, optional on any kind
//     }
//   ]
window.MANIFEST = {
  title: "",
  nodes: [
    /* fill in — see schema above */
  ]
};
EOF

echo "init-explain: wrote $target/viewer.html and $manifest_file"
echo ""
echo "Manifest schema:"
echo "  title: string"
echo "  subtitle?: string"
echo "  meta?: { base?: string, head?: string, generatedFrom?: string }"
echo "  nodes: ["
echo "    {"
echo "      path: string,              // tree path; \"/\" nests folders"
echo "      label?: string,            // tree label; defaults to basename(path)"
echo "      badge?: string,            // small chip in the tree, e.g. \"THE BUG\""
echo "      badgeClass?: string,       // \"bug\" | \"store\" | \"join\" | \"test\" | \"add\" | \"del\" | \"\""
echo "      kind: \"diff\" | \"code\" | \"markdown\","
echo "      patch?: string,            // kind=diff: raw unified-diff text for THIS file"
echo "      code?: string, lang?: string, startLine?: number, highlight?: number[],  // kind=code"
echo "      md?: string,               // kind=markdown: raw markdown"
echo "      explain?: string           // markdown/html shown in the bottom pane, optional on any kind"
echo "    }"
echo "  ]"
