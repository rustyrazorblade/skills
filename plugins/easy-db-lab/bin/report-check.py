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
  - redaction: no IPv4 address, EC2 host name such as ip-10-0-1-15, 12-digit account ID, vpc-,
    subnet-, or sg- ID, or tunnel wording in the customer tiers or in data/*.csv and data/*.json.  A decimal number, the CSV value
    column, and a numeric stats table cell are measurements, not account IDs;
  - WARN for a numeral in summary prose outside the table, the Partial token, and the Unchecked
    line.

Exit codes: 0 no FAIL; 1 a FAIL; 2 a usage or I/O error; 3 a redaction FAIL, in either mode.
Without --gate it never edits a file.  With --gate, a non-redaction FAIL, or a --reason, writes
or replaces the one "⚠ Unchecked: <reasons>" line under "## Caveats" in 1-summary.md and exits
0.  A clean --gate run with no --reason removes a stale Unchecked line.  The rules are in the
plugin's references/report.md.
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

UNCHECKED = "⚠ Unchecked: "
STATS = ["samples", "min", "p50", "mean", "p95", "p99", "max", "total", "rate"]
VERDICTS = {"Confirmed", "Refuted", "Inconclusive"}
PARTIAL = re.compile(r"^Partial: stopped after step \d+$")
COMPARISON = ["Metric", "Baseline", "Candidate", "Delta", "Noise floor", "Verdict"]
FINDINGS = ["Finding", "Evidence", "Severity"]
SPAN = re.compile(r'<span class="verdict verdict-([a-z-]+)">([^<]*)</span>')
LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
HEADING = re.compile(r"^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$")
NUMBER = re.compile(r"^([+\-−]?)(\d+(?:\.\d+)?)")
MEASUREMENT = re.compile(r"^[+\-−]?\d+(?:\.\d+)?$")
ACCOUNT = "12-digit account ID"
REDACTION = [
    ("IPv4 address", re.compile(r"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])")),
    # Twelve digits that are not part of a decimal number such as 214748364800.0.
    (ACCOUNT, re.compile(r"(?<!\d)(?<!\d\.)\d{12}(?!\d)(?!\.\d)")),
    ("EC2 host name", re.compile(r"\bip-(?:\d{1,3}-){3}\d{1,3}\b")),
    ("vpc- ID", re.compile(r"\bvpc-[0-9a-f]{8,17}\b")),
    ("subnet- ID", re.compile(r"\bsubnet-[0-9a-f]{8,17}\b")),
    ("sg- ID", re.compile(r"\bsg-[0-9a-f]{8,17}\b")),
    ("tunnel wording", re.compile(r"\b(?:tunnel(?:s|ed|ing)?|socks5h?|socks|tailscale|port-forward(?:ing)?|ssh -[LD])\b", re.I)),
]
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
            for n, (line, words) in enumerate(without_measurements(rel, text), 1):
                if rel.endswith(".md") and GRAFANA.search(line):
                    self.report.fail(f"Grafana link in {rel} line {n}: download the graph with report-graph.py")
                    clean = False
                for what, pattern in REDACTION:
                    if pattern.search(words if what == ACCOUNT else line):
                        self.report.redact(f"{what} in {rel} line {n}")
                        clean = False
        if clean:
            self.report.ok("no Grafana link and no infrastructure identifier in the customer tiers and data/")


def without_measurements(rel, text):
    """Each line, paired with the line less its measurement cells: the numeric value column of a
    data/*.csv, and the numeric cells under a stat column of a stats table.  A measurement is
    never an account ID; a Node, Arm, or Unit cell can be one."""
    lines = text.splitlines()
    if rel.endswith(".csv"):
        header = next(csv.reader(lines[:1]), [])
        col = header.index("value") if "value" in header else None
        for line in lines:
            row = next(csv.reader([line]), [])
            if col is not None and col < len(row) and MEASUREMENT.match(row[col].strip()):
                row = row[:col] + row[col + 1:]
            yield line, ",".join(row)
        return
    header = None
    for line in lines:
        if re.match(r"^\|\s*Node\s*\|\s*Arm\s*\|", line):
            header = [c.strip() for c in line.split("|")]
        elif not line.lstrip().startswith("|"):
            header = None
        if header:
            cells = line.split("|")
            yield line, "|".join(c for i, c in enumerate(cells) if not (
                i < len(header) and header[i].lower() in STATS and MEASUREMENT.match(c.strip())))
        else:
            yield line, line


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
        entry = UNCHECKED + "; ".join(reasons)
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
