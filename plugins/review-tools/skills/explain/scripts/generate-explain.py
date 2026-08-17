#!/usr/bin/env python3
"""Deterministic generator for an `explain` walkthrough: a single self-contained HTML file built
from a git diff, a GitHub issue + its related issues, and/or optional docs/code, with zero
model-authored markup. Stdlib only (json, argparse, subprocess, pathlib, tempfile, webbrowser) +
shelling out to `git`/`gh` — no pip dependencies. Must run on macOS system python3 and in CI
(Linux); avoid anything requiring a compiled extension.

See plugins/review-tools/skills/explain/SKILL.md for the manifest schema and usage from the skill.
"""

import argparse
import fnmatch
import json
import re
import shutil
import subprocess
import sys
import tempfile
import webbrowser
from pathlib import Path, PurePosixPath

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

        # GitHub's own naming is from the QUERIED issue's perspective: #n's "blocked_by" list
        # names the issues that block #n (so, from m's own page, "m blocks #n"); #n's "blocking"
        # list names the issues #n blocks (so, from m's own page, "m is blocked by #n").
        for m in dependency_numbers(n, owner_repo, "blocked_by"):
            related_numbers.setdefault(m, f"Related: blocks #{n}")
        for m in dependency_numbers(n, owner_repo, "blocking"):
            related_numbers.setdefault(m, f"Related: blocked by #{n}")
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


# OpenSpec's own directory convention (not spec-flow-specific -- OpenSpec is its own generic,
# third-party tool). A 100%-green diff of a brand-new spec/change doc is never useful to review
# line-by-line; the point is to read it. Path-based only, deliberately -- see generate-explain.py's
# own SKILL.md and the openspec-aware-explain-view change for why content-sniffing was rejected.
#
# pathlib for the anchoring (an actual path-segment match, not a string/regex search that a
# prefix like "notopenspec/" could accidentally satisfy), fnmatch for the shape -- glob patterns
# read the same way OpenSpec's own docs describe these paths, rather than a hand-escaped regex
# alternation that's easy to get subtly wrong (anchoring, dot-escaping) and hard to eyeball.
OPENSPEC_TAIL_PATTERNS = [
    "openspec/specs/*.md",
    "openspec/changes/*/specs/*.md",
    "openspec/changes/*/proposal.md",
    "openspec/changes/*/design.md",
    "openspec/changes/*/tasks.md",
]


def is_openspec_path(path):
    parts = PurePosixPath(str(path).replace("\\", "/")).parts
    try:
        idx = parts.index("openspec")
    except ValueError:
        return False
    tail = "/".join(parts[idx:])
    return any(fnmatch.fnmatchcase(tail, pattern) for pattern in OPENSPEC_TAIL_PATTERNS)


def repo_root():
    """Absolute path to the current repo's top level, or None if it can't be resolved (not a git
    repo, detached from any worktree, etc). --diff mode's paths are always repo-root-relative (as
    `git diff` itself emits them), so a working-tree disk read for one of those paths must be
    anchored here -- not to the caller's actual cwd, which is a subdirectory more often than not
    and would otherwise make the read silently fail there."""
    try:
        return Path(run_git(["rev-parse", "--show-toplevel"]).strip())
    except subprocess.CalledProcessError:
        return None


def read_file_at_ref(path, ref, cwd=None):
    """The file's content at `ref`, or None if it can't be read there. `ref=None` means the
    working tree (a plain disk read, anchored at `cwd` when given); otherwise `git show
    ref:path`. Used both to pull an OpenSpec file's current content for rendering, and (with a
    different path) to fetch a capability's baseline spec for the MODIFIED-requirement
    comparison. `cwd` is for --diff mode's repo-root-relative paths (see repo_root()) -- --change
    mode's own disk_reader passes nothing here, since its paths are already relative to wherever
    --change itself was resolved from and must stay that way."""
    if ref is None:
        p = (Path(cwd) / path) if cwd is not None else Path(path)
        if not p.is_file():
            return None
        try:
            return p.read_text(encoding="utf-8")
        except OSError:
            return None
    try:
        return run_git(["show", f"{ref}:{path}"])
    except subprocess.CalledProcessError:
        return None


