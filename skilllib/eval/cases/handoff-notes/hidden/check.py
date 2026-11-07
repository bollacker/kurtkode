#!/usr/bin/env python3
"""Hidden check for handoff-notes/half-done-median. Run in the project folder. Exit 0 = pass.
HANDOFF.md must let a fresh session resume without the conversation:
1. it names the failing test exactly (test_median_even_count), found by running the tests;
2. it gives the project's verify command exactly (python3 tools/check.py, the one CI runs);
3. it records the current decision (even count -> mean of the two middle values), not only the reversed one;
4. it names the second failure only the verify command shows (README.md does not document --median);
5. it points at the file to change next (stats.py).
And the work in progress is left as it was: code, tests, README and NOTES.md unchanged."""
import os, re, sys

case = os.environ.get("CASE_DIR", os.path.join(os.path.dirname(__file__), ".."))
fx = os.path.join(case, "fixtures", "half-done-median")
problems = []

if not os.path.exists("HANDOFF.md"):
    problems.append("HANDOFF.md missing")
    text = ""
else:
    text = open("HANDOFF.md", errors="replace").read()
lines = text.splitlines()
low = text.lower()
if text and len([l for l in lines if l.strip()]) < 6:
    problems.append("HANDOFF.md is too short to resume from")
if text and "test_median_even_count" not in text:
    problems.append("does not name the failing test test_median_even_count")
if text and "python3 tools/check.py" not in text:
    problems.append("does not give the verify command `python3 tools/check.py`")
if text and not re.search(r"(averag|mean)[^\n]{0,80}(two middle|middle two)|(two middle|middle two)[^\n]{0,80}(averag|mean)", low):
    problems.append("does not record the decision: an even count returns the mean of the two middle values")
if text and not any("readme" in l.lower() and "median" in l.lower() for l in lines):
    problems.append("does not mention that README.md must document --median (tools/check.py fails on it)")
if text and "stats.py" not in text:
    problems.append("does not point at stats.py as where the next change goes")

expected = {
    "numstat/stats.py": os.path.join(fx, "_wip", "numstat", "stats.py"),
    "numstat/cli.py": os.path.join(fx, "_wip", "numstat", "cli.py"),
    "tests/test_stats.py": os.path.join(fx, "_wip", "tests", "test_stats.py"),
    "NOTES.md": os.path.join(fx, "_wip", "NOTES.md"),
    "README.md": os.path.join(fx, "README.md"),
}
for path, src in expected.items():
    try:
        same = open(path).read() == open(src).read()
    except OSError:
        same = False
    if not same:
        problems.append(f"{path} was changed or removed; the handoff should leave the work as it is")

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
