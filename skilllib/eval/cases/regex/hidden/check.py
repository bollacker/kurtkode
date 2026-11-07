#!/usr/bin/env python3
"""Hidden check for regex/access-log. Run in the project folder. Exit 0 = pass.
1. parse_line gives the exact expected record for 10 unseen request lines (quoted user with non-ASCII letters,
   seconds, `user=`/`took=` inside the query string, CRLF, trailing spaces, extra fields, PATCH, DEBUG level)
   and None for 13 look-alikes (request text inside another message or another component, lower-case or
   unknown method, missing or malformed fields, unknown level, no timestamp).
2. The project's own tests pass."""
import json, os, subprocess, sys

case = os.environ["CASE_DIR"]
cases = [json.loads(l) for l in open(os.path.join(case, "hidden", "cases.jsonl"), encoding="utf-8")]
prog = r'''
import json, sys
sys.path.insert(0, ".")
from logparse import parse_line
out = []
for line in json.load(sys.stdin):
    try:
        out.append(parse_line(line))
    except Exception as e:
        out.append({"__error__": repr(e)})
print(json.dumps(out))
'''
problems = []
p = subprocess.run([sys.executable, "-c", prog], input=json.dumps([c["line"] for c in cases]), capture_output=True,
                   text=True, timeout=60)
try:
    got = json.loads(p.stdout)
except ValueError:
    print("FAIL: could not run parse_line:", (p.stdout + p.stderr)[-400:])
    sys.exit(1)
for c, g in zip(cases, got):
    want = c["want"]
    ok = (g is None) if want is None else (isinstance(g, dict) and g.get("status") == want["status"]
        and type(g.get("status")) is int and abs(float(g.get("ms", -1)) - want["ms"]) < 1e-6
        and {k: g.get(k) for k in ("method", "path", "user")} == {k: want[k] for k in ("method", "path", "user")})
    if not ok:
        problems.append(f"{c['line']!r}: got {g}, want {want}")
p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], capture_output=True,
                   text=True, timeout=60)
if p.returncode:
    problems.append("project tests fail: " + (p.stdout + p.stderr)[-300:])
for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else f"{len(problems)} problem(s)")
sys.exit(1 if problems else 0)
