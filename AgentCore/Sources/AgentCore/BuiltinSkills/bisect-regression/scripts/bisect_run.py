#!/usr/bin/env python3
"""Find the first bad commit with `git bisect run`, safely.

Usage: bisect_run.py --good REV [--bad REV] [--build CMD] [--timeout SECS] [--timeout-is-bad]
                 [--restore-tracked] -- TEST_COMMAND [ARGS...]
       (a single quoted TEST_COMMAND string is run by the shell)

The test command decides each commit: exit 0 = good, 125 = skip (can't test this commit), any other = bad.
--build CMD runs first at every commit; if it fails the commit is skipped (exit 125), not marked bad.
A test that runs longer than --timeout (default 120 s) is skipped, or bad with --timeout-is-bad (for hangs).

Before bisecting it checks the endpoints: GOOD must pass and BAD must fail, or it stops.
It refuses to start on a dirty tree or while another bisect is running, and always runs `git bisect reset`
at the end (also on errors and Ctrl-C), so the repository is back on the branch it started from.

Prints: ENDPOINT lines, one STEP line per tested commit (hash, good/bad/skip, reason), then
  FIRST_BAD <full hash> <subject>        (exit 0)
  or AMBIGUOUS <hash> ... lines          (exit 1: only skipped commits separate good from bad)
and LOG <path> (a copy of `git bisect log`).
Exit codes: 0 = first bad commit found, 1 = not found (endpoints wrong, ambiguous, aborted),
2 = usage error or the repository isn't ready (dirty tree, bisect already running, bad revision).
"""
import argparse, json, os, re, signal, subprocess, sys, tempfile

SPEC_ENV = "BISECT_PY_STEP_SPEC"


def git(*args, check=True):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {p.stderr.strip()}")
    return p.stdout.strip()


def run_cmd(cmd, timeout):
    shell = len(cmd) == 1
    try:
        p = subprocess.run(cmd[0] if shell else cmd, shell=shell, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr)
    except subprocess.TimeoutExpired:
        return None, f"timed out after {timeout}s"


def step(spec):
    """Decide the checked-out commit. Returns 0 good, 1 bad, 125 skip, 255 abort."""
    head = git("rev-parse", "--short", "HEAD")
    verdict, why = None, ""
    if spec["build"]:
        rc, out = run_cmd(spec["build"], spec["timeout"])
        if rc != 0:
            verdict, why = 125, "build failed" if rc is not None else "build timed out"
    if verdict is None:
        rc, out = run_cmd(spec["test"], spec["timeout"])
        if rc is None:
            verdict, why = (1, "test timed out") if spec["timeout_is_bad"] else (125, "test timed out")
        elif rc == 0:
            verdict, why = 0, "test passed"
        elif rc == 125:
            verdict, why = 125, "test asked to skip (125)"
        else:
            verdict, why = 1, f"test failed (exit {rc})"
    if git("status", "--porcelain", "--untracked-files=no"):
        if spec["restore_tracked"]:
            git("checkout", "-q", "--", ".")
        else:
            verdict, why = 255, "the test changed tracked files; rerun with --restore-tracked"
    name = {0: "good", 1: "bad", 125: "skip", 255: "abort"}[verdict]
    with open(spec["log"], "a") as f:
        f.write(f"STEP {head} {name} ({why})\n")
    return verdict


def main():
    if os.environ.get(SPEC_ENV) and sys.argv[1:] == ["--_step"]:
        return step(json.loads(os.environ[SPEC_ENV]))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--good", required=True, help="a revision where the behavior was right")
    ap.add_argument("--bad", default="HEAD", help="a revision where it is wrong (default HEAD)")
    ap.add_argument("--build", help="shell command run before the test; failure = skip the commit")
    ap.add_argument("--timeout", type=float, default=120)
    ap.add_argument("--timeout-is-bad", action="store_true")
    ap.add_argument("--restore-tracked", action="store_true",
                    help="undo changes the build/test makes to tracked files after each step")
    ap.add_argument("command", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.command[1:] if a.command[:1] == ["--"] else a.command
    if not cmd:
        ap.print_usage(sys.stderr)
        print("error: give the test command after --", file=sys.stderr)
        return 2
    try:
        top = git("rev-parse", "--show-toplevel")
    except RuntimeError:
        print("error: not inside a git repository", file=sys.stderr)
        return 2
    os.chdir(top)
    if os.path.exists(git("rev-parse", "--git-path", "BISECT_START")):
        print("error: a bisect is already running; finish it or run `git bisect reset` first", file=sys.stderr)
        return 2
    if git("status", "--porcelain", "--untracked-files=no"):
        print("error: tracked files have uncommitted changes; commit or stash them first", file=sys.stderr)
        return 2
    try:
        good = git("rev-parse", "--verify", a.good + "^{commit}")
        bad = git("rev-parse", "--verify", a.bad + "^{commit}")
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    orig = git("symbolic-ref", "-q", "--short", "HEAD", check=False) or git("rev-parse", "HEAD")
    logf = tempfile.NamedTemporaryFile("w", prefix="bisect-steps-", suffix=".txt", delete=False).name
    spec = {"build": [a.build] if a.build else None, "test": cmd, "timeout": a.timeout,
            "timeout_is_bad": a.timeout_is_bad, "restore_tracked": a.restore_tracked, "log": logf}
    os.environ[SPEC_ENV] = json.dumps(spec)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    started = False
    try:
        for label, rev, want in (("good", good, 0), ("bad", bad, 1)):
            git("checkout", "-q", "--detach", rev)
            got = step(spec)
            if got != want:
                git("checkout", "-q", orig)
                print(open(logf).read(), end="")
                print(f"ENDPOINT {label} {rev} WRONG: expected {'pass' if want == 0 else 'fail'}, got "
                      f"{ {0: 'pass', 1: 'fail', 125: 'skip', 255: 'abort'}[got] }")
                return 1
            print(f"ENDPOINT {label} {rev} ok")
        git("checkout", "-q", orig)
        open(logf, "w").close()
        git("bisect", "start", bad, good)
        started = True
        p = subprocess.run(["git", "bisect", "run", sys.executable, os.path.abspath(__file__), "--_step"],
                           capture_output=True, text=True)
        out = p.stdout + p.stderr
        print(open(logf).read(), end="")
        log_copy = logf.replace("bisect-steps-", "bisect-log-")
        with open(log_copy, "w") as f:
            f.write(git("bisect", "log", check=False) + "\n")
        m = re.search(r"^([0-9a-f]{40}) is the first bad commit", out, re.M)
        if m:
            sha = m.group(1)
            print(f"FIRST_BAD {sha} {git('log', '-1', '--format=%s', sha)}")
            print(f"LOG {log_copy}")
            return 0
        if "only 'skip'ped commits left" in out:
            for sha in re.findall(r"^([0-9a-f]{40})$", out.split("could be any of:")[-1], re.M):
                print(f"AMBIGUOUS {sha} {git('log', '-1', '--format=%s', sha)}")
            print("NOT_FOUND only skipped (untestable) commits remain between good and bad")
        else:
            print("NOT_FOUND bisect stopped:\n" + "\n".join(out.strip().splitlines()[-8:]))
        print(f"LOG {log_copy}")
        return 1
    finally:
        if started or os.path.exists(git("rev-parse", "--git-path", "BISECT_START")):
            git("bisect", "reset", check=False)
        if (git("symbolic-ref", "-q", "--short", "HEAD", check=False) or git("rev-parse", "HEAD")) != orig:
            git("checkout", "-q", orig, check=False)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(1)