HUNK_HEADER_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@", re.MULTILINE)

# git blame --line-porcelain: each attributed line starts with "<sha> <origline> <finalline>
# [<numlines>]", followed by metadata lines (author/summary/etc.) for the FIRST line of a run,
# then a "\t<content>" line. We only need sha/author/summary, so a simple line-by-line scan
# (rather than a full porcelain parser) is enough.
BLAME_COMMIT_RE = re.compile(r"^([0-9a-f]{40}|[0-9a-f]{7,40}) \d+ \d+")


def commit_message_full(sha):
    """The full commit message (subject + body), not just the one-line summary `git blame`'s
    porcelain output gives — the body is where a "why" actually lives, when the commit bothered
    to write one. A one-liner like "fix bug" explains nothing; the body usually does."""
    try:
        return run_git(["log", "-1", "--format=%B", sha]).strip()
    except subprocess.CalledProcessError:
        return None


def blame_context_for(base, path, chunk, max_commits=3):
    """For a diff hunk's OLD-side line ranges, find the commit(s) that last touched those lines
    as of `base`, and surface each one's FULL commit message (not just its one-line summary) as
    the explanation of why that code looked the way it did before this change. The commit
    metadata (sha/author) is secondary — a small byline under the message, not the headline; a
    bare "who/when" with no explanatory text is close to useless on its own.

    ALWAYS returns a string, never None/empty — a diff node with `blame` enabled but no explain
    set at all reads as "this file has nothing to say," which is indistinguishable from "blame
    silently failed here." A brand-new file, or a hunk that's a pure addition (no old-side lines
    at all — nothing existed there to blame), gets an explicit one-line reason instead of empty."""
    if "\nnew file mode" in chunk:
        return "*New file — no prior history to show.*"

    ranges = []
    for m in HUNK_HEADER_RE.finditer(chunk):
        start = int(m.group(1))
        count = int(m.group(2)) if m.group(2) is not None else 1
        if count > 0:
            ranges.append((start, start + count - 1))
    if not ranges:
        return "*Pure addition — no old-side lines in this diff, so there's nothing to blame.*"

    commit_authors = {}  # sha -> author, insertion-ordered (most-recently-encountered-line first)
    for start, end in ranges:
        try:
            out = run_git(["blame", "--line-porcelain", "-L", f"{start},{end}", base, "--", path])
        except subprocess.CalledProcessError:
            continue
        sha = author = None
        for line in out.split("\n"):
            m = BLAME_COMMIT_RE.match(line)
            if m:
                sha = m.group(1)
                continue
            if line.startswith("author "):
                author = line[len("author "):]
                if sha and sha not in commit_authors:
                    commit_authors[sha] = author or "unknown"
                    if len(commit_authors) >= max_commits:
                        return format_blame(commit_authors)
    return format_blame(commit_authors)


def format_blame(commit_authors):
    if not commit_authors:
        return "*`git blame` found nothing for the changed lines (shallow clone, a binary file, or blame otherwise unavailable here).*"
    # The renderer has no horizontal-rule support, so a "---" separator would just render as a
    # literal "---" paragraph -- each block's own byline already reads as a clear visual break.
    parts = []
    for sha, author in commit_authors.items():
        message = commit_message_full(sha) or "*(no commit message available)*"
        parts.append(f"*`{sha[:7]}` — {author}*\n\n{message}")
    return "\n\n\n".join(parts)


