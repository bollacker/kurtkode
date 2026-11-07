# E1: cross-model agreement as a failure detector (no gold used in the score)
import sys, os, json, statistics as st
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim import Feat, scores, SCORES as BASE, pr_curve, best_f1, at_recall
SCORES = BASE + tuple(x + "-tc" for x in BASE)
D = sys.argv[1]; OUT = sys.argv[2]
LING = "openrouter:inclusionai/ling-3.0-flash"; DS = "openrouter:deepseek/deepseek-v4-flash-0731#off"
HK = "openrouter:anthropic/claude-haiku-5.5"; MER = "openrouter:inception/mercury-2.5"
short = {LING: "ling", DS: "deepseek#off", HK: "Haiku", MER: "mercury-2.5"}
def load(store, models):
    runs = {}
    for l in open(os.path.join(D, store + ".jsonl")):
        r = json.loads(l)
        if r["model"] in models:
            r["feat"] = Feat(r["report"]); r.pop("reqs", None)
            runs[(r["model"], r["task"], r["trial"])] = r
    return runs
def costs(runs, model):
    v = [r for k, r in runs.items() if k[0] == model]
    lp = [r["listPrice"] for r in v if r["listPrice"] is not None]; ch = [r["charged"] for r in v if r["charged"] is not None]
    return st.mean(lp), (st.mean(ch) if ch else None)
