#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pypandoc-binary>=1.13",
# ]
# ///
"""Export a lab report: the summary tier for JIRA, and the shareable book as a zip.

Usage:
    report-export.py jira <docs> <out.txt>
    report-export.py zip <docs> <out.zip>

jira converts 1-summary.md to Atlassian wiki markup through pandoc (pypandoc-binary, so no
system install).  A Lua filter references each image by file name (!scrape-alloc.png!) for
manual attachment, turns links to .md pages into their text, and maps each verdict badge to a
colour.  It removes the writer's escape from a ( that opens no emoticon and from the sign of a
number, so "(MB/s)" and "+20.8%" stay readable.

zip writes the shareable book.  It stages every page that SUMMARY.md lists, the appendix
included, every images/ and data/ file they reference, and the theme (book.toml, lab.css, and
SUMMARY.md) under export/stage/.  In the staged copy it replaces each infrastructure identifier
with a placeholder that names its kind, such as <private-ip>, and each wrapper variable ($EDB,
${EDB}, $EDB_<ARM>) with easy-db-lab.  It then scans the whole staged copy with the same
patterns (report-check.py), builds it with mdbook, and zips the built HTML.  A listed page
outside docs/, a referenced file that does not exist, or an identifier that remains in the
staged copy fails the export, and no zip is written.  The local report/ and the docs files keep
the unredacted record.
"""

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile


def load_check():
    """report-check.py, loaded as a module: its redaction rule is the one the export applies."""
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "report-check.py")
    spec = importlib.util.spec_from_file_location("report_check", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_check = load_check()
redact, scan, measurements = _check.redact, _check.scan, _check.measurements

# Okabe-Ito, the same badge colours as lab.css.
LUA_FILTER = r"""
local colours = {
  confirmed = "#009E73", refuted = "#D55E00", inconclusive = "#E69F00", partial = "#999999",
}

function Span(el)
  for _, class in ipairs(el.classes) do
    local value = class:match("^verdict%-(.+)$")
    if value and colours[value] then
      return pandoc.RawInline("jira",
        "{color:" .. colours[value] .. "}*" .. pandoc.utils.stringify(el) .. "*{color}")
    end
  end
end

function Link(el)
  local target = el.target
  if not target:match("^%a[%w+.-]*:") and (target:match("%.md$") or target:match("%.md#")) then
    return el.content
  end
end

function Image(el)
  el.src = el.src:match("([^/]+)$")
  el.caption = {}
  return el
end

function RawBlock(el)
  if el.format == "html" then return {} end
end

function RawInline(el)
  if el.format == "html" then return {} end
end
"""

LINK_TARGET = re.compile(r"\]\(([^)\s]+)\)")
# The theme files that the staged book needs besides its pages.
THEME = ["SUMMARY.md", "book.toml", "lab.css"]
# The image types that the export copies unchanged.  Every other staged file must be text, so
# that the replace step and the scan read it.
IMAGES = (".png", ".jpg", ".jpeg", ".gif", ".webp")
# The mdbook directives that pull another file into a page.
INCLUDE = re.compile(r"\{\{#(include|rustdoc_include|playground)\b")
# The jira writer escapes every ( so that no text becomes a JIRA emoticon such as (i).  Keep the
# escape only before an emoticon.
EMOTICON = r"(?:[ixyn/!?*+-]|on|off|flag|flagoff|\*[rgby])\)"
ESCAPED_PAREN = re.compile(r"\\\((?!" + EMOTICON + ")")
# A signed number such as +20.8% or -26.4% opens no underline or strikethrough.
ESCAPED_SIGN = re.compile(r"\\([+-])(?=\d)")


def die(msg):
    print(f"report-export: {msg}", file=sys.stderr)
    sys.exit(1)


def jira(docs, out):
    import pypandoc

    summary = os.path.join(docs, "1-summary.md")
    if not os.path.exists(summary):
        die(f"no 1-summary.md in {docs}")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(LUA_FILTER)
        lua = f.name
    try:
        # No smart extension: it turns the -- of a flag such as --arm-windows into an en dash.
        text = pypandoc.convert_file(summary, "jira", format="markdown-auto_identifiers-smart", filters=[lua])
    finally:
        os.unlink(lua)
    # The jira writer puts an {anchor:} macro on every heading; JIRA needs none.
    text = re.sub(r"\{anchor:[^}]*\}", "", text)
    text = ESCAPED_SIGN.sub(r"\1", ESCAPED_PAREN.sub("(", text))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"jira: {out}")


def book_pages(docs):
    """Every page that SUMMARY.md lists, the appendix included, as docs-relative paths."""
    path = os.path.join(docs, "SUMMARY.md")
    if not os.path.exists(path):
        die(f"no SUMMARY.md in {docs}")
    pages = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            for target in LINK_TARGET.findall(line):
                target = os.path.normpath(target.split("#")[0])
                if target.endswith(".md") and target not in pages:
                    pages.append(target)
    outside = [p for p in pages if os.path.isabs(p) or p == os.pardir or p.startswith(os.pardir + os.sep)]
    if outside:
        die("SUMMARY.md lists pages outside docs/: " + ", ".join(outside))
    return pages


def book_files(docs):
    """The pages, the images/ and data/ files they reference, and the theme files."""
    files, missing = [], []
    for page in book_pages(docs):
        path = os.path.join(docs, page)
        if not os.path.exists(path):
            missing.append(page)
            continue
        files.append(page)
        with open(path, encoding="utf-8") as f:
            text = re.sub(r"<!--.*?-->", "", f.read(), flags=re.S)
        for target in LINK_TARGET.findall(text):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                continue
            ref = os.path.normpath(os.path.join(os.path.dirname(page), target.split("#")[0]))
            if not ref.startswith(("images" + os.sep, "data" + os.sep)):
                continue
            if not os.path.exists(os.path.join(docs, ref)):
                missing.append(f"{ref} (referenced by {page})")
            elif ref not in files:
                files.append(ref)
    if missing:
        die("missing referenced files: " + ", ".join(missing))
    if not os.path.exists(os.path.join(docs, "book.toml")):
        die(f"no book.toml in {docs}")
    return files + [t for t in THEME if os.path.exists(os.path.join(docs, t)) and t not in files]