def diff_nodes_from(base, head, paths=None, blame=False):
    cmd = ["diff", "--no-color", base] if head is None else ["diff", "--no-color", base, head]
    if paths:
        cmd += ["--"] + list(paths)
    try:
        diff_text = run_git(cmd)
    except subprocess.CalledProcessError as e:
        fail(f"'git {' '.join(cmd)}' failed: {e.stderr.strip()}")

    # `git diff` always emits repo-root-relative paths, regardless of the caller's actual cwd.
    # Only matters for head=None (a working-tree disk read) -- git show ref:path resolves against
    # the repo itself either way. Resolved once per call, not lazily, so a repo_root() failure
    # (rare -- git diff already succeeded) surfaces here rather than as a silent per-file miss.
    root = repo_root() if head is None else None

    nodes = []
    for i, chunk in enumerate(split_diff_by_file(diff_text)):
        first_line = chunk.split("\n", 1)[0]
        match = DIFF_GIT_RE.match(first_line)
        path = match.group(2) if match else f"unknown-file-{i}"
        is_deleted = "\ndeleted file mode" in chunk

        # An OpenSpec file's diff (almost always 100% green -- a fresh change dir has never
        # existed before) is never useful to review line-by-line; render its actual content
        # instead. Scoped strictly to OpenSpec paths -- every other file, including a brand-new
        # one, keeps the diff view. A deletion has no current content to show, so it stays a diff.
        if is_openspec_path(path) and not is_deleted:
            content = read_file_at_ref(path, head, cwd=root)
            if content is not None:
                nodes.append(markdown_node(
                    path, content,
                    read_baseline=lambda p, _head=head, _root=root: read_file_at_ref(p, _head, cwd=_root),
                ))
                continue
            # Defensive fallback -- git diff just told us this file changed, so failing to read
            # its content is unexpected; render as a diff rather than silently dropping the node.

        node = {"path": path, "kind": "diff", "patch": chunk}
        if "\nnew file mode" in chunk:
            node["badge"] = "new"
            node["badgeClass"] = "add"
        elif is_deleted:
            node["badge"] = "deleted"
            node["badgeClass"] = "del"
        if blame:
            explain = blame_context_for(base, path, chunk)
            if explain:
                node["explain"] = explain
        nodes.append(node)
    return nodes


def load_explain_map(path):
    """{"path": "explanation text", ...} — a caller who has actually read and understood the
    diff supplies this after doing that reading; it's the only source of a REAL explanation of
    what the code does. Blame/commit-history (--blame) is a cheap, mechanical fallback that can
    only ever say who wrote something and quote what they said about it at the time — never an
    actual account of what the current diff does, since git has no understanding of code."""
    p = Path(path)
    if not p.is_file():
        fail(f"--explain-map file not found: {path}")
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        fail(f"--explain-map: couldn't read/parse {path}: {e}")
    if not isinstance(data, dict):
        fail(f"--explain-map: expected a JSON object of {{path: explanation}}, got {type(data).__name__}")
    return data


def apply_explain_map(nodes, explain_map):
    for node in nodes:
        text = explain_map.get(node.get("path"))
        if text:
            node["explain"] = text  # always wins over blame -- a real explanation over a guess


def fetch_pr_review_comments(pr_number, owner_repo):
    """File/line-anchored PR review comments (GitHub's "pulls/{n}/comments" REST endpoint) — NOT
    `gh pr view --json comments`, which returns only top-level issue comments with no path/line.
    Returns [] on any failure (private repo you can't reach, PR not found, etc.) rather than
    failing the whole generation over comment data that's inherently supplementary."""
    try:
        raw = run_gh(["api", f"repos/{owner_repo}/pulls/{pr_number}/comments", "--paginate"])
    except subprocess.CalledProcessError as e:
        print(f"generate-explain: warning: couldn't fetch PR #{pr_number} review comments: {e.stderr.strip()}", file=sys.stderr)
        return []
    # --paginate concatenates one JSON array per page back-to-back, not one combined array.
    comments = []
    decoder = json.JSONDecoder()
    text = raw.strip()
    pos = 0
    while pos < len(text):
        obj, end = decoder.raw_decode(text, pos)
        comments.extend(obj)
        pos = end
        while pos < len(text) and text[pos] in " \t\n\r":
            pos += 1
    return comments


