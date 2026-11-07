#!/usr/bin/env python3
"""Hidden check for code-review/bulk-discounts. Run in the project folder. Exit 0 = pass.
REVIEW.md's "## Findings" section must have one bullet per finding starting with path:line. It must:
1. report the off-by-one in bulk_percent (`qty > min_qty`: 10 units get no discount, the commit says 10 or more);
2. report that find_item now returns None while orders.order_total still catches KeyError (crash on unknown sku),
   cited at find_item or in order_total;
3. not report the deliberate round-down of discounts (commit message and a test state it);
4. not report search.py (find_item there only sees skus taken from ITEMS, so it never returns None);
5. leave the code on the branch unchanged."""
import ast, os, re, subprocess, sys

problems = []


def func_ranges(path):
    tree = ast.parse(open(path).read())
    return {n.name: (n.lineno, n.end_lineno) for n in tree.body if isinstance(n, ast.FunctionDef)}


def findings(text):
    lines = text.splitlines()
    out, inside, cur = [], False, None
    for ln in lines:
        if re.match(r"^\s*#+\s*", ln):
            inside = bool(re.match(r"^\s*#+\s*findings\b", ln, re.I))
            cur = None
            continue
        if not inside:
            continue
        if re.match(r"^\s{0,3}[-*]\s+", ln):
            cur = [ln]
            out.append(cur)
        elif cur is not None and ln.strip():
            cur.append(ln)
        elif not ln.strip():
            cur = None
    result = []
    for b in out:
        t = " ".join(s.strip() for s in b)
        m = re.search(r"([\w./-]+\.py):(\d+)", t)
        result.append((os.path.basename(m.group(1)) if m else None, int(m.group(2)) if m else None, t))
    return result


if not os.path.exists("REVIEW.md"):
    print("FAIL: no REVIEW.md")
    sys.exit(1)
bullets = findings(open("REVIEW.md", encoding="utf-8", errors="replace").read())
if not bullets:
    problems.append("no bullets under a '## Findings' heading in REVIEW.md")

if subprocess.run(["git", "diff", "--quiet", "bulk-discounts", "--", "shop", "tests"]).returncode != 0:
    problems.append("code under shop/ or tests/ differs from the bulk-discounts branch (the review must not edit code)")

pr = func_ranges("shop/pricing.py")
cat = func_ranges("shop/catalog.py")
orders = func_ranges("shop/orders.py")
tiers_line = next(i for i, l in enumerate(open("shop/pricing.py"), 1) if l.startswith("BULK_TIERS"))


def at(b, fname, lo, hi):
    return b[0] == fname and b[1] is not None and lo <= b[1] <= hi


bug1 = any(at(b, "pricing.py", tiers_line, pr["bulk_percent"][1]) for b in bullets)
bug2 = any(at(b, "catalog.py", *cat["find_item"]) or at(b, "orders.py", *orders["order_total"]) for b in bullets)
if not bug1:
    problems.append("missed: off-by-one in bulk_percent (qty > min_qty; 10 units should get 5%)")
if not bug2:
    problems.append("missed: find_item returns None but order_total still expects KeyError")
bait_round = [b for b in bullets if re.search(r"round|truncat|floor|integer division|//|precision", b[2], re.I)]
if bait_round:
    problems.append("false positive: reported the deliberate round-down: " + bait_round[0][2][:160])
bait_search = [b for b in bullets if b[0] == "search.py"]
if bait_search:
    problems.append("false positive: reported search.py: " + bait_search[0][2][:160])

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
