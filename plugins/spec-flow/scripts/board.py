#!/usr/bin/env python3
"""Deterministic board renderer for spec-flow's `board` skill.

Moves everything `board/SKILL.md` used to make the model do by hand — pulling raw `gh issue
list`/`gh pr list` JSON into context, joining it against PR/CI state and local sessions, bucketing
by lifecycle, computing "next up"/"blocked on you"/"stalled", and formatting the final board text —
into one script. The model runs this and prints its stdout; it never sees the raw GitHub JSON and
never hand-writes a join script. `render_board()` is one function per rendered section, and every
section renders only when it has something to report — no empty header, no zero count, no
placeholder line. The two unbounded categories (the ungroomed backlog and the epic list) report as
counts in the summary line rather than as rows, so the board's rendered length does not grow with
the backlog. `prefetch_notes()` fetches blocked/needs-attention comment notes concurrently instead
of one-by-one inside `build_rows()`. Stdlib only, shells out to `gh`/`git`/`claude`.

THIS FILE IS THE AUTHORITY on the classification rules — what counts as "blocked on you",
"stalled", "claimed", what "next up" recommends, epic exclusion and PR/CI correlation. Each rule is
stated in a comment beside the code that implements it. skills/board/SKILL.md covers how to invoke
this and what to do with the output; it deliberately does not restate the rules, so the two cannot
drift apart.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# Resolved from this file's own location, not templated -- board.py runs as a plain script, not
# SKILL.md prose, so there's no ${CLAUDE_PLUGIN_ROOT} substitution happening on its stdout. This
# script already lives in scripts/ alongside spawn-issue-manager.sh.
SPAWN_SCRIPT = str(Path(__file__).resolve().parent / "spawn-issue-manager.sh")

STATUS_ORDER = ["spec-review", "in-review", "in-progress", "addressing", "ready"]
# The actual pipeline order (docs/workflow.md's lifecycle diagram), LEAST advanced first.
# STATUS_ORDER above is a membership set whose sequence is not the lifecycle -- using it as a
# tie-break picked the LESS advanced of two labels for half the adjacent pairs, which is the
# opposite of what a stale-leftover tie-break is for.
LIFECYCLE_ORDER = ["ready", "spec-review", "in-progress", "in-review", "addressing"]
PRIORITY_ORDER = ["P0", "P1", "P2", "P3"]
# Rendered instead of the literal label text. A keycap is three codepoints -- the digit, U+FE0F and
# U+20E3 -- but a terminal draws it in about two cells, so format-width padding (`:3`) pads a
# prioritized row differently from an unprioritized one and every column after it drifts. Emit the
# keycap followed by a literal space instead, and PRIORITY_BLANK when there is no priority label:
# all four keycaps are the same width, so the columns line up without measuring anything.
PRIORITY_KEYCAP = {"P0": "0️⃣", "P1": "1️⃣", "P2": "2️⃣", "P3": "3️⃣"}
PRIORITY_BLANK = "  "


def keycap(priority):
    return PRIORITY_KEYCAP.get(priority, PRIORITY_BLANK)


def fail(message):
    print(f"board: {message}", file=sys.stderr)
    sys.exit(1)


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, cmd, result.stdout, result.stderr)
    return result.stdout


def gh_json(args, default=None):
    try:
        return json.loads(run(["gh", *args]))
    except subprocess.CalledProcessError as e:
        if default is not None:
            print(f"board: warning: 'gh {' '.join(args)}' failed, continuing without it: {e.stderr.strip()}", file=sys.stderr)
            return default
        raise


ISSUE_LIMIT = 400
PR_LIMIT = 200


def fetch_issues():
    return gh_json(["issue", "list", "--state", "open", "--json",
                     "number,title,labels,url,assignees,subIssuesSummary",
                     "--limit", str(ISSUE_LIMIT)], default=[])


def fetch_prs():
    return gh_json(["pr", "list", "--state", "open", "--json",
                     "number,headRefName,title,reviewDecision,url,statusCheckRollup,closingIssuesReferences",
                     "--limit", str(PR_LIMIT)], default=[])


def warn_if_truncated(issues, prs):
    # A silently truncated list drops issues from every bucket, the summary counts, the stalled
    # list and "next up" -- with nothing on screen to say the board is incomplete. Hitting the cap
    # exactly is the only signal available, so report it rather than presenting a partial board as
    # if it were the whole picture.
    if len(issues) >= ISSUE_LIMIT:
        print(f"board: warning: hit the {ISSUE_LIMIT}-issue fetch limit — the board may be "
              f"incomplete, and 'next up' may miss higher-priority work.", file=sys.stderr)
    if len(prs) >= PR_LIMIT:
        print(f"board: warning: hit the {PR_LIMIT}-PR fetch limit — some issues may show no PR "
              f"or CI state.", file=sys.stderr)


def fetch_me():
    try:
        return run(["gh", "api", "user", "--jq", ".login"]).strip()
    except subprocess.CalledProcessError:
        return None


def fetch_sessions():
    try:
        return json.loads(run(["claude", "agents", "--json", "--all"]))
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []


def fetch_archive_pending():
    try:
        default_branch = run(["gh", "repo", "view", "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"]).strip()
        out = run(["git", "ls-tree", "--name-only", f"origin/{default_branch}:openspec/changes"])
    except subprocess.CalledProcessError:
        return 0
    return len([line for line in out.splitlines() if line and line != "archive"])


def last_comment_matching(number, prefix=None):
    args = ["issue", "view", str(number), "--json", "comments"]
    try:
        comments = json.loads(run(["gh", *args])).get("comments", [])
    except subprocess.CalledProcessError as e:
        print(f"board: warning: 'gh {' '.join(args)}' failed, continuing without it: {e.stderr.strip()}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"board: warning: 'gh {' '.join(args)}' returned malformed JSON, continuing without it: {e}", file=sys.stderr)
        return None
    candidates = [c.get("body", "") for c in comments if not prefix or c.get("body", "").startswith(prefix)]
    return candidates[-1] if candidates else None


def prefetch_notes(issues):
    blocked_numbers = [i["number"] for i in issues if "blocked" in label_names(i)]
    attention_numbers = [i["number"] for i in issues if "needs-attention" in label_names(i)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        blocked_futures = {n: pool.submit(last_comment_matching, n, "⛔ Blocked on") for n in blocked_numbers}
        # Must filter by prefix. Without one this returns the last comment of ANY kind, and
        # the pipeline posts several after an attention request, so the row shows an
        # unrelated line. issue-manager posts the request with this prefix; see
        # agents/issue-manager.md.
        attention_futures = {n: pool.submit(last_comment_matching, n, "🆘 Needs attention")
                             for n in attention_numbers}
    return (
        {n: f.result() for n, f in blocked_futures.items()},
        {n: f.result() for n, f in attention_futures.items()},
    )


# ---------------------------------------------------------------------------
# CI rollup -> one of "green" | "running" | "failing". An empty rollup (no CI
# configured) counts as green -- nothing to wait on.
# ---------------------------------------------------------------------------
def ci_status(status_check_rollup):
    if not status_check_rollup:
        return "green"
    running = failing = False
    for check in status_check_rollup:
        conclusion = check.get("conclusion")
        status = check.get("status")
        legacy_state = check.get("state")
        if legacy_state in ("PENDING", "WAITING", "REQUESTED", "EXPECTED") \
                or status in ("QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "PENDING"):
            running = True
        elif legacy_state == "SUCCESS" or conclusion in ("SUCCESS", "NEUTRAL", "SKIPPED"):
            continue
        elif conclusion in ("FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE") \
                or legacy_state in ("FAILURE", "ERROR"):
            failing = True
        else:
            # Unknown/absent conclusion on a check that is not yet reported. Treat as pending, never
            # as failing: a red board entry drops the issue out of BLOCKED ON YOU and "next up",
            # both of which require "green", so guessing wrong here hides real work.
            running = True
    if running:
        return "running"
    if failing:
        return "failing"
    return "green"


def label_names(issue):
    # `or []`, not a default: gh can emit an explicit JSON null, and .get() returns that null
    # rather than the default -- which then raises and takes down the entire board render.
    return {l["name"] for l in (issue.get("labels") or [])}


def status_of(issue):
    # label_names returns a SET, and set iteration order over strings is not insertion order and
    # varies between runs (string hashing is randomized per process). An issue carrying two
    # status labels -- reachable after a crashed run, or a hand edit -- therefore classified into
    # a different bucket on different runs. Resolve deterministically instead, and prefer the
    # most-advanced state so a stale leftover label can't drag the issue backwards on the board.
    found = [n[len("status:"):] for n in label_names(issue) if n.startswith("status:")]
    if not found:
        return None
    known = [s for s in LIFECYCLE_ORDER if s in found]
    if known:
        return known[-1]        # last = furthest along the pipeline
    return sorted(found)[0]


def priority_of(issue):
    # Same set-ordering hazard as status_of: resolve in declared order, not iteration order.
    for name in PRIORITY_ORDER:
        if name in label_names(issue):
            return name
    return None


def priority_key(priority):
    return PRIORITY_ORDER.index(priority) if priority in PRIORITY_ORDER else len(PRIORITY_ORDER)


def build_rows(issues, prs, me, sessions, blocked_reason_fn, needs_attention_note_fn):
    pr_by_issue = {}
    for pr in prs:
        for ref in pr.get("closingIssuesReferences") or []:
            n = ref.get("number")
            if n is not None:
                pr_by_issue.setdefault(n, pr)  # first PR that closes it wins -- one PR per issue is the pipeline's own convention

    # (name, id, startedAt) tuples, not a dict keyed by exact name -- spawn-issue-manager.sh names a
    # session "issue-manager-<N>-<slug>" (a readable slug from the issue title, so several open tabs
    # are distinguishable at a glance), never a fixed string this side could match exactly
    # against. startedAt is kept so a rare double-match (a stale registry entry alongside its
    # live respawn) resolves to the most recent session, the same tie-break
    # spawn-issue-manager.sh's own lookup already uses (`sort_by(.startedAt) | last`).
    live_sessions = []
    for s in sessions:
        if s.get("state") in ("working", "blocked") and s.get("name"):
            live_sessions.append((s["name"], s.get("id"), s.get("startedAt") or ""))

    rows = []
    for issue in issues:
        n = issue["number"]
        labels = label_names(issue)
        is_epic = (issue.get("subIssuesSummary") or {}).get("total", 0) > 0
        assignees = issue.get("assignees") or []
        assignee = assignees[0]["login"] if assignees else None
        pr = pr_by_issue.get(n)

        row = {
            "number": n,
            "title": issue["title"],
            "url": issue["url"],
            "status": status_of(issue),
            "priority": priority_of(issue),
            "assignee": assignee,
            "mine": me is not None and assignee == me,
            "is_epic": is_epic,
            "agent_active": "agent:active" in labels,
            "blocked": "blocked" in labels,
            "needs_attention": "needs-attention" in labels,
            "pr_number": pr["number"] if pr else None,
            "pr_url": pr["url"] if pr else None,
            "ci": ci_status(pr.get("statusCheckRollup")) if pr else None,
        }
        # Boundary-safe prefix match (exact "issue-manager-<n>", or "issue-manager-<n>-" followed by the
        # slug) so issue #4 can never match a live "issue-manager-42-..." session -- a bare
        # startswith("issue-manager-4") would.
        # MIGRATION: the agent was renamed from `issue-pm` to `issue-manager`. Sessions started
        # before the rename keep the old name, and a board that stopped matching them would render
        # every one of them as stalled while they are running perfectly well. Both prefixes are
        # matched until no `issue-pm-*` session remains.
        session_prefixes = (f"issue-manager-{n}", f"issue-pm-{n}")
        attach_id = None
        if row["agent_active"]:
            matches = [
                (live_id, started_at) for live_name, live_id, started_at in live_sessions
                if any(live_name == p or live_name.startswith(p + "-") for p in session_prefixes)
            ]
            if matches:
                attach_id = max(matches, key=lambda m: m[1])[0]
        row["attach_id"] = attach_id

        if row["blocked"]:
            row["blocked_note"] = blocked_reason_fn(n) or "see issue comments"
        if row["needs_attention"]:
            row["attention_note"] = needs_attention_note_fn(n) or "see issue comments"

        rows.append(row)
    return rows


# Everything "past status:ready" in the pipeline sense -- a live issue-manager SHOULD be driving each
# of these, so missing agent:active on any of them is the stalled signal, not just some of them
# (confirmed against the spec: "Stalled -- any issue ... past status:ready with no agent:active").
PAST_READY_STATUSES = ("spec-review", "in-review", "in-progress", "addressing")


def describe(row):
    # Convention: an issue is always `<number>: <title>`, never a bare number.
    return f"{row['number']}: {row['title']}"


def liveness_marker(row):
    if row["status"] not in PAST_READY_STATUSES:
        return ""
    if not row["agent_active"]:
        return " 🔴 STALLED — no agent:active label"
    # The label is a claim, not proof: a crashed issue-manager leaves it set. But attach_id only ever
    # sees THIS machine's sessions, so its absence does not prove death -- the session may be
    # running on another machine, or the claude CLI may have failed. Three honest states, not two.
    if not row["attach_id"]:
        return " 🟡 claimed — agent:active set, no session on this machine"
    return " 🟢 active"


def render_row(row):
    bits = [f"{row['status'] or '(no status)':13} #{row['number']:<5} {keycap(row['priority'])} {row['title']}"]
    bits.append(f"@{row['assignee']}" if row["assignee"] else "(unclaimed)")
    if row["pr_number"]:
        ci_marker = {"green": "✅ CI", "running": "⏳ CI", "failing": "❌ CI"}[row["ci"]]
        bits.append(f"PR #{row['pr_number']} {ci_marker}")
    marker = liveness_marker(row).strip()
    if marker:
        bits.append(marker)
    if row["attach_id"]:
        bits.append(f"(attach: claude agents — select {row['attach_id']})")
    if row["blocked"]:
        bits.append(f"🔒 BLOCKED on {row['blocked_note']}")
    if row["needs_attention"]:
        bits.append(f"🆘 NEEDS ATTENTION — {row['attention_note']}")
    return "  " + "  ".join(b for b in bits if b)


def render_section(header, rows):
    # Every bucket renders the same shape: a header, its rows, and one trailing separator -- and
    # an empty bucket renders nothing at all, so the board never shows a header with no rows.
    out = []
    if rows:
        out.append(header)
        for r in rows:
            out.append(render_row(r))
        out.append("")
    return out


# READY is the third unbounded category. `groom` adds status:ready issues and only `activate`
# removes them, so a repo that grooms faster than it activates renders an ever-longer block. Five
# is the display bound; --ready-limit raises it.
DEFAULT_READY_LIMIT = 5


def render_ready(ready_rows, limit=DEFAULT_READY_LIMIT):
    if not ready_rows:
        return []
    # `staged` is sorted by (priority, number) before bucketing, so ready_rows already arrives in
    # priority order and the first N are the N highest-priority ready issues. A slice of an
    # unsorted list would be arbitrary.
    out = render_section("📋 READY", ready_rows[:limit])
    # max(0, ...) is the guard, not a redundancy: count_bit tests `if not n`, which is false for a
    # negative, so count_bit(-3, ...) returns '-3 more ready'. The plural is passed explicitly to
    # avoid "1 more readys".
    withheld = count_bit(max(0, len(ready_rows) - limit), "more ready", "more ready")
    if withheld:
        # Inside the block, under the rows: the count belongs beside what it describes. The
        # trailing separator render_section appended stays last.
        out.insert(-1, f"  … {withheld} — raise --ready-limit to see the rest")
    return out


# --- Next up (never an epic) ---------------------------------------------------------------
# (verb, row, action) — rendered as a header plus one `- <number>: <title> → <action>` line, so
# the title is never wedged between two colons in a single sentence. See the convention in
# docs/workflow.md.
def compute_next_up(ready_rows):
    # The ONE thing the board recommends: an unclaimed status:ready issue, highest priority first.
    # It is the only work on the board with no owner at all. Merging a green PR, unblocking a
    # stopped agent and grooming a backlog issue were each recommended here once, and each names
    # work another agent already drives -- that issue's own issue-manager, or the backlog's. The
    # board reports state; it does not direct work it does not drive. See design.md, D4.
    unclaimed_ready = [r for r in ready_rows if r["assignee"] is None]
    if not unclaimed_ready:
        return None
    unclaimed_ready.sort(key=lambda r: priority_key(r["priority"]))
    top = unclaimed_ready[0]
    return ("activate", top, f"/spec-flow:activate {top['number']}")


def count_bit(n, singular, plural=None):
    # A zero count renders nothing at all. `blocked: 0` makes the reader parse a number to learn
    # that nothing happened; an absent entry reports the same thing by saying nothing.
    if not n:
        return None
    return f"{n} {singular if n == 1 else (plural or singular + 's')}"


def render_summary(non_epics, blocked_rows, backlog, epics):
    # The ungroomed backlog and the epic list appear here and nowhere else. Both grow without
    # bound -- the delivery buckets above are bounded by how many agents can run at once, these are
    # bounded by nothing -- so they report as a number and the board's length stops tracking the
    # size of the backlog. See design.md, D2.
    summary_bits = [
        count_bit(len(backlog), "ungroomed", "ungroomed"),
        count_bit(len(epics), "epic"),
        count_bit(sum(1 for r in non_epics if r["agent_active"]), "agent:active", "agent:active"),
        count_bit(len(blocked_rows), "blocked", "blocked"),
        count_bit(sum(1 for r in non_epics if r["needs_attention"]), "needs-attention", "needs-attention"),
        count_bit(sum(1 for r in non_epics if r["attach_id"]), "local session matched", "local sessions matched"),
        count_bit(sum(1 for r in non_epics if r["pr_number"]), "open PR"),
    ]
    summary_bits = [b for b in summary_bits if b]
    if not summary_bits:
        return []
    return ["(" + " · ".join(summary_bits) + ")"]


def render_archive_suggestion(archive_pending):
    # Its own line rather than a summary entry, and only when something is actually pending: the
    # absent line is the report. On screen there is something to archive; off screen there is not,
    # with no `specs pending archive: 0` to read past either way.
    if not archive_pending:
        return []
    noun = "spec" if archive_pending == 1 else "specs"
    return ["", f"🗄️  {archive_pending} {noun} pending archive → /spec-flow:archive"]


def render_next_up(next_up):
    out = []
    if next_up:
        out.append("")
        verb, row, action = next_up
        out.append(f"➡️  Next up — {verb}:")
        out.append(f"  - {describe(row)} → {action}")
    return out


# Convention: one issue per line, `- <number>: <title>` — never comma-joined inline.
# See docs/workflow.md, "Conventions".
def render_stalled(stalled):
    out = []
    if stalled:
        out.append("")
        out.append("🔴 Stalled (yours, no agent:active):")
        for r in stalled:
            out.append(f"  - {describe(r)} → {SPAWN_SCRIPT} {r['number']}")
    return out


def render_blocked(blocked_rows):
    out = []
    if blocked_rows:
        out.append("")
        out.append("🔒 Blocked:")
        for r in blocked_rows:
            out.append(f"  - {describe(r)} — {r['blocked_note']}")
    return out


def render_board(rows, me, archive_pending, ready_limit=DEFAULT_READY_LIMIT):
    epics = [r for r in rows if r["is_epic"]]
    non_epics = [r for r in rows if not r["is_epic"]]
    # Counted, never rendered as rows -- so neither list needs sorting.
    backlog = [r for r in non_epics if r["status"] is None]
    staged = [r for r in non_epics if r["status"] is not None]
    staged.sort(key=lambda r: (priority_key(r["priority"]), r["number"]))

    def is_blocked_on_you(r):
        if not r["mine"]:
            return False
        if r["needs_attention"]:
            return True
        if r["status"] == "spec-review":
            return True
        # green: ready for the owner. None: no PR resolved through closingIssuesReferences -- a
        # missing correlation, not a running pipeline, so the owner is still the blocker. Failing
        # and running both belong to the pipeline (address handles a red PR), not to the owner.
        if r["status"] == "in-review" and r["ci"] in ("green", None):
            return True
        # activate's design-choice stop is a real wait on the owner, but it holds status:ready the
        # whole time (the flip happens later, in step 7). A ready issue that is claimed -- assigned,
        # with a live session -- is parked on an answer, not waiting to be picked up.
        if r["status"] == "ready" and r["agent_active"]:
            return True
        return False

    def is_stalled(r):
        # Only a MISSING label proves nothing is driving this. A label with no local session is
        # ambiguous (another machine, or a dead session) -- the 🟡 marker reports that honestly
        # rather than asserting death here, where the suggested remedy is a spawn that
        # spawn-issue-manager.sh would refuse anyway while the label is still set.
        return r["mine"] and r["status"] in PAST_READY_STATUSES and not r["agent_active"]

    blocked_on_you = [r for r in staged if is_blocked_on_you(r)]
    # Membership by issue number, not by row. `r not in blocked_on_you` compares whole row dicts
    # field by field against every entry, over up to ISSUE_LIMIT staged rows and three buckets.
    # The number is the row's identity, so the set answers the same question directly.
    blocked_numbers = {r["number"] for r in blocked_on_you}

    ready_rows = [r for r in staged
                  if r["status"] == "ready" and r["number"] not in blocked_numbers]
    # Includes spec-review too -- someone ELSE's spec-review issue is neither "blocked on you"
    # (not yours) nor ready/backlog, so without this it would silently vanish from the board
    # entirely instead of showing "for visibility" as the spec requires.
    in_flight = [r for r in staged if r["status"] in PAST_READY_STATUSES
                 and r["number"] not in blocked_numbers]

    # An issue whose status: label matches nothing this script knows (a typo like
    # "status:in-progres", or a label added since) is counted in the summary but rendered by no
    # bucket above -- it silently vanishes from the board. STATUS_ORDER exists to name the valid
    # set; use it rather than letting an unknown value fall through every branch.
    unrecognized = [r for r in staged
                    if r["status"] not in STATUS_ORDER
                    and r["number"] not in blocked_numbers]

    stalled = [r for r in staged if is_stalled(r)]
    blocked_rows = [r for r in non_epics if r["blocked"]]
    # compute_next_up receives the full list, never the slice: the cap is a display bound, not a
    # change to what the board considers. render_board never holds a truncated list, so no later
    # edit can hand one to compute_next_up by mistake.
    next_up = compute_next_up(ready_rows)

    out = ["## Delivery board", ""]
    out += render_section("⛳ BLOCKED ON YOU", blocked_on_you)
    out += render_section("❓ UNRECOGNIZED STATUS (fix the label — these are in no pipeline stage)",
                          unrecognized)
    out += render_section("🔧 IN FLIGHT (agents / CI)", in_flight)
    out += render_ready(ready_rows, ready_limit)
    out += render_summary(non_epics, blocked_rows, backlog, epics)
    out += render_archive_suggestion(archive_pending)
    out += render_next_up(next_up)
    out += render_stalled(stalled)
    out += render_blocked(blocked_rows)

    # Each row section appends a trailing "" to separate itself from the next one. Whichever
    # section happens to be last has nothing to separate itself from, so drop that separator --
    # otherwise removing sections leaves the board padded with the gaps they used to fill.
    while out and not out[-1]:
        out.pop()

    return "\n".join(out)


def positive_int(value):
    # An argparse type= callable rather than a check after parse_args: it gives exit 2, argparse's
    # own `argument --ready-limit:` prefix and the usage line, and it runs before any gh call, so
    # no board can print on the error path.
    try:
        n = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected an integer, got {value!r}")
    if n < 1:
        raise argparse.ArgumentTypeError(f"must be 1 or more, got {n}")
    return n


def main():
    parser = argparse.ArgumentParser(description="Render the spec-flow delivery board deterministically.")
    parser.add_argument("--user", help="scope 'blocked on you' to this login (default: gh's authenticated user)")
    parser.add_argument("--ready-limit", type=positive_int, default=DEFAULT_READY_LIMIT,
                        help=f"how many READY rows to render (default: {DEFAULT_READY_LIMIT}); "
                             "the rest report as a count. A large N is the uncap.")
    args = parser.parse_args()

    for binary in ("gh", "git"):
        if shutil.which(binary) is None:
            fail(f"'{binary}' is required but not on PATH.")

    with ThreadPoolExecutor(max_workers=4) as pool:
        issues_f = pool.submit(fetch_issues)
        prs_f = pool.submit(fetch_prs)
        sessions_f = pool.submit(fetch_sessions)
        archive_f = pool.submit(fetch_archive_pending)
        me = args.user or fetch_me()
        issues, prs, sessions, archive_pending = issues_f.result(), prs_f.result(), sessions_f.result(), archive_f.result()

    warn_if_truncated(issues, prs)

    if me is None:
        print("board: warning: couldn't resolve the authenticated user ('gh api user' failed) — "
              "'mine'/'blocked on you' scoping will show nothing as yours", file=sys.stderr)

    blocked_bodies, attention_bodies = prefetch_notes(issues)

    def blocked_reason_fn(n):
        body = blocked_bodies.get(n)
        if not body:
            return None
        m = re.match(r"^(⛔ Blocked on #\d+[^\n]*)", body)
        return m.group(1) if m else body.splitlines()[0]

    def needs_attention_note_fn(n):
        body = attention_bodies.get(n)
        return body.splitlines()[0] if body else None

    rows = build_rows(issues, prs, me, sessions, blocked_reason_fn, needs_attention_note_fn)
    print(render_board(rows, me, archive_pending, args.ready_limit))


if __name__ == "__main__":
    main()
