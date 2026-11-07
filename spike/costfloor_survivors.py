#!/usr/bin/env python3
"""Pick the models that go on from one cost-floor stage to the next (COST_FLOOR_PLAN.md).

Reads the run store of a stage (eval-results/runs/<set>/*/run.json), groups runs by model, drops infrastructure
failures, and keeps a model with at least MIN_PASS passes and at most MAX_FAIL failures. Writes the survivors,
cheapest measured cost per run first, as a models file for kurtkode-eval --models-file, and prints a table.

    python3 spike/costfloor_survivors.py cf1 --min-pass 5 --max-fail 1 -o eval-results/costfloor/models-s2.txt
"""
import argparse
import glob
import json
import os
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(__file__), "..", "eval-results", "runs")


def load(sets):
    runs = []
    for s in sets:
        for f in glob.glob(os.path.join(ROOT, s, "*", "run.json")):
            r = json.load(open(f))
            if r.get("degradation"):
                continue
            runs.append(r)
    return runs


def table(runs):
    by = defaultdict(lambda: {"pass": 0, "fail": 0, "infra": 0, "cost": 0.0, "priced": 0, "seconds": 0.0})
    for r in runs:
        m = by[r["model"]]
        if r.get("infra"):
            m["infra"] += 1
            continue
        m["pass" if r["gold"]["passed"] else "fail"] += 1
        m["seconds"] += r.get("seconds") or 0
        if r.get("listPrice") is not None:
            m["cost"] += r["listPrice"]
            m["priced"] += 1
    for m in by.values():
        n = m["pass"] + m["fail"]
        m["per_run"] = m["cost"] / m["priced"] if m["priced"] else None
        m["rate"] = m["pass"] / n if n else 0.0
        m["per_success"] = m["cost"] / m["pass"] if m["pass"] else None
    return by


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sets", nargs="+")
    ap.add_argument("--min-pass", type=int, default=5)
    ap.add_argument("--max-fail", type=int, default=1)
    ap.add_argument("-o", "--out")
    ap.add_argument("--show", type=int, default=40, help="rows of the survivor table to print")
    a = ap.parse_args()
    by = table(load(a.sets))
    keep = sorted((k for k, m in by.items() if m["pass"] >= a.min_pass and m["fail"] <= a.max_fail),
                  key=lambda k: by[k]["per_run"] if by[k]["per_run"] is not None else 9e9)
    total = sum(m["cost"] for m in by.values())
    infra_only = sum(1 for m in by.values() if m["pass"] + m["fail"] == 0)
    print(f"{len(by)} configurations, {len(keep)} survive (≥{a.min_pass} passes, ≤{a.max_fail} failures); "
          f"{infra_only} ran only into infrastructure failures; ${total:.4f} at list price")
    print(f"{'model':60} {'pass':>4} {'fail':>4} {'infra':>5} {'$/run':>9} {'$/success':>10}")
    for k in keep[: a.show]:
        m = by[k]
        print(f"{k:60} {m['pass']:4} {m['fail']:4} {m['infra']:5} {m['per_run'] or 0:9.5f} {m['per_success'] or 0:10.5f}")
    if a.out:
        with open(a.out, "w") as f:
            f.write(f"# survivors of {', '.join(a.sets)}: ≥{a.min_pass} passes, ≤{a.max_fail} failures; cheapest first\n")
            f.write("\n".join(keep) + "\n")
        print(f"wrote {len(keep)} to {a.out}")


if __name__ == "__main__":
    main()
