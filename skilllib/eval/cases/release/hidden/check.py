#!/usr/bin/env python3
"""Hidden check for release/next-release. Run in the project folder. Exit 0 = pass.
The commits since v1.3.0 add a feature (--json) and fixes, so semver makes the next version 1.4.0.
1. Tag v1.4.0 exists and the commit it points to has 1.4.0 in every place the version lives
   (pyproject.toml, tally/__init__.py, CITATION.cff, docs/install.md) and no 1.3.0 left there.
2. The look-alikes were left alone: the termtables>=1.3.0 dependency and the .tallyrc SCHEMA_VERSION.
3. CHANGELOG.md has a 1.4.0 section above 1.3.0 that names the user-facing changes (--json, empty files,
   CRLF line endings, large files / memory) and none of the chores (dev dependencies, CI cache, README typo,
   refactor, tests); the older sections are unchanged.
4. The tests pass at the tag."""
import os, re, subprocess, sys, tempfile

problems = []


def show(path):
    p = subprocess.run(["git", "show", f"v1.4.0:{path}"], capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


if subprocess.run(["git", "rev-parse", "-q", "--verify", "refs/tags/v1.4.0"], capture_output=True).returncode:
    tags = subprocess.run(["git", "tag"], capture_output=True, text=True).stdout.split()
    print(f"FAIL: no tag v1.4.0 (tags: {tags})")
    sys.exit(1)

want = {
    "pyproject.toml": r'^version = "1\.4\.0"$',
    "tally/__init__.py": r'^__version__ = "1\.4\.0"$',
    "CITATION.cff": r"^version: ['\"]?1\.4\.0['\"]?$",
    "docs/install.md": r"tally==1\.4\.0\b",
}
for path, rx in want.items():
    text = show(path)
    if text is None:
        problems.append(f"{path} missing at v1.4.0")
        continue
    if not re.search(rx, text, re.M):
        problems.append(f"{path} at v1.4.0 does not carry version 1.4.0")
    stale = [l for l in text.splitlines() if "1.3.0" in l and "termtables" not in l]
    if stale:
        problems.append(f"{path} at v1.4.0 still has the old version: {stale}")
if 'dependencies = ["termtables>=1.3.0"]' not in (show("pyproject.toml") or ""):
    problems.append("the termtables>=1.3.0 dependency bound was changed (it is not our version)")
if 'SCHEMA_VERSION = "1.3.0"' not in (show("tally/config.py") or ""):
    problems.append("tally/config.py SCHEMA_VERSION was changed (it is the config-file format version)")

log = show("CHANGELOG.md") or ""
heads = [(m.start(), m.group(0)) for m in re.finditer(r"^## .*$", log, re.M)]
new = [i for i, (_, h) in enumerate(heads) if "1.4.0" in h]
old = [i for i, (_, h) in enumerate(heads) if "1.3.0" in h]
if not new or not old or new[0] > old[0]:
    problems.append("CHANGELOG.md has no 1.4.0 section above 1.3.0")
else:
    i = new[0]
    section = log[heads[i][0]:heads[i + 1][0] if i + 1 < len(heads) else len(log)]
    for label, rx in [("--json output", r"json"), ("empty-file crash fix", r"empty"),
                      ("CRLF fix", r"crlf|line ending|windows"), ("large-file memory change", r"memory|large|huge|line by line")]:
        if not re.search(rx, section, re.I):
            problems.append(f"1.4.0 changelog section does not mention the {label}")
    for label, rx in [("dev dependency bump", r"dev(elopment)?[ -]dep|black|flake8"), ("CI cache", r"\bcache|\bci\b"),
                      ("README typo", r"typo"), ("refactor", r"refactor|build_parser|argument parsing"),
                      ("tests", r"\btests?\b")]:
        if re.search(rx, section, re.I):
            problems.append(f"1.4.0 changelog section lists a chore: {label}")
    orig = open(os.path.join(os.environ["CASE_DIR"], "fixtures", "next-release", "CHANGELOG.md")).read()
    if orig.split("## [1.3.0]", 1)[1] not in log:
        problems.append("older CHANGELOG sections were changed")

with tempfile.TemporaryDirectory() as d:
    subprocess.run(f"git archive v1.4.0 | tar -x -C {d}", shell=True, check=True)
    t = subprocess.run([sys.executable, "-m", "unittest"], cwd=d, capture_output=True, text=True)
    if t.returncode != 0:
        problems.append("tests fail at v1.4.0:\n" + t.stderr[-400:])
    v = subprocess.run([sys.executable, "-m", "tally.cli", "--version"], cwd=d, capture_output=True, text=True)
    if v.stdout.strip() != "tally 1.4.0":
        problems.append(f"`tally --version` at v1.4.0 prints {v.stdout.strip()!r}")

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