def attach_pr_comments(nodes, pr_comments):
    """Attach each file/line-anchored review comment to its diff node (matched by path); comments
    on a path with no matching diff node (e.g. resolved/outdated, or outside this diff's range)
    are collected into their own node instead of silently dropped."""
    by_path = {}
    unmatched = []
    for c in pr_comments:
        path = c.get("path")
        line = c.get("line") if c.get("line") is not None else c.get("original_line")
        entry = {
            "line": line,
            "side": c.get("side") or "RIGHT",
            "author": (c.get("user") or {}).get("login", "unknown"),
            "body": c.get("body") or "",
            "createdAt": c.get("created_at"),
        }
        if path and line is not None:
            by_path.setdefault(path, []).append(entry)
        else:
            unmatched.append({**entry, "path": path or "(unknown file)"})

    node_by_path = {n["path"]: n for n in nodes if n.get("kind") == "diff"}
    for path, entries in by_path.items():
        node = node_by_path.get(path)
        if node is not None:
            node["comments"] = entries
        else:
            unmatched.extend({**e, "path": path} for e in entries)

    if unmatched:
        lines = ["# PR review comments outside this diff", "",
                 "Anchored to a file/line, but that file isn't part of the diff being viewed here "
                 "(comment predates the current base/head range, or the line's since moved) — "
                 "listed so nothing from the review silently disappears:", ""]
        for e in unmatched:
            lines.append(f"**@{e['author']}** on `{e['path']}`" +
                         (f":{e['line']}" if e.get("line") is not None else "") +
                         (f" — {e['createdAt']}" if e.get("createdAt") else ""))
            lines.append("")
            lines.append(e["body"])
            lines.append("")
        nodes.append(markdown_node("pr-comments/outside-diff.md", "\n".join(lines)))


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

# A requirement's own prose (a Scenario, an example response) can legitimately contain a fenced
# code block that itself quotes markdown -- a "## MODIFIED Requirements" example, a "### x" in a
# shell comment. None of the structural regexes below (DELTA_HEADING_RE, REQUIREMENT_BLOCK_RE,
# the section-boundary search in delta_section_span) know about fences, so unmasked they'd treat
# a fenced example line as a real heading: truncating a requirement's content early, splicing the
# Currently:/This change: comparison into the middle of an open fence, or firing a badge/summary
# off a doc that only ever *mentions* delta headers (e.g. a doc about OpenSpec's own syntax).
# Mirrors viewer.html's own FENCE_RE exactly (``` or ~~~, no length/indent requirements beyond
# what viewer.html itself enforces) so masking agrees with how the rendered output actually gets
# split into code vs. prose.
FENCE_LINE_RE = re.compile(r"^\s*(```|~~~)")


def mask_fenced_code(text):
    """Same length and line count as `text`, but every character inside a fenced code block
    (both the fence delimiter lines and their contents) is replaced with a space. Used ONLY to
    find heading/boundary positions safely -- real content is always sliced back out of the
    original `text` using the offsets found here, never read from the masked copy."""
    lines = text.split("\n")
    masked = []
    fence_mark = None
    for line in lines:
        if fence_mark is None:
            m = FENCE_LINE_RE.match(line)
            if m:
                fence_mark = m.group(1)
                masked.append(" " * len(line))
            else:
                masked.append(line)
        else:
            masked.append(" " * len(line))
            if line.strip().startswith(fence_mark):
                fence_mark = None
    return "\n".join(masked)


def delta_badge_for(text):
    found = {m.group(1).upper() for m in DELTA_HEADING_RE.finditer(mask_fenced_code(text))}
    for kind in DELTA_BADGE_PRIORITY:
        if kind in found:
            return kind, DELTA_BADGE_CLASS[kind]
    return None, None


# A delta spec's own path -> its capability's baseline spec, e.g.
# ".../openspec/changes/issue-42/specs/widget/spec.md" -> ".../openspec/specs/widget/spec.md".
# Prefix-agnostic (works whether the delta path is absolute or relative) since it substitutes
# only the matched suffix, preserving whatever came before "openspec/changes/...".
DELTA_SPEC_PATH_RE = re.compile(r"openspec/changes/[^/]+/specs/([^/]+)/spec\.md$")

# One "### Requirement: <title>" heading through everything up to (not including) the next
# "###"/"##" heading or end of string -- works the same whether parsing a delta spec's own
# section or a baseline spec's flat "## Requirements" list.
REQUIREMENT_BLOCK_RE = re.compile(r"(^### Requirement:[ \t]*(.+?)[ \t]*$\n(?:(?!^###[ \t]|^##[ \t]).*\n?)*)", re.MULTILINE)


