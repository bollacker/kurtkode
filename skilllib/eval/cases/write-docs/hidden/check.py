#!/usr/bin/env python3
"""Hidden check for write-docs/tally-cli. Run in the project folder. Exit 0 = pass.
1. README.md exists; tally.py is unchanged.
2. Every command in its sh/bash/shell/zsh/console blocks runs, pasted in order into one bash session (set -e), in a
   fresh copy of the tracked files plus README.md, with HOME pointing at an empty folder and TALLY_DB unset.
3. Those blocks use all four subcommands: add, report, budget, check.
4. Key facts: the TALLY_DB variable, the default tally.db in the current directory (not the stale ~/.tally path
   from the module docstring), and exit status 3 from check when a category is over budget."""
GUARD = (  # a documented non-zero exit (check's 3, report's 1) is fine; a missing command, usage error or crash isn't
    "set -E\ntrap 'rc=$?; case $rc in 2|126|127) echo \"README command failed (exit $rc): $BASH_COMMAND\"; exit $rc;; esac' ERR\n")
import os, re, shutil, subprocess, sys, tempfile

problems = []
if not os.path.exists("README.md"):
    print("FAIL: no README.md")
    sys.exit(1)
text = open("README.md", encoding="utf-8", errors="replace").read()
if subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "tally.py"]).returncode:
    problems.append("tally.py was changed (the task was documentation)")

cmds, lines, i = [], text.splitlines(), 0
while i < len(lines):
    m = re.match(r"^\s*(`{3,}|~{3,})\s*([\w-]*)", lines[i])
    if not m:
        i += 1
        continue
    fence, tag, body = m.group(1), m.group(2).lower(), []
    i += 1
    while i < len(lines) and not lines[i].strip().startswith(fence):
        body.append(lines[i])
        i += 1
    i += 1
    if tag in ("sh", "bash", "shell", "zsh", "console", "shell-session"):
        if tag in ("console", "shell-session"):
            body = [l.strip()[2:] for l in body if l.strip().startswith("$ ")]
        cmds += [re.sub(r"^\s*\$ ", "", l) for l in body]
script = "\n".join(cmds)
for sub in ("add", "report", "budget", "check"):
    if not re.search(r"tally(\.py)?\s+(--?\S+\s+)*" + sub + r"\b", script):
        problems.append(f"no runnable example of the '{sub}' command in a sh/bash/console block")

tmp = tempfile.mkdtemp()
try:
    work, home = os.path.join(tmp, "p"), os.path.join(tmp, "home")
    os.makedirs(home)
    os.makedirs(work)
    tracked = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split()
    for rel in tracked + ["README.md"]:
        if os.path.exists(rel):
            os.makedirs(os.path.dirname(os.path.join(work, rel)) or work, exist_ok=True)
            shutil.copy2(rel, os.path.join(work, rel))
    env = {k: v for k, v in os.environ.items() if k != "TALLY_DB"}
    env["HOME"] = home
    try:
        p = subprocess.run(["bash", "-c", GUARD + script + "\n"], cwd=work, env=env, capture_output=True,
                           text=True, timeout=120, stdin=subprocess.DEVNULL)
        if p.returncode != 0 or "Traceback (most recent call last)" in p.stdout + p.stderr:
            problems.append(f"README commands fail (exit {p.returncode}): " + (p.stdout + p.stderr)[-400:])
    except subprocess.TimeoutExpired:
        problems.append("README commands timed out")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

if "TALLY_DB" not in text:
    problems.append("README does not mention the TALLY_DB environment variable")
if "tally.db" not in text:
    problems.append("README does not say where data is stored by default (tally.db)")
# Mentioning the stale path to warn about it is fine; presenting it as where data lives is not.
_warn = re.compile(r"docstring|stale|outdated|out of date|mismatch|incorrect|wrong|not |n't|instead|but ", re.I)
if any(re.search(r"~/\.tally|\.tally/", l) and not _warn.search(l) for l in text.splitlines()):
    problems.append("README repeats the stale ~/.tally/tally.db path from the docstring")
doc_lines = text.splitlines()
exit3 = any(re.search(r"\b3\b", l) and re.search(r"over|budget|check", l, re.I)
            and re.search(r"exit|status|code|return", " ".join(doc_lines[max(0, n - 10):n + 1]), re.I)
            for n, l in enumerate(doc_lines))
if not exit3:
    problems.append("README does not document that check exits with status 3 when over budget")

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
