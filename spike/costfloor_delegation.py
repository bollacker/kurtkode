#!/usr/bin/env python3
"""Cost-floor stage 4 (COST_FLOOR_PLAN.md): each parent alone against the same parent with cheap subagents it is told
to use, on the five delegation scenarios. Reads eval-results/costfloor/stage4*.json; writes Markdown on stdout.

Costs are the parent's list price per run. The subagents' own calls aren't in the parent's record; they're estimated
from the subagent model's cost per bank run (cheap: $0.0002 for ling-3.0-flash, $0.0011 for claude-haiku-5.5).
"""
import glob
import json
import os
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(__file__), "..", "eval-results", "costfloor")
SCENARIOS = ["survey", "log-sweep", "two-questions", "tiny-lookup", "small-fix"]
EXPECT = {"survey": "delegate", "log-sweep": "delegate", "two-questions": "delegate", "tiny-lookup": "don't", "small-fix": "don't"}
SUB_COST = {"ling-3.0-flash": 0.0002, "claude-haiku-5.5": 0.0011}


def label(m):
    base, _, rest = m.partition(" +subagents >")
    base = base.split("/")[-1]
    if not rest:
        return base, "alone"
    return base, "+ " + rest.split("/")[-1].replace(" forced", "")


def main():
    rows = defaultdict(list)
    for f in glob.glob(os.path.join(ROOT, "stage4*.json")):
        for r in json.load(open(f))["results"]:
            rows[(*label(r["model"]), r["scenario"])].append(r)
    parents = sorted({k[0] for k in rows})
    print("| parent | setup | " + " | ".join(f"{s} ({EXPECT[s]})" for s in SCENARIOS) + " | mean $/run |")
    print("|---|---|" + "---|" * len(SCENARIOS) + "---|")
    for p in parents:
        for setup in sorted({k[1] for k in rows if k[0] == p}, key=lambda s: (s != "alone", s)):
            cells, costs = [], []
            for s in SCENARIOS:
                v = rows.get((p, setup, s), [])
                if not v:
                    cells.append("–")
                    continue
                k = sum(r["check"]["passed"] for r in v)
                subs = sum(r.get("subagentRuns", 0) for r in v) / len(v)
                sub_cost = SUB_COST.get(setup[2:], 0) * subs
                c = sum(r.get("listPrice") or 0 for r in v) / len(v) + sub_cost
                costs.append(c)
                secs = sum(r["seconds"] for r in v) / len(v)
                cells.append(f"{k}/{len(v)} · ${c:.4f} · {secs:.0f}s" + (f" · {subs:.1f} sub" if setup != "alone" else ""))
            print(f"| {p} | {setup} | " + " | ".join(cells) + f" | ${sum(costs) / max(1, len(costs)):.4f} |")
    print()
    # Failures, for the write-up
    print("Failures:\n")
    for (p, setup, s), v in sorted(rows.items()):
        for r in v:
            if not r["check"]["passed"]:
                print(f"- {p} {setup}, {s}: " + "; ".join(r["check"]["notes"][:2]))


if __name__ == "__main__":
    main()