def baseline_path_for(delta_spec_path):
    m = DELTA_SPEC_PATH_RE.search(str(delta_spec_path))
    if not m:
        return None
    prefix = str(delta_spec_path)[:m.start()]
    return f"{prefix}openspec/specs/{m.group(1)}/spec.md"


def parse_requirements(text):
    """{title: full block text (heading line + body, trailing newlines stripped)}. Boundaries are
    found against a fence-masked copy (see mask_fenced_code) so a "### Requirement:"-looking line
    quoted inside a fenced example never gets mistaken for a real requirement heading; the
    returned content is always sliced back out of the real, unmasked `text`."""
    text = text or ""
    masked = mask_fenced_code(text)
    return {
        text[m.start(2):m.end(2)].strip(): text[m.start(1):m.end(1)].rstrip("\n")
        for m in REQUIREMENT_BLOCK_RE.finditer(masked)
    }


def delta_section_span(text, category):
    """(start, end) character offsets of a "## <category> Requirements" section's BODY (after
    its own heading line, up to the next "## " heading or end of text), or None if absent. Found
    against a fence-masked copy of `text` so a fenced example's own "## ..." line can never be
    mistaken for the section's real start/end -- the returned offsets are valid against `text`
    itself, since masking preserves length and line breaks exactly."""
    masked = mask_fenced_code(text)
    m = re.search(rf"^##[ \t]+{category}[ \t]+Requirements\b.*$", masked, re.MULTILINE | re.IGNORECASE)
    if not m:
        return None
    start = m.end() + 1 if m.end() < len(masked) and masked[m.end()] == "\n" else m.end()
    tail = re.search(r"^##[ \t]+\S", masked[start:], re.MULTILINE)
    end = start + tail.start() if tail else len(masked)
    return start, end


def inject_baseline_comparisons(text, baseline_requirements):
    """Splice a "Currently:/This change:" prose comparison into each MODIFIED requirement whose
    title matches something in `baseline_requirements` -- silently leaves a requirement
    untouched when there's no match (a real, expected case: a new capability, or a rename within
    the same change), never an error. Requirement boundaries within the section are found against
    a fence-masked copy, so a requirement whose own body quotes a fenced "## "/"### " example
    never gets truncated mid-fence, and the comparison is never spliced into the middle of an
    open fence -- it always lands after the requirement's real (unmasked) content ends."""
    if not baseline_requirements:
        return text
    span = delta_section_span(text, "MODIFIED")
    if not span:
        return text
    start, end = span
    section_text = text[start:end]
    masked_section = mask_fenced_code(section_text)

    pieces = []
    pos = 0
    for m in REQUIREMENT_BLOCK_RE.finditer(masked_section):
        pieces.append(section_text[pos:m.start(1)])
        block = section_text[m.start(1):m.end(1)]
        title = section_text[m.start(2):m.end(2)].strip()
        old_block = baseline_requirements.get(title)
        if old_block:
            # Drop each block's own "### Requirement:" heading line for the comparison -- the
            # requirement's title is already established by the surrounding section; repeating it
            # three times (the section itself + two comparison blocks) is just noise.
            old_body = re.sub(r"^### Requirement:.*\n", "", old_block, count=1).strip()
            new_body = re.sub(r"^### Requirement:.*\n", "", block, count=1).strip()
            block = block.rstrip("\n") + f"\n\n**Currently:**\n\n{old_body}\n\n**This change:**\n\n{new_body}\n\n"
        pieces.append(block)
        pos = m.end(1)
    pieces.append(section_text[pos:])

    new_section = "".join(pieces)
    return text[:start] + new_section + text[end:]


