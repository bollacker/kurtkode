#!/usr/bin/env python3
"""Compare task-test arms from one or more results files.

Usage: analyze.py RESULTS.jsonl [MORE.jsonl ...] [--markdown]

Per skill: pass rate (check), mean rubric score (judge), mean cost, mean tool calls, for each arm present
(baseline = no skills, skills = whole library found by the model, forced = told to load the skill,
control = an irrelevant skill of similar length forced). The verdict compares forced (and skills) with both
baseline and control: a skill earns its place when it beats both.
"""
import json, sys, collections, math

ARMS = ["baseline", "control", "skills", "forced"]


def wilson(k, n, z=1.96):
    if n == 0:
        return (0, 0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0, c - h), min(1, c + h))


def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    md = "--markdown" in sys.argv
    rows = [json.loads(l) for f in files for l in open(f) if l.strip()]
    rows = [r for r in rows if r.get("kind") == "task"]
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in rows:
        by[(r["skill"], r["case"])][r["arm"]].append(r)

    def stats(rs):
        if not rs:
            return None
        n = len(rs)
        k = sum(r["pass"] for r in rs)
        rub = [r["judge"]["rubric_pct"] for r in rs if (r.get("judge") or {}).get("rubric_pct") is not None]
        return {"n": n, "pass": k, "rate": k / n, "rubric": sum(rub) / len(rub) if rub else None,
                "cost": sum(r["cost"] for r in rs) / n, "calls": sum(sum((r.get("tools") or {}).values()) for r in rs) / n,
                "loaded": sum(1 for r in rs if r["skill"] in r["loaded"]) / n,
                "errors": sum(1 for r in rs if r.get("error"))}

    def cell(s):
        if not s:
            return "-"
        rub = f"{s['rubric']*100:.0f}" if s["rubric"] is not None else "–"
        return f"{s['pass']}/{s['n']} r{rub} ${s['cost']:.2f} {s['calls']:.0f}c"

    present = [a for a in ARMS if any(a in v for v in by.values())]
    tot = {a: [] for a in present}
    verdicts = collections.Counter()
    lines = []
    head = ["skill/case"] + present + ["verdict"]
    for key in sorted(by):
        arms = by[key]
        st = {a: stats(arms.get(a, [])) for a in present}
        for a in present:
            tot[a] += arms.get(a, [])
        b, c, f = st.get("baseline"), st.get("control"), st.get("forced")
        verdict = ""
        if b and f:
            def score(s):   # pass rate first, rubric as a tiebreak worth up to a tenth of a pass
                return s["rate"] + 0.1 * (s["rubric"] or 0)
            ref = max(score(b), score(c)) if c else score(b)
            d = score(f) - ref
            verdict = "helps" if d >= 0.2 else ("hurts" if d <= -0.2 else "same")
            if verdict == "same" and b["rate"] == 1 and f["rate"] == 1:
                verdict = "ceiling"
            verdicts[verdict] += 1
        lines.append([f"{key[0]}/{key[1]}"] + [cell(st[a]) for a in present] + [verdict])
    total = ["ALL"]
    for a in present:
        s = stats(tot[a])
        lo, hi = wilson(s["pass"], s["n"])
        total.append(f"{s['pass']}/{s['n']} ({s['rate']*100:.0f}%, {lo*100:.0f}–{hi*100:.0f}) r{(s['rubric'] or 0)*100:.0f} ${s['cost']:.3f} {s['calls']:.0f}c")
    total.append(" ".join(f"{k}={v}" for k, v in verdicts.most_common()))
    lines.append(total)
    if md:
        print("| " + " | ".join(head) + " |")
        print("|" + "---|" * len(head))
        for l in lines:
            print("| " + " | ".join(l) + " |")
    else:
        w = [max(len(str(l[i])) for l in lines + [head]) for i in range(len(head))]
        for l in [head] + lines:
            print("  ".join(str(x).ljust(w[i]) for i, x in enumerate(l)))
    errs = sum(1 for r in rows if r.get("error"))
    if errs:
        print(f"\n{errs} runs had errors")
    nl = [r for r in tot.get("skills", []) if r["skill"] not in r["loaded"]]
    if nl:
        print(f"\nskills arm: own skill not loaded in {len(nl)}/{len(tot['skills'])} runs:",
              ", ".join(sorted({f'{r['skill']}/{r['case']}' for r in nl})))


if __name__ == "__main__":
    main()
