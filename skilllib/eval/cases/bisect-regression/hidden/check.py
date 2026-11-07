#!/usr/bin/env python3
"""Hidden check for bisect-regression/cents-regression. Run in the project folder. Exit 0 = pass.
1. CULPRIT.txt names (full or abbreviated hash) the commit that truncates cents ("Store amounts as integer cents"),
   not the unbuildable stretch, the separator change or the "rounding" decoy.
2. The repository is left usable: no bisect in progress, back on branch main."""
import os, re, subprocess, sys


def git(*a):
    p = subprocess.run(["git", *a], capture_output=True, text=True)
    return p.returncode, p.stdout.strip()


problems = []
want = git("log", "main", "--format=%H", "--grep=^Store amounts as integer cents$")[1].split()
if len(want) != 1:
    problems.append(f"fixture history not as expected: {want}")
try:
    text = open("CULPRIT.txt").read()
except OSError:
    text = ""
    problems.append("CULPRIT.txt missing")
m = re.search(r"\b[0-9a-f]{7,40}\b", text)
if text and not m:
    problems.append(f"no commit hash in CULPRIT.txt: {text[:200]!r}")
elif m:
    rc, got = git("rev-parse", "--verify", "--quiet", m.group(0) + "^{commit}")
    if rc != 0:
        problems.append(f"{m.group(0)} is not a commit in this repository")
    elif want and got != want[0]:
        problems.append(f"CULPRIT.txt names {got[:12]} ({git('log', '-1', '--format=%s', got)[1]}), not the first bad commit")
if os.path.exists(git("rev-parse", "--git-path", "BISECT_START")[1]):
    problems.append("a git bisect is still in progress (run `git bisect reset`)")
if git("symbolic-ref", "-q", "--short", "HEAD")[1] != "main":
    problems.append("HEAD is not back on branch main")
for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