def delta_summary_prefix(text):
    """A "N added · M modified · ..." count line plus jump links to each present category's
    heading anchor (matching viewer.html's own slugify() -- lowercase, non-alnum runs to "-"),
    or None if no delta headers are present at all. Counts are taken from the fence-masked
    section text, so a fenced example that merely quotes what a requirement/rename line looks
    like is never counted as a real one."""
    masked = mask_fenced_code(text)
    counts = {}
    for category in ("ADDED", "MODIFIED", "REMOVED", "RENAMED"):
        span = delta_section_span(text, category)
        if span is None:
            continue
        section_masked = masked[span[0]:span[1]]
        if category == "RENAMED":
            count = len(re.findall(r"^-\s*FROM:", section_masked, re.MULTILINE))
        else:
            count = len(REQUIREMENT_BLOCK_RE.findall(section_masked))
        if count:
            counts[category] = count
    if not counts:
        return None
    summary_line = " · ".join(f"{n} {cat.lower()}" for cat, n in counts.items())
    links = "  ".join(f"[{cat}](#{cat.lower()}-requirements)" for cat in counts)
    return f"{summary_line}\n\n{links}\n\n"


def markdown_node(path, text, read_baseline=None):
    node = {"path": str(path), "kind": "markdown", "md": text}
    badge, badge_class = delta_badge_for(text)
    if badge:
        node["badge"] = badge
        node["badgeClass"] = badge_class

        baseline_requirements = {}
        if read_baseline is not None:
            baseline_path = baseline_path_for(path)
            if baseline_path:
                baseline_text = read_baseline(baseline_path)
                if baseline_text:
                    baseline_requirements = parse_requirements(baseline_text)

        enriched = inject_baseline_comparisons(text, baseline_requirements)
        summary = delta_summary_prefix(enriched)
        if summary:
            enriched = summary + enriched
        node["md"] = enriched
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

    # Disk-relative, matching how --change itself always resolves (no git-ref awareness needed
    # here) -- this is what lets a delta spec reached via --change get the same MODIFIED-requirement
    # baseline comparison as one reached via --diff's own OpenSpec-path detection (see markdown_node).
    disk_reader = lambda p: read_file_at_ref(p, None)

    nodes = []
    for fname in ("proposal.md", "design.md", "tasks.md"):
        f = d / fname
        if f.is_file():
            nodes.append(markdown_node(f, read_text(f), read_baseline=disk_reader))

    specs_dir = d / "specs"
    if specs_dir.is_dir():
        for f in sorted(specs_dir.rglob("*.md")):
            nodes.append(markdown_node(f, read_text(f), read_baseline=disk_reader))

    return nodes


MAX_SYMBOL_HITS = 200  # a blast-radius list beyond this is noise, not signal — truncate and say so


def blast_radius_node(symbol):
    """A deterministic, language-agnostic "who else references this" list: a plain word-boundary
    `git grep` for the symbol across tracked files in the working tree (no AST/language server —
    that's the tradeoff for working the same way in any language). Always returns a node, even on
    zero matches, so "checked, found nothing" is visible rather than the symbol silently missing
    from the tree."""
    try:
        out = run_git(["grep", "-n", "-w", "--full-name", "-e", symbol])
    except subprocess.CalledProcessError as e:
        if e.returncode == 1:
            out = ""  # git grep exits 1 for "no matches" — not an error
        else:
            print(f"generate-explain: warning: 'git grep' failed for --symbol {symbol}: {e.stderr.strip()}", file=sys.stderr)
            return markdown_node(f"blast-radius/{symbol}.md", f"# Callers of `{symbol}`\n\n`git grep` failed — see stderr.\n")

    hits = [line for line in out.split("\n") if line]
    lines = [f"# Callers of `{symbol}`", ""]
    if not hits:
        lines.append("No references found (word-boundary `git grep` across tracked files in the working tree).")
    else:
        truncated = hits[:MAX_SYMBOL_HITS]
        lines.append(f"{len(hits)} reference(s) across the working tree" +
                     (f" (showing first {MAX_SYMBOL_HITS})" if len(hits) > MAX_SYMBOL_HITS else "") + ":")
        lines.append("")
        for hit in truncated:
            # "path:lineno:content" — content may itself contain ":", so split with maxsplit=2
            parts = hit.split(":", 2)
            if len(parts) == 3:
                path, lineno, content = parts
                lines.append(f"- `{path}:{lineno}` — `{content.strip()}`")
            else:
                lines.append(f"- `{hit}`")
    return markdown_node(f"blast-radius/{symbol}.md", "\n".join(lines))


