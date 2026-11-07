#!/usr/bin/env python3
"""Compile the exchange-rate table. Usage: build_rates.py RATES.csv OUT.json
Each row is CURRENCY,RATE (units of the currency per 1 USD). Exit 1 on a malformed row."""
import csv, json, os, sys

src, out = sys.argv[1], sys.argv[2]
rates = {}
with open(src, newline="") as f:
    rows = csv.reader(f)
    header = next(rows)
    for lineno, row in enumerate(rows, 2):
        if len(row) != 2:
            print(f"{src}:{lineno}: error: expected 2 fields (currency,rate), got {len(row)}: {row}")
            sys.exit(1)
        code, rate = row[0].strip(), float(row[1])
        if len(code) != 3 or rate <= 0:
            print(f"{src}:{lineno}: error: bad row {row}")
            sys.exit(1)
        rates[code] = rate
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
with open(out, "w") as f:
    json.dump(rates, f, indent=1, sort_keys=True)
print(f"wrote {len(rates)} rates to {out}")
