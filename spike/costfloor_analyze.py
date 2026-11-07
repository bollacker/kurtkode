#!/usr/bin/env python3
"""Cost-floor analysis (COST_FLOOR_PLAN.md): the frontier, the cheapest configuration above each floor, per-kind
estimates, and the screening funnel, as Markdown on stdout.

    python3 spike/costfloor_analyze.py > eval-results/costfloor/analysis.md

Bank = the 34-task bank (sets cf1 + cf2), hard = the 14-task hard tier (cf3a finalists, cf3b references). Infrastructure
failures are left out of every rate. Rates have 95% Wilson intervals; floors are judged on the lower bound.
"""
import math
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(__file__))
import costfloor_survivors as cs  # noqa: E402

FLOORS = (0.80, 0.90, 0.95)


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (p, max(0.0, c - h), min(1.0, c + h))


def stats(runs):
    ok = [r for r in runs if not r.get("infra")]
    k = sum(1 for r in ok if r["gold"]["passed"])
    priced = [r["listPrice"] for r in ok if r.get("listPrice") is not None]
    cost = sum(priced) / len(priced) if priced else None
    secs = sum(r.get("seconds") or 0 for r in ok) / len(ok) if ok else 0
    p, lo, hi = wilson(k, len(ok))
    return {"n": len(ok), "k": k, "p": p, "lo": lo, "hi": hi, "cost": cost, "secs": secs,
            "infra": len(runs) - len(ok), "per_success": cost / p if cost is not None and p > 0 else None}


def by_model(runs):
    out = defaultdict(list)
    for r in runs:
        out[r["model"]].append(r)
    return out


def short(m):
    return m.replace("openrouter:", "")


def money(x, d=5):
    return "–" if x is None else f"${x:.{d}f}"


def pct(x):
    return f"{100 * x:.0f}%"


