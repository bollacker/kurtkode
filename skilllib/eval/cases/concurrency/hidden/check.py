#!/usr/bin/env python3
"""Hidden check for concurrency/oversell. Run in the project folder. Exit 0 = pass.
1. The project's tests pass.
2. hidden/stress.py passes 3 times in a row: no overselling, no lost restocks, units conserved across concurrent
   two-way transfers, every reservation audited, and no deadlock (each run must finish within 60 s).
The stress run switches threads as often as possible and sleeps inside audit.record, so a check-then-act race shows
up every time, and a "fix" that only adds sleeps or locks part of the read-modify-write still fails."""
import os, subprocess, sys

CASE = os.environ.get("CASE_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
problems = []
p = subprocess.run([sys.executable, "-m", "unittest", "-q"], capture_output=True, text=True, timeout=120)
if p.returncode != 0:
    problems.append("the project's own tests fail:\n" + (p.stdout + p.stderr)[-600:])
for run in range(3):
    try:
        p = subprocess.run([sys.executable, os.path.join(CASE, "hidden", "stress.py")], capture_output=True,
                           text=True, timeout=60)
    except subprocess.TimeoutExpired:
        problems.append(f"stress run {run + 1} did not finish in 60 s (deadlock?)")
        break
    if p.returncode != 0:
        problems.append(f"stress run {run + 1}:\n" + (p.stdout + p.stderr)[-1200:])
        break
for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
