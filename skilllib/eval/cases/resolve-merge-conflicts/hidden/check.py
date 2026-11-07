#!/usr/bin/env python3
"""Hidden check for resolve-merge-conflicts/grams-vs-express. Run in the project folder. Exit 0 = pass.
1. The merge is finished: no unmerged paths, no MERGE_HEAD, HEAD is a merge of main's grams commit and express.
2. No conflict markers in tracked files.
3. Main's intent survives: every weight is integer grams (weight_g), including in the checkout quote.
4. Express's intent survives: express=True costs 1.5x and bills at least 1 kg (= 1000 g), in orders and quotes.
5. The project's own suite passes and still has all 7 tests from both sides (none deleted or skipped)."""
import os, re, subprocess, sys

problems = []


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout.strip()


if git("ls-files", "-u"):
    problems.append("unmerged paths remain")
if git("rev-parse", "-q", "--verify", "MERGE_HEAD"):
    problems.append("merge not committed (MERGE_HEAD still present)")
parents = git("rev-list", "--parents", "-n", "1", "HEAD").split()[1:]
tips = dict(l.split("\t", 1)[::-1] for l in git("log", "--all", "--format=%H\t%s").splitlines())
grams, express = tips.get("Store weights as integer grams"), tips.get("Show standard and express prices on the checkout page")
if len(parents) != 2 or set(parents) != {grams, express}:
    problems.append(f"HEAD is not the merge of main and express (parents {parents})")

for path in git("ls-files").splitlines():
    try:
        text = open(path, errors="replace").read()
    except OSError:
        continue
    if re.search(r"^(<<<<<<<|>>>>>>>)( |$)|^=======$|^\|\|\|\|\|\|\|( |$)", text, re.M):
        problems.append(f"conflict markers left in {path}")

sys.path.insert(0, os.getcwd())
try:
    from parcel.shipping import shipping_cost
    from parcel.orders import order_total
    from parcel.quote import quick_quote
    cases = [
        ("shipping_cost(2500, 'domestic')", lambda: shipping_cost(2500, "domestic"), 8.0),
        ("shipping_cost(1000, 'intl')", lambda: shipping_cost(1000, "intl"), 16.2),
        ("shipping_cost(weight_g=2500, zone='domestic')", lambda: shipping_cost(weight_g=2500, zone="domestic"), 8.0),
        ("shipping_cost(500, 'domestic', express=True)", lambda: shipping_cost(500, "domestic", express=True), 9.3),
        ("shipping_cost(2000, 'domestic', express=True)", lambda: shipping_cost(2000, "domestic", express=True), 11.1),
        ("shipping_cost(1500, 'intl', express=True)", lambda: shipping_cost(1500, "intl", express=True), 25.2),
        ("order_total([(10.0, 300), (5.0, 200)], 'domestic')", lambda: order_total([(10.0, 300), (5.0, 200)], "domestic"), 20.6),
        ("order_total(..., express=True)", lambda: order_total([(10.0, 300), (5.0, 200)], "domestic", express=True), 24.3),
        ("quick_quote(500, 'domestic')", lambda: quick_quote(500, "domestic"), {"standard": 5.6, "express": 9.3}),
        ("quick_quote(3000, 'intl')", lambda: quick_quote(3000, "intl"), {"standard": 18.6, "express": 27.9}),
    ]
    for label, fn, want in cases:
        try:
            got = fn()
        except Exception as e:
            got = repr(e)
        if got != want:
            problems.append(f"{label} = {got}, want {want}")
except Exception as e:
    problems.append(f"could not import the parcel modules: {e!r}")

p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", ".", "-v"],
                   capture_output=True, text=True)
out = p.stdout + p.stderr
if p.returncode != 0:
    problems.append("project test suite fails: " + out[-400:])
m = re.search(r"Ran (\d+) test", out)
ran = int(m.group(1)) if m else 0
skipped = re.search(r"skipped=(\d+)", out)
if ran < 7 or skipped:
    problems.append(f"suite ran {ran} tests (skipped: {skipped.group(1) if skipped else 0}); want all 7 from both sides")

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