def main():
    bank = by_model(cs.load(["cf1", "cf2"]))
    hard = by_model(cs.load(["cf3a", "cf3b"]))
    screen = by_model(cs.load(["cf1"]))
    refs = sorted(by_model(cs.load(["cf3b"])))  # screened in stage 1 too, but references, not finalists
    finalists = sorted(m for m in by_model(cs.load(["cf3a"])) if m in bank)

    # Funnel
    print("## The funnel\n")
    s1 = {m: stats([r for r in rs if r["trial"] == 1]) for m, rs in screen.items()}
    infra_only = sum(1 for s in s1.values() if s["n"] == 0)
    surv = sum(1 for s in s1.values() if s["k"] >= 5 and s["n"] - s["k"] <= 1)
    print(f"- Stage 1 screened {len(s1)} configurations: {infra_only} never ran (every run an infrastructure failure), "
          f"{surv} passed at least 5 of 6.")
    s2 = {m: stats(rs) for m, rs in bank.items() if len({r['task'] for r in rs}) > 6}
    print(f"- Stage 2 ran the whole bank on {len(s2)} of them.")
    print(f"- Stage 3a ran the hard tier on {len(finalists)} finalists; stage 3b on {len(refs)} frontier references.\n")

    # Finalists table
    rows = []
    for m in finalists:
        b, h, a = stats(bank[m]), stats(hard[m]), stats(bank[m] + hard[m])
        rows.append((m, b, h, a))
    rows.sort(key=lambda t: (t[3]["per_success"] or 9e9))
    print("## Finalists: bank and hard tier together\n")
    print("Cost is list price per run, the mean over every run the configuration made; $/success = cost ÷ pass rate.\n")
    print("| configuration | bank | hard | all (95% CI) | $/run | $/success | mean s |")
    print("|---|---|---|---|---|---|---|")
    for m, b, h, a in rows:
        print(f"| {short(m)} | {b['k']}/{b['n']} | {h['k']}/{h['n']} | {pct(a['p'])} ({pct(a['lo'])}–{pct(a['hi'])}) "
              f"| {money(a['cost'])} | {money(a['per_success'])} | {a['secs']:.0f} |")
    print()
    print("## References (hard tier only)\n")
    print("| model | hard (95% CI) | $/run | $/success | mean s |")
    print("|---|---|---|---|---|")
    for m in refs:
        h = stats(hard[m])
        print(f"| {short(m)} | {h['k']}/{h['n']} ({pct(h['lo'])}–{pct(h['hi'])}) | {money(h['cost'], 4)} | "
              f"{money(h['per_success'], 4)} | {h['secs']:.0f} |")
    print()

    # Cheapest above floors
    print("## Cheapest above the floor\n")
    print("A configuration clears a floor when the lower bound of its 95% interval does (bank + hard runs together).\n")
    print("| floor | cheapest by $/success | rate (lower bound) | $/success | next two |")
    print("|---|---|---|---|---|")
    for f in FLOORS:
        ok = sorted((t for t in rows if t[3]["lo"] >= f), key=lambda t: t[3]["per_success"] or 9e9)
        if not ok:
            best_lo = max(rows, key=lambda t: t[3]["lo"])
            print(f"| {pct(f)} | none certified; highest lower bound {short(best_lo[0])} at {pct(best_lo[3]['lo'])} | | | |")
            continue
        m, _, _, a = ok[0]
        nxt = ", ".join(f"{short(t[0])} ({money(t[3]['per_success'])})" for t in ok[1:3])
        print(f"| {pct(f)} | {short(m)} | {pct(a['p'])} ({pct(a['lo'])}) | {money(a['per_success'])} | {nxt} |")
    print()
    # Point estimates too: certification needs many runs
    print("By point estimate (no interval), the cheapest at each floor:\n")
    for f in FLOORS:
        ok = sorted((t for t in rows if t[3]["p"] >= f), key=lambda t: t[3]["per_success"] or 9e9)
        if ok:
            print(f"- {pct(f)}: {short(ok[0][0])} ({pct(ok[0][3]['p'])}, {money(ok[0][3]['per_success'])} per success)")
    print()

    # Per kind for the top finalists
    print("## By kind (top 8 finalists by $/success; estimates, not certified)\n")
    top = [t[0] for t in rows[:8]]
    kinds = sorted({r["kind"] for m in top for r in bank[m] + hard[m] if r.get("kind")})
    print("| configuration | " + " | ".join(kinds) + " |")
    print("|---|" + "---|" * len(kinds))
    for m in top:
        cells = []
        for k in kinds:
            s = stats([r for r in bank[m] + hard[m] if r.get("kind") == k])
            cells.append(f"{s['k']}/{s['n']}")
        print(f"| {short(m)} | " + " | ".join(cells) + " |")
    print()

    # Reasoning off vs default
    print("## Reasoning off against default (stage 1 and 2 runs, configurations that ran both)\n")
    pairs = []
    for m in bank:
        if m.endswith("#off") and m[:-4] in bank:
            on, off = stats(bank[m[:-4]]), stats(bank[m])
            if on["n"] >= 20 and off["n"] >= 20:
                pairs.append((m[:-4], on, off))
    better = sum(1 for _, on, off in pairs if off["per_success"] and on["per_success"] and off["per_success"] < on["per_success"])
    print(f"{len(pairs)} models ran the bank both ways; reasoning off was cheaper per success for {better} of them.\n")
    print("| model | default: rate, $/success | off: rate, $/success |")
    print("|---|---|---|")
    for m, on, off in sorted(pairs, key=lambda t: t[1]["per_success"] or 9e9)[:15]:
        print(f"| {short(m)} | {pct(on['p'])}, {money(on['per_success'])} | {pct(off['p'])}, {money(off['per_success'])} |")
    print()

    # Unreliable cheap models: infra
    print("## Unreliable: infrastructure failures in stage 1\n")
    reasons = defaultdict(int)
    for rs in screen.values():
        for r in rs:
            if r.get("infra"):
                why = r["infra"]
                key = ("reasoning can't be turned off" if "Reasoning is mandatory" in why else
                       "rate limited (429)" if "429" in why else
                       "no provider without training on prompts (404)" if "404" in why else
                       why[:60])
                reasons[key] += 1
    for k, v in sorted(reasons.items(), key=lambda t: -t[1])[:8]:
        print(f"- {v} runs: {k}")
    print()


if __name__ == "__main__":
    main()
