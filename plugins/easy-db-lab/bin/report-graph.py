#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "matplotlib>=3.8",
#   "requests[socks]>=2.31",
# ]
# ///
"""Download a lab report graph from Mimir, and plot it with its evidence block.

Two subcommands:

  fetch  queries Mimir query_range and writes <docs>/data/<name>.csv (long form:
         timestamp_utc,node,arm,value) and <docs>/data/<name>.json (query, start, end, step,
         unit, scale, arms).  It never stores the Mimir URL or the tenant.  It refuses a query
         with no cluster="..." or cluster=~"..." matcher before it sends it, because one tenant
         holds many clusters.  It fails on a connection error, a non-success status, zero
         series, and a node value that looks like an IPv4 address or an EC2 host name
         (ip-10-0-1-15) with no --node mapping.

  plot   reads one or more CSVs from <docs>/data, writes <docs>/images/<name>.png with the
         shared style, and prints the full evidence block (heading, image, stats table, Window,
         Query, Data) on stdout.  The stats table has one row per node and one rollup row per
         arm (Node = all) from pooled samples.  CSVs with a different unit or step are an error.
         CSVs whose queries differ are an error, unless they differ only in the cluster="..." or
         cluster=~"..." matcher; then the block has one Query line per arm.  CSVs with a
         different window are an error unless --align elapsed is given.  With
         --align, two CSVs that share an arm are an error if their windows differ.  --name holds
         letters, digits, _, . and -, and no "..".

Usage:
    report-graph.py fetch --mimir-url URL --tenant T --query PROMQL --start ISO --end ISO \\
        [--step 30s] --node-label instance [--node VALUE=db0]... [--arm baseline=db0,db1]... \\
        --unit "MB/s" [--scale 1e-6] --name scrape-alloc --docs <docs> [--proxy socks5h://...]
    report-graph.py plot --csv <docs>/data/a.csv [--csv ...] --title "..." [--name n] \\
        [--style <docs>/lab.mplstyle] [--stats samples,min,p50,mean,p99,max] \\
        [--align elapsed] [--page 2-evidence.md] --docs <docs>

The statistics: samples, min, p50, mean, p95, p99, max, total, and rate.  total and rate are for
a counter: total is the last value minus the first, and rate is the total divided by the window
in seconds.  An arm's rollup pools the samples of its nodes; its total is the sum of the node
totals.  The rules for evidence blocks are in the plugin's references/report.md.
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

ROLE_COLOURS = {"baseline": "#999999", "candidate": "#0072B2"}
LINE_STYLES = ["-", "--", ":", "-."]
STAT_TITLES = {
    "samples": "Samples", "min": "Min", "p50": "p50", "mean": "Mean", "p95": "p95",
    "p99": "p99", "max": "Max", "total": "Total", "rate": "Rate",
}
DEFAULT_STATS = "samples,min,p50,mean,p99,max"
IPV4 = re.compile(r"^\d{1,3}(\.\d{1,3}){3}(:\d+)?$")
# An EC2 host name holds the IP: ip-10-0-1-15, ip-10-0-1-15.ec2.internal, ...compute.internal.
EC2_HOST = re.compile(r"^ip-\d{1,3}(-\d{1,3}){3}(\.[A-Za-z0-9.-]+)?(:\d+)?$")
# --name becomes a file name under data/ or images/, so it holds no path.
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
# A Mimir tenant holds many clusters, so each arm's query selects its own cluster label.
CLUSTER_MATCHER = re.compile(r'(?<![A-Za-z0-9_])cluster\s*=~?\s*"(?:[^"\\]|\\.)*"')


def die(msg):
    print(f"report-graph: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_time(text):
    try:
        t = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        die(f"not an ISO 8601 time: {text}")
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    return t.astimezone(timezone.utc)


def iso(t):
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def step_seconds(text):
    m = re.fullmatch(r"(\d+)([smh]?)", text.strip())
    if not m:
        die(f"not a step such as 30s, 1m, or 15: {text}")
    return int(m.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600}[m.group(2)]


def pairs(values, flag):
    """Parse repeated KEY=VALUE flags into (key, value) tuples."""
    out = []
    for v in values or []:
        if "=" not in v:
            die(f"{flag} takes KEY=VALUE, got: {v}")
        k, _, rest = v.partition("=")
        out.append((k, rest))
    return out


# --- fetch ---


def fetch(args):
    import requests

    if not CLUSTER_MATCHER.search(args.query):
        die('the query has no cluster matcher; a Mimir tenant holds many clusters, so add '
            'cluster="<this cluster>" to the selector')
    start, end = parse_time(args.start), parse_time(args.end)
    step = step_seconds(args.step)
    node_map = dict(pairs(args.node, "--node"))
    arms = {}
    for arm, nodes in pairs(args.arm, "--arm"):
        arms[arm] = [n for n in nodes.split(",") if n]
    node_arm = {n: arm for arm, nodes in arms.items() for n in nodes}

    url = args.mimir_url.rstrip("/") + "/api/v1/query_range"
    proxies = {"http": args.proxy, "https": args.proxy} if args.proxy else None
    params = {"query": args.query, "start": int(start.timestamp()),
              "end": int(end.timestamp()), "step": step}
    try:
        resp = requests.get(url, params=params, headers={"X-Scope-OrgID": args.tenant},
                            proxies=proxies, timeout=args.timeout)
    except requests.exceptions.RequestException as e:
        die(f"cannot reach Mimir: {e.__class__.__name__}: {e}")
    try:
        body = resp.json()
    except ValueError:
        body = {}
    if resp.status_code != 200 or body.get("status") != "success":
        die(f"Mimir returned HTTP {resp.status_code}: {body.get('error') or resp.text[:200]}")
    result = body.get("data", {}).get("result", [])
    if not result:
        die("the query returned no series; check the query, the node selector, and the window")

    rows, seen = [], set()
    for series in result:
        value = series.get("metric", {}).get(args.node_label)
        if value is None:
            die(f"a series has no {args.node_label} label; aggregate by {args.node_label}")
        if value in node_map:
            node = node_map[value]
        elif IPV4.match(value) or EC2_HOST.match(value):
            die("a node value looks like an IPv4 address or an EC2 host name; select nodes by "
                "host name, or map it with --node VALUE=NAME")
        else:
            node = value
        if node in seen:
            die(f"the query returned more than one series for node {node}; "
                f"aggregate by {args.node_label}")
        seen.add(node)
        if arms and node not in node_arm:
            die(f"node {node} is in no --arm")
        arm = node_arm.get(node, "")
        for ts, raw in series.get("values", []):
            v = float(raw)
            if math.isfinite(v):
                rows.append((iso(datetime.fromtimestamp(float(ts), timezone.utc)), node, arm,
                             repr(round(v * args.scale, 6))))

    data = os.path.join(args.docs, "data")
    os.makedirs(data, exist_ok=True)
    with open(os.path.join(data, f"{args.name}.csv"), "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["timestamp_utc", "node", "arm", "value"])
        w.writerows(rows)
    meta = {"query": args.query, "start": iso(start), "end": iso(end), "step": f"{step}s",
            "unit": args.unit, "scale": args.scale, "arms": arms}
    with open(os.path.join(data, f"{args.name}.json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print(f"data: {os.path.join(data, args.name)}.csv ({len(rows)} samples, {len(seen)} nodes)")


# --- plot ---


def quantile(vals, q):
    if len(vals) == 1:
        return vals[0]
    return statistics.quantiles(vals, n=100, method="inclusive")[q - 1]


def node_stats(points, seconds):
    """Statistics for one node: points is a time-ordered list of (datetime, value)."""
    vals = sorted(v for _, v in points)
    total = points[-1][1] - points[0][1]
    return {
        "samples": len(vals), "min": vals[0], "p50": statistics.median(vals),
        "mean": statistics.fmean(vals), "p95": quantile(vals, 95), "p99": quantile(vals, 99),
        "max": vals[-1], "total": total, "rate": total / seconds if seconds else 0.0,
    }


def rollup_stats(series, seconds):
    """Statistics for an arm from the pooled samples of its nodes."""
    vals = sorted(v for points in series for _, v in points)
    total = sum(points[-1][1] - points[0][1] for points in series)
    return {
        "samples": len(vals), "min": vals[0], "p50": statistics.median(vals),
        "mean": statistics.fmean(vals), "p95": quantile(vals, 95), "p99": quantile(vals, 99),
        "max": vals[-1], "total": total, "rate": total / seconds if seconds else 0.0,
    }


def fmt(stat, v):
    if stat == "samples":
        return str(v)
    if v == 0 or abs(v) >= 1:
        return f"{v:.2f}"
    # Four significant digits in fixed point, never an exponent, so report-check reads the cell.
    places = 3 - math.floor(math.log10(abs(v)))
    return f"{v:.{places}f}".rstrip("0").rstrip(".")


def duration(seconds):
    h, rem = divmod(int(seconds), 3600)
    m, s = divmod(rem, 60)
    return f"{h}h {m}m {s}s" if h else f"{m}m {s}s"


def load(path, docs):
    real = os.path.realpath(path)
    data_dir = os.path.realpath(os.path.join(docs, "data"))
    if os.path.dirname(real) != data_dir:
        die(f"{path}: plot reads CSVs from {os.path.join(docs, 'data')}, where fetch writes them")
    meta_path = os.path.splitext(real)[0] + ".json"
    if not os.path.exists(meta_path):
        die(f"{path}: no metadata file {os.path.basename(meta_path)} next to it")
    with open(meta_path) as f:
        meta = json.load(f)
    with open(real, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        die(f"{path}: the CSV has no rows; fetch it again before you plot")
    return real, meta, rows


def query_shape(query):
    """The query with its cluster matcher blanked: two arms' queries can differ only there."""
    return CLUSTER_MATCHER.sub('cluster=""', query or "")


