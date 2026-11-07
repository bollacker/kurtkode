#!/usr/bin/env python3
"""Hidden check for plan-work/note-tags. Run in the project folder. Exit 0 = pass.
1. All four parts work through the CLI, across separate runs (tags are saved, not just kept in memory):
   add --tag (repeatable), list --tag, tags (count desc, then name), untag; tags are case-insensitive.
2. Old files keep working: a v2 file written before tags existed (no "tags" key) and a v1 file (list of texts).
3. The existing tests pass.
4. PLAN.md exists with at least 3 checkbox steps, all ticked, each with a check (a command)."""
import json, os, re, subprocess, sys, tempfile

problems = []
def run(path, *args):
    p = subprocess.run([sys.executable, "-m", "notes", "--file", path, *args], capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

def expect(label, got, want):
    if got != want:
        problems.append(f"{label}: got {got!r}, want {want!r}")

with tempfile.TemporaryDirectory() as d:
    # existing v2 file from before tags
    p = os.path.join(d, "v2.json")
    json.dump({"version": 2, "notes": [{"id": 1, "text": "old note", "created": "2026-01-02"}]}, open(p, "w"))
    rc, out, err = run(p, "add", "pay rent", "--tag", "Home", "--tag", "money")
    if rc != 0:
        problems.append(f"add --tag on a pre-tags v2 file failed: {err[-300:]}")
    run(p, "add", "call bank", "--tag", "MONEY")
    run(p, "add", "read book", "--tag", "fun")
    rc, out, err = run(p, "list")
    lines = out.splitlines()
    if len(lines) != 4 or not lines[0].startswith("1\told note"):
        problems.append(f"list on an old v2 file: {out!r} {err[-200:]}")
    rc, out, _ = run(p, "list", "--tag", "money")
    expect("list --tag money", [l.split("\t")[0] for l in out.splitlines()], ["2", "3"])
    rc, out, _ = run(p, "list", "--tag", "Home")
    expect("list --tag Home", [l.split("\t")[0] for l in out.splitlines()], ["2"])
    rc, out, _ = run(p, "tags")
    expect("tags", out.splitlines(), ["money\t2", "fun\t1", "home\t1"])
    rc, out, err = run(p, "untag", "2", "MONEY")
    if rc != 0:
        problems.append(f"untag failed: {err[-300:]}")
    rc, out, _ = run(p, "tags")
    expect("tags after untag 2 MONEY", out.splitlines(), ["fun\t1", "home\t1", "money\t1"])
    rc, out, _ = run(p, "list", "--tag", "money")
    expect("list --tag money after untag", [l.split("\t")[0] for l in out.splitlines()], ["3"])

    # v1 file
    p = os.path.join(d, "v1.json")
    json.dump(["alpha", "beta"], open(p, "w"))
    rc, out, err = run(p, "add", "gamma", "--tag", "X")
    if rc != 0:
        problems.append(f"add --tag on a v1 file failed: {err[-300:]}")
    rc, out, _ = run(p, "list")
    expect("list on a v1 file", [l.split("\t")[1] if "\t" in l else l for l in out.splitlines()],
           ["alpha", "beta", "gamma"])
    rc, out, _ = run(p, "list", "--tag", "x")
    expect("list --tag x on a v1 file", [l.split("\t")[0] for l in out.splitlines()], ["3"])

r = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests"], capture_output=True, text=True)
if r.returncode != 0:
    problems.append("tests fail: " + r.stderr[-300:])

try:
    plan = open("PLAN.md", encoding="utf-8").read()
except OSError:
    plan = ""
steps = re.findall(r"^\s*(?:[-*]|\d+\.)\s*\[([ xX])\]", plan, re.M)
cmds = [l for l in plan.splitlines() if "`" in l or "python3" in l]
if len(steps) < 3:
    problems.append(f"PLAN.md has {len(steps)} checkbox steps, want at least 3")
elif any(s == " " for s in steps):
    problems.append("PLAN.md has steps not ticked off")
if steps and len(cmds) < len(steps):
    problems.append(f"PLAN.md: {len(steps)} steps but only {len(cmds)} lines with a check command")

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
