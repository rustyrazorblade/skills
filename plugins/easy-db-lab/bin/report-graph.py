#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "requests[socks]>=2.31",
# ]
# ///
"""Download a lab report graph from Mimir and Grafana, and print its evidence block.

Three subcommands:

  fetch   queries Mimir query_range and writes <docs>/data/<name>.csv (long form:
          timestamp_utc,node,arm,value) and <docs>/data/<name>.json (query, start, end, step,
          unit, scale, arms).  It never stores the Mimir URL or the tenant.  It refuses a query
          with no cluster="..." or cluster=~"..." matcher before it sends it, because one tenant
          holds many clusters.  It fails on a connection error, a non-success status, and zero
          series.  It writes each node label as it is, an IP-like label too; --node VALUE=NAME
          maps a label to a role name.

  render  downloads one Grafana panel render to <docs>/images/<name>.png.  It sends one GET to
          /render/d-solo/<UID>/ with panelId, from, to, each var-<NAME>, width, height, tz=UTC,
          and theme (dark by default, so the image matches the report page; --theme light for
          the light theme).  An ISO time goes out as epoch milliseconds; a Grafana relative time
          such as now-93600s goes out unchanged.  It writes the image only for a status 200 and a
          non-empty PNG body; any other result exits non-zero and leaves the old image as it was.
          It never stores the Grafana URL.

  block   reads one or more CSVs from <docs>/data and one or more images from <docs>/images, and
          prints the full evidence block (heading, image, stats table, Window, Query, Data) on
          stdout.  It draws nothing and writes no file.  Each image must be a non-empty PNG; an
          image given as ARM=PATH carries the arm in its alt text.  The stats table has one row
          per node and one rollup row per arm (Node = all) from pooled samples.  CSVs with a
          different unit or step are an error.  CSVs whose queries differ are an error, unless
          they differ only in the cluster="..." or cluster=~"..." matcher; then the block has one
          Query line per arm.  CSVs with a different window are an error unless --arm-windows is
          given.  With --arm-windows, two CSVs that share an arm are an error if their windows
          differ.

--name holds letters, digits, _, . and -, and no "..".

Usage:
    report-graph.py fetch --mimir-url URL --tenant T --query PROMQL --start ISO --end ISO \\
        [--step 30s] --node-label instance [--node VALUE=db0]... [--arm baseline=db0,db1]... \\
        --unit "MB/s" [--scale 1e-6] --name scrape-alloc --docs <docs> [--proxy socks5h://...]
    report-graph.py render --grafana-url URL --dashboard UID --panel ID --from TIME --to TIME \\
        [--var NAME=VALUE]... [--width 1200] [--height 600] [--theme dark|light] \\
        --name scrape-alloc --docs <docs> [--proxy socks5h://...] [--timeout 60]
    report-graph.py block --csv <docs>/data/a.csv [--csv ...] --image [ARM=]<docs>/images/a.png \\
        [--image ...] --title "..." [--stats samples,min,p50,mean,p99,max] [--arm-windows] \\
        [--page 2-evidence.md] --docs <docs>

The statistics: samples, min, p50, mean, p95, p99, max, total, and rate.  total and rate are for
a counter: total is the last value minus the first, and rate is the total divided by the window
in seconds.  An arm's rollup pools the samples of its nodes; its total is the sum of the node
totals.  The rules for evidence blocks and renders are in the plugin's references/report.md.
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
from urllib.parse import quote

STAT_TITLES = {
    "samples": "Samples", "min": "Min", "p50": "p50", "mean": "Mean", "p95": "p95",
    "p99": "p99", "max": "Max", "total": "Total", "rate": "Rate",
}
DEFAULT_STATS = "samples,min,p50,mean,p99,max"
# --name becomes a file name under data/ or images/, so it holds no path.
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
# A Mimir tenant holds many clusters, so each arm's query selects its own cluster label.
CLUSTER_MATCHER = re.compile(r'(?<![A-Za-z0-9_])cluster\s*=~?\s*"(?:[^"\\]|\\.)*"')
# A Grafana relative time: now, now-93600s, now-1h/h.  It goes to Grafana unchanged.
RELATIVE_TIME = re.compile(r"^now([+-]\d+[smhdwMy])?(/[smhdwMy])?$")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def die(msg):
    print(f"report-graph: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_time(text, kind="an ISO 8601 time"):
    try:
        t = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        die(f"not {kind}: {text}")
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


def proxies(args):
    return {"http": args.proxy, "https": args.proxy} if args.proxy else None


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
    params = {"query": args.query, "start": int(start.timestamp()),
              "end": int(end.timestamp()), "step": step}
    try:
        resp = requests.get(url, params=params, headers={"X-Scope-OrgID": args.tenant},
                            proxies=proxies(args), timeout=args.timeout)
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
        node = node_map.get(value, value)
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


# --- render ---


def grafana_time(text):
    """A Grafana relative time goes out unchanged; an ISO time goes out as epoch milliseconds."""
    if RELATIVE_TIME.match(text):
        return text
    t = parse_time(text, "an ISO 8601 time or a Grafana relative time such as now-3600s")
    return str(int(t.timestamp() * 1000))


def render(args):
    import requests

    params = [("panelId", args.panel), ("from", grafana_time(args.from_)),
              ("to", grafana_time(args.to))]
    params += [(f"var-{k}", v) for k, v in pairs(args.var, "--var")]
    params += [("width", args.width), ("height", args.height), ("tz", "UTC"),
               ("theme", args.theme)]
    url = f"{args.grafana_url.rstrip('/')}/render/d-solo/{quote(args.dashboard, safe='')}/"
    try:
        resp = requests.get(url, params=params, proxies=proxies(args), timeout=args.timeout)
    except requests.exceptions.RequestException as e:
        die(f"cannot reach Grafana: {e.__class__.__name__}: {e}")
    if resp.status_code != 200:
        die(f"Grafana returned HTTP {resp.status_code}: {resp.text[:200]}")
    body = resp.content
    if not body:
        die("Grafana returned an empty body; check the dashboard uid, the panel id, and the renderer")
    if not body.startswith(PNG_SIGNATURE):
        die(f"Grafana returned a body that is not a PNG ({resp.headers.get('Content-Type', 'no type')}); "
            "check that anonymous access and the image renderer work")

    # Write a temporary file and rename it, so a render never leaves half an image.
    images = os.path.join(args.docs, "images")
    os.makedirs(images, exist_ok=True)
    png = os.path.join(images, f"{args.name}.png")
    tmp = f"{png}.tmp"
    with open(tmp, "wb") as f:
        f.write(body)
    os.replace(tmp, png)
    print(f"image: {png} ({len(body)} bytes)")


# --- block ---


def quantile(vals, q):
    if len(vals) == 1:
        return vals[0]
    return statistics.quantiles(vals, n=100, method="inclusive")[q - 1]


def node_stats(points, seconds):
    """Statistics for one node: points is a time-ordered list of (datetime, value)."""
    return rollup_stats([points], seconds)


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
        die(f"{path}: block reads CSVs from {os.path.join(docs, 'data')}, where fetch writes them")
    meta_path = os.path.splitext(real)[0] + ".json"
    if not os.path.exists(meta_path):
        die(f"{path}: no metadata file {os.path.basename(meta_path)} next to it")
    with open(meta_path) as f:
        meta = json.load(f)
    with open(real, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        die(f"{path}: the CSV has no rows; fetch it again before you build the block")
    return real, meta, rows


# An --image ARM=PATH prefix is an arm name; a path holds a / or starts with a dot.
IMAGE_ARM = re.compile(r"^([A-Za-z0-9][A-Za-z0-9_-]*)=(.+)$")


def load_image(spec, docs):
    """Parse --image [ARM=]PATH and check that PATH is a non-empty PNG under <docs>/images."""
    m = IMAGE_ARM.match(spec)
    arm, path = (m.group(1), m.group(2)) if m else ("", spec)
    real = os.path.realpath(path)
    images_dir = os.path.realpath(os.path.join(docs, "images"))
    if os.path.dirname(real) != images_dir:
        die(f"{path}: block reads images from {os.path.join(docs, 'images')}, where render writes them")
    if not os.path.isfile(real):
        die(f"{path}: no such image; render it before you build the block")
    with open(real, "rb") as f:
        head = f.read(len(PNG_SIGNATURE))
    if not head:
        die(f"{path}: the image is empty; render it again")
    if head != PNG_SIGNATURE:
        die(f"{path}: the image is not a PNG; render it again")
    return arm, real


def query_shape(query):
    """The query with its cluster matcher blanked: two arms' queries can differ only there."""
    return CLUSTER_MATCHER.sub('cluster=""', query or "")


