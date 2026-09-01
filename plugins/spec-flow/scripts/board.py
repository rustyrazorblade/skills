#!/usr/bin/env python3
"""Deterministic board renderer for spec-flow's `board` skill.

Moves everything `board/SKILL.md` used to make the model do by hand — pulling raw `gh issue
list`/`gh pr list` JSON into context, joining it against PR/CI state and local sessions, bucketing
by lifecycle, computing "next up"/"blocked on you"/"stalled", and formatting the final board text —
into one script. The model runs this and prints its stdout; it never sees the raw GitHub JSON and
never hand-writes a join script. Stdlib only, shells out to `gh`/`git`/`claude`. See
plugins/spec-flow/skills/board/SKILL.md for the render this reproduces and the rules behind it.
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
# script already lives in scripts/ alongside spawn-issue-pm.sh.
SPAWN_SCRIPT = str(Path(__file__).resolve().parent / "spawn-issue-pm.sh")

STATUS_ORDER = ["spec-review", "in-review", "in-progress", "addressing", "ready"]
PRIORITY_ORDER = ["P0", "P1", "P2", "P3"]


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


def fetch_issues():
    return gh_json(["issue", "list", "--state", "open", "--json",
                     "number,title,labels,url,assignees,subIssuesSummary,subIssues", "--limit", "100"], default=[])


def fetch_prs():
    return gh_json(["pr", "list", "--state", "open", "--json",
                     "number,headRefName,title,reviewDecision,url,statusCheckRollup,closingIssuesReferences",
                     "--limit", "100"], default=[])


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
    try:
        comments = json.loads(run(["gh", "issue", "view", str(number), "--json", "comments"])).get("comments", [])
    except subprocess.CalledProcessError:
        return None
    candidates = [c.get("body", "") for c in comments if not prefix or c.get("body", "").startswith(prefix)]
    return candidates[-1] if candidates else None


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
        if legacy_state == "PENDING" or status in ("QUEUED", "IN_PROGRESS"):
            running = True
        elif legacy_state == "SUCCESS" or conclusion in ("SUCCESS", "NEUTRAL", "SKIPPED"):
            continue
        else:
            failing = True
    if running:
        return "running"
    if failing:
        return "failing"
    return "green"


def label_names(issue):
    return {l["name"] for l in issue.get("labels", [])}


def status_of(issue):
    for name in label_names(issue):
        if name.startswith("status:"):
            return name[len("status:"):]
    return None


def priority_of(issue):
    for name in label_names(issue):
        if name in PRIORITY_ORDER:
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

    # (name, id, startedAt) tuples, not a dict keyed by exact name -- spawn-issue-pm.sh names a
    # session "issue-pm-<N>-<slug>" (a readable slug from the issue title, so several open tabs
    # are distinguishable at a glance), never a fixed string this side could match exactly
    # against. startedAt is kept so a rare double-match (a stale registry entry alongside its
    # live respawn) resolves to the most recent session, the same tie-break
    # spawn-issue-pm.sh's own lookup already uses (`sort_by(.startedAt) | last`).
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
            "sub_issues": issue.get("subIssues", {}).get("nodes", []) if is_epic else [],
            "sub_total": (issue.get("subIssuesSummary") or {}).get("total", 0),
            "sub_completed": (issue.get("subIssuesSummary") or {}).get("completed", 0),
            "agent_active": "agent:active" in labels,
            "blocked": "blocked" in labels,
            "needs_attention": "needs-attention" in labels,
            "pr_number": pr["number"] if pr else None,
            "pr_url": pr["url"] if pr else None,
            "ci": ci_status(pr.get("statusCheckRollup")) if pr else None,
        }
        # Boundary-safe prefix match (exact "issue-pm-<n>", or "issue-pm-<n>-" followed by the
        # slug) so issue #4 can never match a live "issue-pm-42-..." session -- a bare
        # startswith("issue-pm-4") would.
        session_prefix = f"issue-pm-{n}"
        attach_id = None
        if row["agent_active"]:
            matches = [
                (live_id, started_at) for live_name, live_id, started_at in live_sessions
                if live_name == session_prefix or live_name.startswith(session_prefix + "-")
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


# Everything "past status:ready" in the pipeline sense -- a live issue-pm SHOULD be driving each
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
    # The label is a claim, not proof: a crashed issue-pm leaves it set. But attach_id only ever
    # sees THIS machine's sessions, so its absence does not prove death -- the session may be
    # running on another machine, or the claude CLI may have failed. Three honest states, not two.
    if not row["attach_id"]:
        return " 🟡 claimed — agent:active set, no session on this machine"
    return " 🟢 active"


def render_row(row):
    bits = [f"{row['status'] or '(no status)':13} #{row['number']:<5} {row['priority'] or '--':3} {row['title']}"]
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


def render_board(rows, me, archive_pending):
    epics = [r for r in rows if r["is_epic"]]
    non_epics = [r for r in rows if not r["is_epic"]]
    backlog = [r for r in non_epics if r["status"] is None]
    staged = [r for r in non_epics if r["status"] is not None]
    staged.sort(key=lambda r: (priority_key(r["priority"]), r["number"]))
    backlog.sort(key=lambda r: (priority_key(r["priority"]), r["number"]))

    def is_blocked_on_you(r):
        if r["needs_attention"] and r["mine"]:
            return True
        if r["status"] == "spec-review" and r["mine"]:
            return True
        if r["status"] == "in-review" and r["mine"] and r["ci"] == "green":
            return True
        return False

    def is_stalled(r):
        # Only a MISSING label proves nothing is driving this. A label with no local session is
        # ambiguous (another machine, or a dead session) -- the 🟡 marker reports that honestly
        # rather than asserting death here, where the suggested remedy is a spawn that
        # spawn-issue-pm.sh would refuse anyway while the label is still set.
        return r["mine"] and r["status"] in PAST_READY_STATUSES and not r["agent_active"]

    blocked_on_you = [r for r in staged if is_blocked_on_you(r)]
    ready_rows = [r for r in staged if r["status"] == "ready"]
    # Includes spec-review too -- someone ELSE's spec-review issue is neither "blocked on you"
    # (not yours) nor ready/backlog, so without this it would silently vanish from the board
    # entirely instead of showing "for visibility" as the spec requires.
    in_flight = [r for r in staged if r["status"] in PAST_READY_STATUSES
                 and r not in blocked_on_you]

    out = ["## Delivery board", ""]

    if blocked_on_you:
        out.append("⛳ BLOCKED ON YOU")
        for r in blocked_on_you:
            out.append(render_row(r))
        out.append("")

    if in_flight:
        out.append("🔧 IN FLIGHT (agents / CI)")
        for r in in_flight:
            out.append(render_row(r))
        out.append("")

    if ready_rows:
        out.append("📋 READY")
        for r in ready_rows:
            out.append(render_row(r))
        out.append("")

    if backlog:
        out.append("📥 BACKLOG (ungroomed)")
        for r in backlog:
            out.append(f"  (no labels)  #{r['number']:<5} {r['title']}  → /spec-flow:groom {r['number']}")
        out.append("")

    if epics:
        out.append("📦 EPICS (not directly workable — see sub-issues)")
        for r in epics:
            out.append(f"  {r['status'] or '(no status)':13} #{r['number']:<5} {r['priority'] or '--':3} {r['title']}  "
                        f"{r['sub_total']} sub-issues ({r['sub_completed']} done)")
            # Convention: one issue per line, `- <number>: <title>` — never a comma-joined
            # run of issues inline. See docs/workflow.md, "Conventions".
            if r["sub_issues"]:
                for s in r["sub_issues"]:
                    out.append(f"      - {s.get('number')}: {s.get('title', '')}")
            else:
                out.append("      (no sub-issues listed)")
        out.append("")

    # --- Next up (scoped to `me`, never an epic) -------------------------------------------
    # (verb, row, action) — rendered as a header plus one `- <number>: <title> → <action>` line,
    # so the title is never wedged between two colons in a single sentence. See the convention in
    # docs/workflow.md.
    next_up = None
    mine_in_review_green = [r for r in staged if r["mine"] and r["status"] == "in-review" and r["ci"] == "green"]
    if mine_in_review_green:
        mine_in_review_green.sort(key=lambda r: priority_key(r["priority"]))
        top = mine_in_review_green[0]
        next_up = ("finish", top, f"PR #{top['pr_number']} is green, merge it")
    else:
        unclaimed_ready = [r for r in ready_rows if r["assignee"] is None]
        if unclaimed_ready:
            unclaimed_ready.sort(key=lambda r: priority_key(r["priority"]))
            top = unclaimed_ready[0]
            next_up = ("activate", top, f"/spec-flow:activate {top['number']}")
        elif backlog:
            top = backlog[0]
            next_up = ("groom", top, f"/spec-flow:groom {top['number']}")

    stalled = [r for r in staged if is_stalled(r)]
    blocked_rows = [r for r in non_epics if r["blocked"]]

    summary_bits = [
        f"agent:active: {sum(1 for r in non_epics if r['agent_active'])}",
        f"blocked: {len(blocked_rows)}",
        f"needs-attention: {sum(1 for r in non_epics if r['needs_attention'])}",
        f"local sessions matched: {sum(1 for r in non_epics if r['attach_id'])}",
        f"open PRs: {sum(1 for r in non_epics if r['pr_number'])}",
    ]
    if archive_pending:
        summary_bits.append(f"specs pending archive: {archive_pending} → /spec-flow:archive")
    out.append("(" + " · ".join(summary_bits) + ")")

    if next_up:
        out.append("")
        verb, row, action = next_up
        out.append(f"➡️  Next up — {verb}:")
        out.append(f"  - {describe(row)} → {action}")
    # Convention: one issue per line, `- <number>: <title>` — never comma-joined inline.
    # See docs/workflow.md, "Conventions".
    if stalled:
        out.append("")
        out.append("🔴 Stalled (yours, no agent:active):")
        for r in stalled:
            out.append(f"  - {describe(r)} → {SPAWN_SCRIPT} {r['number']}")
    if blocked_rows:
        out.append("")
        out.append("🔒 Blocked:")
        for r in blocked_rows:
            out.append(f"  - {describe(r)} — {r['blocked_note']}")

    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description="Render the spec-flow delivery board deterministically.")
    parser.add_argument("--user", help="scope 'next up'/'blocked on you' to this login (default: gh's authenticated user)")
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

    if me is None:
        print("board: warning: couldn't resolve the authenticated user ('gh api user' failed) — "
              "'mine'/'blocked on you' scoping will show nothing as yours", file=sys.stderr)

    def blocked_reason_fn(n):
        body = last_comment_matching(n, prefix="⛔ Blocked on")
        if not body:
            return None
        m = re.match(r"^(⛔ Blocked on #\d+[^\n]*)", body)
        return m.group(1) if m else body.splitlines()[0]

    def needs_attention_note_fn(n):
        # Must filter by prefix. Without one this returns the last comment of ANY kind, and the
        # pipeline posts several after an attention request, so the row shows an unrelated line.
        # issue-pm posts the request with this prefix; see agents/issue-pm.md.
        body = last_comment_matching(n, prefix="🆘 Needs attention")
        return body.splitlines()[0] if body else None

    rows = build_rows(issues, prs, me, sessions, blocked_reason_fn, needs_attention_note_fn)
    print(render_board(rows, me, archive_pending))


if __name__ == "__main__":
    main()
