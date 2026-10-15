#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Check a lab report: every summary claim against its evidence, plus redaction.

Usage:
    report-check.py [--gate [--reason TEXT]...] <docs>

It reads files only and uses no network.  It prints PASS, FAIL, or WARN per check.

The customer tiers are the pages that docs/SUMMARY.md lists before "# Appendix": 1-summary.md,
2-evidence.md, and any nested evidence/ page.  The checks:

  - the summary layout: a title that is not the template placeholder, a Verdict line with one
    of Confirmed, Refuted, Inconclusive, or "Partial: stopped after step N" and one sentence, a
    comparison or Findings table, "## What this means", and "## Caveats";
  - verdict badges: <span class="verdict verdict-<value>">Value</span>, class and text agree;
  - each comparison row: the Metric link resolves (mdbook slug rule, nested pages too) to a
    complete evidence block; the checker merges the block's CSVs, keys them by (Node, Arm),
    recomputes the baseline and candidate rollups and the delta (cand - base) / base, and
    compares the values, the sign, the size, and the unit with the row;
  - the Noise floor cell: "not measured", or a value linked to an A/A evidence block, which the
    checker recomputes as |delta| of the same statistic; Confirmed or Refuted needs |delta| above
    a present noise floor;
  - each Findings row links to a complete evidence block;
  - every evidence block has an image from images/, a stats table, a Window line, a Query line,
    and a Data link to CSVs in data/ with their JSON; malformed data (a missing column or field,
    a value that is not a number, a timestamp that is not ISO 8601) is a FAIL that names the file;
  - a Cassandra run (the plan or a journal names `cassandra use` or `cassandra start`) has a
    "Reasoning review: done" or "Reasoning review: not run (cassandra-expert not installed)" line;
  - no Grafana link in the customer tiers;
  - redaction: no SOCKS URL, IPv4 or IPv6 address, EC2 host name such as ip-10-0-1-15 or
    ec2-54-12-34-56.compute-1.amazonaws.com, 12-digit, dashed, or spaced account ID, vpc-,
    subnet-, sg-, igw-, i-, eni-, vol-, or ami- ID, port number, tunnel wording, host:port
    service URL, local home or key path, AWS profile name, SSO start URL, email address, S3 URL
    or bucket name, AWS access key ID or secret key, bearer token, or Grafana service account
    token in the customer tiers or in data/*.csv and data/*.json.  A decimal number, the CSV value column,
    a numeric stats table cell, and the last group of a UUID are not account IDs; a dotted
    version after jdk, java, or openjdk, such as JDK 11.0.20.1, is not an address, unless it
    is a private address or has a :port.  report-export.py loads the same patterns
    from this file;
  - WARN for a numeral in summary prose outside the table, the Partial token, and the Unchecked
    line.

Exit codes: 0 no FAIL; 1 a FAIL; 2 a usage or I/O error; 3 a redaction FAIL, in either mode.
Without --gate it never edits a file.  With --gate, a non-redaction FAIL, or a --reason, writes
or replaces the one "⚠ Unchecked: <reasons>" line under "## Caveats" in 1-summary.md and exits
0.  The line numbers each reason: "⚠ Unchecked: (1) <reason> (2) <reason>".  A clean --gate
run with no --reason removes a stale Unchecked line.  The rules are in the plugin's
references/report.md.
"""

import argparse
import csv
import json
import math
import os
import re
import statistics
import sys
from datetime import datetime, timezone

# --- redaction: one list for the check and for report-export.py zip ---

# REDACTION names each kind of infrastructure identifier, the pattern that finds it, and the
# placeholder that replaces it.  scan() finds what redact() would replace, so the check and the
# replace step of report-export.py, which loads this file, cannot drift.

STATS = ["samples", "min", "p50", "mean", "p95", "p99", "max", "total", "rate"]
MEASUREMENT = re.compile(r"^[+\-−]?\d+(?:\.\d+)?$")
ACCOUNT = "12-digit account ID"
_IPV4 = r"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?!\d|\.\d)"
# An IPv6 address: eight groups, or a :: form with a group on at least one side, such as
# 2600:1f18::1, fe80::, or ::1.  A time such as 12:34:56 and a MAC address have no ::, and the
# guards keep std::vector and a::before.  An address holds a digit, so Abc::Def in code stays.
_H6 = r"[0-9a-f]{1,4}"
_IPV6 = (r"(?<![\w:.])(?=[\w:]*\d)(?:(?:" + _H6 + r":){7}" + _H6 + r"|" + _H6 + r"(?::" + _H6 + r"){0,6}::(?:" + _H6 + r"(?::" + _H6
         + r"){0,6})?|::" + _H6 + r"(?::" + _H6 + r"){0,6})(?![\w:])")
_TUNNEL_WORD = r"(?:ssh -[LD](?:\s+[^\s`\"']+)?|tunnel(?:s|ed|ing)?|socks5h?|socks|tailscale|port-forward(?:ing)?)"
# The rest of a path or a URL: no space, quote, or bracket, and no sentence stop at the end.
_REST = r"(?:[^\s`\"'<>()\[\]]*[^\s`\"'<>()\[\].,;:!?])?"
# A profile value that is a name, not a variable such as "$AWS_PROFILE", a flag, or a placeholder
# that scan() has removed.
_NAME = r"[\"']?((?![$<\-\x00])[^\s\"'`;)]+)"


class Pattern:
    """A regular expression: each match is one identifier, or its group when group is set."""

    def __init__(self, pattern, flags=0, group=0):
        self.regex = re.compile(pattern, flags)
        self.group = group

    def spans(self, text):
        return [m.span(self.group) for m in self.regex.finditer(text)]


class IPv4:
    """An IPv4 address, with its :port.  A dotted version such as JDK 11.0.20.1, java version
    17.0.8.1, v1.2.3.4, or openjdk-11.0.20.1 is not one.  A quad after any other word, such as
    cassandra or kernel, is an address.  A private address (10/8, 172.16/12, 192.168/16) and a
    quad with a :port are always addresses, after a JDK word too."""

    ADDRESS = re.compile(r"(?<![\w.-])" + _IPV4 + r"(?::\d{1,5}\b)?")
    VERSION = re.compile(r"\b(?:jdk|java|openjdk)(?:\s+version)?\s+$", re.I)
    PRIVATE = re.compile(r"^(?:10\.|172\.(?:1[6-9]|2\d|3[01])\.|192\.168\.)")

    def version(self, text, m):
        return ":" not in m.group(0) and not self.PRIVATE.match(m.group(0)) and self.VERSION.search(text[:m.start()])

    def spans(self, text):
        return [m.span() for m in self.ADDRESS.finditer(text) if not self.version(text, m)]


class PortNumbers:
    """Each number in a port phrase: "port 1080", "localhost:1080", and "port changed from 1080
    to 52764".  Only the numbers are identifiers; the words stay.  A phrase starts with a number
    or a LEAD word, so "port to 5 nodes" is prose, not a port."""

    LEAD = r"(?:changed|moved|went|was|is|now|then|number|before|after)"
    FILLER = r"(?:" + LEAD + r"|from|to|and|or)"
    PHRASE = re.compile(r"\bports?(?=\s+(?:" + LEAD + r"|\d{1,5})\b)(?:\s+(?:" + FILLER + r"|\d{1,5})\b)+|\blocalhost:\d{1,5}\b", re.I)
    NUMBER = re.compile(r"\d+")

    def spans(self, text):
        return [(m.start() + n.start(), m.start() + n.end())
                for m in self.PHRASE.finditer(text) for n in self.NUMBER.finditer(m.group(0))]


# (kind, pattern, placeholder).  Matches that overlap merge under the placeholder of the widest
# one: a SOCKS URL holds its IPv4 address, and an IPv4 address holds its :port.
REDACTION = [
    ("SOCKS proxy URL", Pattern(r"\bsocks5h?://[^\s`\"')]+", re.I), "socks-proxy"),
    ("SSO start URL", Pattern(r"(?:https?://)?[\w-]+(?:\.[\w-]+)*\.awsapps\.com\b(?:/" + _REST + ")?", re.I), "sso-url"),
    ("S3 URL", Pattern(r"\bs3://" + _REST + r"|(?:https?://)?[\w.-]+\.s3(?:[.-][\w-]+)*\.amazonaws\.com\b(?:/" + _REST + ")?",
                       re.I), "s3-url"),
    ("S3 bucket name", Pattern(r"\beasy-db-lab-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I), "s3-bucket"),
    # A URL with a port, such as http://control0:3000/d/abc, or a host with a port: a host name
    # with a digit or a dot, such as control0:3000 or db0.lab.internal:9042, localhost, or a
    # bracketed IPv6 address such as [::1]:9042.  A docker tag such as postgres:16 and a label
    # such as Note:30 stay.
    ("host:port service URL", Pattern(r"\b[a-z][a-z0-9+.-]*://(?:\[[0-9a-f:.]+\]|[\w.-]+):\d{1,5}\b(?:/" + _REST + r")?"
                                      r"|(?<![\w.:/@-])(?:localhost|[a-z][\w-]*\d[\w-]*|[a-z][\w-]*(?:\.[\w-]+)+"
                                      r"|\[[0-9a-f:.]*:[0-9a-f:.]*\]):\d{2,5}\b"
                                      r"(?:/" + _REST + r")?", re.I), "service-url"),
    ("email address", Pattern(r"(?<![\w.+-])[\w.+-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}\b", re.I), "email"),
    ("local path", Pattern(r"(?<![\w.~$/-])(?:/(?:Users|home)/|(?:~|\$HOME|\$\{HOME\})/\.(?:ssh|aws|easy-db-lab)\b/?)" + _REST), "local-path"),
    # The key file of -i: a path that starts with /, ~/, ./, or ../, or a .pem, .key, or id_*
    # file.  After ssh, scp, or sftp and their options, any path, but not a placeholder, which
    # scan() makes a NUL.  The -i of sed and grep stays.
    ("key file path", Pattern(r"(?<!\S)-i\s+((?:~|\.\.?)?/" + _REST + r"|[^\s`\"'<>]*(?:\.pem\b|\.key\b|\bid_[a-z0-9]+\b)"
                              + _REST + ")", re.I, 1), "local-path"),
    ("ssh key file path", Pattern(r"\b(?:ssh|scp|sftp)(?:\s+-[a-z]\S*(?:\s+[^\s-]\S*)?)*?\s+-i\s+([^\s`\"'<>\x00]" + _REST + ")",
                                  re.I, 1), "local-path"),
    ("AWS profile name", Pattern(r"--profile(?:=|\s+)" + _NAME, 0, 1), "aws-profile"),
    ("AWS_PROFILE value", Pattern(r"\bAWS_PROFILE=" + _NAME, 0, 1), "aws-profile"),
    ("AccountUser role", Pattern(r"\bAccountUser-[\w-]+"), "aws-profile"),
    # Credentials.  A secret is the value after aws_secret_access_key, or 40 base64 characters
    # after a secret word; a variable such as "$AWS_SECRET" stays.  A bearer token is 16 or more
    # token characters, so "a Bearer token" stays, and it does not end in a period.
    ("AWS access key ID", Pattern(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"), "aws-access-key"),
    ("AWS secret access key", Pattern(r"\baws_secret_access_key[\"']?\s*[=:]\s*[\"']?((?![$<\x00])[^\s\"'`<>\x00]+)", re.I, 1),
     "aws-secret"),
    ("AWS secret key", Pattern(r"secret[\w-]*[\"']?\s*[=:]?\s*[\"']?([A-Za-z0-9/+]{40})(?![A-Za-z0-9/+])", re.I, 1),
     "aws-secret"),
    ("bearer token", Pattern(r"\bBearer\s+([\w.~+/-]{15,}[\w~+/-]=*)", re.I, 1), "token"),
    ("Grafana service account token", Pattern(r"\bglsa_[A-Za-z0-9_]+"), "token"),
    # Before IPv4, so that ::ffff:10.0.1.15 is one <ipv6>.
    ("IPv6 address", Pattern(_IPV6, re.I), "ipv6"),
    ("IPv4 address", IPv4(), "private-ip"),
    ("EC2 host name", Pattern(r"\bip-(?:\d{1,3}-){3}\d{1,3}\b"), "ec2-host"),
    ("public EC2 DNS name", Pattern(r"\bec2-(?:\d{1,3}-){3}\d{1,3}(?:(?:\.[a-z0-9-]+)*\.amazonaws\.com)?\b", re.I), "ec2-host"),
    # Twelve digits that are not part of a decimal number such as 214748364800.0, and not the
    # last group of a UUID such as a cluster label.
    (ACCOUNT, Pattern(r"(?<!\d)(?<!\d\.)(?<![0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-)\d{12}(?!\d)(?!\.\d)", re.I),
     "account-id"),
    # The console form of an account ID, such as 4178-3501-3894; not a group of a UUID.
    ("dashed account ID", Pattern(r"(?<![\w-])\d{4}-\d{4}-\d{4}(?![\w-])"), "account-id"),
    # The spaced form, such as 4178 3501 3894: three groups exactly, at most three words after
    # an account cue (account, acct, AWS, or owner), so "heap 1024 2048 4096" stays.  A row of
    # four or more 4-digit numbers, or one that ends in a decimal, stays.  A sentence period
    # can end it.
    ("spaced account ID", Pattern(r"\b(?:accounts?|acct|aws|owner)\b(?:[^\w\n]+\w+){0,3}?[^\w\n]+"
                                  r"((?<![\w.-])(?<!\d )\d{4} \d{4} \d{4}(?![\w-]|\.\d)(?! \d))", re.I, 1), "account-id"),
    ("vpc- ID", Pattern(r"\bvpc-[0-9a-f]{8,17}\b"), "vpc-id"),
    ("subnet- ID", Pattern(r"\bsubnet-[0-9a-f]{8,17}\b"), "subnet-id"),
    ("sg- ID", Pattern(r"\bsg-[0-9a-f]{8,17}\b"), "sg-id"),
    ("igw- ID", Pattern(r"\bigw-[0-9a-f]{8,17}\b"), "igw-id"),
    ("i- ID", Pattern(r"\bi-[0-9a-f]{8,17}\b"), "instance-id"),
    ("eni- ID", Pattern(r"\beni-[0-9a-f]{8,17}\b"), "eni-id"),
    ("vol- ID", Pattern(r"\bvol-[0-9a-f]{8,17}\b"), "volume-id"),
    ("ami- ID", Pattern(r"\bami-[0-9a-f]{8,17}\b"), "ami-id"),
    ("port number", PortNumbers(), "port"),
    ("tunnel wording", Pattern(r"\b" + _TUNNEL_WORD + r"\b(?:\s+" + _TUNNEL_WORD + r"\b)*", re.I), "tunnel"),
]
_NAMES = "|".join(sorted({p for _, _, p in REDACTION}, key=len, reverse=True))
# A placeholder as redact() writes it, \<kind> or <kind>, or as mdbook writes it, &lt;kind&gt;.
PLACEHOLDER = re.compile(r"(?:\\?<|&lt;)(?:" + _NAMES + r")(?:>|&gt;)")
# A link fragment: in markdown ](page.md#frag); in HTML href="page.html#frag" and id="frag"; and
# in the search index, "page.html#frag".
# mdbook makes a heading id from the redacted heading, so a fragment can hold a placeholder name
# such as tunnel-setup.  redact() never changes a fragment; scan() reads a placeholder name in
# one as a placeholder, and any other identifier in one fails.
FRAGMENT = re.compile(r"(\]\([^)\s#]*#|\bhref=\"[^\"#]*#|[\w./-]+\.html#|\bid=\")([^)\s\"]+)")
FRAGMENT_NAME = re.compile(r"(?<![a-z0-9])(?:" + _NAMES + r")(?![a-z0-9])")
# The wrapper variables: $EDB, ${EDB}, $EDB_<ARM>, and ${EDB_<ARM>}.  EDB_LAB_BIN is not one.
WRAPPER = re.compile(r"\$\{EDB(?:_(?!LAB_BIN\b)[A-Z0-9_]+)?\}|\$EDB(?:_(?!LAB_BIN\b)[A-Z0-9_]+)?\b")
COMMAND = "easy-db-lab"
FENCE = re.compile(r"^\s*(```|~~~)")
CODE_SPAN = re.compile(r"(`+)(.+?)\1")


def measurement_spans(rel, text):
    """Each line, paired with the (start, end) spans of its measurement cells: the numeric value
    column of a data/*.csv, and the numeric cells under a stat column of a stats table.  A
    measurement is never an account ID; a Node, Arm, or Unit cell can be one."""
    lines = text.splitlines()
    if rel.endswith(".csv"):
        header = next(csv.reader(lines[:1]), [])
        col = header.index("value") if "value" in header else None
        for line in lines:
            row = next(csv.reader([line]), [])
            cells = line.split(",")
            if col is not None and len(cells) == len(row) and col < len(row) and MEASUREMENT.match(row[col].strip()):
                start = sum(len(c) + 1 for c in cells[:col])
                yield line, [(start, start + len(cells[col]))]
            else:
                yield line, []
        return
    header = None
    for line in lines:
        if re.match(r"^\|\s*Node\s*\|\s*Arm\s*\|", line):
            header = [c.strip() for c in line.split("|")]
        elif not line.lstrip().startswith("|"):
            header = None
        spans = []
        if header:
            start = 0
            for i, cell in enumerate(line.split("|")):
                if i < len(header) and header[i].lower() in STATS and MEASUREMENT.match(cell.strip()):
                    spans.append((start, start + len(cell)))
                start += len(cell) + 1
        yield line, spans


def without_measurements(rel, text):
    """Each line, paired with the line less its measurement cells."""
    for line, spans in measurement_spans(rel, text):
        words, last = [], 0
        for start, end in spans:
            words.append(line[last:start])
            last = end
        words.append(line[last:])
        yield line, "".join(words)


def measurements(rel, text):
    """The text of each measurement cell in the file."""
    return {line[s:e].strip() for line, spans in measurement_spans(rel, text) for s, e in spans}


def scan(rel, text, keep=frozenset()):
    """(kind, line number) for each infrastructure identifier that remains.  A placeholder is
    not an identifier.  It becomes a NUL, not a space, so that "--profile <aws-profile> s3"
    does not read s3 as the profile.  keep holds measurements from the staged markdown: in the
    built HTML, where no stats table is markdown, such a number is not an account ID."""
    found = []
    kept = re.compile(r"(?<!\d)(?:" + "|".join(map(re.escape, sorted(keep))) + r")(?![\d])") if keep else None
    for n, (line, words) in enumerate(without_measurements(rel, text), 1):
        line, words = (FRAGMENT.sub(lambda m: m.group(1) + FRAGMENT_NAME.sub("\x00", m.group(2)), PLACEHOLDER.sub("\x00", t))
                       for t in (line, words))
        if kept:
            words = kept.sub("\x00", words)
        for kind, pattern, _ in REDACTION:
            if pattern.spans(words if kind == ACCOUNT else line):
                found.append((kind, n))
    return found


def _replace(segment, placeholder, protected, offset):
    """Replace each identifier in segment, in one pass over the original text.  Matches that
    overlap merge, and one placeholder covers the merged text: the placeholder of the widest
    match, or of the earlier kind when two are as wide.  So "ssh -L 9042:10.0.0.1:9042" becomes
    one <tunnel>.  A match inside a placeholder or a link fragment stays, so the replace step
    can run twice and a fragment keeps pointing at its heading.  The account pattern keeps a
    measurement cell; protected spans are line offsets, and segment starts at offset in the
    line."""
    kept = [m.span() for m in PLACEHOLDER.finditer(segment)] + [m.span(2) for m in FRAGMENT.finditer(segment)]
    found = []
    for rank, (kind, pattern, name) in enumerate(REDACTION):
        for start, end in pattern.spans(segment):
            if kind == ACCOUNT and any(a <= offset + start < b for a, b in protected):
                continue
            if any(a <= start and end <= b for a, b in kept):
                continue
            found.append((start, end, rank, name))
    chosen = []
    for start, end, rank, name in sorted(found):
        if chosen and start < chosen[-1][1]:
            s, e, widest = chosen[-1]
            if (end - start, -rank) > widest[0]:
                widest = ((end - start, -rank), name)
            chosen[-1] = (s, max(e, end), widest)
        else:
            chosen.append((start, end, ((end - start, -rank), name)))
    out, last = [], 0
    for start, end, (_, name) in chosen:
        out.append(WRAPPER.sub(COMMAND, segment[last:start]))
        out.append(placeholder(name))
        last = end
    out.append(WRAPPER.sub(COMMAND, segment[last:]))
    return "".join(out)


def redact(rel, text):
    """The text with each identifier replaced by its <kind> placeholder and each wrapper variable
    by the command name.  In a markdown page, a placeholder outside code is escaped as \\<kind>,
    so that mdbook shows it rather than read it as an HTML tag.  In an SVG, HTML, or XML file it
    is &lt;kind&gt;, so that the file stays well formed."""
    raw = lambda name: f"<{name}>"
    if rel.lower().endswith((".svg", ".html", ".htm", ".xml")):
        raw = lambda name: f"&lt;{name}&gt;"
    escaped = lambda name: f"\\<{name}>"
    markdown = rel.endswith(".md")
    out, fenced = [], False
    for line, spans in measurement_spans(rel, text):
        if not markdown:
            out.append(_replace(line, raw, spans, 0))
            continue
        if FENCE.match(line):
            fenced = not fenced
            out.append(_replace(line, raw, spans, 0))
            continue
        if fenced:
            out.append(_replace(line, raw, spans, 0))
            continue
        parts, last = [], 0
        for m in CODE_SPAN.finditer(line):
            parts.append(_replace(line[last:m.start()], escaped, spans, last))
            parts.append(_replace(m.group(0), raw, spans, m.start()))
            last = m.end()
        parts.append(_replace(line[last:], escaped, spans, last))
        out.append("".join(parts))
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


# --- the check ---

UNCHECKED = "⚠ Unchecked: "
VERDICTS = {"Confirmed", "Refuted", "Inconclusive"}
PARTIAL = re.compile(r"^Partial: stopped after step \d+$")
COMPARISON = ["Metric", "Baseline", "Candidate", "Delta", "Noise floor", "Verdict"]
FINDINGS = ["Finding", "Evidence", "Severity"]
SPAN = re.compile(r'<span class="verdict verdict-([a-z-]+)">([^<]*)</span>')
LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
HEADING = re.compile(r"^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$")
NUMBER = re.compile(r"^([+\-−]?)(\d+(?:\.\d+)?)")
GRAFANA = re.compile(r"https?://[^\s)]*(?:grafana|/d/[A-Za-z0-9_-]+|/d-solo/|/render/)[^\s)]*", re.I)
CASSANDRA_RUN = re.compile(r"\bcassandra\s+(?:use|start)\b")


class Usage(Exception):
    pass


class Report:
    def __init__(self):
        self.fails, self.redactions, self.warns = [], [], []

    def ok(self, msg):
        print(f"PASS: {msg}")

    def fail(self, msg):
        print(f"FAIL: {msg}")
        self.fails.append(msg)

    def redact(self, msg):
        print(f"FAIL: redaction: {msg}")
        self.redactions.append(msg)

    def warn(self, msg):
        print(f"WARN: {msg}")
        self.warns.append(msg)


# --- pages, sections, and slugs ---


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_comments(text):
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def scaffold_only(text):
    """True when the file holds only headings, one-line comments, and blank lines."""
    return all(re.match(r"^\s*(#|<!--.*-->\s*$|$)", line) for line in text.splitlines())


def slug(text):
    """mdbook's id rule: keep alphanumerics, _ and -, lowercased; whitespace becomes -."""
    text = re.sub(r"[`*]", "", text)
    text = LINK.sub(r"\1", text)
    out = []
    for ch in text:
        if ch.isalnum() or ch in "_-":
            out.append(ch.lower())
        elif ch.isspace():
            out.append("-")
    return "".join(out)


def sections(text):
    """Split a page into sections: (title, slug, lines), one per heading."""
    out, used, current, in_fence = [], {}, None, False
    for line in text.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
        m = None if in_fence else HEADING.match(line)
        if m:
            base = slug(m.group(2))
            n = used.get(base, 0)
            used[base] = n + 1
            current = (m.group(2), base if n == 0 else f"{base}-{n}", [])
            out.append(current)
        elif current is not None:
            current[2].append(line)
    return out


def customer_pages(docs):
    """Pages before # Appendix in SUMMARY.md, as docs-relative paths."""
    summary = os.path.join(docs, "SUMMARY.md")
    if not os.path.exists(summary):
        return [p for p in ("1-summary.md", "2-evidence.md") if os.path.exists(os.path.join(docs, p))]
    pages = []
    for line in read(summary).splitlines():
        if re.match(r"^#\s+Appendix\b", line):
            break
        for _, target in LINK.findall(line):
            target = os.path.normpath(target.split("#")[0])
            if target.endswith(".md") and target not in pages:
                pages.append(target)
    return pages


def outside_docs(page):
    """True for a docs-relative path that leaves docs/: absolute, or one that starts with ..."""
    return os.path.isabs(page) or page == os.pardir or page.startswith(os.pardir + os.sep)


# --- evidence blocks ---


class Block:
    def __init__(self, page, title, anchor, lines):
        self.page, self.title, self.anchor = page, title, anchor
        self.images, self.has_table, self.windows, self.query, self.csvs = [], False, [], None, []
        self.evidence = None
        for line in lines:
            m = re.match(r"^!\[[^\]]*\]\(([^)\s]+)\)", line)
            if m:
                self.images.append(m.group(1))
            if re.match(r"^\|\s*Node\s*\|\s*Arm\s*\|", line):
                self.has_table = True
            if re.match(r"^Window( \([^)]*\))?: ", line):
                self.windows.append(line)
            m = re.match(r"^Query( \([^)]*\))?: `(.*)`\s*$", line)
            if m:
                self.query = m.group(2)
            if line.startswith("Data: "):
                self.csvs += [t for _, t in LINK.findall(line) if t.endswith(".csv")]

    @property
    def name(self):
        return f"{self.page}#{self.anchor}"

    def is_block(self):
        return bool(self.images or self.has_table or self.windows or self.query or self.csvs)


def resolve(docs, page, target):
    """A link target relative to a page, as a docs-relative path, or None outside docs."""
    path = os.path.normpath(os.path.join(os.path.dirname(page), target))
    return None if path.startswith("..") or os.path.isabs(path) else path


def check_block(docs, block, report):
    """Report a block as PASS or FAIL.  Returns True when it is complete."""
    missing = []
    if not block.images:
        missing.append("image")
    if not block.has_table:
        missing.append("stats table")
    if not block.windows:
        missing.append("Window line")
    if block.query is None:
        missing.append("Query line")
    if not block.csvs:
        missing.append("Data link")
    for img in block.images:
        if re.match(r"^[a-z]+://", img):
            missing.append(f"a downloaded image (it links {img.split('/')[2]})")
            continue
        path = resolve(docs, block.page, img)
        if path is None or not path.startswith("images" + os.sep) or not os.path.exists(os.path.join(docs, path)):
            missing.append(f"the image file {img} in images/")
    for c in block.csvs:
        path = resolve(docs, block.page, c)
        if path is None or not path.startswith("data" + os.sep) or not os.path.exists(os.path.join(docs, path)):
            missing.append(f"the data file {c} in data/")
        elif not os.path.exists(os.path.join(docs, os.path.splitext(path)[0] + ".json")):
            missing.append(f"the metadata JSON next to {c}")
    if missing:
        report.fail(f"evidence block {block.name}: no {', no '.join(missing)}")
        return False
    try:
        block.evidence = Evidence(docs, block)
    except BadData as e:
        report.fail(f"evidence block {block.name}: malformed data: {e}")
        return False
    report.ok(f"evidence block {block.name}")
    return True


# --- statistics from CSV ---


def parse_time(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)


def quantile(vals, q):
    return vals[0] if len(vals) == 1 else statistics.quantiles(vals, n=100, method="inclusive")[q - 1]


def arm_stat(series, seconds, stat):
    """A statistic for one arm from the pooled samples of its nodes."""
    vals = sorted(v for points in series for _, v in points)
    total = sum(points[-1][1] - points[0][1] for points in series)
    return {
        "samples": lambda: len(vals), "min": lambda: vals[0], "p50": lambda: statistics.median(vals),
        "mean": lambda: statistics.fmean(vals), "p95": lambda: quantile(vals, 95),
        "p99": lambda: quantile(vals, 99), "max": lambda: vals[-1], "total": lambda: total,
        "rate": lambda: total / seconds if seconds else 0.0,
    }[stat]()


class BadData(Exception):
    """Evidence data that cannot be read: the message names the data file and the problem."""


class Evidence:
    """The merged CSVs of one block, keyed by (Node, Arm).  Raises BadData on malformed data."""

    def __init__(self, docs, block):
        self.series, self.window, self.units = {}, {}, set()
        for c in block.csvs:
            rel = resolve(docs, block.page, c)
            meta_rel = os.path.splitext(rel)[0] + ".json"
            meta = self.metadata(os.path.join(docs, meta_rel), meta_rel)
            self.units.add(meta["unit"])
            with open(os.path.join(docs, rel), newline="") as f:
                reader = csv.DictReader(f)
                missing = [k for k in ("timestamp_utc", "node", "arm", "value") if k not in (reader.fieldnames or [])]
                if missing:
                    raise BadData(f"{rel}: no {', no '.join(missing)} column")
                for n, r in enumerate(reader, 2):
                    try:
                        t = parse_time(r["timestamp_utc"])
                    except (AttributeError, TypeError, ValueError):
                        raise BadData(f"{rel} line {n}: the timestamp {r['timestamp_utc']!r} is not ISO 8601") from None
                    try:
                        v = float(r["value"])
                    except (TypeError, ValueError):
                        raise BadData(f"{rel} line {n}: the value {r['value']!r} is not a number") from None
                    self.series.setdefault((r["node"], r["arm"]), []).append((t, v))
                    window = (meta["start"], meta["end"])
                    if self.window.setdefault(r["arm"], window) != window:
                        raise BadData(f"{rel}: the arm {r['arm']} has two windows; another CSV of the block "
                                      "gives it a different start or end")
        for points in self.series.values():
            points.sort()

    @staticmethod
    def metadata(path, rel):
        try:
            with open(path, encoding="utf-8") as f:
                meta = json.load(f)
        except ValueError as e:
            raise BadData(f"{rel}: not valid JSON: {e}") from None
        if not isinstance(meta, dict):
            raise BadData(f"{rel}: not a JSON object")
        missing = [k for k in ("start", "end", "unit") if k not in meta]
        if missing:
            raise BadData(f"{rel}: no {', no '.join(missing)} field")
        try:
            return {**meta, "start": parse_time(meta["start"]), "end": parse_time(meta["end"])}
        except (AttributeError, TypeError, ValueError):
            raise BadData(f"{rel}: the start {meta['start']!r} or the end {meta['end']!r} cannot be read") from None

    def arms(self):
        return {arm for _, arm in self.series}

    def stat(self, arm, stat):
        start, end = self.window[arm]
        return arm_stat([p for (_, a), p in self.series.items() if a == arm], (end - start).total_seconds(), stat)


# --- the summary ---


def decimals(text):
    return len(text.split(".")[1]) if "." in text else 0


def number(cell):
    m = NUMBER.match(cell.strip().replace(",", ""))
    if not m:
        return None, 0
    v = float(m.group(2))
    return (-v if m.group(1) in "-−" and m.group(1) else v), decimals(m.group(2))


def tolerance(places, floor=0.0):
    return max(floor, 0.5 * 10 ** -places * (1 + 1e-6)) + 1e-9


def verdict_value(text, report, where):
    """Check one verdict badge; return its value or None."""
    m = SPAN.search(text)
    if not m:
        report.fail(f"{where}: no verdict badge <span class=\"verdict verdict-<value>\">Value</span>")
        return None
    cls, value = m.group(1), m.group(2).strip()
    if value not in VERDICTS and not PARTIAL.match(value):
        report.fail(f"{where}: verdict {value!r} is not Confirmed, Refuted, Inconclusive, or \"Partial: stopped after step N\"")
        return None
    if cls != value.split(":")[0].lower():
        report.fail(f"{where}: verdict class verdict-{cls} does not agree with the text {value!r}")
        return None
    return value


def table(lines):
    """The first markdown table: (header cells, row cell lists)."""
    rows = []
    for line in lines:
        if line.lstrip().startswith("|"):
            rows.append([c.strip() for c in line.strip().strip("|").split("|")])
        elif rows:
            break
    if len(rows) < 2:
        return None, []
    return rows[0], [r for r in rows[2:] if any(r)]


class Checker:
    def __init__(self, docs, report):
        self.docs, self.report = docs, report
        pages = customer_pages(docs)
        self.outside = [p for p in pages if outside_docs(p)]
        self.pages = [p for p in pages if not outside_docs(p)]
        self.blocks = {}

    def load_blocks(self):
        for page in self.outside:
            self.report.fail(f"SUMMARY.md lists {page}, which is outside docs/; every customer page must be under docs/")
        for page in self.pages:
            if page == "1-summary.md":
                continue
            path = os.path.join(self.docs, page)
            if not os.path.exists(path):
                self.report.fail(f"SUMMARY.md lists {page}, but the file is missing")
                continue
            for title, anchor, lines in sections(read(path)):
                b = Block(page, title, anchor, lines)
                if b.is_block():
                    self.blocks[b.name] = (b, check_block(self.docs, b, self.report))

    def block_for(self, target, where):
        """Follow a summary link to a complete evidence block, or report a FAIL."""
        if "#" not in target:
            self.report.fail(f"{where}: the link {target} names no evidence anchor")
            return None
        page, anchor = target.split("#", 1)
        page = resolve(self.docs, "1-summary.md", page)
        key = f"{page}#{anchor}"
        if key not in self.blocks:
            self.report.fail(f"{where}: the anchor {target} is not an evidence block in the customer tiers")
            return None
        block, complete = self.blocks[key]
        if not complete:
            self.report.fail(f"{where}: its evidence block {key} is incomplete")
            return None
        return block

    def summary(self, text):
        lines = text.splitlines()
        title = next((l for l in lines if re.match(r"^#(\s|$)", l)), None)
        if title is None or not strip_comments(title.lstrip("#")).strip():
            self.report.fail("summary title is empty or the template placeholder")
        else:
            self.report.ok(f"summary title: {strip_comments(title.lstrip('#')).strip()}")

        vline = next((l for l in lines if re.match(r"^(\*\*)?Verdict:", l)), None)
        if vline is None:
            self.report.fail("summary has no Verdict line")
        else:
            value = verdict_value(vline, self.report, "Verdict line")
            rest = SPAN.sub("", vline.split(":", 1)[1]).strip(" .*")
            if value is not None and not rest:
                self.report.fail("Verdict line needs one sentence after the verdict")
            elif value is not None:
                self.report.ok(f"Verdict line: {value}")

        for heading in ("## What this means", "## Caveats"):
            if heading in lines:
                self.report.ok(f"summary has {heading}")
            else:
                self.report.fail(f"summary has no {heading} section")

        header, rows = table(lines)
        if header == COMPARISON:
            for row in rows:
                self.comparison_row(row)
        elif header == FINDINGS:
            for row in rows:
                self.finding_row(row)
        else:
            self.report.fail("summary table is neither the comparison table (" + ", ".join(COMPARISON)
                             + ") nor the Findings table (" + ", ".join(FINDINGS) + ")")

        self.reasoning(lines)
        self.numerals(lines)

    def comparison_row(self, row):
        if len(row) != len(COMPARISON):
            self.report.fail(f"comparison row has {len(row)} cells, not {len(COMPARISON)}: {' | '.join(row)}")
            return
        metric, base_cell, cand_cell, delta_cell, noise_cell, verdict_cell = row
        m = LINK.search(metric)
        if not m:
            self.report.fail(f"row {metric}: the Metric cell links to no evidence anchor")
            return
        name, target = m.groups()
        where = f"row {name}"
        stat = next((s for s in STATS if re.search(rf"\b{s}\b", name, re.I)), None)
        unit = re.search(r"\(([^()]+)\)\s*$", name)
        verdict = verdict_value(verdict_cell, self.report, f"{where} Verdict")
        if stat is None:
            self.report.fail(f"{where}: the Metric cell names no statistic ({', '.join(STATS)})")
            return
        if unit is None:
            self.report.fail(f"{where}: the Metric cell names no unit, for example (MB/s)")
            return
        block = self.block_for(target, where)
        if block is None:
            return
        ev = block.evidence
        if unit.group(1) not in ev.units:
            self.report.fail(f"{where}: unit {unit.group(1)} differs from the evidence JSON unit {', '.join(sorted(ev.units))}")
            return
        if not {"baseline", "candidate"} <= ev.arms():
            self.report.fail(f"{where}: the evidence needs the arms baseline and candidate, it has {', '.join(sorted(ev.arms()))}")
            return
        base, cand = ev.stat("baseline", stat), ev.stat("candidate", stat)
        ok = True
        for label, cell, actual in (("Baseline", base_cell, base), ("Candidate", cand_cell, cand)):
            v, places = number(cell)
            if v is None:
                self.report.fail(f"{where}: {label} {cell!r} is not a number")
                ok = False
            elif abs(v - actual) > tolerance(places):
                self.report.fail(f"{where}: {label} {cell} differs from the evidence value {actual:.4g}")
                ok = False
        if base == 0:
            self.report.fail(f"{where}: the baseline is zero, so the delta is not defined")
            return
        delta = (cand - base) / base * 100
        claim, places = number(delta_cell.rstrip("%").strip())
        if claim is None or not delta_cell.strip().endswith("%"):
            self.report.fail(f"{where}: Delta {delta_cell!r} is not a percentage such as +20.8%")
            ok = False
        elif claim != 0 and delta != 0 and (claim > 0) != (delta > 0):
            self.report.fail(f"{where}: Delta {delta_cell} has the wrong sign; the evidence gives {delta:+.1f}%")
            ok = False
        elif abs(claim - delta) > tolerance(places, 0.1):
            self.report.fail(f"{where}: Delta {delta_cell} differs in size from the evidence {delta:+.1f}%")
            ok = False
        if ok:
            self.report.ok(f"{where}: {stat} baseline {base:.4g}, candidate {cand:.4g}, delta {delta:+.1f}%")
        self.noise(name, noise_cell, stat, delta, verdict)

    def noise(self, name, cell, stat, delta, verdict):
        where = f"noise floor {name}"
        if cell.strip().lower() == "not measured":
            self.report.ok(f"{where}: not measured")
            return
        m = LINK.fullmatch(cell.strip())
        if not m:
            if number(cell)[0] is not None:
                self.report.fail(f"{where}: the value {cell} must link to the evidence block it came from")
            else:
                self.report.fail(f"{where}: {cell!r} is empty or not numeric; write a linked value or \"not measured\"")
            return
        text, target = m.groups()
        claim, places = number(text.rstrip("%"))
        if claim is None or not text.strip().endswith("%"):
            self.report.fail(f"{where}: {text!r} is not a percentage such as 1.2%")
            return
        block = self.block_for(target, where)
        if block is None:
            return
        ev = block.evidence
        if not {"baseline", "candidate"} <= ev.arms():
            self.report.fail(f"{where}: the A/A evidence needs the arms baseline and candidate")
            return
        base, cand = ev.stat("baseline", stat), ev.stat("candidate", stat)
        floor = abs(cand - base) / base * 100 if base else math.inf
        if abs(claim - floor) > tolerance(places, 0.1):
            self.report.fail(f"{where}: {text} differs from the evidence {floor:.1f}%")
            return
        if verdict in ("Confirmed", "Refuted") and abs(delta) <= floor:
            self.report.fail(f"{where}: {verdict} needs |delta| {abs(delta):.1f}% above the noise floor {floor:.1f}%")
            return
        self.report.ok(f"{where}: {floor:.1f}%")

    def finding_row(self, row):
        if len(row) != len(FINDINGS):
            self.report.fail(f"Findings row has {len(row)} cells, not {len(FINDINGS)}: {' | '.join(row)}")
            return
        finding, evidence, _ = row
        links = LINK.findall(evidence)
        if not links:
            self.report.fail(f"finding {finding}: the Evidence cell links to no evidence block")
            return
        if all(self.block_for(t, f"finding {finding}") for _, t in links):
            self.report.ok(f"finding {finding}")

    def reasoning(self, lines):
        names = os.listdir(self.docs)
        sources = [n for n in names if re.match(r"^[34]-(plan|journal)(-[^/]+)?\.md$", n)]
        cassandra = any(CASSANDRA_RUN.search(read(os.path.join(self.docs, n))) for n in sources)
        line = next((l.strip() for l in lines if l.startswith("Reasoning review:")), None)
        if line is not None and line not in ("Reasoning review: done",
                                             "Reasoning review: not run (cassandra-expert not installed)"):
            self.report.fail(f"the Reasoning review line {line!r} is not \"done\" or \"not run (cassandra-expert not installed)\"")
        elif cassandra and line is None:
            self.report.fail("Cassandra run: the summary has no Reasoning review line")
        elif cassandra:
            self.report.ok(f"Cassandra run: {line}")

    def numerals(self, lines):
        in_table, in_comment = False, False
        for n, line in enumerate(lines, 1):
            if "<!--" in line and "-->" not in line:
                in_comment = True
            if in_comment:
                in_comment = "-->" not in line
                continue
            if line.lstrip().startswith("|") or line.startswith("#") or line.startswith(UNCHECKED):
                continue
            text = strip_comments(line)
            text = SPAN.sub(lambda m: "" if PARTIAL.match(m.group(2).strip()) else m.group(2), text)
            text = re.sub(r"`[^`]*`", "", LINK.sub(r"\1", text))
            if re.search(r"(?<![A-Za-z0-9_.\-])\d+(?:\.\d+)?%?", text):
                self.report.warn(f"numeral in summary prose, line {n}: state each number once, in its evidence block")

    def grafana_and_redaction(self):
        files = [p for p in self.pages if os.path.exists(os.path.join(self.docs, p))]
        data = os.path.join(self.docs, "data")
        if os.path.isdir(data):
            files += [os.path.join("data", n) for n in sorted(os.listdir(data)) if n.endswith((".csv", ".json"))]
        clean = True
        for rel in files:
            text = read(os.path.join(self.docs, rel))
            if rel.endswith(".md"):
                for n, line in enumerate(text.splitlines(), 1):
                    if GRAFANA.search(line):
                        self.report.fail(f"Grafana link in {rel} line {n}: download the graph with report-graph.py")
                        clean = False
            for what, n in scan(rel, text):
                self.report.redact(f"{what} in {rel} line {n}")
                clean = False
        if clean:
            self.report.ok("no Grafana link and no infrastructure identifier in the customer tiers and data/")


def gate(docs, reasons):
    """Write, replace, or remove the one Unchecked line under ## Caveats."""
    path = os.path.join(docs, "1-summary.md")
    lines = read(path).splitlines()
    kept, skip_blank, stale = [], False, False
    for line in lines:
        if line.startswith(UNCHECKED):
            stale, skip_blank = True, True
            continue
        if skip_blank and line == "":
            skip_blank = False
            continue
        skip_blank = False
        kept.append(line)
    if reasons:
        # A reason can hold a ; or a newline: number each one, and keep the line one line.
        entry = UNCHECKED + " ".join(f"({n}) {' '.join(r.split())}" for n, r in enumerate(reasons, 1))
        if "## Caveats" in kept:
            i = kept.index("## Caveats")
            kept[i + 1:i + 1] = ["", entry]
        else:
            kept += ["", "## Caveats", "", entry]
        print("GATE: wrote the Unchecked line under ## Caveats")
    elif stale:
        print("GATE: removed a stale Unchecked line")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(kept).rstrip("\n") + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--gate", action="store_true", help="teardown gate: write the Unchecked line and exit 0")
    ap.add_argument("--reason", action="append", default=[], help="a reason from the check subagent or cassandra-expert")
    ap.add_argument("docs")
    args = ap.parse_args()
    if args.reason and not args.gate:
        ap.error("--reason needs --gate")

    docs = args.docs
    summary_path = os.path.join(docs, "1-summary.md")
    try:
        if not os.path.isdir(docs):
            raise Usage(f"not a docs directory: {docs}")
        if not os.path.exists(summary_path):
            raise Usage(f"no 1-summary.md in {docs}")
        report = Report()
        checker = Checker(docs, report)
        checker.load_blocks()
        text = read(summary_path)
        if scaffold_only(text):
            report.warn("1-summary.md holds only scaffold content; there is no claim to check")
        else:
            checker.summary(text)
        checker.grafana_and_redaction()
    except Usage as e:
        print(f"report-check: {e}", file=sys.stderr)
        sys.exit(2)
    except (OSError, ValueError, KeyError) as e:
        print(f"report-check: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(2)

    print(f"report-check: {len(report.fails) + len(report.redactions)} failed ({len(report.redactions)} redaction), {len(report.warns)} warnings")
    if report.redactions:
        print("report-check: a redaction FAIL blocks the upload; fix the customer tiers and data/", file=sys.stderr)
        sys.exit(3)
    if args.gate:
        gate(docs, report.fails + args.reason)
        sys.exit(0)
    sys.exit(1 if report.fails else 0)


if __name__ == "__main__":
    main()