def arm_order(arms):
    roles = [a for a in ("baseline", "candidate") if a in arms]
    return roles + [a for a in arms if a not in roles]


def block(args):
    stats = [s.strip() for s in args.stats.split(",") if s.strip()]
    for s in stats:
        if s not in STAT_TITLES:
            die(f"unknown statistic {s}; use {', '.join(STAT_TITLES)}")
    docs = os.path.realpath(args.docs)
    loaded = [load(p, docs) for p in args.csv]
    images = [load_image(spec, docs) for spec in args.image]

    first = loaded[0][1]
    for path, meta, _ in loaded[1:]:
        if query_shape(meta.get("query")) != query_shape(first.get("query")):
            die(f"the CSVs differ in query, apart from the cluster matcher: {first.get('query')!r} "
                f"and {meta.get('query')!r}")
        for field in ("unit", "step"):
            if meta.get(field) != first.get(field):
                die(f"the CSVs differ in {field}: {first.get(field)!r} and {meta.get(field)!r}")
        if not args.arm_windows and (meta.get("start"), meta.get("end")) != (first.get("start"), first.get("end")):
            die("the CSVs have different windows; use --arm-windows to keep each arm's own window")

    if args.arm_windows:
        # Each arm keeps the window of its CSV, so an arm in two CSVs needs one window in both.
        source = {}
        for path, meta, rows in loaded:
            window = (meta.get("start"), meta.get("end"))
            for arm in sorted({r["arm"] for r in rows}):
                first_path, first_window = source.setdefault(arm, (path, window))
                if first_window != window:
                    die(f"arm {arm} is in {os.path.basename(first_path)} and {os.path.basename(path)} with "
                        "different windows; with --arm-windows each arm has one window")

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

    page_dir = os.path.dirname(os.path.join(docs, args.page))
    rel = lambda p: os.path.relpath(p, page_dir)
    unit = first.get("unit", "")
    out = [f"## {args.title}", ""]
    for arm, png in images:
        alt = f"{args.title} ({arm})" if arm else args.title
        out += [f"![{alt}]({rel(png)})", ""]
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
    if args.arm_windows:
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

    r = sub.add_parser("render", help="download one Grafana panel render to images/<name>.png")
    r.add_argument("--grafana-url", required=True)
    r.add_argument("--dashboard", required=True, help="the dashboard uid")
    r.add_argument("--panel", type=int, required=True, help="the panel id")
    r.add_argument("--from", dest="from_", required=True, help="ISO 8601 UTC, or now-<N>s")
    r.add_argument("--to", required=True, help="ISO 8601 UTC, or now")
    r.add_argument("--var", action="append", help="NAME=VALUE; sent as var-NAME=VALUE")
    r.add_argument("--width", type=int, default=1200)
    r.add_argument("--height", type=int, default=600)
    r.add_argument("--theme", choices=("dark", "light"), default="dark",
                   help="the Grafana theme; dark matches the report page")
    r.add_argument("--name", required=True)
    r.add_argument("--docs", required=True)
    r.add_argument("--proxy", help="for example socks5h://127.0.0.1:1080")
    r.add_argument("--timeout", type=float, default=60.0)

    b = sub.add_parser("block", help="print the evidence block from CSVs and rendered images")
    b.add_argument("--csv", action="append", required=True)
    b.add_argument("--image", action="append", required=True, help="[ARM=]PATH under <docs>/images")
    b.add_argument("--title", required=True)
    b.add_argument("--stats", default=DEFAULT_STATS)
    b.add_argument("--arm-windows", action="store_true", help="keep each arm's own window")
    b.add_argument("--page", default="2-evidence.md", help="the page the block goes in, relative to --docs")
    b.add_argument("--docs", required=True)

    args = ap.parse_args()
    name = getattr(args, "name", None)
    if name is not None and (not NAME.match(name) or ".." in name):
        die(f"--name {name!r} is not a file name; use letters, digits, _, . and -, with no ..")
    {"fetch": fetch, "render": render, "block": block}[args.cmd](args)


if __name__ == "__main__":
    main()
