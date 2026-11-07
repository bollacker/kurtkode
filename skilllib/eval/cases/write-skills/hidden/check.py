#!/usr/bin/env python3
"""Hidden check for write-skills/migration-skill. Run in the project folder. Exit 0 = pass.
1. A new skill folder exists in agent/skills/ (besides run-tests) and passes the library's validator: front matter
   with only name and description, name = folder, description starts "Use when" and fits 230 characters, body
   within 150 lines / 6 KB, referenced files exist. (The decoy run-tests skill has extra fields and a summary
   description; copying its shape fails.)
2. The skill carries the house procedure: tools/migrate_check.py, tools/dump_schema.py / schema.sql, the down file,
   and the rule against editing migrations already on main.
3. Trigger tests exist: a cases.json somewhere in the project with >= 5 should and >= 3 should_not requests,
   distinct, none in both lists (checked by the same validator)."""
import glob, os, re, subprocess, sys

case = os.environ.get("CASE_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
validator = os.path.normpath(os.path.join(case, "..", "..", "..", "skills", "write-skills", "scripts",
                                          "validate_skill.py"))
problems = []

new = sorted(d for d in glob.glob("agent/skills/*/") if os.path.basename(d.rstrip("/")) != "run-tests")
if not new:
    problems.append("no new skill folder in agent/skills/")
good_skill = False
for d in new:
    p = subprocess.run([sys.executable, validator, d], capture_output=True, text=True)
    errs = [l.strip() for l in p.stdout.splitlines() if l.strip().startswith("error:")]
    body = open(os.path.join(d, "SKILL.md"), errors="replace").read() if os.path.exists(os.path.join(d, "SKILL.md")) else ""
    low = body.lower()
    missing = []
    if "migrate_check.py" not in body:
        missing.append("tools/migrate_check.py")
    if "dump_schema.py" not in body or "schema.sql" not in body:
        missing.append("regenerating schema.sql with tools/dump_schema.py")
    if "down" not in low:
        missing.append("the .down.sql file")
    if not any(re.search(r"\b(never|don't|do not|not)\b", l) and re.search(r"\b(edit|modify|change|renumber)", l)
               for l in low.splitlines()):
        missing.append("the rule not to edit migrations already on main")
    if p.returncode == 0 and not missing:
        good_skill = True
    else:
        problems.append(f"{d}: validator exit {p.returncode} {errs}; missing from the body: {missing}")
if new and good_skill:
    problems = []  # one good skill is enough

cases = [c for c in glob.glob("**/cases.json", recursive=True) if not c.startswith((".git/", ".agents/"))]
cases += [c for c in glob.glob(".*/**/cases.json", recursive=True) if not c.startswith((".git/", ".agents/"))]
good_cases = False
for c in cases:
    p = subprocess.run([sys.executable, validator, "--cases", c], capture_output=True, text=True)
    if p.returncode == 0:
        good_cases = True
    else:
        problems.append(f"{c}: " + " ".join(l.strip() for l in p.stdout.splitlines() if "error:" in l))
if not cases:
    problems.append("no cases.json with trigger tests found")
elif good_cases:
    problems = [x for x in problems if "cases.json" not in x]

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
