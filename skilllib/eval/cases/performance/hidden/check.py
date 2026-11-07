#!/usr/bin/env python3
"""Hidden check for performance/slow-summary. Run in the project folder. Exit 0 = pass.
1. summarize() output is byte-identical to the original's on a big log and on edge cases (malformed lines, ties,
   empty input, a single user).
2. On the big log (many distinct users) it is at least 4x faster than the original, timed in the same run: best of 3
   for the new code against one run of the original, so the ratio is robust to machine speed.
The hot spot is the list-based UserIndex (O(users) per line), not the regex the user suspects."""
import os, random, subprocess, sys, tempfile

CASE = os.environ.get("CASE_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGINAL = os.path.join(CASE, "hidden", "original")
RUNNER = r'''
import hashlib, sys, time
sys.path.insert(0, sys.argv[1])
from logsum.summary import summarize
lines = open(sys.argv[2], encoding="utf-8").readlines()
best, out = None, None
for _ in range(int(sys.argv[3])):
    t = time.perf_counter(); out = summarize(lines); dt = time.perf_counter() - t
    best = dt if best is None else min(best, dt)
open(sys.argv[4], "w", encoding="utf-8").write(out)
print(best)
'''
tmp = tempfile.mkdtemp()
PATHS = ["/api/v1/orders", "/api/v1/users", "/api/v1/cart", "/api/v1/search", "/api/v1/login", "/api/v1/items"]


def log(n, users, seed, junk=0):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        ts = f"2026-09-{1 + rnd.randrange(28):02d}T{rnd.randrange(24):02d}:{rnd.randrange(60):02d}:{rnd.randrange(60):02d}"
        lvl = "ERROR" if rnd.random() < 0.05 else rnd.choice(["INFO", "WARN"])
        out.append(f"{ts} {lvl} user=n{rnd.randrange(users)}.x@corp.example path={rnd.choice(PATHS)} ms={rnd.randrange(1, 2000)}\n")
        if junk and rnd.random() < junk:
            out.append(rnd.choice(["garbage\n", "\n", f"{ts} INFO user=a path=/x\n", f"{ts} info user=a path=/x ms=3\n"]))
    return out


cases = {
    "big": log(30000, 15000, 7, junk=0.01),
    "ties": log(400, 5, 3),
    "single user": log(50, 1, 4),
    "edge": ["garbage\n", "\n", "2026-09-01T00:00:00 INFO user=a path=/x ms=1\n",
             "2026-09-01T23:00:00 ERROR user=b path=/x ms=9\n", "2026-09-01T23:30:00 INFO user=a path=/y ms=5"],
    "empty": [],
}
problems = []
times = {}
for name, lines in cases.items():
    src = os.path.join(tmp, name.replace(" ", "_") + ".log")
    open(src, "w", encoding="utf-8").write("".join(lines))
    outs = {}
    for label, root, reps in (("original", ORIGINAL, 1), ("new", os.getcwd(), 3 if name == "big" else 1)):
        dst = os.path.join(tmp, f"{label}_{name.replace(' ', '_')}.json")
        p = subprocess.run([sys.executable, "-c", RUNNER, root, src, str(reps), dst], capture_output=True, text=True,
                           timeout=600)
        if p.returncode != 0:
            problems.append(f"{label} summarize() failed on the {name} log: {(p.stdout + p.stderr)[-400:]}")
            break
        times[(label, name)] = float(p.stdout.split()[-1])
        outs[label] = open(dst, encoding="utf-8").read()
    else:
        if outs["new"] != outs["original"]:
            problems.append(f"output differs from the original on the {name} log")

if ("new", "big") in times:
    ratio = times[("original", "big")] / max(times[("new", "big")], 1e-9)
    print(f"big log: original {times[('original', 'big')]:.2f}s, new {times[('new', 'big')]:.2f}s, speedup {ratio:.1f}x")
    if ratio < 4:
        problems.append(f"speedup on the big log is {ratio:.1f}x, need at least 4x")
for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
