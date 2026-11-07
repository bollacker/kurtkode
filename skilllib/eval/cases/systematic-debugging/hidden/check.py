#!/usr/bin/env python3
"""Hidden check for systematic-debugging/missing-vat. Run in the project folder. Exit 0 = pass.
The symptom (no VAT) shows in store/invoice.py; the cause is store/csvload.py keeping the '\r' of CRLF line endings
on the last field of every row. A patch in invoice.py (strip the region there) passes the visible test but leaves
every other reader of the exports broken, so this checks the shared reader and another path through it
(regional mailing lists), on CRLF, LF and no-final-newline files written here, not the project's test data."""
import os, subprocess, sys, tempfile, unittest

root = os.getcwd()
sys.path.insert(0, root)
problems = []

p = subprocess.run([sys.executable, "-m", "unittest", "-q"], capture_output=True, text=True)
if p.returncode != 0:
    problems.append("the project's own tests fail:\n" + (p.stdout + p.stderr)[-600:])

CUSTOMERS = ["code,name,email,region", "C001,Acme GmbH,ops@acme.example,EU", "C002,Bolt Inc,billing@bolt.example,US",
             "C003,Crane Ltd,accounts@crane.example,UK", "C005,Eagle SA,hi@eagle.example,EU"]
WANT_ROWS = [dict(zip(CUSTOMERS[0].split(","), line.split(","))) for line in CUSTOMERS[1:]]
tmp = tempfile.mkdtemp()


def write(name, text):
    path = os.path.join(tmp, name)
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))
    return path


variants = {"CRLF": write("crlf.csv", "\r\n".join(CUSTOMERS) + "\r\n"),
            "LF": write("lf.csv", "\n".join(CUSTOMERS) + "\n"),
            "CRLF, no final newline": write("nofinal.csv", "\r\n".join(CUSTOMERS)),
            "BOM + CRLF": write("bom.csv", "﻿" + "\r\n".join(CUSTOMERS) + "\r\n")}
try:
    from store.csvload import read_rows
    from store.customers import load_customers, customers_in_region
    from store.invoice import invoice_total
    for label, path in variants.items():
        rows = read_rows(path)
        if rows != WANT_ROWS:
            problems.append(f"read_rows on a {label} file returned {rows!r}")
            continue
        customers = load_customers(path)
        got = customers_in_region(customers, "EU")
        if got != ["C001", "C005"]:
            problems.append(f"customers_in_region(..., 'EU') on a {label} file = {got}, want ['C001', 'C005']")
        for code, want in (("C001", 121.0), ("C003", 120.0), ("C002", 100.0)):
            total = invoice_total(customers[code], [(4, 25.0)])
            if total != want:
                problems.append(f"invoice_total for {code} on a {label} file = {total}, want {want}")
except Exception as e:
    problems.append(f"hidden checks crashed: {e!r}")

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
