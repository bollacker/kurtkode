#!/usr/bin/env python3
"""Hidden check for upgrade-dependencies/textkit-v2. Run in the project folder. Exit 0 = pass.
1. vendor.txt selects textkit 2.0.0 and the vendored 2.0.0 code is unchanged (no patching the dependency).
2. With textkit 1.4.2 removed from vendor/, the app runs on 2.0.0 and its output is exactly what it was on
   1.4.2: same URLs and tag slugs (slugify's new default separator) and the same excerpts and feed titles
   (truncate's new width meaning), not just the loud renames.
3. The project's own tests pass."""
import hashlib, json, os, re, shutil, subprocess, sys

case = os.environ["CASE_DIR"]
problems = []
pins = [l.split() for l in open("vendor.txt") if l.strip() and not l.startswith("#")]
if ["textkit", "2.0.0"] not in pins or any(p[0] == "textkit" and p[1] != "2.0.0" for p in pins):
    problems.append(f"vendor.txt does not select textkit 2.0.0 only: {pins}")
for line in open(os.path.join(case, "hidden", "protected.sha256")):
    digest, path = line.split()
    if not os.path.exists(path) or hashlib.sha256(open(path, "rb").read()).hexdigest() != digest:
        problems.append(f"{path} was changed or removed (fix the app, not the dependency)")

old, aside = "vendor/textkit-1.4.2", "vendor/.textkit-1.4.2-hidden-by-check"
moved = os.path.isdir(old)
if moved:
    os.rename(old, aside)
try:
    p = subprocess.run([sys.executable, os.path.join(case, "hidden", "probe.py")], capture_output=True, text=True)
    if p.returncode != 0:
        problems.append("app fails on textkit 2.0.0 alone:\n" + p.stderr[-600:])
    else:
        got = json.loads(p.stdout)
        if got.pop("version") != "2.0.0":
            problems.append("the app is not running on textkit 2.0.0")
        want = json.load(open(os.path.join(case, "hidden", "expected.json")))
        for key in sorted(want):
            if got.get(key) != want[key]:
                problems.append(f"output changed after the upgrade ({key}): got {got.get(key)!r}, want {want[key]!r}")
    t = subprocess.run([sys.executable, "-m", "unittest"], capture_output=True, text=True)
    if t.returncode != 0 or not re.search(r"Ran [1-9]", t.stderr):
        problems.append("project tests fail:\n" + t.stderr[-600:])
finally:
    if moved:
        os.rename(aside, old)

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