def default_title(args, head, primary_issue_title):
    """A title that names what's actually being explained, instead of the generic "Explain" --
    picked from whichever input is the most identity-bearing single artifact: an issue's own
    title beats everything (it already names the work); an OpenSpec change dir names a specific
    proposed change; a diff is named by its branch/head when there is one to point to; a doc/code
    file falls back to its own name. Only reached when --title wasn't passed explicitly."""
    if primary_issue_title:
        return primary_issue_title
    if args.change:
        names = [Path(c).name for c in args.change]
        return names[0] if len(names) == 1 else f"{names[0]} +{len(names) - 1} more"
    if args.diff:
        # `head` is already the resolved value -- when --branch drove it (no explicit --head),
        # head == args.branch; when both were passed, --head wins over --branch for the actual
        # diff (see main()'s --branch/--head resolution), so it must win for the title too.
        if head:
            return f"Diff: {head}"
        return "Diff: working tree"
    if args.doc:
        names = [Path(d).name for d in args.doc]
        return names[0] if len(names) == 1 else f"{names[0]} +{len(names) - 1} more"
    if args.code:
        names = [Path(c).name for c in args.code]
        return names[0] if len(names) == 1 else f"{names[0]} +{len(names) - 1} more"
    if args.symbol:
        return args.symbol[0] if len(args.symbol) == 1 else f"{args.symbol[0]} +{len(args.symbol) - 1} more"
    return "Explain"


