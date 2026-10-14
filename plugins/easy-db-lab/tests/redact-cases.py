"""Run the redaction cases in fixtures/redact/cases.tsv against report-check.py.

Usage: python3 redact-cases.py <report-check.py> <cases.tsv>

Each case line is: name, the file name the text is in, the input text, and the expected redacted
text, separated by tabs.  An expected text of = means the input stays unchanged.  Blank lines and
lines that begin with # are ignored.  For each case it prints one line, "ok<TAB>name" or
"bad<TAB>name<TAB>detail": redact() must give the expected text, and scan() must find nothing in
it.
"""

import importlib.util
import sys

spec = importlib.util.spec_from_file_location("report_check", sys.argv[1])
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

with open(sys.argv[2], encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        name, rel, given, want = line.split("\t")
        want = given if want == "=" else want
        got = check.redact(rel, given)
        left = check.scan(rel, got)
        if got != want:
            print(f"bad\t{name}\tredact gave {got!r}, expected {want!r}")
        elif left:
            print(f"bad\t{name}\tscan finds {left} in {got!r}")
        else:
            print(f"ok\t{name}")
