# E2: self-consistency (agreement with the same model's other trials on the same task) as a failure detector
import sys, os, json, statistics as st, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim import Feat, scores, SCORES, pr_curve, best_f1
D = sys.argv[1]; OUT = sys.argv[2]
LING = "openrouter:inclusionai/ling-3.0-flash"; DS = "openrouter:deepseek/deepseek-v4-flash-0731#off"
HK = "openrouter:anthropic/claude-haiku-5.5"; MER = "openrouter:inception/mercury-2.5"
md = []; p = lambda s="": md.append(s)
p("## E2. Self-consistency as a failure detector\n")
p("For each run, agreement with the same model's other trials of the same task (scores as in E1). Variants: `mean9` = mean similarity to the other 9 trials (needs 10 runs per task: ~10× cost); `medoid` = similarity to the task's medoid trial (the trial with the highest mean similarity; the medoid itself uses its mean9); `pair1` = similarity to ONE other trial, averaged over the 9 possible partners (the realistic deployment: one extra trial, 2× cost). Fire when the score ≤ t. Empty reports score 0 against everything.\n")
summ = []
for store, models in (("cf6", [LING, DS, HK]), ("cf3a", None)):
    allruns = collections.defaultdict(dict)
    for l in open(os.path.join(D, store + ".jsonl")):
        r = json.loads(l)
        r.pop("reqs", None); r["feat"] = Feat(r["report"])
        allruns[r["model"]][(r["task"], r["trial"])] = r
    if models is None:
        models = [m for m in sorted(allruns, key=lambda m: -sum(not r["passed"] for r in allruns[m].values())) if len(allruns[m]) >= 140]
    hk = allruns[HK]
    hcost = st.mean(r["listPrice"] for r in hk.values())
    for m in models:
        runs = allruns[m]
        nf = sum(1 for r in runs.values() if not r["passed"])
        if nf == 0: continue
        cost = st.mean(r["listPrice"] for r in runs.values())
        if m == DS and store == "cf6": cost = 0.00045
        bytask = collections.defaultdict(list)
        for k in runs: bytask[k[0]].append(k)
        feats = {}
        items = {(v, s): [] for v in ("mean9", "medoid", "pair1") for s in SCORES}
        pairs_for_econ = []  # (key, partner, score dict)
        for t, ks in bytask.items():
            M = {(a, b): scores(runs[a]["feat"], runs[b]["feat"]) for a in ks for b in ks if a != b}
            means = {a: {s: st.mean(M[(a, b)][s] for b in ks if b != a) for s in SCORES} for a in ks}
            for s in SCORES:
                med = max(ks, key=lambda a: means[a][s])
                for a in ks:
                    fail = not runs[a]["passed"]
                    items[("mean9", s)].append((means[a][s], fail, 1, a))
                    items[("medoid", s)].append((means[a][s] if a == med else M[(a, med)][s], fail, 1, a))
                    for b in ks:
                        if b != a: items[("pair1", s)].append((M[(a, b)][s], fail, 1 / (len(ks) - 1), a))
        N = len(runs)
        p(f"### {store}: {m.split(':')[1]} — {N} runs, {nf} failures (base rate {100*nf/N:.1f}%), {sum(1 for r in runs.values() if not r['passed'] and r['feat'].empty)} of them empty reports; cost/run ${cost:.5f}\n")
        p("| variant | score | PR-AUC (AP) | AP / base | AP (non-empty) | best-F1 t | recall | precision | fire rate | recall @ fire ≤10% (precision) |")
        p("|---|---|---|---|---|---|---|---|---|---|")
        best = None
        for (v, s), its in items.items():
            rows, ap, base, P, tot = pr_curve([(x, f, w) for x, f, w, a in its])
            ne = [(x, f, w) for x, f, w, a in its if not runs[a]["feat"].empty]
            ap_ne = pr_curve(ne)[1] if any(f for x, f, w in ne) else None
            b = best_f1(rows)
            r10 = max((r for r in rows if r["fire"] <= 0.10), key=lambda r: (r["recall"], -r["fire"]), default=None)
            if b:
                f1, r = b
                p(f"| {v} | {s} | {ap:.3f} | {ap/base:.1f}× | {'–' if ap_ne is None else '%.3f' % ap_ne} | {r['t']:.3f} | {100*r['recall']:.0f}% ({r['tp']:.1f}/{P:.0f}) | {100*r['precision']:.0f}% | {100*r['fire']:.1f}% | {('%.0f%% (%.0f%%)' % (100*r10['recall'], 100*r10['precision'])) if r10 and r10['tp'] + r10['fp'] else '–'} |")
            if v == "pair1" and (best is None or ap > best[0]): best = (ap, s, rows, its)
            summ.append((store, m, v, s, ap, base, ap_ne, b[1] if b else None))
        p()
        # economics for the realistic pair1 variant (one extra trial), best score
        ap, s, rows, its = best
        p(f"Economics, `pair1` with `{s}` (one extra trial of the same model, escalate to Haiku when the pair disagrees; final answer = Haiku's run of the same task/trial). Haiku ${hcost:.5f}/run. Rows: first threshold reaching each 10% recall step.\n")
        p("| t | fire rate | recall | precision | cascade $/run | cascade pass |"); p("|---|---|---|---|---|---|")
        nextm = 0.0
        for r in rows:
            if r["recall"] + 1e-9 < nextm and r is not rows[-1] and r is not rows[0]: continue
            if r["tp"] == 0 and r is not rows[0]: continue
            nextm = (int(r["recall"] * 10 + 1e-9) + 1) / 10
            fired_w = 0; ok = 0; tw = 0
            for x, f, w, a in its:
                fire = x <= r["t"]
                h = hk.get(a)
                if h is None: continue
                tw += w; fired_w += w * fire
                ok += w * (h["passed"] if fire else runs[a]["passed"])
            p(f"| {r['t']:.3f} | {100*r['fire']:.1f}% | {100*r['recall']:.0f}% | {100*r['precision']:.1f}% | ${2*cost + hcost*fired_w/tw:.5f} | {100*ok/tw:.2f}% |")
        pa = sum(r["passed"] for r in runs.values()) / N
        ph = sum(hk[k]["passed"] for k in runs if k in hk) / sum(1 for k in runs if k in hk)
        p(f"\nReference: always {m.split('/')[-1]} ${cost:.5f}, pass {100*pa:.2f}%; always Haiku ${hcost:.5f}, pass {100*ph:.2f}%; two trials without escalation ${2*cost:.5f}.\n")
json.dump([(a, b, c, d, e, f, g, h) for a, b, c, d, e, f, g, h in summ], open(OUT + ".json", "w"))
open(OUT, "w").write("\n".join(md))
