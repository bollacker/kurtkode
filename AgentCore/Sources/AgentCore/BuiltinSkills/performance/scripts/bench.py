#!/usr/bin/env python3
"""Time a command over several runs and check that an optimization kept its output identical.

Usage: bench.py [-n RUNS] [--warmup N] [--save FILE] [--compare FILE] [--max-slowdown R] [--timeout SECS]
                -- COMMAND [ARGS...]          (a single quoted COMMAND string is run by the shell)

  --save FILE      store the timings and the command's stdout (FILE and FILE.out) as the baseline
  --compare FILE   compare against a saved baseline: speedup of the median and whether stdout is identical
  --max-slowdown R with --compare, fail if the median is more than R times the baseline's (default 1.10)

Prints:
  RUNS n=5 min=1.234s median=1.250s max=1.301s
  OUTPUT sha256=<first 16 hex> bytes=<n> exit=<status>
  with --compare also:
  BASELINE median=2.400s  NOW median=0.240s  SPEEDUP 10.00x
  OUTPUT same | OUTPUT DIFFERENT first difference at line <k>
Times are wall clock per run, including process start-up: use an input big enough that a run takes 0.5 s or more.
Exit codes: 0 = ran (and with --compare: output identical and not slower than allowed),
1 = the command failed, the output differs from the baseline or it got slower, 2 = usage error.
"""
import argparse, hashlib, json, statistics, subprocess, sys, time


def run(cmd, timeout):
    shell = len(cmd) == 1
    t = time.perf_counter()
    p = subprocess.run(cmd[0] if shell else cmd, shell=shell, capture_output=True, timeout=timeout)
    return time.perf_counter() - t, p.returncode, p.stdout, p.stderr


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-n", "--runs", type=int, default=5)
    ap.add_argument("--warmup", type=int, default=1)
    ap.add_argument("--save")
    ap.add_argument("--compare")
    ap.add_argument("--max-slowdown", type=float, default=1.10)
    ap.add_argument("--timeout", type=float, default=1800)
    ap.add_argument("command", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.command[1:] if a.command[:1] == ["--"] else a.command
    if not cmd or a.runs < 1:
        ap.print_usage(sys.stderr)
        return 2
    base = None
    if a.compare:
        try:
            base = json.load(open(a.compare))
            base_out = open(a.compare + ".out", "rb").read()
        except OSError as e:
            print(f"error: can't read baseline: {e}", file=sys.stderr)
            return 2
    times, out, rc = [], b"", 0
    try:
        for i in range(a.warmup + a.runs):
            dt, rc, out, err = run(cmd, a.timeout)
            if rc != 0:
                print(f"FAILED exit={rc}\n" + err.decode(errors="replace")[-2000:])
                return 1
            if i >= a.warmup:
                times.append(dt)
    except subprocess.TimeoutExpired:
        print(f"FAILED timed out after {a.timeout}s")
        return 1
    med = statistics.median(times)
    digest = hashlib.sha256(out).hexdigest()
    print(f"RUNS n={len(times)} min={min(times):.3f}s median={med:.3f}s max={max(times):.3f}s")
    print(f"OUTPUT sha256={digest[:16]} bytes={len(out)} exit={rc}")
    if a.save:
        json.dump({"command": cmd, "times": times, "median": med, "sha256": digest}, open(a.save, "w"))
        open(a.save + ".out", "wb").write(out)
        print(f"SAVED {a.save}")
    status = 0
    if base is not None:
        speedup = base["median"] / med if med > 0 else float("inf")
        print(f"BASELINE median={base['median']:.3f}s  NOW median={med:.3f}s  SPEEDUP {speedup:.2f}x")
        if out == base_out:
            print("OUTPUT same")
        else:
            old, new = base_out.splitlines(), out.splitlines()
            k = next((i for i, (x, y) in enumerate(zip(old, new)) if x != y), min(len(old), len(new)))
            print(f"OUTPUT DIFFERENT first difference at line {k + 1}")
            status = 1
        if med > base["median"] * a.max_slowdown:
            print(f"SLOWER than baseline by more than {a.max_slowdown:.2f}x")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