md = []
def p(s=""): md.append(s)
p("## E1. Cross-model agreement as a failure detector\n")
summary = []
for store, pairs, models, esc in (
    ("cf6", [(LING, DS), (LING, HK), (DS, LING), (DS, HK), (HK, LING), (HK, DS)], [LING, DS, HK], HK),
    ("cf3a", [(MER, LING), (MER, HK), (MER, DS), (LING, MER)], [LING, DS, HK, MER], HK)):
    runs = load(store, set(models))
    c = {m: costs(runs, m) for m in models}
    p(f"### {store}: per-model mean cost per run (from the store)\n")
    p("| model | runs | gold failures | mean listPrice | mean charged |"); p("|---|---|---|---|---|")
    for m in models:
        v = [r for k, r in runs.items() if k[0] == m]
        p(f"| {short[m]} | {len(v)} | {sum(1 for r in v if not r['passed'])} | ${c[m][0]:.5f} | {'$%.5f' % c[m][1] if c[m][1] else '–'} |")
    p()
    # cost to use in economics
    ucost = {m: c[m][0] for m in models}
    if store == "cf6": ucost[DS] = 0.00045  # corrected list price (cf6 list price is inflated ~6x)
    p(f"Costs used in the economics: " + ", ".join(f"{short[m]} ${ucost[m]:.5f}" for m in models) + (" (deepseek: corrected list price; cf6 stored list is inflated ~6×, charged is $%.5f)" % c[DS][1] if store == "cf6" else "") + "\n")
    for A, B in pairs:
        keys = [(t, tr) for (m, t, tr) in runs if m == A and (B, t, tr) in runs]
        sc = {k: scores(runs[(A,) + k]["feat"], runs[(B,) + k]["feat"]) for k in keys}
        # task-centered variants: score minus the median of the same pair's score on the task's other trials (leave-one-out)
        for k in keys:
            for s0 in BASE:
                others = sorted(sc[o][s0] for o in keys if o[0] == k[0] and o != k)
                sc[k][s0 + "-tc"] = sc[k][s0] - (others[len(others)//2] if others else 0)
        nonempty = [k for k in keys if not runs[(A,) + k]["feat"].empty]
        nfail_ne = sum(1 for k in nonempty if not runs[(A,) + k]["passed"])
        nfail = sum(1 for k in keys if not runs[(A,) + k]["passed"])
        p(f"### {store}: A = {short[A]}, B = {short[B]} ({len(keys)} matched (task, trial) pairs, {nfail} A failures, base rate {100*nfail/len(keys):.1f}%)\n")
        p(f"Scores: Jaccard of `words` (stop words removed), `idents` (numbers, paths, snake/Camel tokens, quoted strings), `paths` (file paths only), `last` (words of the last sentence), `mean` of the four; `-tc` = task-centered (minus the median of the same pair's score on the task's 9 other trials; needs other runs of the task, so it is an oracle-calibrated variant). AP(non-empty) = AP over the {len(nonempty)} pairs whose A report is non-empty ({nfail_ne} failures), i.e. what the detector adds beyond the existing emptyReport check.\n")
        p("| score | PR-AUC (AP) | AP / base rate | AP (non-empty A) | best-F1 threshold (fire if score ≤ t) | recall | precision | fire rate | recall @ fire ≤10% | precision there |")
        p("|---|---|---|---|---|---|---|---|---|---|")
        curves = {}
        for s in SCORES:
            items = [(sc[k][s], not runs[(A,) + k]["passed"], 1) for k in keys]
            rows, ap, base, P, tot = pr_curve(items); curves[s] = rows
            b = best_f1(rows)
            ne_items = [(sc[k][s], not runs[(A,) + k]["passed"], 1) for k in nonempty]
            ap_ne = pr_curve(ne_items)[1] if nfail_ne else None
            ape = "–" if ap_ne is None else f"{ap_ne:.3f}"
            r10 = max((r for r in rows if r["fire"] <= 0.10), key=lambda r: (r["recall"], -r["fire"]), default=None)
            if b:
                f1, r = b
                p(f"| {s} | {ap:.3f} | {ap/base:.1f}× | {ape} | {r['t']:.3f} | {100*r['recall']:.0f}% ({r['tp']}/{P}) | {100*r['precision']:.0f}% ({r['tp']}/{r['tp']+r['fp']}) | {100*r['fire']:.1f}% | {('%.0f%% (t=%.3f)' % (100*r10['recall'], r10['t'])) if r10 else '–'} | {('%.0f%%' % (100*r10['precision'])) if r10 and r10['tp']+r10['fp'] else '–'} |")
            else:
                p(f"| {s} | {ap:.3f} | – | {ape} | – | – | – | – | – | – |")
            summary.append((store, short[A], short[B], s, ap, base, b))
        p()
        # threshold sweep for the 'mean' and best-AP score
        bestS = max(BASE, key=lambda s: summary[[i for i, x in enumerate(summary) if x[:4] == (store, short[A], short[B], s)][0]][4])
        rows = curves[bestS]
        p(f"Sweep for the best-AP deployable (non-task-centered) score (`{bestS}`), each row a threshold where recall rises (fire if score ≤ t):\n")
        cheap_pair = A != HK and B != HK
        hdr = "| t | fire rate | recall | precision |" + (" cascade $/run | cascade pass | extra $/run of false alarms |" if cheap_pair else "")
        p(hdr); p("|---|---|---|---|" + ("---|---|---|" if cheap_pair else ""))
        last_tp = -1
        for r in rows:
            if r["tp"] == last_tp and r is not rows[-1]: continue
            last_tp = r["tp"]
            line = f"| {r['t']:.3f} | {100*r['fire']:.1f}% | {100*r['recall']:.0f}% ({r['tp']}) | {100*r['precision']:.1f}% |"
            if cheap_pair:
                fired = [k for k in keys if sc[k][bestS] <= r["t"]]
                fs = set(fired)
                hk_ok = [k for k in keys if (HK,) + k in runs]
                cost = ucost[A] + ucost[B] + ucost[HK] * len(fired) / len(keys)
                passes = sum((runs[(HK,) + k]["passed"] if k in fs else runs[(A,) + k]["passed"]) for k in hk_ok) / len(hk_ok)
                fa = sum(1 for k in fired if runs[(A,) + k]["passed"])
                line += f" ${cost:.5f} | {100*passes:.2f}% | ${ucost[HK]*fa/len(keys):.5f} |"
            p(line)
        p()
        if cheap_pair:
            pa = sum(runs[(A,) + k]["passed"] for k in keys) / len(keys)
            ph = sum(runs[(HK,) + k]["passed"] for k in keys if (HK,) + k in runs) / sum(1 for k in keys if (HK,) + k in runs)
            p(f"Reference: always {short[A]} ${ucost[A]:.5f}/run, pass {100*pa:.2f}%; always Haiku ${ucost[HK]:.5f}/run, pass {100*ph:.2f}%; ({short[A]}+{short[B]}, never escalate) ${ucost[A]+ucost[B]:.5f}/run.\n")
json.dump([(a, b, c, d, e, f, (g[1] if g else None)) for a, b, c, d, e, f, g in summary], open(OUT + ".json", "w"))
open(OUT, "w").write("\n".join(md))
print("\n".join(md))
