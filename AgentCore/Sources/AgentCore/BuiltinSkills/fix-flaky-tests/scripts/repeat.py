#!/usr/bin/env python3
"""Run a command many times and count passes and failures (exit status 0 = pass).

Usage: repeat.py [-n RUNS] [--stop-on-fail] [--timeout SECS] -- COMMAND [ARGS...]
       (a single quoted COMMAND string is run by the shell)

Prints one line per failure (run number, exit status), then a summary line:
  "RESULT passed=P failed=F runs=N"
and the last 40 lines of the first failing run's output.

Exit codes: 0 = every run passed, 1 = at least one run failed, 2 = usage error.
"""
import argparse, subprocess, sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-n", "--runs", type=int, default=30)
    ap.add_argument("--stop-on-fail", action="store_true")
    ap.add_argument("--timeout", type=float, default=300)
    ap.add_argument("command", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.command[1:] if a.command[:1] == ["--"] else a.command
    if not cmd or a.runs < 1:
        ap.print_usage(sys.stderr)
        return 2
    shell = len(cmd) == 1
    passed = failed = 0
    first_fail = None
    for i in range(1, a.runs + 1):
        try:
            p = subprocess.run(cmd[0] if shell else cmd, shell=shell, capture_output=True, text=True, timeout=a.timeout)
            rc, out = p.returncode, p.stdout + p.stderr
        except subprocess.TimeoutExpired as e:
            rc, out = 124, f"timed out after {a.timeout}s"
        if rc == 0:
            passed += 1
        else:
            failed += 1
            print(f"run {i}: FAILED (exit {rc})")
            if first_fail is None:
                first_fail = out
            if a.stop_on_fail:
                break
    print(f"RESULT passed={passed} failed={failed} runs={passed + failed}")
    if first_fail is not None:
        print("--- first failing run (last 40 lines) ---")
        print("\n".join(first_fail.rstrip().splitlines()[-40:]))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
