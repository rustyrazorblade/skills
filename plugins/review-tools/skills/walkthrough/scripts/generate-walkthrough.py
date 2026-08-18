#!/usr/bin/env python3
"""Deterministic renderer for a `walkthrough` presentation: an agent-authored manifest (a diagram
plus an ordered list of narrated steps) in, one self-contained HTML file out. Stdlib only (json,
argparse, pathlib, webbrowser) — no pip dependencies, no `git`/`gh`, no network. Must run on macOS
system python3 and in CI (Linux).

Unlike generate-explain.py, this script derives NOTHING: it validates the manifest and injects it
into the viewer shell, nothing more. Every byte of content — the diagram markup, each step's
narration, each code excerpt — is written by the invoking agent. See
plugins/review-tools/skills/walkthrough/SKILL.md for the manifest schema and authoring guidance.
"""

import argparse
import functools
import json
import sys
import webbrowser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "lib"))
from html_shell import default_out_path, inject_manifest  # noqa: E402
from html_shell import fail as _fail  # noqa: E402

PROG = "generate-walkthrough"
fail = functools.partial(_fail, prog=PROG)

DIAGRAM_TYPES = ("svg", "html")


def load_manifest(path):
    p = Path(path)
    if not p.is_file():
        fail(f"--manifest file not found: {path}")
    try:
        text = p.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        fail(f"--manifest: couldn't read {path}: {e}")
    if not text.strip():
        fail(f"--manifest: {path} is empty — a walkthrough needs a diagram and at least one step")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        fail(f"--manifest: couldn't parse {path} as JSON: {e}")
    if not isinstance(data, dict):
        fail(f"--manifest: expected a JSON object at the top level, got {type(data).__name__}")
    return data


def require_text(value, what):
    """The one shape check every required string field shares: present, a string, and not blank.
    Returns an error phrase, or None when the value is fine."""
    if value is None:
        return f"missing required field {what}"
    if not isinstance(value, str):
        return f"{what} must be a string, got {type(value).__name__}"
    if not value.strip():
        return f"{what} is empty"
    return None


def validate_diagram(diagram):
    if diagram is None:
        fail("manifest is missing its required 'diagram' — a walkthrough always leads with a "
             "diagram, never a bare list of steps")
    if not isinstance(diagram, dict):
        fail(f"'diagram' must be an object with 'type' and 'source', got {type(diagram).__name__}")
    problem = require_text(diagram.get("source"), "'diagram.source'")
    if problem:
        fail(f"{problem} — there is nothing to draw")
    diagram_type = diagram.get("type")
    if diagram_type not in DIAGRAM_TYPES:
        fail(f"'diagram.type' must be one of {'/'.join(DIAGRAM_TYPES)}, got {diagram_type!r} — "
             "diagrams are agent-authored inline markup; no diagramming library is bundled")


def step_label(index, step):
    """"step 2 ('Wiring')" — the 1-based position always, plus the title when there is one to
    quote. An error that only says "a step is invalid" is useless in a 12-step manifest."""
    title = step.get("title") if isinstance(step, dict) else None
    if isinstance(title, str) and title.strip():
        return f"step {index} ({title.strip()!r})"
    return f"step {index}"


def validate_excerpt(excerpt, index, label):
    where = f"{label}, excerpt {index}"
    if not isinstance(excerpt, dict):
        fail(f"{where}: must be an object, got {type(excerpt).__name__}")
    for field in ("path", "code"):
        problem = require_text(excerpt.get(field), f"'{field}'")
        if problem:
            fail(f"{where}: {problem}")
    start_line = excerpt.get("startLine")
    if start_line is None:
        fail(f"{where}: missing required field 'startLine'")
    if isinstance(start_line, bool) or not isinstance(start_line, int):
        fail(f"{where}: 'startLine' must be an integer, got {type(start_line).__name__}")

    # The one optional field the viewer can't shrug off: it iterates `highlight` directly, so a
    # non-list here would blank the whole presentation at open time while this script still
    # exited 0. Every other optional field renders harmlessly whatever its type.
    highlight = excerpt.get("highlight")
    if highlight is not None:
        if not isinstance(highlight, list) or any(
                isinstance(n, bool) or not isinstance(n, int) for n in highlight):
            fail(f"{where}: 'highlight' must be a list of line numbers, got {highlight!r}")


def validate_step(step, index):
    label = step_label(index, step)
    if not isinstance(step, dict):
        fail(f"{label}: must be an object, got {type(step).__name__}")
    for field in ("title", "narration"):
        problem = require_text(step.get(field), f"'{field}'")
        if problem:
            fail(f"{label}: {problem}")
    excerpts = step.get("excerpts")
    if excerpts is None:
        fail(f"{label}: missing required field 'excerpts' — every step shows at least one excerpt")
    if not isinstance(excerpts, list):
        fail(f"{label}: 'excerpts' must be a list, got {type(excerpts).__name__}")
    if not excerpts:
        fail(f"{label}: 'excerpts' is empty — every step shows at least one excerpt")
    for i, excerpt in enumerate(excerpts, start=1):
        validate_excerpt(excerpt, i, label)


def validate(manifest, source_path):
    problem = require_text(manifest.get("title"), "'title'")
    if problem:
        fail(f"manifest {problem}")
    validate_diagram(manifest.get("diagram"))
    steps = manifest.get("steps")
    if steps is None:
        fail("manifest is missing its required 'steps' list")
    if not isinstance(steps, list):
        fail(f"'steps' must be a list, got {type(steps).__name__}")
    if not steps:
        fail(f"--manifest: {source_path} has an empty 'steps' list — a walkthrough with no steps "
             "is never worth rendering")
    for i, step in enumerate(steps, start=1):
        validate_step(step, i)


def main():
    parser = argparse.ArgumentParser(
        description="Render an agent-authored walkthrough manifest (diagram + ordered steps) as "
                    "one self-contained HTML presentation.")
    parser.add_argument("--manifest", required=True, metavar="PATH",
                        help="the walkthrough manifest JSON — the sole source of content; this "
                             "script derives nothing on its own")
    parser.add_argument("--out", help="output HTML path (default: a generated path under the system temp dir)")
    parser.add_argument("--open", action="store_true", help="open the result in a browser (only when explicitly passed)")
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    validate(manifest, args.manifest)

    viewer_path = Path(__file__).resolve().parent.parent / "assets" / "viewer.html"
    if not viewer_path.is_file():
        fail(f"viewer shell not found at {viewer_path} — was assets/viewer.html removed?")
    viewer_html = viewer_path.read_text(encoding="utf-8")

    out_html = inject_manifest(viewer_html, manifest, PROG)

    out_path = Path(args.out).resolve() if args.out else default_out_path("walkthrough-")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(out_html, encoding="utf-8")

    print(str(out_path))
    print(f"open {out_path}")

    if args.open:
        webbrowser.open(f"file://{out_path}")


if __name__ == "__main__":
    main()
