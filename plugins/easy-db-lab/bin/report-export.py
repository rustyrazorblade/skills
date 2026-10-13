#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pypandoc-binary>=1.13",
# ]
# ///
"""Export a lab report: the summary tier for JIRA, and the customer tiers as a zip.

Usage:
    report-export.py jira <docs> <out.txt>
    report-export.py zip <docs> <out.zip>

jira converts 1-summary.md to Atlassian wiki markup through pandoc (pypandoc-binary, so no
system install).  A Lua filter references each image by file name (!scrape-alloc.png!) for
manual attachment, turns links to .md pages into their text, and maps each verdict badge to a
colour.  It removes the writer's escape from a ( that opens no emoticon and from the sign of a
number, so "(MB/s)" and "+20.8%" stay readable.

zip takes the pages that SUMMARY.md lists before "# Appendix" (the summary, the evidence, and
nested evidence pages), plus every images/ and data/ file they reference.  A listed page outside
docs/ fails the export.  The appendix (plan,
journal, issues) is not in the zip.  A referenced file that does not exist fails the export, and
no zip is written.
"""

import argparse
import os
import re
import sys
import tempfile
import zipfile

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
        # No smart extension: it turns the -- of a flag such as --align into an en dash.
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


def customer_pages(docs):
    path = os.path.join(docs, "SUMMARY.md")
    if not os.path.exists(path):
        die(f"no SUMMARY.md in {docs}")
    pages = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if re.match(r"^#\s+Appendix\b", line):
                break
            for target in LINK_TARGET.findall(line):
                target = os.path.normpath(target.split("#")[0])
                if target.endswith(".md") and target not in pages:
                    pages.append(target)
    outside = [p for p in pages if os.path.isabs(p) or p == os.pardir or p.startswith(os.pardir + os.sep)]
    if outside:
        die("SUMMARY.md lists customer pages outside docs/: " + ", ".join(outside))
    return pages


def zip_report(docs, out):
    files, missing = [], []
    for page in customer_pages(docs):
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
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    tmp = out + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            z.write(os.path.join(docs, rel), rel)
    os.replace(tmp, out)
    print(f"zip: {out} ({len(files)} files)")


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
