#!/usr/bin/env python3
"""Hidden check for test-driven-development/split-bill. Run in the project folder. Exit 0 = pass.
1. The agent's split_bill (ledger/split.py) matches the reference on the issue's examples, the error rules and 2000
   seeded random inputs.
2. The agent's tests (everything under tests/) pass when ledger/split.py is replaced by the reference, and fail for
   at least 8 of 10 seeded mutants of the reference."""
import os, random, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REF = open(os.path.join(HERE, "split_ref.py")).read()
NEED = 8
MUTANTS = [
    ("ties go to the later position", "key=lambda i: (-rema[i], i)", "key=lambda i: (-rema[i], -i)"),
    ("leftover cents go to the first positions", "order = sorted(range(len(weights)), key=lambda i: (-rema[i], i))",
     "order = list(range(len(weights)))"),
    ("leftover cents go to the largest weights", "key=lambda i: (-rema[i], i)", "key=lambda i: (-weights[i], i)"),
    ("leftover cents go to the smallest remainders", "key=lambda i: (-rema[i], i)", "key=lambda i: (rema[i], i)"),
    ("all-zero weights not a ValueError", '    if whole == 0:\n        raise ValueError("all weights are zero")\n', ""),
    ("negative weight accepted", "    if any(w < 0 for w in weights):", "    if any(w < -1000 for w in weights):"),
    ("negative total accepted", "or total_cents < 0:", "or total_cents < -1000:"),
    ("non-integer total accepted", "if not isinstance(total_cents, int) or", "if"),
    ("empty weights return []", '        raise ValueError("no weights")', "        return []"),
    ("zero weights dropped from the result", "    return base", "    return [b for b, w in zip(base, weights) if w]"),
]


def outcome(fn, total, weights):
    try:
        return ("ok", fn(total, list(weights)))
    except ValueError:
        return ("ValueError",)
    except Exception as e:
        return ("other error", type(e).__name__)


def check_impl(root, problems):
    ns = {}
    exec(compile(REF, "split_ref.py", "exec"), ns)
    ref = ns["split_bill"]
    sys.path.insert(0, root)
    try:
        from ledger.split import split_bill
    except Exception as e:
        problems.append(f"can't import split_bill from ledger/split.py: {e!r}"); return
    cases = [(100, [1, 1, 1]), (1000, [2, 1, 1]), (0, [1, 2]), (7, [3, 1, 1]), (100, [1, 2]), (5, [0, 1, 0, 1]),
             (1, [1, 1]), (10, []), (10, [1, -1]), (10, [0, 0]), (-1, [1]), (10.5, [1, 1]), (99, [5]), (3, [0, 2, 1])]
    rnd = random.Random(42)
    for _ in range(2000):
        n = rnd.randint(1, 6)
        cases.append((rnd.randint(0, 5000), [rnd.choice([0, 1, 1, 2, 3, 5, 7, 10]) for _ in range(n)]))
    bad = [(t, w, outcome(split_bill, t, w), outcome(ref, t, w)) for t, w in cases
           if outcome(split_bill, t, w) != outcome(ref, t, w)]
    if bad:
        t, w, got, want = bad[0]
        problems.append(f"split_bill differs from the issue on {len(bad)} inputs, e.g. split_bill({t}, {w}) "
                        f"gave {got}, want {want}")


def run_tests(proj, source):
    with open(os.path.join(proj, "ledger", "split.py"), "w") as f:
        f.write(source)
    for d, _, _ in os.walk(proj):
        if d.endswith("__pycache__"):
            shutil.rmtree(d, ignore_errors=True)
    try:
        p = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=proj,
                           capture_output=True, text=True, timeout=60)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def check_tests(root, problems):
    work = tempfile.mkdtemp(prefix="tdd-check-")
    try:
        proj = os.path.join(work, "p")
        shutil.copytree(root, proj, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        rc, out = run_tests(proj, REF)
        if rc != 0:
            problems.append("the tests fail on a correct split_bill (they assert something the issue doesn't say):\n"
                            + out[-1200:]); return
        killed, survived = 0, []
        for name, old, new in MUTANTS:
            assert REF.count(old) == 1, name
            rc, _ = run_tests(proj, REF.replace(old, new))
            killed += rc != 0
            if rc == 0:
                survived.append(name)
        print(f"mutants killed: {killed}/{len(MUTANTS)}")
        for s in survived:
            print("  survived:", s)
        if killed < NEED:
            problems.append(f"the tests kill {killed}/{len(MUTANTS)} mutants, need {NEED}")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    root = os.getcwd()
    problems = []
    if not os.path.isfile(os.path.join(root, "tests", "test_split.py")):
        problems.append("no tests/test_split.py")
    check_impl(root, problems)
    check_tests(root, problems)
    for p in problems:
        print("FAIL:", p)
    print("PASS" if not problems else "")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
