#!/usr/bin/env python3
"""Validates one task of a real set the way the harness will check it (TaskBankReal.swift).

    validate_task.py SETDIR ID [--repeat N] [--keep] [--sandbox-only]

Unpacks the fixture as `prepare` does (gitignore, prepareCommand, a commit), then:
  visible@parent   the fixture's own suite, sandboxed (information: should pass)
  before           the suite with the hidden tests laid over, unsandboxed (must FAIL: the task isn't done yet)
  gold             ID.gold.diff applied, hidden tests laid over, unsandboxed, N times (must PASS every time)
  gold sandboxed   the same inside the eval's sandbox (insandbox.sh), N times (must PASS: the model's own runs and
                   the re-run check are sandboxed)
  visible@gold     the fixture's own suite at gold, sandboxed (must PASS: else the re-run check would flag a good run)
A write-tests task (kind write-tests; build_task.py --write-tests) is checked instead as:
  visible@fixed    the fixture's suite, sandboxed (must PASS)
  visible@buggy    the same with ID-buggy.tgz laid over (must PASS: the old tests miss the bug, or there is no task)
  reference        the commit's own tests laid over, unsandboxed and sandboxed, N times each (must PASS)
  reference@buggy  those tests with the buggy files laid over, unsandboxed and sandboxed (must FAIL: the task can be
                   done, by the tests the commit added)
With --sandbox-only every step runs in the sandbox (third-party repositories, whose code the user allows to run only
there). Prints one JSON line; exit 0 only when every required step held.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
SANDBOX_ONLY = False

def sh(cmd, cwd, sandbox=False, timeout=900):
    if sandbox or SANDBOX_ONLY:
        env = dict(os.environ, WS=cwd)
        argv = [os.path.join(HERE, "insandbox.sh"), cmd]
    else:
        env = None
        argv = ["/bin/zsh", "-c", cmd]
    t = time.time()
    try:
        p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr)[-600:], round(time.time() - t, 1)
    except subprocess.TimeoutExpired:
        return 124, "timed out", round(time.time() - t, 1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("setdir"); ap.add_argument("id")
    ap.add_argument("--repeat", type=int, default=3)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--sandbox-only", action="store_true")
    a = ap.parse_args()
    global SANDBOX_ONLY
    SANDBOX_ONLY = a.sandbox_only
    s = json.load(open(os.path.join(a.setdir, "tasks.json")))
    task = next(t for t in s["tasks"] if t["id"] == a.id)
    test = (task.get("testCommand") or s["testCommand"]).replace("{python}", s.get("python", "python3"))
    timeout = s.get("checkTimeout", 900)
    hidden = os.path.join(a.setdir, task["hiddenTests"]) if task.get("hiddenTests") else None
    gold = os.path.abspath(os.path.join(a.setdir, a.id + ".gold.diff"))

    d = tempfile.mkdtemp(prefix=f"kk-validate-{a.id}-")
    out = {"id": a.id}
    try:
        subprocess.run(["tar", "-xzf", os.path.join(a.setdir, a.id + ".tgz"), "-C", d], check=True)
        ignore = os.path.join(d, ".gitignore")
        if s.get("gitignore") is not None:
            own = open(ignore).read() if os.path.exists(ignore) else ""
            open(ignore, "w").write((own if not own or own.endswith("\n") else own + "\n") + "\n".join(s["gitignore"]) + "\n")
        else:
            open(ignore, "w").write("__pycache__/\n*.pyc\n.pytest_cache/\n*.egg-info/\n.coverage\n")
        if s.get("prepareCommand"):
            code, tail, secs = sh(s["prepareCommand"], d, timeout=1800)
            out["prepare"] = {"exit": code, "s": secs}
            if code != 0:
                out["error"] = "prepare failed: " + tail; print(json.dumps(out)); sys.exit(1)
        for c in (["init", "-q"], ["add", "-A"], ["-c", "user.email=v@v", "-c", "user.name=v", "commit", "-qm", "fixture"]):
            subprocess.run(["git", "-C", d, *c], check=True, capture_output=True)

        def overlay():
            if hidden: subprocess.run(["tar", "-xzf", hidden, "-C", d], check=True)
        def reset():
            subprocess.run(["git", "-C", d, "checkout", "-q", "--", "."], check=True)
            subprocess.run(["git", "-C", d, "clean", "-qfd"], check=True)

        if task.get("kind") == "write-tests":
            ok = write_tests(a, d, test, timeout, out)
            out["valid"] = ok
            print(json.dumps(out))
            sys.exit(0 if ok else 1)

        code, tail, secs = sh(test, d, sandbox=True, timeout=timeout)
        out["visible@parent"] = {"exit": code, "s": secs}
        overlay()
        code, tail, secs = sh(test, d, timeout=timeout)
        out["before"] = {"exit": code, "s": secs, "tail": tail[-200:]}
        reset()
        ap_ = subprocess.run(["git", "-C", d, "apply", gold], capture_output=True, text=True)
        if ap_.returncode != 0:
            out["error"] = "gold diff doesn't apply: " + ap_.stderr[-300:]; print(json.dumps(out)); sys.exit(1)
        code, tail, secs = sh(test, d, sandbox=True, timeout=timeout)
        out["visible@gold"] = {"exit": code, "s": secs, **({"tail": tail[-300:]} if code else {})}
        overlay()
        runs = [sh(test, d, timeout=timeout) for _ in range(a.repeat)]
        out["gold"] = [{"exit": c, "s": t} for c, _, t in runs]
        if any(c for c, _, _ in runs): out["gold_tail"] = next(t for c, t, _ in runs if c)[-300:]
        boxed = [sh(test, d, sandbox=True, timeout=timeout) for _ in range(a.repeat)]
        out["gold sandboxed"] = [{"exit": c, "s": t} for c, _, t in boxed]
        if any(c for c, _, _ in boxed): out["boxed_tail"] = next(t for c, t, _ in boxed if c)[-300:]
        ok = (out["before"]["exit"] != 0 and out["visible@gold"]["exit"] == 0
              and all(c == 0 for c, _, _ in runs) and all(c == 0 for c, _, _ in boxed))
        out["valid"] = ok
        print(json.dumps(out))
        sys.exit(0 if ok else 1)
    finally:
        if a.keep: print("kept", d, file=sys.stderr)
        else: shutil.rmtree(d, ignore_errors=True)

def write_tests(a, d, test, timeout, out):
    buggy = os.path.join(a.setdir, a.id + "-buggy.tgz")
    reference = os.path.join(a.setdir, a.id + "-reference.tgz")
    def lay(tgz): subprocess.run(["tar", "-xzf", tgz, "-C", d], check=True)
    def reset():
        subprocess.run(["git", "-C", d, "checkout", "-q", "--", "."], check=True)
        subprocess.run(["git", "-C", d, "clean", "-qfd"], check=True)
    def step(name, sandbox=False):
        code, tail, secs = sh(test, d, sandbox=sandbox, timeout=timeout)
        out[name] = {"exit": code, "s": secs, **({"tail": tail[-300:]} if code else {})}
        return code
    fixed = step("visible@fixed", sandbox=True)
    lay(buggy)
    missed = step("visible@buggy", sandbox=True)
    reset(); lay(reference)
    runs = [sh(test, d, sandbox=boxed, timeout=timeout) for boxed in (False, True) for _ in range(a.repeat)]
    out["reference"] = [{"exit": c, "s": t} for c, _, t in runs]
    if any(c for c, _, _ in runs): out["reference_tail"] = next(t for c, t, _ in runs if c)[-300:]
    lay(buggy)
    caught = [step("reference@buggy"), step("reference@buggy sandboxed", sandbox=True)]
    return fixed == 0 and missed == 0 and all(c == 0 for c, _, _ in runs) and all(c != 0 for c in caught)

if __name__ == "__main__":
    main()
