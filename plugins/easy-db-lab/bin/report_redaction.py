"""The redaction rule of the lab report, shared by report-check.py and report-export.py.

One list, REDACTION, names each kind of infrastructure identifier, the pattern that finds it,
and the placeholder that replaces it.  scan() finds what redact() would replace, so the check
and the replace step cannot drift.  A measurement (the numeric value column of a data/*.csv,
and a numeric cell under a stat column of a stats table) is never an account ID.  The rules are
in the plugin's references/report.md.
"""

import csv
import re

STATS = ["samples", "min", "p50", "mean", "p95", "p99", "max", "total", "rate"]
MEASUREMENT = re.compile(r"^[+\-−]?\d+(?:\.\d+)?$")
ACCOUNT = "12-digit account ID"
_IPV4 = r"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?!\d|\.\d)"
_TUNNEL_WORD = r"(?:ssh -[LD](?:\s+[^\s`\"']+)?|tunnel(?:s|ed|ing)?|socks5h?|socks|tailscale|port-forward(?:ing)?)"


class Pattern:
    """A regular expression: each match is one identifier."""

    def __init__(self, pattern, flags=0):
        self.regex = re.compile(pattern, flags)

    def spans(self, text):
        return [m.span() for m in self.regex.finditer(text)]


class PortNumbers:
    """Each number in a port phrase: "port 1080", "localhost:1080", and "port changed from 1080
    to 52764".  Only the numbers are identifiers; the words stay."""

    FILLER = r"(?:changed|moved|went|from|to|and|or|was|is|now|then|number|before|after)"
    PHRASE = re.compile(r"\bports?(?:\s+(?:" + FILLER + r"|\d{1,5})\b)+|\blocalhost:\d{1,5}\b", re.I)
    NUMBER = re.compile(r"\d+")

    def spans(self, text):
        return [(m.start() + n.start(), m.start() + n.end())
                for m in self.PHRASE.finditer(text) for n in self.NUMBER.finditer(m.group(0))]


# (kind, pattern, placeholder).  An earlier kind wins an overlap: a SOCKS URL holds its IPv4
# address, and an IPv4 address holds its :port.
REDACTION = [
    ("SOCKS proxy URL", Pattern(r"\bsocks5h?://[^\s`\"')]+", re.I), "socks-proxy"),
    ("IPv4 address", Pattern(_IPV4 + r"(?::\d{1,5}\b)?"), "private-ip"),
    ("EC2 host name", Pattern(r"\bip-(?:\d{1,3}-){3}\d{1,3}\b"), "ec2-host"),
    # Twelve digits that are not part of a decimal number such as 214748364800.0, and not the
    # last group of a UUID such as a cluster label.
    (ACCOUNT, Pattern(r"(?<!\d)(?<!\d\.)(?<![0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-)\d{12}(?!\d)(?!\.\d)", re.I),
     "account-id"),
    ("vpc- ID", Pattern(r"\bvpc-[0-9a-f]{8,17}\b"), "vpc-id"),
    ("subnet- ID", Pattern(r"\bsubnet-[0-9a-f]{8,17}\b"), "subnet-id"),
    ("sg- ID", Pattern(r"\bsg-[0-9a-f]{8,17}\b"), "sg-id"),
    ("igw- ID", Pattern(r"\bigw-[0-9a-f]{8,17}\b"), "igw-id"),
    ("i- ID", Pattern(r"\bi-[0-9a-f]{8,17}\b"), "instance-id"),
    ("port number", PortNumbers(), "port"),
    ("tunnel wording", Pattern(r"\b" + _TUNNEL_WORD + r"\b(?:\s+" + _TUNNEL_WORD + r"\b)*", re.I), "tunnel"),
]
PLACEHOLDER = re.compile(r"\\?<(?:" + "|".join(p for _, _, p in REDACTION) + r")>")
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


def scan(rel, text):
    """(kind, line number) for each infrastructure identifier that remains.  A placeholder is
    not an identifier."""
    found = []
    for n, (line, words) in enumerate(without_measurements(rel, text), 1):
        line, words = PLACEHOLDER.sub(" ", line), PLACEHOLDER.sub(" ", words)
        for kind, pattern, _ in REDACTION:
            if pattern.spans(words if kind == ACCOUNT else line):
                found.append((kind, n))
    return found


def _replace(segment, placeholder, protected, offset):
    """Replace each identifier in segment, in one pass over the original text.  An earlier kind
    wins an overlap, so a SOCKS URL keeps its IPv4 address inside one placeholder.  The account
    pattern keeps a measurement cell; protected spans are line offsets, and segment starts at
    offset in the line."""
    chosen = []
    for kind, pattern, name in REDACTION:
        for start, end in pattern.spans(segment):
            if kind == ACCOUNT and any(a <= offset + start < b for a, b in protected):
                continue
            if any(start < e and s < end for s, e, _ in chosen):
                continue
            chosen.append((start, end, name))
    out, last = [], 0
    for start, end, name in sorted(chosen):
        out.append(WRAPPER.sub(COMMAND, segment[last:start]))
        out.append(placeholder(name))
        last = end
    out.append(WRAPPER.sub(COMMAND, segment[last:]))
    return "".join(out)


def redact(rel, text):
    """The text with each identifier replaced by its <kind> placeholder and each wrapper variable
    by the command name.  In a markdown page, a placeholder outside code is escaped as \\<kind>,
    so that mdbook shows it rather than read it as an HTML tag."""
    raw = lambda name: f"<{name}>"
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
