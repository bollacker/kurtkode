#!/usr/bin/env python3
"""Hidden check for implement-change/invoice-discount. Run in the project folder. Exit 0 = pass.
The house helpers in billing/money.py round half-up on integer cents (percent_of) and format with thousands
separators and a leading minus (fmt). Float math, round() or f"{x:.2f}" get some of these cases wrong.
1. Discounted invoices render Subtotal / Discount (N%) / Total lines in the existing line format, exact amounts.
2. total_cents() returns the discounted total.
3. Invoices without a discount render exactly as before.
4. The suite passes and has more tests than before (tests were added)."""
import os, re, subprocess, sys

sys.path.insert(0, os.getcwd())
problems = []
W = 40

def line(label, amount):
    return label + amount.rjust(W - len(label))

cases = [
    # items, pct, subtotal, discount, total (display strings)
    ([("Widget", 1, 1430)], 15, "$14.30", "-$2.15", "$12.15", 1215),
    ([("Laptop", 10, 129999)], 10, "$12,999.90", "-$1,299.99", "$11,699.91", 1169991),
    ([("Pen", 1, 433)], 50, "$4.33", "-$2.17", "$2.16", 216),
    ([("Cable", 3, 399), ("Hub", 1, 2450)], 20, "$36.47", "-$7.29", "$29.18", 2918),
]
try:
    from billing.invoice import Invoice, Item, render
    for n, (items, pct, sub, disc, tot, tot_c) in enumerate(cases):
        inv = Invoice(f"D-{n}", [Item(*i) for i in items], discount_pct=pct)
        got = render(inv).splitlines()
        want_tail = [line("Subtotal", sub), line(f"Discount ({pct}%)", disc), line("Total", tot)]
        if got[-3:] != want_tail:
            problems.append(f"{pct}% on {sub}: last lines {got[-3:]!r}, want {want_tail!r}")
        for d, q, u in items:
            if not any(l.startswith(f"{q} x {d}") for l in got):
                problems.append(f"item line for {d} missing")
        if inv.total_cents() != tot_c:
            problems.append(f"{pct}% on {sub}: total_cents() = {inv.total_cents()}, want {tot_c}")
    inv = Invoice("A-1", [Item("Widget", 2, 1250), Item("Cable", 1, 399)])
    want = ["Invoice A-1", "-" * W, line("2 x Widget", "$25.00"), line("1 x Cable", "$3.99"), "-" * W,
            line("Total", "$28.99")]
    if render(inv).splitlines() != want:
        problems.append("an invoice without a discount no longer renders as before")
    if inv.total_cents() != 2899:
        problems.append("total without discount changed")
except Exception as e:
    problems.append(f"crashed: {e!r}")

r = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests"], capture_output=True, text=True)
m = re.search(r"Ran (\d+) test", r.stderr)
if r.returncode != 0:
    problems.append("tests fail: " + r.stderr[-300:])
elif not m or int(m.group(1)) <= 5:
    problems.append("no tests were added for the discount")

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
