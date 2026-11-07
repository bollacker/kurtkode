#!/usr/bin/env python3
"""Hidden check for codemod/rename-fetch-user. Run in the project folder (a git repo). Exit 0 = pass.
1. Exactly the expected files differ from the first commit (hidden/expected/ holds their wanted contents), and each
   matches its expected text (trailing whitespace ignored). Decoys untouched: legacy.crm.fetch_user and its callers,
   RemoteClient.fetch_user, fetch_user_profile, prefetch_users, metric names, log texts, config, scripts.
2. No new files left in app/, legacy/ or config/ (e.g. an alias module).
3. The project's tests pass."""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = os.path.join(HERE, "expected")
root = os.getcwd()
problems = []


def git(*args):
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True).stdout


def norm(text):
    return "\n".join(line.rstrip() for line in text.rstrip().splitlines())


first = git("rev-list", "--max-parents=0", "HEAD").split()[0]
changed = {p for p in git("diff", "--name-only", first, "--").splitlines() if p}
expected = set()
for d, _, files in os.walk(EXP):
    for f in files:
        expected.add(os.path.relpath(os.path.join(d, f), EXP).replace(os.sep, "/"))

for p in sorted(expected - changed):
    problems.append(f"not changed but should be: {p}")
for p in sorted(changed - expected):
    problems.append(f"changed but should not be: {p}")
for p in sorted(expected & changed):
    try:
        got = open(os.path.join(root, p), encoding="utf-8").read()
    except OSError:
        problems.append(f"missing: {p}"); continue
    want = open(os.path.join(EXP, p), encoding="utf-8").read()
    if norm(got) != norm(want):
        g, w = norm(got).splitlines(), norm(want).splitlines()
        i = next((i for i, (a, b) in enumerate(zip(g, w)) if a != b), min(len(g), len(w)))
        problems.append(f"{p}:{i + 1}: got {g[i] if i < len(g) else '<end>'!r}, want {w[i] if i < len(w) else '<end>'!r}")
new = [p for p in git("ls-files", "--others", "--exclude-standard", "--", "app", "legacy", "config").splitlines()
       if p and not p.endswith(".pyc")]
if new:
    problems.append("new files left in the package: " + ", ".join(new))
t = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=root,
                   capture_output=True, text=True, timeout=120)
if t.returncode != 0:
    problems.append("tests fail:\n" + (t.stdout + t.stderr)[-1000:])

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