def texts(docs, files):
    """The files that are text: each one that is not a known image and decodes as UTF-8.  A file
    that is neither fails the export, because the replace step cannot read it."""
    out, unknown = [], []
    for rel in files:
        if rel.lower().endswith(IMAGES):
            continue
        with open(os.path.join(docs, rel), "rb") as f:
            try:
                f.read().decode("utf-8")
            except UnicodeDecodeError:
                unknown.append(rel)
                continue
        out.append(rel)
    if unknown:
        die("referenced files that are neither text nor a png, jpg, gif, or webp image: " + ", ".join(unknown))
    return out


def stage(docs, files, text_files, dest):
    """Copy files into dest, with each text file redacted."""
    shutil.rmtree(dest, ignore_errors=True)
    for rel in files:
        src, out = os.path.join(docs, rel), os.path.join(dest, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if rel in text_files:
            with open(src, encoding="utf-8") as f:
                text = redact(rel, f.read())
            with open(out, "w", encoding="utf-8") as f:
                f.write(text)
        else:
            shutil.copyfile(src, out)


def leftovers(dest, text_files):
    """One message per identifier that remains in the staged text files."""
    found = []
    for rel in text_files:
        with open(os.path.join(dest, rel), encoding="utf-8") as f:
            found += [f"{kind} in {rel} line {n}" for kind, n in scan(rel, f.read())]
    return found


def includes(dest, text_files):
    """One message per mdbook include directive in a staged page.  mdbook would pull the named
    file into the book after the replace step, unredacted."""
    found = []
    for rel in text_files:
        if rel.endswith(".md"):
            with open(os.path.join(dest, rel), encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    found += [f"{{{{#{d} in {rel} line {n}" for d in INCLUDE.findall(line)]
    return found


def measured(dest, text_files):
    """The measurement cells of the staged files, which the built HTML shows outside markdown."""
    out = set()
    for rel in text_files:
        with open(os.path.join(dest, rel), encoding="utf-8") as f:
            out |= measurements(rel, f.read())
    return out


def built_leftovers(html, keep):
    """One message per identifier in a text file of the built HTML: the pages, print.html, the
    search index, and the table of contents.  mdbook can turn text that the staged scan cannot
    read, such as 10\\.0\\.1\\.15, into an identifier."""
    found = []
    for root, _, names in os.walk(html):
        for name in sorted(names):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, html)
            if rel.lower().endswith(IMAGES):
                continue
            with open(path, "rb") as f:
                try:
                    text = f.read().decode("utf-8")
                except UnicodeDecodeError:
                    continue
            found += [f"{kind} in {rel} line {n}" for kind, n in scan(rel, text, keep)]
    return found


def named(files):
    """One message per identifier in a staged file's path.  The replace step never renames a
    file, because a page links to it by that name."""
    return [f"{kind} in the file name {rel}" for rel in files for kind, _ in scan("name.txt", rel)]


def zip_report(docs, out):
    files = book_files(docs)
    found = named(files)
    if found:
        die("redaction: rename these files and their links: " + "; ".join(found))
    export = os.path.dirname(os.path.abspath(out))
    staged, html = os.path.join(export, "stage"), os.path.join(export, "html")
    text_files = texts(docs, files)
    stage(docs, files, text_files, staged)
    found = leftovers(staged, text_files) + includes(staged, text_files)
    if found:
        die("redaction: identifiers remain in the staged book under " + staged + ": " + "; ".join(found))
    mdbook = shutil.which("mdbook")
    if not mdbook:
        die("mdbook is required but not on PATH")
    env = dict(os.environ)
    # make passes the summary H1 as the book title; it is redacted like the pages.  mdbook
    # escapes the title as plain text, so the placeholder takes no markdown escape.
    if "MDBOOK_BOOK__TITLE" in env:
        env["MDBOOK_BOOK__TITLE"] = redact("title.txt", env["MDBOOK_BOOK__TITLE"]).strip()
    shutil.rmtree(html, ignore_errors=True)
    built = subprocess.run([mdbook, "build", "--dest-dir", html, staged], env=env, capture_output=True, text=True)
    if built.returncode != 0:
        die("mdbook build of the staged book failed: " + built.stderr.strip())
    # mdbook copies book.toml into the built HTML; it is a build input, not part of the book.
    os.remove(os.path.join(html, "book.toml"))
    found = built_leftovers(html, measured(staged, text_files))
    if found:
        die("redaction: identifiers remain in the built book under " + html + ": " + "; ".join(found))
    tmp = out + ".tmp"
    count = 0
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, names in os.walk(html):
            for name in sorted(names):
                path = os.path.join(root, name)
                z.write(path, os.path.relpath(path, html))
                count += 1
    os.replace(tmp, out)
    # The built HTML is in the zip; a stale copy under export/ would go into the next local build.
    shutil.rmtree(html)
    print(f"zip: {out} ({count} files, {len(files)} staged under {staged})")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("format", choices=["jira", "zip"])
    ap.add_argument("docs")
    ap.add_argument("out")
    args = ap.parse_args()
    if not os.path.isdir(args.docs):
        die(f"not a docs directory: {args.docs}")
    jira(args.docs, args.out) if args.format == "jira" else zip_report(args.docs, args.out)


if __name__ == "__main__":
    main()
