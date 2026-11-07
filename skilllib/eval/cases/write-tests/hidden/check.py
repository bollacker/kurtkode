#!/usr/bin/env python3
"""Hidden check for write-tests/durations. Run in the project folder. Exit 0 = pass.
The agent's tests (everything under tests/) run against the original timeparse/durations.py (they must pass) and
against 10 seeded mutants of it (each mutant is "killed" when the tests fail). Pass = tests green on the original and
at least 9 of 10 mutants killed. The module is restored from hidden/ first, so editing it doesn't help."""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ORIG = open(os.path.join(HERE, "durations_orig.py")).read()
NEED = 9

MUTANTS = [  # (name, old text, new text): each old text occurs exactly once in the original
    ("30 days exactly rejected", "    if total > MAX_SECONDS:", "    if total >= MAX_SECONDS:"),
    ("repeated unit accepted", "        if rank <= last:", "        if rank < last:"),
    ("out-of-order unit accepted", "        if rank <= last:", "        if rank == last:"),
    ("format(0) is empty", '        return "0s"', '        return ""'),
    ("parts equal to 1 dropped", "        if n:", "        if n > 1:"),
    ("negative format accepted", "    if seconds < 0 or seconds > MAX_SECONDS:", "    if seconds > MAX_SECONDS:"),
    ("format(30 days) rejected", "    if seconds < 0 or seconds > MAX_SECONDS:", "    if seconds < 0 or seconds >= MAX_SECONDS:"),
    ("blank text parses as 0", "    s = text.strip()", "    s = text"),
    ("empty text parses as 0", '    if not s:\n        raise ValueError("empty duration")\n', ""),
    ("last part wins", "        total += int(number) * UNITS[unit]", "        total = int(number) * UNITS[unit]"),
]


def run_tests(proj, source):
    with open(os.path.join(proj, "timeparse", "durations.py"), "w") as f:
        f.write(source)
    for d, _, files in os.walk(proj):
        if "__pycache__" in d:
            shutil.rmtree(d, ignore_errors=True)
    try:
        p = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=proj,
                           capture_output=True, text=True, timeout=60)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def main():
    root = os.getcwd()
    if not os.path.isdir(os.path.join(root, "tests")):
        print("FAIL: no tests/ folder"); return 1
    work = tempfile.mkdtemp(prefix="wt-check-")
    try:
        proj = os.path.join(work, "p")
        shutil.copytree(root, proj, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        rc, out = run_tests(proj, ORIG)
        if rc != 0 or "Ran 0 tests" in out:
            print("FAIL: the tests don't pass on the original module (or there are none):\n" + out[-1500:]); return 1
        killed, survived = 0, []
        for name, old, new in MUTANTS:
            assert ORIG.count(old) == 1, name
            rc, _ = run_tests(proj, ORIG.replace(old, new))
            if rc != 0:
                killed += 1
            else:
                survived.append(name)
        print(f"mutants killed: {killed}/{len(MUTANTS)}")
        for s in survived:
            print("  survived:", s)
        if killed < NEED:
            print(f"FAIL: need at least {NEED} killed"); return 1
        print("PASS"); return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
