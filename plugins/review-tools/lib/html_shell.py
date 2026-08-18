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
    # ensure_ascii keeps the payload plain-ASCII-safe; escaping "</" as "<\/" is the standard
    # technique to stop an embedded "</script>" substring (e.g. inside a doc or diff) from
    # prematurely closing the injected <script> tag.
    manifest_json = json.dumps(manifest, ensure_ascii=True).replace("</", "<\\/")
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
