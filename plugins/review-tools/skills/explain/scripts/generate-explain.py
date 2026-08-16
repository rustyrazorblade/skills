#!/usr/bin/env python3
"""Deterministic generator for an `explain` walkthrough: a single self-contained HTML file built
from a git diff, a GitHub issue + its related issues, and/or optional docs/code, with zero
model-authored markup. Stdlib only (json, argparse, subprocess, pathlib, tempfile, webbrowser) +
shelling out to `git`/`gh` — no pip dependencies. Must run on macOS system python3 and in CI
(Linux); avoid anything requiring a compiled extension.

See plugins/review-tools/skills/explain/SKILL.md for the manifest schema and usage from the skill.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import webbrowser
from pathlib import Path

# The canonical "nothing here yet" tree — diffing against it renders a from-scratch add of
# everything in <head>. Used only when no other base can be resolved (e.g. a repo with a single
# commit and no configured origin/HEAD).
EMPTY_TREE_SHA = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

DIFF_GIT_RE = re.compile(r"^diff --git a/(.+) b/(.+)$")

LANG_BY_SUFFIX = {
    ".py": "python", ".js": "javascript", ".ts": "typescript", ".tsx": "tsx", ".jsx": "jsx",
    ".rs": "rust", ".go": "go", ".java": "java", ".kt": "kotlin", ".rb": "ruby", ".sh": "bash",
    ".md": "markdown", ".json": "json", ".yaml": "yaml", ".yml": "yaml", ".sql": "sql",
    ".c": "c", ".h": "c", ".cpp": "cpp", ".hpp": "cpp", ".swift": "swift", ".html": "html",
    ".css": "css",
}


def fail(message):
    print(f"generate-explain: {message}", file=sys.stderr)
    sys.exit(1)


def run_git(args, cwd=None):
    result = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)
    return result.stdout


def run_gh(args):
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)
    return result.stdout


ISSUE_MENTION_RE = re.compile(r"(?<!\w)#(\d+)\b")


def repo_slug():
    """"owner/repo" of the current directory's GitHub remote, for the dependencies API (which
    isn't scoped by `gh issue`'s own repo-inference the way `gh issue view` is)."""
    try:
        return run_gh(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]).strip()
    except subprocess.CalledProcessError as e:
        fail(f"couldn't resolve the GitHub repo ('gh repo view' failed): {e.stderr.strip()}")


def fetch_issue(number, with_comments):
    fields = "number,title,body,url,state,labels"
    if with_comments:
        fields += ",comments"
    try:
        raw = run_gh(["issue", "view", str(number), "--json", fields])
    except subprocess.CalledProcessError as e:
        return None
    return json.loads(raw)


def dependency_numbers(number, owner_repo, relation):
    # relation: "blocked_by" or "blocking". Native GitHub issue-dependencies API — additive to,
    # not a substitute for, the #-mention scan below (an issue can reference another without a
    # formal dependency link, and vice versa).
    try:
        raw = run_gh(["api", f"repos/{owner_repo}/issues/{number}/dependencies/{relation}"])
    except subprocess.CalledProcessError:
        return []
    try:
        items = json.loads(raw)
    except json.JSONDecodeError:
        return []
    return [item["number"] for item in items if "number" in item]


def mentioned_numbers(issue_data):
    text = (issue_data.get("body") or "")
    for c in issue_data.get("comments") or []:
        text += "\n" + (c.get("body") or "")
    return [int(n) for n in ISSUE_MENTION_RE.findall(text)]


def issue_markdown(issue_data, relation_note=None):
    lines = [f"# #{issue_data['number']} — {issue_data['title']}"]
    meta_bits = [issue_data.get("state", "").upper()]
    labels = [l["name"] for l in issue_data.get("labels") or []]
    if labels:
        meta_bits.append(", ".join(labels))
    lines.append(f"*{' · '.join(b for b in meta_bits if b)}*")
    if relation_note:
        lines.append(f"*{relation_note}*")
    lines.append("")
    lines.append(issue_data.get("body") or "*(no description)*")

    comments = issue_data.get("comments") or []
    if comments:
        lines.append("")
        lines.append("## Discussion")
        for c in comments:
            author = (c.get("author") or {}).get("login", "unknown")
            created = c.get("createdAt", "")
            lines.append("")
            lines.append(f"**@{author}** — {created}")
            lines.append("")
            lines.append(c.get("body") or "")
    return "\n".join(lines)


def issue_nodes_from(issue_numbers):
    """Primary issues (full body + comments) plus, one level out, every issue they're linked to
    via a native GitHub dependency or a bare "#N" mention in their body/comments — so "related
    issues and the research that went into this one" doesn't require any code diff to exist yet.
    Returns (nodes, primary_title_for_default_title_or_None)."""
    nodes = []
    primary_title = None
    seen = set()
    related_numbers = {}  # number -> relation note, for issues NOT explicitly requested

    owner_repo = repo_slug()

    for n in issue_numbers:
        if n in seen:
            continue
        seen.add(n)
        data = fetch_issue(n, with_comments=True)
        if data is None:
            print(f"generate-explain: warning: issue #{n} not found or inaccessible, skipping", file=sys.stderr)
            continue
        if primary_title is None:
            primary_title = f"#{n} — {data['title']}"
        nodes.append(markdown_node(f"issue-{n}.md", issue_markdown(data)))

        for m in dependency_numbers(n, owner_repo, "blocked_by"):
            related_numbers.setdefault(m, f"Related: blocked by #{n}")
        for m in dependency_numbers(n, owner_repo, "blocking"):
            related_numbers.setdefault(m, f"Related: blocks #{n}")
        for m in mentioned_numbers(data):
            if m != n:
                related_numbers.setdefault(m, f"Related: mentioned in #{n}")

    for m, note in related_numbers.items():
        if m in seen:
            continue
        seen.add(m)
        data = fetch_issue(m, with_comments=False)
        if data is None:
            continue
        nodes.append(markdown_node(f"related/issue-{m}.md", issue_markdown(data, relation_note=note)))

    return nodes, primary_title


def resolve_default_branch():
    try:
        out = run_git(["symbolic-ref", "refs/remotes/origin/HEAD"]).strip()
        # "refs/remotes/origin/main" -> "main"
        return out.rsplit("/", 1)[-1] or None
    except subprocess.CalledProcessError:
        return None


def resolve_base():
    """Merge-base against the default branch, with sensible fallbacks. Order: origin/HEAD's
    target branch, then origin/main, then origin/master, then the previous commit (a lone-commit
    repo with no configured origin), then the empty tree (a repo with exactly one commit)."""
    candidates = []
    default_branch = resolve_default_branch()
    if default_branch:
        candidates.append(default_branch)
    candidates += ["main", "master"]

    seen = set()
    for branch in candidates:
        if branch in seen:
            continue
        seen.add(branch)
        ref = f"origin/{branch}"
        try:
            run_git(["rev-parse", "--verify", "--quiet", ref])
        except subprocess.CalledProcessError:
            continue
        try:
            return run_git(["merge-base", "HEAD", ref]).strip()
        except subprocess.CalledProcessError:
            continue

    try:
        return run_git(["rev-parse", "HEAD~1"]).strip()
    except subprocess.CalledProcessError:
        return EMPTY_TREE_SHA


def split_diff_by_file(diff_text):
    """Split `git diff`'s combined output into one raw patch string per file, each starting at
    its own "diff --git" line."""
    chunks = []
    current = []
    for line in diff_text.split("\n"):
        if line.startswith("diff --git "):
            if current:
                chunks.append("\n".join(current))
            current = [line]
        elif current:
            current.append(line)
    if current:
        chunks.append("\n".join(current))
    return chunks


def diff_nodes_from(base, head):
    cmd = ["diff", "--no-color", base] if head is None else ["diff", "--no-color", base, head]
    try:
        diff_text = run_git(cmd)
    except subprocess.CalledProcessError as e:
        fail(f"'git {' '.join(cmd)}' failed: {e.stderr.strip()}")

    nodes = []
    for i, chunk in enumerate(split_diff_by_file(diff_text)):
        first_line = chunk.split("\n", 1)[0]
        match = DIFF_GIT_RE.match(first_line)
        path = match.group(2) if match else f"unknown-file-{i}"

        node = {"path": path, "kind": "diff", "patch": chunk}
        if "\nnew file mode" in chunk:
            node["badge"] = "new"
            node["badgeClass"] = "add"
        elif "\ndeleted file mode" in chunk:
            node["badge"] = "deleted"
            node["badgeClass"] = "del"
        nodes.append(node)
    return nodes


def read_text(path):
    p = Path(path)
    if not p.is_file():
        fail(f"file not found: {path}")
    try:
        return p.read_text(encoding="utf-8")
    except OSError as e:
        fail(f"could not read {path}: {e}")


# OpenSpec's own delta-spec convention (not spec-flow-specific — OpenSpec is its own generic
# tool): a "## ADDED/MODIFIED/REMOVED/RENAMED Requirements" heading. Priority when a file has
# more than one (REMOVED/MODIFIED are the riskier changes to miss, so they win the tree badge —
# the markdown renderer itself still color-codes every section, this is just the one-badge
# quick-scan hint in the file tree).
DELTA_HEADING_RE = re.compile(r"^##\s+(ADDED|MODIFIED|REMOVED|RENAMED)\s+Requirements\b", re.IGNORECASE | re.MULTILINE)
DELTA_BADGE_PRIORITY = ["REMOVED", "MODIFIED", "RENAMED", "ADDED"]
DELTA_BADGE_CLASS = {"ADDED": "add", "MODIFIED": "mod", "REMOVED": "del", "RENAMED": "mod"}


def delta_badge_for(text):
    found = {m.group(1).upper() for m in DELTA_HEADING_RE.finditer(text)}
    for kind in DELTA_BADGE_PRIORITY:
        if kind in found:
            return kind, DELTA_BADGE_CLASS[kind]
    return None, None


def markdown_node(path, text):
    node = {"path": str(path), "kind": "markdown", "md": text}
    badge, badge_class = delta_badge_for(text)
    if badge:
        node["badge"] = badge
        node["badgeClass"] = badge_class
    return node


def code_node(path, text):
    node = {"path": str(path), "kind": "code", "code": text}
    lang = LANG_BY_SUFFIX.get(Path(path).suffix)
    if lang:
        node["lang"] = lang
    return node


def change_nodes_from(change_dir):
    d = Path(change_dir)
    if not d.is_dir():
        print(f"generate-explain: warning: --change dir not found, skipping: {change_dir}", file=sys.stderr)
        return []

    nodes = []
    for fname in ("proposal.md", "design.md", "tasks.md"):
        f = d / fname
        if f.is_file():
            nodes.append(markdown_node(f, read_text(f)))

    specs_dir = d / "specs"
    if specs_dir.is_dir():
        for f in sorted(specs_dir.rglob("*.md")):
            nodes.append(markdown_node(f, read_text(f)))

    return nodes


def build_manifest(args, base, head):
    nodes = []
    source_bits = []
    meta = {}

    if args.diff:
        nodes += diff_nodes_from(base, head)
        head_label = head or "working tree"
        meta["base"] = base
        meta["head"] = head_label
        source_bits.append(f"git diff {base}..{head_label}")

    primary_issue_title = None
    if args.issue:
        issue_nodes, primary_issue_title = issue_nodes_from(args.issue)
        nodes += issue_nodes
        source_bits.append(f"{len(args.issue)} issue(s) + related")

    for change_dir in args.change or []:
        nodes += change_nodes_from(change_dir)
    if args.change:
        source_bits.append(f"{len(args.change)} change dir(s)")
    for doc in args.doc or []:
        nodes.append(markdown_node(doc, read_text(doc)))
    if args.doc:
        source_bits.append(f"{len(args.doc)} doc(s)")
    for code in args.code or []:
        nodes.append(code_node(code, read_text(code)))
    if args.code:
        source_bits.append(f"{len(args.code)} code file(s)")

    meta["generatedFrom"] = ", ".join(source_bits) if source_bits else "no inputs"

    manifest = {
        "title": args.title or primary_issue_title or "Explain",
        "meta": meta,
        "nodes": nodes,
    }
    if args.subtitle:
        manifest["subtitle"] = args.subtitle
    return manifest


def inject_manifest(viewer_html, manifest):
    # ensure_ascii keeps the payload plain-ASCII-safe; escaping "</" as "<\/" is the standard
    # technique to stop an embedded "</script>" substring (e.g. inside a doc or diff) from
    # prematurely closing the injected <script> tag.
    manifest_json = json.dumps(manifest, ensure_ascii=True).replace("</", "<\\/")
    script_tag = f"<script>window.MANIFEST = {manifest_json};</script>"
    if "<!--MANIFEST-->" not in viewer_html:
        fail("assets/viewer.html is missing its <!--MANIFEST--> marker — was it edited?")
    return viewer_html.replace("<!--MANIFEST-->", script_tag, 1)


def default_out_path():
    fd_path = Path(tempfile.gettempdir())
    fd_path.mkdir(parents=True, exist_ok=True)
    # mkstemp for a guaranteed-unique name; we immediately overwrite via write_text below, so the
    # empty file it creates is just a placeholder reservation.
    import os
    fd, name = tempfile.mkstemp(prefix="explain-", suffix=".html", dir=str(fd_path))
    os.close(fd)
    return Path(name)


def main():
    parser = argparse.ArgumentParser(description="Generate a deterministic IDE-style HTML explain view from a git diff, a GitHub issue, and/or docs.")
    parser.add_argument("--diff", action="store_true",
                         help="include a git diff (base/head below); omit for a docs-only or issue-only view — no diff is computed unless this is passed")
    parser.add_argument("--base", help="diff base ref (default: merge-base with the default branch); only meaningful with --diff")
    parser.add_argument("--head", help="diff head ref (default: working tree); only meaningful with --diff")
    parser.add_argument("--issue", action="append", type=int, default=[], metavar="N",
                         help="a GitHub issue number: its body + comments, plus (one level out) every issue it's linked to via a native dependency or a bare #N mention (repeatable)")
    parser.add_argument("--change", action="append", default=[], metavar="DIR",
                         help="an OpenSpec change dir; auto-includes proposal.md/design.md/tasks.md + specs/**/*.md (repeatable)")
    parser.add_argument("--doc", action="append", default=[], metavar="PATH",
                         help="an extra markdown file -> a markdown node (repeatable)")
    parser.add_argument("--code", action="append", default=[], metavar="PATH",
                         help="show a file as a non-diff code node (repeatable)")
    parser.add_argument("--title")
    parser.add_argument("--subtitle")
    parser.add_argument("--out", help="output HTML path (default: a generated path under the system temp dir)")
    parser.add_argument("--open", action="store_true", help="open the result in a browser (only when explicitly passed)")
    args = parser.parse_args()

    if not (args.diff or args.issue or args.change or args.doc or args.code):
        fail("nothing to render — pass at least one of --diff, --issue, --change, --doc, --code")

    if args.diff and shutil.which("git") is None:
        fail("'git' is required but not on PATH (needed for --diff).")
    if args.issue and shutil.which("gh") is None:
        fail("'gh' is required but not on PATH (needed for --issue).")

    base = head = None
    if args.diff:
        base = args.base or resolve_base()
        head = args.head  # None means "working tree" — handled in diff_nodes_from

    manifest = build_manifest(args, base, head)

    viewer_path = Path(__file__).resolve().parent.parent / "assets" / "viewer.html"
    if not viewer_path.is_file():
        fail(f"viewer shell not found at {viewer_path} — was assets/viewer.html removed?")
    viewer_html = viewer_path.read_text(encoding="utf-8")

    out_html = inject_manifest(viewer_html, manifest)

    out_path = Path(args.out).resolve() if args.out else default_out_path()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(out_html, encoding="utf-8")

    print(str(out_path))
    print(f"open {out_path}")

    if args.open:
        webbrowser.open(f"file://{out_path}")


if __name__ == "__main__":
    main()
