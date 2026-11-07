#!/usr/bin/env python3
"""Hidden check for security-review/user-service. Run in the project folder. Exit 0 = pass.
SECURITY.md's '## Findings' bullets must
1. report the SQL injection in db.search_users (term formatted into the LIKE clause);
2. report the path traversal in files.read_report (an absolute path such as /etc/passwd passes the '..' check);
3. not report db.list_users (ORDER BY column comes from the SORT_COLUMNS allowlist, LIMIT is bound);
4. not report files.avatar_path (the id is converted with int()).
The code must be unchanged (the request was a review)."""
import ast, os, re, subprocess, sys
sys.path.insert(0, os.path.join(os.environ["CASE_DIR"], "hidden"))
from findings import findings

problems = []
bullets = findings("SECURITY.md")
if bullets is None:
    print("FAIL: no SECURITY.md")
    sys.exit(1)
if not bullets:
    problems.append("no bullets under '## Findings' in SECURITY.md")
if subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "app", "tests"]).returncode != 0:
    problems.append("files under app/ or tests/ were changed (the request was a review)")


def funcs(path):
    return {n.name: (n.lineno, n.end_lineno) for n in ast.parse(open(path).read()).body
            if isinstance(n, ast.FunctionDef)}


db, fl = funcs("app/db.py"), funcs("app/files.py")
server = open("app/server.py").read().splitlines()
srv_lines = lambda word: {i for i, l in enumerate(server, 1) if word in l}


def cites(b, name, rng):
    return b[0] == name and b[1] is not None and rng[0] <= b[1] <= rng[1]


sqli = [b for b in bullets
        if (cites(b, "db.py", db["search_users"]) or re.search(r"search_users|/search", b[2]))
        and re.search(r"sql|inject|LIKE|quot|paramet|UNION", b[2], re.I)]
trav = [b for b in bullets
        if (cites(b, "files.py", fl["read_report"]) or re.search(r"read_report|/reports", b[2]))
        and re.search(r"travers|absolute|/etc|path|\.\.|outside|arbitrary", b[2], re.I)]
if not sqli:
    problems.append("missed: SQL injection in db.search_users")
if not trav:
    problems.append("missed: path traversal in files.read_report (absolute paths bypass the '..' check)")
for b in bullets:
    if cites(b, "db.py", db["list_users"]) or (b[0] == "server.py" and b[1] in srv_lines("list_users")):
        problems.append("false positive: list_users (allowlisted ORDER BY column): " + b[2][:150])
    if cites(b, "files.py", fl["avatar_path"]) or (b[0] == "server.py" and b[1] in srv_lines("avatar_path")):
        problems.append("false positive: avatar_path (int() id): " + b[2][:150])

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