def arm_order(arms):
    roles = [a for a in ("baseline", "candidate") if a in arms]
    return roles + [a for a in arms if a not in roles]


def plot(args):
    stats = [s.strip() for s in args.stats.split(",") if s.strip()]
    for s in stats:
        if s not in STAT_TITLES:
            die(f"unknown statistic {s}; use {', '.join(STAT_TITLES)}")
    docs = os.path.realpath(args.docs)
    loaded = [load(p, docs) for p in args.csv]

    first = loaded[0][1]
    for path, meta, _ in loaded[1:]:
        if query_shape(meta.get("query")) != query_shape(first.get("query")):
            die(f"the CSVs differ in query, apart from the cluster matcher: {first.get('query')!r} "
                f"and {meta.get('query')!r}")
        for field in ("unit", "step"):
            if meta.get(field) != first.get(field):
                die(f"the CSVs differ in {field}: {first.get(field)!r} and {meta.get(field)!r}")
        if not args.align and (meta.get("start"), meta.get("end")) != (first.get("start"), first.get("end")):
            die("the CSVs have different windows; use --align elapsed to plot each arm from its own start")

    if args.align:
        # Each arm keeps the window of its CSV, so an arm in two CSVs needs one window in both.
        source = {}
        for path, meta, rows in loaded:
            window = (meta.get("start"), meta.get("end"))
            for arm in sorted({r["arm"] for r in rows}):
                first_path, first_window = source.setdefault(arm, (path, window))
                if first_window != window:
                    die(f"arm {arm} is in {os.path.basename(first_path)} and {os.path.basename(path)} with "
                        "different windows; with --align elapsed each arm has one window")

    # Series keyed by (arm, node).  Each arm keeps the window of the CSV it came from.
    series, arm_window, arm_query, arms = {}, {}, {}, []
    for path, meta, rows in loaded:
        window = (parse_time(meta["start"]), parse_time(meta["end"]))
        for r in rows:
            key = (r["arm"], r["node"])
            series.setdefault(key, []).append((parse_time(r["timestamp_utc"]), float(r["value"])))
            if r["arm"] not in arms:
                arms.append(r["arm"])
            arm_window.setdefault(r["arm"], window)
            arm_query.setdefault(r["arm"], meta.get("query", ""))
    for points in series.values():
        points.sort()
    arms = arm_order(arms)

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.dates as mdates
    import matplotlib.pyplot as plt

    style = args.style or os.path.join(docs, "lab.mplstyle")
    plt.style.use(style)
    palette = plt.rcParams["axes.prop_cycle"].by_key().get("color", [])
    role_hex = {c.lower().lstrip("#") for c in ROLE_COLOURS.values()}
    extra = [c for c in palette if c.lower().lstrip("#") not in role_hex]

    fig, ax = plt.subplots()
    extra_i = 0
    for arm in arms:
        nodes = sorted(n for a, n in series if a == arm)
        if arm in ROLE_COLOURS:
            arm_colour = ROLE_COLOURS[arm]
        elif arm and extra:
            arm_colour = extra[extra_i % len(extra)]
            extra_i += 1
        else:
            arm_colour = None
        start = arm_window[arm][0]
        for i, node in enumerate(nodes):
            points = series[(arm, node)]
            if args.align:
                xs = [(t - start).total_seconds() for t, _ in points]
            else:
                xs = [t for t, _ in points]
            colour = arm_colour or (palette[i % len(palette)] if palette else None)
            label = f"{node} ({arm})" if arm else node
            ax.plot(xs, [v for _, v in points], color=colour, label=label,
                    linestyle=LINE_STYLES[i % len(LINE_STYLES)] if arm else "-")
    ax.set_title(args.title)
    ax.set_ylabel(first.get("unit", ""))
    if args.align:
        ax.set_xlabel("Elapsed (s)")
    else:
        ax.set_xlabel("Time (UTC)")
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M", tz=timezone.utc))
    ax.legend()

    name = args.name or os.path.splitext(os.path.basename(args.csv[0]))[0]
    images = os.path.join(docs, "images")
    os.makedirs(images, exist_ok=True)
    png = os.path.join(images, f"{name}.png")
    fig.savefig(png)
    plt.close(fig)

    page_dir = os.path.dirname(os.path.join(docs, args.page))
    rel = lambda p: os.path.relpath(p, page_dir)
    unit = first.get("unit", "")
    out = [f"## {args.title}", "", f"![{args.title}]({rel(png)})", ""]
    out.append("| Node | Arm | " + " | ".join(STAT_TITLES[s] for s in stats) + " | Unit |")
    out.append("|:--|:--|" + "--:|" * len(stats) + ":--|")
    for arm in arms:
        seconds = (arm_window[arm][1] - arm_window[arm][0]).total_seconds()
        nodes = sorted(n for a, n in series if a == arm)
        for node in nodes:
            st = node_stats(series[(arm, node)], seconds)
            label = f"{node} ({arm})" if arm else node
            out.append(f"| {label} | {arm} | " + " | ".join(fmt(s, st[s]) for s in stats) + f" | {unit} |")
        st = rollup_stats([series[(arm, n)] for n in nodes], seconds)
        out.append(f"| all | {arm} | " + " | ".join(fmt(s, st[s]) for s in stats) + f" | {unit} |")
    out.append("")
    step = first.get("step", "")
    if args.align:
        for arm in arms:
            s, e = arm_window[arm]
            out.append(f"Window ({arm}): {iso(s)} to {iso(e)} ({duration((e - s).total_seconds())}), step {step}")
            out.append("")
    else:
        s, e = parse_time(first["start"]), parse_time(first["end"])
        out.append(f"Window: {iso(s)} to {iso(e)} ({duration((e - s).total_seconds())}), step {step}")
        out.append("")
    if len({meta.get("query") for _, meta, _ in loaded}) == 1:
        out.append(f"Query: `{first.get('query', '')}`")
        out.append("")
    else:
        for arm in arms:
            out.append(f"Query ({arm}): `{arm_query[arm]}`")
            out.append("")
    out.append("Data: " + ", ".join(f"[{os.path.basename(p)}]({rel(p)})" for p, _, _ in loaded))
    print("\n".join(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch", help="query Mimir and write data/<name>.csv and .json")
    f.add_argument("--mimir-url", required=True)
    f.add_argument("--tenant", required=True)
    f.add_argument("--query", required=True)
    f.add_argument("--start", required=True)
    f.add_argument("--end", required=True)
    f.add_argument("--step", default="30s")
    f.add_argument("--node-label", required=True)
    f.add_argument("--node", action="append", help="VALUE=NAME; map a node label value to a host name")
    f.add_argument("--arm", action="append", help="ARM=node1,node2")
    f.add_argument("--unit", required=True)
    f.add_argument("--scale", type=float, default=1.0)
    f.add_argument("--name", required=True)
    f.add_argument("--docs", required=True)
    f.add_argument("--proxy", help="for example socks5h://127.0.0.1:1080")
    f.add_argument("--timeout", type=float, default=30.0)

    p = sub.add_parser("plot", help="plot CSVs to images/<name>.png and print the evidence block")
    p.add_argument("--csv", action="append", required=True)
    p.add_argument("--title", required=True)
    p.add_argument("--name")
    p.add_argument("--style")
    p.add_argument("--stats", default=DEFAULT_STATS)
    p.add_argument("--align", choices=["elapsed"])
    p.add_argument("--page", default="2-evidence.md", help="the page the block goes in, relative to --docs")
    p.add_argument("--docs", required=True)

    args = ap.parse_args()
    if args.name is not None and (not NAME.match(args.name) or ".." in args.name):
        die(f"--name {args.name!r} is not a file name; use letters, digits, _, . and -, with no ..")
    fetch(args) if args.cmd == "fetch" else plot(args)


if __name__ == "__main__":
    main()
