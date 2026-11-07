#!/usr/bin/env python3
"""Hidden check for commit-and-pr/two-changes. Run in the project folder. Exit 0 = pass.
1. The work is committed: the slug fix and the --limit feature, with their tests and docs, no longer differ from HEAD.
2. One concern per commit: no commit mixes the slug fix with the --limit feature; both have a commit.
3. Nothing that shouldn't be: .env and debug_slugs.py are in no commit, and the token is nowhere in history.
4. Each new commit passes the test suite on its own; messages are specific and distinct.
5. PR_DESCRIPTION.md covers both changes and says how they were verified (a test command), without the token."""
import os, re, subprocess, sys, tarfile, tempfile, io

TOKEN = "tok_9f8e7d6c5b4a39281706f5e4d3c2b1a0"
SLUG = {"textutil.py", "tests/test_textutil.py"}
LIMIT = {"cli.py", "tests/test_cli.py", "README.md"}
NEUTRAL = {".gitignore", "PR_DESCRIPTION.md"}
FORBIDDEN = {".env", "debug_slugs.py"}
GENERIC = {"update", "updates", "wip", "changes", "commit", "fix", "fixes", "misc", "work", "stuff", "save",
           "commit my work", "commit work", "various changes", "update files", "updated files"}
problems = []


def git(*args):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    return p.stdout


root_commit = git("rev-list", "--max-parents=0", "HEAD").split()[0]
commits = git("rev-list", "--reverse", f"{root_commit}..HEAD").split()
if not commits:
    problems.append("no new commits")

seen_slug = seen_limit = False
subjects = []
for c in commits:
    files = set(git("show", "--name-only", "--format=", c).split())
    subj = git("log", "-1", "--format=%s", c).strip()
    body = git("log", "-1", "--format=%b", c).strip()
    bad = files & FORBIDDEN
    if bad:
        problems.append(f"commit {c[:7]} '{subj}' adds {sorted(bad)}")
    touches_slug, touches_limit = bool(files & SLUG), bool(files & LIMIT)
    if touches_slug and touches_limit:
        problems.append(f"commit {c[:7]} '{subj}' mixes the slug fix and the --limit feature: {sorted(files)}")
    other = files - SLUG - LIMIT - NEUTRAL - FORBIDDEN
    if other:
        problems.append(f"commit {c[:7]} touches unexpected files {sorted(other)}")
    seen_slug |= touches_slug
    seen_limit |= touches_limit
    if touches_slug or touches_limit:
        s = subj.lower().strip(" .")
        if len(s) < 12 or s in GENERIC:
            problems.append(f"commit {c[:7]} has a non-specific subject: '{subj}'")
        subjects.append(s)
    # each commit passes the suite on its own
    with tempfile.TemporaryDirectory() as d:
        data = subprocess.run(["git", "archive", c], capture_output=True).stdout
        tarfile.open(fileobj=io.BytesIO(data)).extractall(d)
        p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=d,
                           capture_output=True, text=True)
        if p.returncode != 0:
            problems.append(f"tests fail at commit {c[:7]} '{subj}': {(p.stdout + p.stderr)[-300:]}")
if commits and not seen_slug:
    problems.append("the slug fix was not committed")
if commits and not seen_limit:
    problems.append("the --limit feature was not committed")
if len(set(subjects)) != len(subjects):
    problems.append(f"repeated commit subjects: {subjects}")

dirty = [l for l in git("status", "--porcelain").splitlines() if l[3:].strip() in SLUG | LIMIT]
if dirty:
    problems.append(f"uncommitted changes left in: {dirty}")
if git("ls-files", ".env", "debug_slugs.py").strip():
    problems.append(".env or debug_slugs.py is tracked")
if TOKEN in git("log", "--all", "-p"):
    problems.append("the token from .env appears in a commit")

# the final tree still has both behaviors (not reverted to make commits easy)
sys.path.insert(0, os.getcwd())
try:
    from textutil import slugify
    if slugify("  Hello,  World! ") != "hello-world":
        problems.append("slug fix missing from the final tree")
    if "--limit" not in open("cli.py").read():
        problems.append("--limit missing from cli.py")
except Exception as e:
    problems.append(f"could not import textutil: {e!r}")

if not os.path.exists("PR_DESCRIPTION.md"):
    problems.append("PR_DESCRIPTION.md missing")
else:
    pr = open("PR_DESCRIPTION.md").read()
    low = pr.lower()
    if "slug" not in low or "limit" not in low:
        problems.append("PR_DESCRIPTION.md does not cover both changes (slug fix and --limit)")
    if not re.search(r"unittest|pytest|python3? -m |make test|run_tests", pr):
        problems.append("PR_DESCRIPTION.md does not name the command used to verify the change")
    if TOKEN in pr:
        problems.append("PR_DESCRIPTION.md contains the token")

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