def build_manifest(args, base, head):
    nodes = []
    source_bits = []
    meta = {}

    if args.diff:
        nodes += diff_nodes_from(base, head, paths=args.path, blame=args.blame)
        head_label = head or "working tree"
        meta["base"] = base
        meta["head"] = head_label
        scope = f" -- {' '.join(args.path)}" if args.path else ""
        source_bits.append(f"git diff {base}..{head_label}{scope}")

        if args.pr:
            pr_comments = fetch_pr_review_comments(args.pr, repo_slug())
            attach_pr_comments(nodes, pr_comments)
            source_bits.append(f"PR #{args.pr} review comments ({len(pr_comments)})")
    elif args.pr:
        print("generate-explain: warning: --pr has no diff to attach comments to without --diff — ignoring --pr", file=sys.stderr)

    primary_issue_title = None
    if args.issue:
        issue_nodes, primary_issue_title = issue_nodes_from(args.issue)
        nodes += issue_nodes
        source_bits.append(f"{len(args.issue)} issue(s) + related")

    for change_dir in args.change or []:
        nodes += change_nodes_from(change_dir)
    if args.change:
        source_bits.append(f"{len(args.change)} change dir(s)")
    # Disk-relative, matching how --doc itself always resolves (a plain path, not a git ref) --
    # same reasoning as --change's own disk_reader in change_nodes_from, so a delta spec reached
    # via --doc gets the identical MODIFIED-requirement baseline comparison --diff/--change give.
    doc_baseline_reader = lambda p: read_file_at_ref(p, None)
    for doc in args.doc or []:
        nodes.append(markdown_node(doc, read_text(doc), read_baseline=doc_baseline_reader))
    if args.doc:
        source_bits.append(f"{len(args.doc)} doc(s)")
    for code in args.code or []:
        nodes.append(code_node(code, read_text(code)))
    if args.code:
        source_bits.append(f"{len(args.code)} code file(s)")
    for symbol in args.symbol or []:
        nodes.append(blast_radius_node(symbol))
    if args.symbol:
        source_bits.append(f"{len(args.symbol)} symbol blast-radius search(es)")

    meta["generatedFrom"] = ", ".join(source_bits) if source_bits else "no inputs"

    if args.explain_map:
        apply_explain_map(nodes, load_explain_map(args.explain_map))
        source_bits.append("caller-supplied explanations")

    manifest = {
        "title": args.title or default_title(args, head, primary_issue_title),
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
    parser.add_argument("--worktree", action="store_true",
                         help="alias for --diff with no --base/--head override -- 'explain what's uncommitted here', which is already --diff's own default behavior (merge-base vs. working tree). Purely a clearer, more discoverable name for that default; adds no new resolution logic")
    parser.add_argument("--branch", metavar="NAME",
                         help="alias for --diff --head NAME -- 'explain this branch against the default branch'. Ignored if --head is also passed explicitly (--head wins). Generic git-level convenience only -- no issue-number guessing, no assumptions about branch-naming conventions, so this stays usable in any repo")
    parser.add_argument("--base", help="diff base ref (default: merge-base with the default branch); only meaningful with --diff")
    parser.add_argument("--head", help="diff head ref (default: working tree); only meaningful with --diff")
    parser.add_argument("--path", action="append", default=[], metavar="PATH",
                         help="scope --diff to this path (repeatable, passed to git diff as -- <path>...); only meaningful with --diff, omit to diff the whole repo")
    parser.add_argument("--blame", action="store_true",
                         help="populate each diff node's explain pane with commit-history context (each touched commit's full message) — opt-in, and a mechanical fallback at best: git can quote what someone once wrote, never explain what the CURRENT diff actually does. Prefer --explain-map when you can. Only meaningful with --diff; overridden per-node by --explain-map when both apply")
    parser.add_argument("--no-blame", action="store_true",
                         help="accepted for backward compatibility — --blame is opt-in again (not the default), so this no longer changes anything")
    parser.add_argument("--explain-map", metavar="PATH",
                         help="a JSON file of {\"path\": \"explanation\", ...} — REAL explanations of what the code does, written by a caller that has actually read the diff (an LLM; git cannot produce this). Applies to any node whose path matches a key, of any kind, always taking priority over --blame for that node")
    parser.add_argument("--issue", action="append", type=int, default=[], metavar="N",
                         help="a GitHub issue number: its body + comments, plus (one level out) every issue it's linked to via a native dependency or a bare #N mention (repeatable)")
    parser.add_argument("--change", action="append", default=[], metavar="DIR",
                         help="an OpenSpec change dir; auto-includes proposal.md/design.md/tasks.md + specs/**/*.md (repeatable)")
    parser.add_argument("--doc", action="append", default=[], metavar="PATH",
                         help="an extra markdown file -> a markdown node (repeatable)")
    parser.add_argument("--code", action="append", default=[], metavar="PATH",
                         help="show a file as a non-diff code node (repeatable)")
    parser.add_argument("--symbol", action="append", default=[], metavar="NAME",
                         help="blast-radius: a word-boundary `git grep` for NAME across the working tree, rendered as a callers list under blast-radius/ (repeatable, deterministic, language-agnostic — no AST/language server)")
    parser.add_argument("--pr", type=int, metavar="N",
                         help="overlay this PR's file/line-anchored GitHub review comments onto the --diff nodes they were left on; only meaningful with --diff (ignored otherwise, with a warning)")
    parser.add_argument("--title")
    parser.add_argument("--subtitle")
    parser.add_argument("--out", help="output HTML path (default: a generated path under the system temp dir)")
    parser.add_argument("--open", action="store_true", help="open the result in a browser (only when explicitly passed)")
    args = parser.parse_args()

    # --worktree/--branch are pure sugar, resolved before anything else reads args.diff/args.head.
    if args.worktree:
        args.diff = True
    if args.branch:
        args.diff = True
        if not args.head:
            args.head = args.branch

    if not (args.diff or args.issue or args.change or args.doc or args.code or args.symbol):
        fail("nothing to render — pass at least one of --diff (or --worktree/--branch), --issue, --change, --doc, --code, --symbol")

    if args.diff and shutil.which("git") is None:
        fail("'git' is required but not on PATH (needed for --diff).")
    if args.issue and shutil.which("gh") is None:
        fail("'gh' is required but not on PATH (needed for --issue).")
    if args.pr and shutil.which("gh") is None:
        fail("'gh' is required but not on PATH (needed for --pr).")
    if args.symbol and shutil.which("git") is None:
        fail("'git' is required but not on PATH (needed for --symbol).")

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
