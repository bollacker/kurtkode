#!/usr/bin/env python3
"""Find the test that makes another test fail when it runs first (a "polluter"), by bisection.

Usage: find_polluter.py --run 'RUNNER {tests}' --target TEST_ID --candidates FILE

  --run         a shell command that runs the given tests IN THE ORDER GIVEN; {tests} is replaced by
                space-separated test ids. Examples:
                  'python3 -m unittest {tests}'            (ids like tests.test_a.TestA.test_x)
                  'python3 -m pytest -p no:randomly -q {tests}'
                  'npx jest --runInBand {tests}'           (file paths; order may not be honored, check first)
  --target      the test that fails sometimes
  --candidates  a file with one test id per line: the tests that may run before the target

First it checks that the target passes alone and fails after all candidates; then it halves the candidates,
keeping the half that still makes the target fail, until one test is left.

Prints "POLLUTER <test id>" (exit 1: found), "NO POLLUTER: ..." (exit 0: the target never failed after the
candidates, or failed alone, which means its flakiness isn't order-dependent), or a usage error (exit 2).
"""
import argparse, shlex, subprocess, sys


def runs_fail(run, tests):
    cmd = run.replace("{tests}", " ".join(shlex.quote(t) for t in tests))
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return p.returncode != 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--candidates", required=True)
    a = ap.parse_args()
    if "{tests}" not in a.run:
        print("--run must contain {tests}", file=sys.stderr)
        return 2
    cands = [l.strip() for l in open(a.candidates) if l.strip() and l.strip() != a.target]
    if not cands:
        print("no candidates", file=sys.stderr)
        return 2
    if runs_fail(a.run, [a.target]):
        print("NO POLLUTER: the target fails when run alone (not an ordering problem; look at timing or environment)")
        return 0
    if not runs_fail(a.run, cands + [a.target]):
        print("NO POLLUTER: the target passed after all candidates in this order (try another order or more runs)")
        return 0
    steps = 0
    while len(cands) > 1:
        half = cands[: len(cands) // 2]
        rest = cands[len(cands) // 2:]
        steps += 1
        if runs_fail(a.run, half + [a.target]):
            cands = half
        elif runs_fail(a.run, rest + [a.target]):
            cands = rest
        else:
            print(f"NO POLLUTER: no single half breaks the target; it may need two tests together: {' '.join(cands)}")
            return 0
    print(f"POLLUTER {cands[0]}  (found in {steps} bisection steps)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
