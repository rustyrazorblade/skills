"""Helpers shared by review-tools' HTML generators (`generate-explain.py`,
`generate-walkthrough.py`): loud failure, manifest injection into a static viewer shell, and the
default temp output path. Stdlib only — same constraint as the generators themselves (macOS system
python3 and CI Linux, no pip dependencies).

Each generator passes its own program name / filename prefix, since those are the only parts of
this logic that ever differed between them.
"""

import json
import os
import sys
import tempfile
from pathlib import Path


def fail(message, prog):
    print(f"{prog}: {message}", file=sys.stderr)
    sys.exit(1)


def inject_manifest(viewer_html, manifest, prog):
    # ensure_ascii keeps the payload plain-ASCII-safe; every "<" then becomes a "<" escape,
    # which is safe because inside JSON a "<" can only ever appear within a string literal, and
    # the parser resolves the escape back to the same character. Escaping only "</" is not
    # enough: HTML's script-data tokenizer treats an embedded "<!--" followed by "<script" as
    # entering double-escaped state, after which a later "</script>" no longer closes the tag —
    # content as ordinary as an HTML template excerpt ("<!--[if IE]><script>") would then eat
    # the rest of the page and silently render the shell's demo fallback instead.
    manifest_json = json.dumps(manifest, ensure_ascii=True).replace("<", "\\u003c")
    script_tag = f"<script>window.MANIFEST = {manifest_json};</script>"
    if "<!--MANIFEST-->" not in viewer_html:
        fail("assets/viewer.html is missing its <!--MANIFEST--> marker — was it edited?", prog)
    return viewer_html.replace("<!--MANIFEST-->", script_tag, 1)


def default_out_path(prefix):
    fd_path = Path(tempfile.gettempdir())
    fd_path.mkdir(parents=True, exist_ok=True)
    # mkstemp for a guaranteed-unique name; the caller immediately overwrites it, so the empty
    # file it creates is just a placeholder reservation.
    fd, name = tempfile.mkstemp(prefix=prefix, suffix=".html", dir=str(fd_path))
    os.close(fd)
    return Path(name)
